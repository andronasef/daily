import 'dart:math' as math;
import '../data/memorize_models.dart';

/// Implementation of the Anki / SuperMemo-2 (SM-2) Spaced Repetition Algorithm.
///
/// Designed to space verse reviews efficiently:
/// - Again (من الأول): resets repetition, interval = 1 day, lowers ease factor.
/// - Hard (صعب): slight interval increase (x1.2), slightly lowers ease factor.
/// - Good (جيد): standard progression based on ease factor.
/// - Easy (سهل): boosted interval (x1.3 bonus), increases ease factor.
class AnkiEngine {
  const AnkiEngine._();

  static const double minEaseFactor = 1.3;
  static const double initialEaseFactor = 2.5;
  static const int masteryThresholdDays = 30;

  /// Calculates the next [MemorizeVerse] state following a review rating.
  static MemorizeVerse calculateNextReview({
    required MemorizeVerse verse,
    required ReviewRating rating,
    DateTime? now,
  }) {
    final reviewTime = now ?? DateTime.now();
    int newRepetition = verse.repetition;
    int newInterval = verse.interval;
    double newEaseFactor = verse.easeFactor;
    int newLapses = verse.lapses;
    SrsState newState = verse.state;

    switch (rating) {
      case ReviewRating.again:
        newRepetition = 0;
        newInterval = 1;
        newEaseFactor = math.max(minEaseFactor, newEaseFactor - 0.2);
        newLapses += 1;
        newState = SrsState.learning;
        break;

      case ReviewRating.hard:
        if (newRepetition == 0) {
          newInterval = 1;
        } else {
          newInterval = math.max(1, (newInterval * 1.2).round());
        }
        newEaseFactor = math.max(minEaseFactor, newEaseFactor - 0.15);
        newState = SrsState.learning;
        break;

      case ReviewRating.good:
        if (newRepetition == 0) {
          newInterval = 1;
        } else if (newRepetition == 1) {
          newInterval = 3;
        } else {
          newInterval = math.max(1, (newInterval * newEaseFactor).round());
        }
        newRepetition += 1;
        newState = newInterval >= masteryThresholdDays
            ? SrsState.mastered
            : SrsState.review;
        break;

      case ReviewRating.easy:
        if (newRepetition == 0) {
          newInterval = 3;
        } else if (newRepetition == 1) {
          newInterval = 6;
        } else {
          newInterval = math.max(
            1,
            (newInterval * newEaseFactor * 1.3).round(),
          );
        }
        newEaseFactor += 0.15;
        newRepetition += 1;
        newState = newInterval >= masteryThresholdDays
            ? SrsState.mastered
            : SrsState.review;
        break;
    }

    final newDueDate = DateTime(
      reviewTime.year,
      reviewTime.month,
      reviewTime.day + newInterval,
      reviewTime.hour,
      reviewTime.minute,
    );

    // Calculate streak
    final newStreak = _calculateStreak(
      lastReviewed: verse.lastReviewedAt,
      now: reviewTime,
      currentStreak: verse.streak,
    );

    return verse.copyWith(
      repetition: newRepetition,
      interval: newInterval,
      easeFactor: newEaseFactor,
      dueDate: newDueDate,
      lastReviewedAt: reviewTime,
      lapses: newLapses,
      state: newState,
      streak: newStreak,
    );
  }

  static int _calculateStreak({
    required DateTime? lastReviewed,
    required DateTime now,
    required int currentStreak,
  }) {
    if (lastReviewed == null) return 1;

    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(
      lastReviewed.year,
      lastReviewed.month,
      lastReviewed.day,
    );
    final difference = today.difference(lastDay).inDays;

    if (difference == 0) {
      // Already practiced today, keep streak
      return currentStreak > 0 ? currentStreak : 1;
    } else if (difference == 1) {
      // Practiced yesterday, increment
      return currentStreak + 1;
    } else {
      // Gap > 1 day, reset streak
      return 1;
    }
  }

  /// Estimated days label for user buttons on review card
  static String estimateIntervalLabel({
    required MemorizeVerse verse,
    required ReviewRating rating,
  }) {
    switch (rating) {
      case ReviewRating.again:
        return '1 يوم';
      case ReviewRating.hard:
        final days = verse.repetition == 0
            ? 1
            : math.max(1, (verse.interval * 1.2).round());
        return '$days ${days == 1 ? "يوم" : "أيام"}';
      case ReviewRating.good:
        final days = verse.repetition == 0
            ? 1
            : (verse.repetition == 1
                ? 3
                : math.max(1, (verse.interval * verse.easeFactor).round()));
        return '$days ${days == 1 ? "يوم" : "أيام"}';
      case ReviewRating.easy:
        final days = verse.repetition == 0
            ? 3
            : (verse.repetition == 1
                ? 6
                : math.max(
                    1,
                    (verse.interval * verse.easeFactor * 1.3).round(),
                  ));
        return '$days ${days == 1 ? "يوم" : "أيام"}';
    }
  }
}
