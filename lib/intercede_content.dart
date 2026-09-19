import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

import 'settings.dart';

// ponytail: network-only, no local cache — intercede data is small and
// write-heavy; staleness would be more confusing than a spinner. Ceiling:
// add Settings-based cache like leyaana_content.dart if latency hurts.

const _projectId = 'kfme7y2v';
const _dataset = 'production';
const _apiVersion = 'v2024-01-01';

/// Write token: entered in Settings (stored on-device). --dart-define=SANITY_WRITE_TOKEN
/// is a fallback for dev builds. Without it the section is read-only.
const _envToken = String.fromEnvironment('SANITY_WRITE_TOKEN', defaultValue: '');

String get _writeToken {
  final t = Settings.instance.sanityToken;
  return t.isNotEmpty ? t : _envToken;
}

bool get intercedeCanEdit => _writeToken.isNotEmpty;

// ---- models -----------------------------------------------------------------

class PrayerLog {
  PrayerLog({required this.prayedAt, this.note});
  final DateTime prayedAt;
  final String? note;
}

class Prayer {
  Prayer({
    required this.id,
    required this.title,
    this.startedAt,
    this.completedAt,
    this.outcome,
    this.logs = const [],
  });

  final String id;
  final String title;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? outcome;
  final List<PrayerLog> logs;

  bool get isDone => completedAt != null;

  /// Already prayed at some point today — drives the daily checklist.
  bool get prayedToday {
    final l = lastPrayedAt;
    if (l == null) return false;
    final now = DateTime.now();
    return l.year == now.year && l.month == now.month && l.day == now.day;
  }

  DateTime? get lastPrayedAt =>
      logs.isEmpty ? null : logs.map((l) => l.prayedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class Entity {
  Entity({
    required this.id,
    required this.name,
    this.note,
    this.createdAt,
    this.prayers = const [],
  });

  final String id;
  final String name;
  final String? note;
  final DateTime? createdAt;
  final List<Prayer> prayers;

  List<Prayer> get active {
    final list = prayers.where((p) => !p.isDone).toList();
    list.sort((a, b) {
      final al = a.lastPrayedAt;
      final bl = b.lastPrayedAt;
      if (al == null && bl == null) return 0;
      if (al == null) return -1;
      if (bl == null) return 1;
      return al.compareTo(bl);
    });
    return list;
  }

  List<Prayer> get archived {
    final list = prayers.where((p) => p.isDone).toList();
    list.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    return list;
  }

  DateTime? get lastPrayedAt {
    final dates = prayers
        .map((p) => p.lastPrayedAt)
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

// ---- relative date formatting -----------------------------------------------

String relativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inMinutes < 1) return 'دلوقتي';
  if (diff.inMinutes < 60) return 'من ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'من ${diff.inHours} ساعة';
  if (diff.inDays == 1) return 'من إمبارح';
  if (diff.inDays < 7) return 'من ${diff.inDays} أيام';
  if (diff.inDays < 30) return 'من ${diff.inDays ~/ 7} أسبوع';
  if (diff.inDays < 365) return 'من ${diff.inDays ~/ 30} شهر';
  return 'من ${diff.inDays ~/ 365} سنة';
}

String durationSpan(DateTime start) {
  final diff = DateTime.now().difference(start);
  if (diff.inDays < 7) return '${diff.inDays} أيام';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7} أسابيع';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} شهور';
  return '${diff.inDays ~/ 365} سنين';
}

// ---- Sanity fetch -----------------------------------------------------------

const _query = '''
*[_type == "intercedeEntity"]{_id, name, note, createdAt, _createdAt,
  "prayers": *[_type == "intercedePrayer" && entity._ref == ^._id]
    {_id, title, startedAt, completedAt, outcome, logs}}
''';

DateTime? _parseDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String _nowUtc() => DateTime.now().toUtc().toIso8601String();

List<PrayerLog> _parseLogs(dynamic raw) {
  if (raw is! List) return [];
  final logs = raw
      .whereType<Map<String, dynamic>>()
      .where((m) => m['prayedAt'] != null)
      .map((m) => PrayerLog(
            prayedAt: _parseDate(m['prayedAt'])!,
            note: m['note']?.toString(),
          ))
      .toList();
  logs.sort((a, b) => b.prayedAt.compareTo(a.prayedAt));
  return logs;
}

Prayer _parsePrayer(Map<String, dynamic> m) => Prayer(
      id: m['_id'] as String,
      title: (m['title'] ?? '').toString(),
      startedAt: _parseDate(m['startedAt']),
      completedAt: _parseDate(m['completedAt']),
      outcome: m['outcome']?.toString(),
      logs: _parseLogs(m['logs']),
    );

Entity _parseEntity(Map<String, dynamic> m) {
  final rawPrayers = m['prayers'] as List? ?? [];
  return Entity(
    id: m['_id'] as String,
    name: (m['name'] ?? '').toString(),
    note: m['note']?.toString(),
    createdAt: _parseDate(m['createdAt'] ?? m['_createdAt']),
    prayers: rawPrayers
        .whereType<Map<String, dynamic>>()
        .map(_parsePrayer)
        .toList(),
  );
}

Future<List<Entity>> fetchEntities() async {
  final uri = Uri.parse(
          'https://$_projectId.api.sanity.io/$_apiVersion/data/query/$_dataset')
      .replace(queryParameters: {'query': _query});
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('Sanity ${res.statusCode}');
  final result =
      (jsonDecode(res.body)['result'] as List).cast<Map<String, dynamic>>();
  return result.map(_parseEntity).toList();
}

// ---- Sanity mutate ----------------------------------------------------------

Future<void> _mutate(List<Map<String, dynamic>> mutations) async {
  if (_writeToken.isEmpty) {
    throw Exception('مفيش Sanity write token متظبط.');
  }
  final uri = Uri.parse(
      'https://$_projectId.api.sanity.io/$_apiVersion/data/mutate/$_dataset?returnIds=true');
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

String _key() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random();
  return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
}

// ---- entity CRUD ------------------------------------------------------------

Future<void> addEntity(String name, {String? note}) => _mutate([
      {
        'create': {
          '_type': 'intercedeEntity',
          'name': name,
          if (note != null && note.isNotEmpty) 'note': note,
          'createdAt': _nowUtc(),
        }
      }
    ]);

Future<void> editEntity(String id, String name, {String? note}) => _mutate([
      {
        'patch': {
          'id': id,
          'set': {
            'name': name,
            'note': note ?? '',
          },
        }
      }
    ]);

Future<void> deleteEntity(Entity e) => _mutate([
      for (final p in e.prayers) {'delete': {'id': p.id}},
      {'delete': {'id': e.id}},
    ]);

// ---- prayer CRUD ------------------------------------------------------------

Future<void> addPrayer(String entityId, String title,
        {DateTime? startedAt}) =>
    _mutate([
      {
        'create': {
          '_type': 'intercedePrayer',
          'title': title,
          'entity': {'_type': 'reference', '_ref': entityId},
          'startedAt': (startedAt ?? DateTime.now()).toUtc().toIso8601String(),
        }
      }
    ]);

Future<void> editPrayer(String id, String title) => _mutate([
      {
        'patch': {
          'id': id,
          'set': {'title': title},
        }
      }
    ]);

Future<void> deletePrayer(String id) => _mutate([
      {'delete': {'id': id}}
    ]);

Future<void> logPrayed(List<String> prayerIds, {String? note}) => _mutate([
      for (final id in prayerIds)
        {
          'patch': {
            'id': id,
            'setIfMissing': {'logs': []},
            'insert': {
              'after': 'logs[-1]',
              'items': [
                {
                  '_key': _key(),
                  '_type': 'prayerLog',
                  'prayedAt': _nowUtc(),
                  if (note != null && note.isNotEmpty) 'note': note,
                }
              ],
            },
          }
        }
    ]);

Future<void> completePrayer(String id, {String? outcome}) => _mutate([
      {
        'patch': {
          'id': id,
          'set': {
            'completedAt': _nowUtc(),
            if (outcome != null && outcome.isNotEmpty) 'outcome': outcome,
          },
        }
      }
    ]);

Future<void> reopenPrayer(String id) => _mutate([
      {
        'patch': {
          'id': id,
          'unset': ['completedAt'],
        }
      }
    ]);


// ---- cross-entity views -----------------------------------------------------

/// A prayer together with the entity it belongs to, for the flat lists that
/// cut across entities (the daily checklist and the archive).
class EntityPrayer {
  EntityPrayer(this.entity, this.prayer);
  final Entity entity;
  final Prayer prayer;
}

/// Every active prayer, not-yet-prayed-today first (most neglected at the very
/// top), then today's done ones newest-first so the list empties as you go.
List<EntityPrayer> openPrayers(List<Entity> entities) {
  final pending = <EntityPrayer>[];
  final done = <EntityPrayer>[];
  for (final e in entities) {
    for (final p in e.prayers) {
      if (p.isDone) continue;
      (p.prayedToday ? done : pending).add(EntityPrayer(e, p));
    }
  }
  pending.sort((a, b) {
    final al = a.prayer.lastPrayedAt, bl = b.prayer.lastPrayedAt;
    if (al == null && bl == null) {
      return a.prayer.title.compareTo(b.prayer.title);
    }
    if (al == null) return -1; // never prayed = most neglected
    if (bl == null) return 1;
    return al.compareTo(bl);
  });
  done.sort((a, b) => b.prayer.lastPrayedAt!.compareTo(a.prayer.lastPrayedAt!));
  return [...pending, ...done];
}

/// Every completed prayer across all entities, most recently answered first.
List<EntityPrayer> answeredPrayers(List<Entity> entities) {
  final all = <EntityPrayer>[];
  for (final e in entities) {
    for (final p in e.prayers) {
      if (p.isDone) all.add(EntityPrayer(e, p));
    }
  }
  all.sort((a, b) => b.prayer.completedAt!.compareTo(a.prayer.completedAt!));
  return all;
}
