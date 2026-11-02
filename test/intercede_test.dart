import 'package:flutter_test/flutter_test.dart';
import 'package:aio/features/intercede/data/models.dart';

void main() {
  group('relativeDate', () {
    test('returns "دلوقتي" for just now', () {
      expect(relativeDate(DateTime.now()), 'دلوقتي');
    });

    test('returns minutes for recent times', () {
      final fiveMinAgo = DateTime.now().subtract(const Duration(minutes: 5));
      expect(relativeDate(fiveMinAgo), 'من 5 دقيقة');
    });

    test('returns hours for same-day', () {
      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));
      expect(relativeDate(threeHoursAgo), 'من 3 ساعة');
    });

    test('returns "من إمبارح" for yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(relativeDate(yesterday), 'من إمبارح');
    });

    test('returns days for this week', () {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      expect(relativeDate(threeDaysAgo), 'من 3 أيام');
    });

    test('returns weeks for 14 days ago', () {
      final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
      expect(relativeDate(twoWeeksAgo), 'من 2 أسبوع');
    });

    test('returns months for 60 days ago', () {
      final twoMonthsAgo = DateTime.now().subtract(const Duration(days: 60));
      expect(relativeDate(twoMonthsAgo), 'من 2 شهر');
    });

    test('returns years for 400 days ago', () {
      final overAYear = DateTime.now().subtract(const Duration(days: 400));
      expect(relativeDate(overAYear), 'من 1 سنة');
    });
  });

  group('Entity.active ordering', () {
    test('never-prayed prayers come first, then oldest-last-prayed', () {
      final now = DateTime.now();
      final entity = Entity(
        id: 'e1',
        name: 'test',
        prayers: [
          Prayer(
            id: 'p1',
            title: 'recent',
            logs: [PrayerLog(prayedAt: now)],
          ),
          Prayer(id: 'p2', title: 'never-prayed', logs: []),
          Prayer(
            id: 'p3',
            title: 'old',
            logs: [PrayerLog(prayedAt: now.subtract(const Duration(days: 10)))],
          ),
        ],
      );

      final active = entity.active;
      expect(active.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
    });
  });

  group('openPrayers', () {
    test('all modes keep pending pins first and prayed pins last', () {
      final day = DateTime(2026, 11, 2, 12);
      final data = [
        Entity(
          id: 'e',
          name: 'اسم',
          prayers: [
            Prayer(id: 'normal', title: 'ألف'),
            Prayer(id: 'pin', title: 'ياء', pinned: true),
            Prayer(
              id: 'done',
              title: 'باء',
              pinned: true,
              logs: [PrayerLog(prayedAt: day)],
            ),
            Prayer(id: 'archive', title: 'قديم', completedAt: day),
          ],
        ),
      ];
      for (final mode in PrayerSort.values) {
        expect(
          openPrayers(data, sort: mode, now: day).map((i) => i.prayer.id),
          ['pin', 'normal', 'done'],
        );
      }
    });
    test('random is stable within a day and changes across days', () {
      final prayers = List.generate(
        30,
        (i) => Prayer(id: 'intercedePrayer.${i * 7919}abcdefgh', title: '$i'),
      );
      List<String> order(List<Prayer> values, int day) => openPrayers([
        Entity(id: 'e', name: 'اسم', prayers: values),
      ], now: DateTime(2026, 11, day)).map((i) => i.prayer.id).toList();
      expect(order(prayers, 2), order(prayers.reversed.toList(), 2));
      expect(order(prayers, 2).take(5), isNot(order(prayers, 3).take(5)));
      expect(PrayerSort.fromName('invalid'), PrayerSort.random);
    });
    test('date modes put missing dates last and alphabetical folds Arabic', () {
      final data = [
        Entity(
          id: 'e',
          name: 'اسم',
          prayers: [
            Prayer(id: 'a', title: 'إيمان', startedAt: DateTime(2020)),
            Prayer(id: 'b', title: 'ايمان', startedAt: DateTime(2025)),
            Prayer(id: 'c', title: 'باء'),
          ],
        ),
      ];
      expect(
        openPrayers(data, sort: PrayerSort.oldest).map((i) => i.prayer.id),
        ['a', 'b', 'c'],
      );
      expect(
        openPrayers(data, sort: PrayerSort.newest).map((i) => i.prayer.id),
        ['b', 'a', 'c'],
      );
      expect(
        openPrayers(
          data,
          sort: PrayerSort.alphabetical,
        ).map((i) => i.prayer.id),
        ['a', 'b', 'c'],
      );
    });
    test('default ordering is shuffled rather than alphabetical', () {
      final prayers = List.generate(
        30,
        (i) => Prayer(
          id: 'intercedePrayer.${i.toString().padLeft(12, '0')}',
          title: i.toString().padLeft(2, '0'),
        ),
      );
      final result = openPrayers([
        Entity(id: 'e', name: 'اسم', prayers: prayers),
      ]);
      expect(
        result.map((i) => i.prayer.id).toList(),
        isNot(prayers.map((p) => p.id).toList()),
      );
    });
    test('today\'s done ones sink below the ones still pending', () {
      final now = DateTime.now();
      final entities = [
        Entity(
          id: 'e1',
          name: 'andrew',
          prayers: [
            Prayer(
              id: 'done-today',
              title: 'done',
              logs: [PrayerLog(prayedAt: now)],
            ),
            Prayer(
              id: 'stale',
              title: 'stale',
              logs: [
                PrayerLog(prayedAt: now.subtract(const Duration(days: 30))),
              ],
            ),
          ],
        ),
        Entity(
          id: 'e2',
          name: 'youssef',
          prayers: [
            Prayer(id: 'never', title: 'never', logs: []),
            Prayer(
              id: 'completed',
              title: 'archived',
              completedAt: now,
              logs: [],
            ),
          ],
        ),
      ];

      // never-prayed, then the stalest, then today's — and nothing completed.
      expect(
        openPrayers(
          entities,
          sort: PrayerSort.neglected,
        ).map((i) => i.prayer.id).toList(),
        ['never', 'stale', 'done-today'],
      );
      expect(answeredPrayers(entities).map((i) => i.prayer.id).toList(), [
        'completed',
      ]);
    });
  });
}
