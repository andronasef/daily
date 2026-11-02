import 'dart:convert';

import 'package:aio/core/settings.dart';
import 'package:aio/features/intercede/data/models.dart';
import 'package:aio/features/intercede/data/store.dart';
import 'package:aio/features/intercede/data/widget_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBridge extends IntercedeWidgetBridge {
  List<WidgetPrayerTap> taps = [];
  List<List<String>> acknowledgments = [];
  bool failAck = false;
  void Function()? beforeAck;
  String? snapshot;
  @override
  Future<void> publish(String value) async {
    snapshot = value;
  }

  @override
  Future<List<WidgetPrayerTap>> peek() async => List.of(taps);
  @override
  Future<void> ack(List<String> keys) async {
    if (failAck) throw StateError('ack failed');
    beforeAck?.call();
    acknowledgments.add(keys);
    taps.removeWhere((t) => keys.contains(t.key));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  test('snapshot retains every ordered prayer and shared pinned count', () {
    final entities = [
      Entity(
        id: 'e',
        name: 'ماما',
        prayers: [
          for (var i = 0; i < 8; i++)
            Prayer(id: 'p$i', title: 'طلب $i', pinned: i == 7),
        ],
      ),
    ];
    final items =
        (jsonDecode(intercedeWidgetSnapshot(entities)) as Map)['items'] as List;
    expect(items, hasLength(8));
    expect(items.first['id'], 'p7');
    expect(items.where((i) => i['c'] == true), hasLength(1));
    expect(items.first['e'], 'ماما');
  });

  test('native event validation rejects malformed selectors and times', () {
    expect(
      WidgetPrayerTap.parse({'k': 'bad"key', 'id': 'p1', 'at': 1}),
      isNull,
    );
    expect(WidgetPrayerTap.parse({'k': 'good', 'id': 'p1', 'at': -1}), isNull);
  });

  test(
    'failed save retains tap, cold restart replays durable outbox',
    () async {
      final bridge = FakeBridge();
      final tap = WidgetPrayerTap(
        'event1',
        'p1',
        DateTime(2026, 11, 1, 23, 59),
      );
      bridge.taps = [tap];
      final disk = <String, String>{
        'intercede:entities': jsonEncode([
          {
            '_id': 'e',
            'name': 'ماما',
            'prayers': [
              {'_id': 'p1', 'title': 'صحتها'},
            ],
          },
        ]),
      };
      var failEntities = true;
      IntercedeStore store() => IntercedeStore.forTesting(
        readCache: (key) => disk[key],
        writeCache: (key, value) async {
          if (key == 'intercede:entities' && failEntities) {
            throw StateError('disk');
          }
          disk[key] = value;
        },
        fetch: () async => throw StateError('offline'),
        send: (_) async {},
        canWrite: () => false,
        bridge: bridge,
      );
      await store().load();
      expect(bridge.acknowledgments, isEmpty);
      expect(disk['intercede:outbox'], contains('event1'));
      failEntities = false;
      final restarted = store();
      await restarted.load();
      expect(bridge.taps, isEmpty);
      expect(
        restarted.entities.value!.single.prayers.single.logs.single.prayedAt,
        tap.at,
      );
      expect(jsonDecode(disk['intercede:outbox']!) as List, hasLength(1));
    },
  );

  test(
    'lost ack redelivers without duplicate logs and preserves concurrent taps',
    () async {
      final bridge = FakeBridge()..failAck = true;
      final at = DateTime(2026, 11, 1, 23, 59);
      bridge.taps = [WidgetPrayerTap('event1', 'p1', at)];
      final disk = <String, String>{
        'intercede:entities': jsonEncode([
          {
            '_id': 'e',
            'name': 'ماما',
            'prayers': [
              {'_id': 'p1', 'title': 'صحتها'},
            ],
          },
        ]),
      };
      final store = IntercedeStore.forTesting(
        readCache: (k) => disk[k],
        writeCache: (k, v) async {
          disk[k] = v;
        },
        fetch: () async => throw StateError('offline'),
        send: (_) async {},
        canWrite: () => false,
        bridge: bridge,
      );
      await store.load();
      expect(bridge.taps, hasLength(1));
      bridge.failAck = false;
      bridge.beforeAck = () =>
          bridge.taps.add(WidgetPrayerTap('event2', 'p1', at));
      await store.onResume();
      expect(bridge.taps.map((t) => t.key), ['event2']);
      expect(store.entities.value!.single.prayers.single.logs, hasLength(1));
      expect(jsonDecode(disk['intercede:outbox']!) as List, hasLength(1));
    },
  );

  test(
    'unavailable cache defers unknown taps until authoritative refresh',
    () async {
      final bridge = FakeBridge()
        ..taps = [WidgetPrayerTap('event1', 'deleted', DateTime(2026))];
      final disk = <String, String>{};
      var online = false;
      final store = IntercedeStore.forTesting(
        readCache: (k) => disk[k],
        writeCache: (k, v) async {
          disk[k] = v;
        },
        fetch: () async {
          if (!online) throw StateError('offline');
          return [];
        },
        send: (_) async {},
        canWrite: () => false,
        bridge: bridge,
      );
      await store.load();
      expect(bridge.taps, hasLength(1));
      online = true;
      await store.refresh();
      expect(bridge.taps, isEmpty);
      expect(store.hasPending, false);
    },
  );
}
