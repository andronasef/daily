import 'dart:math';

import '../../../core/sanity/client.dart';
import 'models.dart';

// ponytail: network-only, no local cache — intercede data is small and
// write-heavy; staleness would be more confusing than a spinner. Ceiling:
// add Settings-based cache like leyaana_content.dart if latency hurts.

bool get intercedeCanEdit => sanityCanWrite;

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
      .map(
        (m) => PrayerLog(
          prayedAt: _parseDate(m['prayedAt'])!,
          note: m['note']?.toString(),
        ),
      )
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
  final result = await sanityQuery(_query, cdn: false);
  return result.map(_parseEntity).toList();
}

String _key() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random();
  return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
}

// ---- entity CRUD ------------------------------------------------------------

Future<void> addEntity(String name, {String? note}) => sanityMutate([
  {
    'create': {
      '_type': 'intercedeEntity',
      'name': name,
      if (note != null && note.isNotEmpty) 'note': note,
      'createdAt': _nowUtc(),
    },
  },
]);

Future<void> editEntity(String id, String name, {String? note}) =>
    sanityMutate([
      {
        'patch': {
          'id': id,
          'set': {'name': name, 'note': note ?? ''},
        },
      },
    ]);

Future<void> deleteEntity(Entity e) => sanityMutate([
  for (final p in e.prayers)
    {
      'delete': {'id': p.id},
    },
  {
    'delete': {'id': e.id},
  },
]);

// ---- prayer CRUD ------------------------------------------------------------

Future<void> addPrayer(String entityId, String title, {DateTime? startedAt}) =>
    sanityMutate([
      {
        'create': {
          '_type': 'intercedePrayer',
          'title': title,
          'entity': {'_type': 'reference', '_ref': entityId},
          'startedAt': (startedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
      },
    ]);

Future<void> editPrayer(String id, String title) => sanityMutate([
  {
    'patch': {
      'id': id,
      'set': {'title': title},
    },
  },
]);

Future<void> deletePrayer(String id) => sanityMutate([
  {
    'delete': {'id': id},
  },
]);

Future<void> logPrayed(List<String> prayerIds, {String? note}) => sanityMutate([
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
            },
          ],
        },
      },
    },
]);

Future<void> completePrayer(String id, {String? outcome}) => sanityMutate([
  {
    'patch': {
      'id': id,
      'set': {
        'completedAt': _nowUtc(),
        if (outcome != null && outcome.isNotEmpty) 'outcome': outcome,
      },
    },
  },
]);

Future<void> reopenPrayer(String id) => sanityMutate([
  {
    'patch': {
      'id': id,
      'unset': ['completedAt'],
    },
  },
]);
