import 'package:aio/features/memorize/data/memorize_models.dart';
import 'package:aio/features/memorize/domain/anki_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnkiEngine SM-2 Spaced Repetition', () {
    late MemorizeVerse newVerse;

    setUp(() {
      newVerse = MemorizeVerse(
        id: 'test_1',
        title: 'مزمور 23: 1',
        verse: 'الرَّبُّ رَاعِيَّ فَلاَ يَعْوِزُنِي شَيْءٌ.',
        category: 'سلام',
        createdAt: DateTime(2026, 1, 1),
        dueDate: DateTime(2026, 1, 1),
      );
    });

    test('Initial state of a new verse', () {
      expect(newVerse.state, SrsState.newCard);
      expect(newVerse.repetition, 0);
      expect(newVerse.interval, 0);
      expect(newVerse.easeFactor, 2.5);
      expect(newVerse.isDue, true);
    });

    test('Rating Again resets repetitions and sets interval to 1 day', () {
      final reviewed = AnkiEngine.calculateNextReview(
        verse: newVerse.copyWith(repetition: 4, interval: 14),
        rating: ReviewRating.again,
        now: DateTime(2026, 1, 10),
      );

      expect(reviewed.repetition, 0);
      expect(reviewed.interval, 1);
      expect(reviewed.state, SrsState.learning);
      expect(reviewed.lapses, 1);
      expect(reviewed.easeFactor, 2.3);
      expect(reviewed.dueDate.day, 11);
    });

    test('Rating Good progresses interval according to repetitions and ease factor', () {
      // First review
      final rev1 = AnkiEngine.calculateNextReview(
        verse: newVerse,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 1),
      );
      expect(rev1.repetition, 1);
      expect(rev1.interval, 1);
      expect(rev1.state, SrsState.review);

      // Second review
      final rev2 = AnkiEngine.calculateNextReview(
        verse: rev1,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 2),
      );
      expect(rev2.repetition, 2);
      expect(rev2.interval, 3);

      // Third review (3 * 2.5 = ~8 days)
      final rev3 = AnkiEngine.calculateNextReview(
        verse: rev2,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 5),
      );
      expect(rev3.repetition, 3);
      expect(rev3.interval, 8);
    });

    test('Rating Easy provides ease bonus and longer interval', () {
      final rev1 = AnkiEngine.calculateNextReview(
        verse: newVerse,
        rating: ReviewRating.easy,
        now: DateTime(2026, 1, 1),
      );
      expect(rev1.repetition, 1);
      expect(rev1.interval, 3);
      expect(rev1.easeFactor, 2.65);

      final rev2 = AnkiEngine.calculateNextReview(
        verse: rev1,
        rating: ReviewRating.easy,
        now: DateTime(2026, 1, 4),
      );
      expect(rev2.repetition, 2);
      expect(rev2.interval, 6);
    });

    test('Transition to Mastered state when interval reaches threshold', () {
      final highVerse = newVerse.copyWith(
        repetition: 5,
        interval: 20,
        easeFactor: 2.5,
      );
      final reviewed = AnkiEngine.calculateNextReview(
        verse: highVerse,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 1),
      );

      // 20 * 2.5 = 50 days >= 30 days threshold
      expect(reviewed.interval, 50);
      expect(reviewed.state, SrsState.mastered);
    });

    test('Streak increments correctly across consecutive days', () {
      final day1 = AnkiEngine.calculateNextReview(
        verse: newVerse,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 1),
      );
      expect(day1.streak, 1);

      // Practiced again on same day: streak maintained
      final sameDay = AnkiEngine.calculateNextReview(
        verse: day1,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 1),
      );
      expect(sameDay.streak, 1);

      // Practiced next day: streak increments
      final day2 = AnkiEngine.calculateNextReview(
        verse: day1,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 2),
      );
      expect(day2.streak, 2);

      // Practiced after gap > 1 day: streak resets to 1
      final afterGap = AnkiEngine.calculateNextReview(
        verse: day2,
        rating: ReviewRating.good,
        now: DateTime(2026, 1, 5),
      );
      expect(afterGap.streak, 1);
    });

    test('Words parsing extracts clean words from verse', () {
      final verse = MemorizeVerse(
        id: 'v1',
        title: 'ي1',
        verse: 'فِي الْبَدْءِ كَانَ الْكَلِمَةُ',
        createdAt: DateTime.now(),
        dueDate: DateTime.now(),
      );
      expect(verse.words, ['فِي', 'الْبَدْءِ', 'كَانَ', 'الْكَلِمَةُ']);
    });
  });
}
