import 'dart:math';

import '../../../core/sanity/client.dart';
import 'models.dart';
import 'store.dart';

// ponytail: offline-first. Reads come from IntercedeStore's disk cache and
// refresh in the background; writes apply locally and queue in its outbox
// until they reach Sanity. Ceiling: the outbox flushes on app resume and on
// every action — add connectivity_plus or a workmanager job if queued actions
// sit too long.

bool get intercedeCanEdit => sanityCanWrite;

// ---- Sanity fetch -----------------------------------------------------------

const _query = '''
*[_type == "intercedeEntity"]{_id, name, note, createdAt, _createdAt,
  "prayers": *[_type == "intercedePrayer" && entity._ref == ^._id]
    {_id, title, startedAt, completedAt, outcome, pinned, logs}}
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
  pinned: m['pinned'] == true,
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

/// Raw `_query` payload, cached verbatim by [IntercedeStore].
Future<List<Map<String, dynamic>>> fetchEntitiesRaw() =>
    sanityQuery(_query, cdn: false);

List<Entity> parseEntities(List<Map<String, dynamic>> raw) =>
    raw.map(_parseEntity).toList();

String _key() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random();
  return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
}

// ---- entity CRUD ------------------------------------------------------------

Future<void> addEntity(String name, {String? note}) =>
    IntercedeStore.instance.apply([
      {
        'createIfNotExists': {
          '_id': 'intercedeEntity.${_key()}',
          '_type': 'intercedeEntity',
          'name': name,
          if (note != null && note.isNotEmpty) 'note': note,
          'createdAt': _nowUtc(),
        },
      },
    ]);

Future<void> editEntity(String id, String name, {String? note}) =>
    IntercedeStore.instance.apply([
      {
        'patch': {
          'id': id,
          'set': {'name': name, 'note': note ?? ''},
        },
      },
    ]);

Future<void> deleteEntity(Entity e) => IntercedeStore.instance.apply([
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
    IntercedeStore.instance.apply([
      {
        // Client-generated id: the queued create is idempotent, and a patch
        // queued behind it can target the doc before Sanity has seen it.
        'createIfNotExists': {
          '_id': 'intercedePrayer.${_key()}',
          '_type': 'intercedePrayer',
          'title': title,
          'entity': {'_type': 'reference', '_ref': entityId},
          'startedAt': (startedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
      },
    ]);

Future<void> editPrayer(String id, String title) =>
    IntercedeStore.instance.apply([
      {
        'patch': {
          'id': id,
          'set': {'title': title},
        },
      },
    ]);

Future<void> setPinned(String id, bool pinned) =>
    IntercedeStore.instance.apply([
      {
        'patch': {
          'id': id,
          'set': {'pinned': pinned},
        },
      },
    ]);

Future<void> deletePrayer(String id) => IntercedeStore.instance.apply([
  {
    'delete': {'id': id},
  },
]);

Future<void> logPrayed(List<String> prayerIds, {String? note}) =>
    IntercedeStore.instance.apply([
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

Future<void> completePrayer(String id, {String? outcome}) =>
    IntercedeStore.instance.apply([
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

Future<void> reopenPrayer(String id) => IntercedeStore.instance.apply([
  {
    'patch': {
      'id': id,
      'unset': ['completedAt'],
    },
  },
]);
