import 'package:flutter_test/flutter_test.dart';
import 'package:aio/intercede_content.dart';

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
      final threeHoursAgo =
          DateTime.now().subtract(const Duration(hours: 3));
      expect(relativeDate(threeHoursAgo), 'من 3 ساعة');
    });

    test('returns "من إمبارح" for yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(relativeDate(yesterday), 'من إمبارح');
    });

    test('returns days for this week', () {
      final threeDaysAgo =
          DateTime.now().subtract(const Duration(days: 3));
      expect(relativeDate(threeDaysAgo), 'من 3 أيام');
    });

    test('returns weeks for 14 days ago', () {
      final twoWeeksAgo =
          DateTime.now().subtract(const Duration(days: 14));
      expect(relativeDate(twoWeeksAgo), 'من 2 أسبوع');
    });

    test('returns months for 60 days ago', () {
      final twoMonthsAgo =
          DateTime.now().subtract(const Duration(days: 60));
      expect(relativeDate(twoMonthsAgo), 'من 2 شهر');
    });

    test('returns years for 400 days ago', () {
      final overAYear =
          DateTime.now().subtract(const Duration(days: 400));
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
          Prayer(
            id: 'p2',
            title: 'never-prayed',
            logs: [],
          ),
          Prayer(
            id: 'p3',
            title: 'old',
            logs: [
              PrayerLog(prayedAt: now.subtract(const Duration(days: 10)))
            ],
          ),
        ],
      );

      final active = entity.active;
      expect(active.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
    });
  });

  group('openPrayers', () {
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
        openPrayers(entities).map((i) => i.prayer.id).toList(),
        ['never', 'stale', 'done-today'],
      );
      expect(
        answeredPrayers(entities).map((i) => i.prayer.id).toList(),
        ['completed'],
      );
    });
  });
}
