import 'dart:convert';

import '../../../core/sanity/client.dart';
import '../../../core/settings.dart';
import 'daily_pick.dart';

bool get leyaanaCanEdit => sanityCanWrite;

// ---- content model ----------------------------------------------------------

class Verse {
  Verse({
    required this.id,
    this.title,
    required this.verse,
    this.order,
    this.createdAt,
  });
  final String id;
  final String? title;
  final String verse;
  final int? order;
  final String? createdAt;
}

class NamedContent {
  NamedContent({
    required this.id,
    required this.name,
    this.mean,
    this.content,
    this.order,
    this.createdAt,
  });
  final String id;
  final String name;
  final String? mean;
  final String? content;
  final int? order;
  final String? createdAt;
}

class DailyContent {
  DailyContent({
    required this.dailyVerse,
    required this.weeklyVerse,
    required this.monthlyVerse,
    required this.godName,
    required this.blessing,
  });
  final Verse? dailyVerse;
  final Verse? weeklyVerse;
  final Verse? monthlyVerse;
  final NamedContent? godName;
  final NamedContent? blessing;
}

// ---- queries & caching ------------------------------------------------------

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
    final result = await sanityQuery(_queries[type]!, cdn: true);
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
  content: m['content'] != null
      ? _applyName(m['content'].toString()).trim()
      : null,
  order: (m['order'] is num) ? (m['order'] as num).toInt() : null,
  createdAt: m['_createdAt']?.toString(),
);

// ---- editing (Sanity mutate API) ------------------------------------------

/// Raw sorted docs for the admin list. [type] is the Sanity _type:
/// 'verse' | 'godName' | 'heavenlyBlessing'. NOT personalized (edit the source).
Future<List<Map<String, dynamic>>> fetchRawForEdit(String type) async {
  final items = await _fetchType(type);
  return [...items]..sort(_compare);
}

Future<void> createDoc(String type, Map<String, dynamic> fields) =>
    sanityMutate([
      {
        'create': {'_type': type, ...fields},
      },
    ]);

Future<void> updateDoc(String id, Map<String, dynamic> fields) => sanityMutate([
  {
    'patch': {'id': id, 'set': fields},
  },
]);

Future<void> deleteDoc(String id) => sanityMutate([
  {
    'delete': {'id': id},
  },
]);

/// Personalized daily verse for the UTC day of each of [dates], keyed by
/// getPeriodKey('daily'). One fetch, so notifications + widget can be
/// precomputed for the next N days without a background worker.
Future<Map<String, Verse>> dailyVersesFor(Iterable<DateTime> dates) async {
  final verses = [...await _fetchType('verse')]..sort(_compare);
  if (verses.isEmpty) return {};
  final person = Settings.instance.personKey;
  return {
    for (final d in dates)
      getPeriodKey('daily', d): _parseVerse(
        verses[pickIndex(
          getPeriodKey('daily', d),
          person,
          'verse',
          verses.length,
        )],
      ),
  };
}

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
    final m = pick(verses, 'verse', period);
    return m == null ? null : _parseVerse(m);
  }

  final gn = pick(godNames, 'godName', 'daily');
  final bl = pick(blessings, 'blessing', 'daily');

  return DailyContent(
    dailyVerse: v('daily'),
    weeklyVerse: v('weekly'),
    monthlyVerse: v('monthly'),
    godName: gn == null ? null : _parseNamed(gn),
    blessing: bl == null ? null : _parseNamed(bl),
  );
}
