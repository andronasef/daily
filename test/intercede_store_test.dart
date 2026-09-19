import 'package:aio/features/intercede/data/repository.dart';
import 'package:aio/features/intercede/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

/// One entity with one prayer, in the exact shape the `_query` GROQ returns.
List<Map<String, dynamic>> fixture() => [
  {
    '_id': 'e1',
    'name': 'ماما',
    'prayers': <Map<String, dynamic>>[
      {'_id': 'p1', 'title': 'صحتها', 'pinned': false},
    ],
  },
];

Map<String, dynamic> prayer(List<Map<String, dynamic>> json) =>
    (json.first['prayers'] as List).first as Map<String, dynamic>;

void main() {
  test('patch set pins a nested prayer', () {
    final json = fixture();
    applyMutation(json, {
      'patch': {
        'id': 'p1',
        'set': {'pinned': true},
      },
    });
    expect(prayer(json)['pinned'], true);
  });

  test('setIfMissing + insert appends a log, creating the list', () {
    final json = fixture();
    final log = {'_key': 'k1', 'prayedAt': '2026-09-19T06:00:00.000Z'};
    void pray(Map<String, dynamic> item) => applyMutation(json, {
      'patch': {
        'id': 'p1',
        'setIfMissing': {'logs': []},
        'insert': {
          'after': 'logs[-1]',
          'items': [item],
        },
      },
    });
    pray(log);
    expect(prayer(json)['logs'], [log]);
    final log2 = {'_key': 'k2', 'prayedAt': '2026-09-19T07:00:00.000Z'};
    pray(log2);
    expect(prayer(json)['logs'], [log, log2]);
  });

  test('unset drops completedAt', () {
    final json = fixture();
    applyMutation(json, {
      'patch': {
        'id': 'p1',
        'set': {'completedAt': 'x'},
      },
    });
    applyMutation(json, {
      'patch': {
        'id': 'p1',
        'unset': ['completedAt'],
      },
    });
    expect(prayer(json).containsKey('completedAt'), false);
  });

  test('delete removes a nested prayer, and an entity with its prayers', () {
    final json = fixture();
    applyMutation(json, {
      'delete': {'id': 'p1'},
    });
    expect(json.first['prayers'], isEmpty);
    applyMutation(json, {
      'delete': {'id': 'e1'},
    });
    expect(json, isEmpty);
  });

  test('createIfNotExists lands a prayer under its referenced entity', () {
    final json = fixture();
    final doc = {
      '_id': 'p2',
      '_type': 'intercedePrayer',
      'title': 'شغلها',
      'entity': {'_type': 'reference', '_ref': 'e1'},
    };
    applyMutation(json, {'createIfNotExists': doc});
    expect((json.first['prayers'] as List).length, 2);
    // Idempotent: replaying the queued create must not duplicate it.
    applyMutation(json, {'createIfNotExists': doc});
    expect((json.first['prayers'] as List).length, 2);
  });

  test('creating an entity then a prayer under it works offline', () {
    final json = <Map<String, dynamic>>[];
    applyMutation(json, {
      'createIfNotExists': {
        '_id': 'e9',
        '_type': 'intercedeEntity',
        'name': 'بابا',
      },
    });
    applyMutation(json, {
      'createIfNotExists': {
        '_id': 'p9',
        '_type': 'intercedePrayer',
        'title': 'سلام',
        'entity': {'_ref': 'e9'},
      },
    });
    final entities = parseEntities(json);
    expect(entities.single.name, 'بابا');
    expect(entities.single.prayers.single.title, 'سلام');
  });

  test('replaying the outbox over a fresh server payload keeps local edits', () {
    final outbox = [
      {
        'patch': {
          'id': 'p1',
          'set': {'pinned': true},
        },
      },
    ];
    // Server still has pinned: false — the queued patch must win after replay.
    final fresh = fixture();
    for (final m in outbox) {
      applyMutation(fresh, m);
    }
    expect(parseEntities(fresh).single.prayers.single.pinned, true);
  });
}
