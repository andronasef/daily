import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings.dart';

/// Native port of temp/leyaana content logic so this app lands on the SAME
/// daily item the PWA shows. Any drift here shows up as a mismatched verse in
/// verification, so the hash/period/sort logic is reproduced byte-for-byte.

// ---- period.ts port ---------------------------------------------------------

/// JS: hash = (hash<<5)-hash+code; hash |= 0; return Math.abs(hash).
/// `|= 0` forces 32-bit signed wraparound — Dart ints are 64-bit, so clamp
/// each step with toSigned(32).
int hashValue(String value) {
  int hash = 0;
  for (int i = 0; i < value.length; i++) {
    hash = ((hash << 5) - hash + value.codeUnitAt(i)).toSigned(32);
  }
  return hash.abs();
}

/// JS getPeriodKey uses date.toISOString() (UTC), so day/week/month buckets are
/// UTC-based. Keep that or the index diverges near midnight.
String getPeriodKey(String period, [DateTime? date]) {
  final utc = (date ?? DateTime.now()).toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');

  if (period == 'monthly') return '$y-$m';
  if (period == 'daily') return '$y-$m-$d';

  // weekly: days since epoch of UTC midnight, +4 so the boundary lands Sunday.
  final daysSinceEpoch =
      (DateTime.utc(utc.year, utc.month, utc.day).millisecondsSinceEpoch /
              86400000)
          .floor();
  return 'W${((daysSinceEpoch + 4) / 7).floor()}';
}

int pickIndex(String periodKey, String userKey, String typeKey, int length) {
  return hashValue('$periodKey:$userKey:$typeKey') % length;
}

// ---- content model ----------------------------------------------------------

class Verse {
  Verse({required this.id, this.title, required this.verse, this.order, this.createdAt});
  final String id;
  final String? title;
  final String verse;
  final int? order;
  final String? createdAt;
}

class NamedContent {
  NamedContent({required this.id, required this.name, this.mean, this.content, this.order, this.createdAt});
  final String id;
  final String name;
  final String? mean;
  final String? content;
  final int? order;
  final String? createdAt;
}

// ---- Sanity fetch (public read, no token) -----------------------------------

const _sanityProjectId = 'kfme7y2v';
const _sanityDataset = 'production';
const _sanityApiVersion = 'v2024-01-01';

/// Paste your Sanity write token here (or pass --dart-define=SANITY_WRITE_TOKEN=...).
/// Needed only for the ليا انا add/edit/delete screen. Reads work without it.
/// ponytail: token compiled into the app — fine for a personal build; anyone
/// with the APK could write to the dataset. Move behind a proxy if it ships.
const _writeToken = String.fromEnvironment('SANITY_WRITE_TOKEN', defaultValue: '');

bool get leyaanaCanEdit => _writeToken.isNotEmpty;

const _queries = {
  'verse':
      '*[_type == "verse"] | order(coalesce(order, 999999) asc, _createdAt asc){_id, _type, _createdAt, order, title, verse}',
  'godName':
      '*[_type == "godName"] | order(coalesce(order, 999999) asc, _createdAt asc){_id, _type, _createdAt, order, name, mean, content}',
  'heavenlyBlessing':
      '*[_type == "heavenlyBlessing"] | order(coalesce(order, 999999) asc, _createdAt asc){_id, _type, _createdAt, order, name, mean, content}',
};

Future<List<Map<String, dynamic>>> _fetchType(String type) async {
  final cacheKey = 'content-cache:$type';
  try {
    final uri = Uri.parse(
        'https://$_sanityProjectId.apicdn.sanity.io/$_sanityApiVersion/data/query/$_sanityDataset')
        .replace(queryParameters: {'query': _queries[type]!});
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Sanity ${res.statusCode}');
    final result = (jsonDecode(res.body)['result'] as List).cast<Map<String, dynamic>>();
    await Settings.instance.setCache(cacheKey, jsonEncode(result));
    return result;
  } catch (e) {
    final cached = Settings.instance.getCache(cacheKey);
    if (cached != null) {
      return (jsonDecode(cached) as List).cast<Map<String, dynamic>>();
    }
    rethrow;
  }
}

/// Matches sortContent(): order asc (default 999999), tiebreak (_createdAt||_id).
int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ao = (a['order'] is num) ? (a['order'] as num).toInt() : 999999;
  final bo = (b['order'] is num) ? (b['order'] as num).toInt() : 999999;
  if (ao != bo) return ao - bo;
  final ak = (a['_createdAt'] ?? a['_id']).toString();
  final bk = (b['_createdAt'] ?? b['_id']).toString();
  return ak.compareTo(bk);
}

// ---- personalization (api.ts) ----------------------------------------------

String _applyName(String text) =>
    text.replaceAll('<الاسم>', Settings.instance.personKey);

Verse _parseVerse(Map<String, dynamic> m) {
  final raw = (m['verse'] ?? m['content'] ?? '').toString();
  final parts = raw.split('---');
  var text = raw;
  if (parts.length == 2) {
    text = Settings.instance.isMale ? parts[0] : parts[1];
  }
  text = _applyName(text).trim();
  return Verse(
    id: (m['_id'] ?? '').toString(),
    title: m['title']?.toString(),
    verse: text,
    order: (m['order'] is num) ? (m['order'] as num).toInt() : null,
    createdAt: m['_createdAt']?.toString(),
  );
}

NamedContent _parseNamed(Map<String, dynamic> m) => NamedContent(
      id: (m['_id'] ?? '').toString(),
      name: _applyName((m['name'] ?? m['title'] ?? '').toString()).trim(),
      mean: m['mean'] != null ? _applyName(m['mean'].toString()).trim() : null,
      content: m['content'] != null ? _applyName(m['content'].toString()).trim() : null,
      order: (m['order'] is num) ? (m['order'] as num).toInt() : null,
      createdAt: m['_createdAt']?.toString(),
    );

// ---- public API: today's picks ---------------------------------------------

class DailyContent {
  DailyContent({required this.dailyVerse, required this.weeklyVerse, required this.monthlyVerse, required this.godName, required this.blessing});
  final Verse? dailyVerse;
  final Verse? weeklyVerse;
  final Verse? monthlyVerse;
  final NamedContent? godName;
  final NamedContent? blessing;
}

/// Picks the same item the PWA would for the current UTC period + this user.
Map<String, dynamic>? _pick(List<Map<String, dynamic>> items, String typeKey, String period) {
  if (items.isEmpty) return null;
  final key = getPeriodKey(period);
  final idx = pickIndex(key, Settings.instance.personKey, typeKey, items.length);
  return items[idx];
}

// ---- editing (Sanity mutate API) ------------------------------------------

/// Raw sorted docs for the admin list. [type] is the Sanity _type:
/// 'verse' | 'godName' | 'heavenlyBlessing'. NOT personalized (edit the source).
Future<List<Map<String, dynamic>>> fetchRawForEdit(String type) async {
  final items = await _fetchType(type);
  return [...items]..sort(_compare);
}

Future<void> _mutate(List<Map<String, dynamic>> mutations) async {
  if (_writeToken.isEmpty) {
    throw Exception('مفيش Sanity write token متظبط.');
  }
  final uri = Uri.parse(
      'https://$_sanityProjectId.api.sanity.io/$_sanityApiVersion/data/mutate/$_sanityDataset?returnIds=true');
  final res = await http
      .post(uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_writeToken',
          },
          body: jsonEncode({'mutations': mutations}))
      .timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) {
    throw Exception('Sanity ${res.statusCode}: ${res.body}');
  }
}

Future<void> createDoc(String type, Map<String, dynamic> fields) =>
    _mutate([
      {
        'create': {'_type': type, ...fields}
      }
    ]);

Future<void> updateDoc(String id, Map<String, dynamic> fields) => _mutate([
      {
        'patch': {'id': id, 'set': fields}
      }
    ]);

Future<void> deleteDoc(String id) => _mutate([
      {
        'delete': {'id': id}
      }
    ]);

Future<DailyContent> loadDailyContent() async {
  final results = await Future.wait([
    _fetchType('verse'),
    _fetchType('godName'),
    _fetchType('heavenlyBlessing'),
  ]);
  final verses = [...results[0]]..sort(_compare);
  final godNames = [...results[1]]..sort(_compare);
  final blessings = [...results[2]]..sort(_compare);

  Verse? v(String period) {
    final m = _pick(verses, 'verse', period);
    return m == null ? null : _parseVerse(m);
  }

  final gn = _pick(godNames, 'godName', 'daily');
  final bl = _pick(blessings, 'blessing', 'daily');

  return DailyContent(
    dailyVerse: v('daily'),
    weeklyVerse: v('weekly'),
    monthlyVerse: v('monthly'),
    godName: gn == null ? null : _parseNamed(gn),
    blessing: bl == null ? null : _parseNamed(bl),
  );
}
