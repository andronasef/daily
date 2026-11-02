---
last_mapped_commit: 988a5a4aa6f05076368c2d503e7e9348a013ae9f
last_mapped_at: 2026-11-02
---
# Testing Patterns

**Analysis Date:** 2026-11-02

## Test Framework

**Runner:**
- `flutter_test` (SDK package, declared in `pubspec.yaml` under `dev_dependencies`)
- Config: none beyond the default. `analysis_options.yaml` covers static analysis only.

**Assertion Library:**
- `flutter_test` matchers: `expect`, `isTrue`, `isFalse`, `isEmpty`, `isNot`, `inInclusiveRange`, `startsWith`, `containsKey`-style checks via `.containsKey(...)`.

**Mocking:** none. No `mockito`, `mocktail`, or `fake` packages are in `pubspec.yaml`, and no `setMockInitialValues` calls exist in `test/`.

**Run Commands:**

```bash
flutter test                              # Run all tests in test/
flutter test test/anki_engine_test.dart   # Run one file
flutter test --name "Rating Again"        # Run tests whose name matches
flutter analyze                           # Static analysis (not part of CI)
```

Coverage is not configured. There is no `flutter test --coverage` step in the repo.

## Test File Organization

**Location:**
- All tests live in a flat `test/` directory at the project root. There is no co-location with `lib/` and no `integration_test/` directory.

**Naming:**
- `*_test.dart` suffix. Current files:
  - `test/anki_engine_test.dart` (SM-2 scheduling, `lib/features/memorize/domain/anki_engine.dart`)
  - `test/intercede_store_test.dart` (outbox mutation replay, `lib/features/intercede/data/store.dart`)
  - `test/intercede_test.dart` (relative dates and prayer ordering, `lib/features/intercede/data/models.dart`)
  - `test/search_test.dart` (Arabic-aware matching, `lib/core/format/arabic.dart`)
  - `test/widget_test.dart` (leyaana daily-pick hashing, `lib/features/leyaana/data/daily_pick.dart`)

**Caveat:** `test/widget_test.dart` is the Flutter template name but contains no widget test. It tests `daily_pick.dart`. Rename it (for example to `test/daily_pick_test.dart`) before adding real widget tests, so the name stays accurate.

**Structure:**

```
test/
├── anki_engine_test.dart
├── intercede_store_test.dart
├── intercede_test.dart
├── search_test.dart
└── widget_test.dart
```

Place a new unit test next to its feature in name and mirror the `lib/` path in the file name. A new test for `lib/features/journal/data/journal_db.dart` goes in `test/journal_db_test.dart`.

## Test Structure

**Suite Organization:**
Group by the unit under test. Use `group` for the subject and `test` for each behaviour. Name tests as sentences that state the expected outcome:

```dart
// test/anki_engine_test.dart
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

    test('Rating Again resets repetitions and sets interval to 1 day', () {
      ...
    });
  });
}
```

Test names are written in English. Test data is in Arabic. Keep it that way: the fixtures should reflect real user content.

**Patterns:**
- Use `setUp` for a shared model fixture (`anki_engine_test.dart`). Use `late` for the field.
- Use a top-level fixture function for shaped JSON that matches the Sanity `_query` payload (`fixture()` in `test/intercede_store_test.dart`). Return a fresh value per call so tests do not share mutable state.
- Use a small helper to reach nested data (`prayer(json)` in `test/intercede_store_test.dart`).
- Build inputs explicitly with fixed dates (`DateTime(2026, 1, 1)`, `DateTime.utc(2026, 7, 24, 12)`) and pass `now:` into logic that accepts it. Do not depend on the wall clock for logic tests.
- Use `inInclusiveRange` for bounded random or hashed output, and assert determinism by calling twice (`pickIndex(...)` in `test/widget_test.dart`).

**Assertion pattern for state transitions:** assert every changed field, not only the headline one. The SM-2 test checks `repetition`, `interval`, `state`, `lapses`, `easeFactor`, and `dueDate.day` together. Follow this when you add rules.

## Mocking

**Framework:** none. Tests use plain values and pure functions.

**What to test without mocks:**
- Pure logic: `AnkiEngine.calculateNextReview`, `applyMutation`, `matchesQuery`, `relativeDate`, `pickIndex`.
- Model behaviour: `Prayer.prayedToday`, `Entity.active` ordering.

**What is not covered and needs a seam first:**
- `sanityQuery` and `sanityMutate` (`lib/core/sanity/client.dart`) call `http` directly. To test the flush and refresh paths in `IntercedeStore`, first pass an `http.Client` in, or extract the HTTP call behind a function that tests can replace. Do not add `mockito` for one case. Prefer a plain function parameter or a top-level `var` override.
- `Settings` (`lib/core/settings.dart`) is a `SharedPreferences` singleton. For tests that touch it, call `SharedPreferences.setMockInitialValues({})` in `setUp` (the standard `shared_preferences` test hook), then `await Settings.init()`. No existing test does this yet.
- `MemorizeDb` (`lib/features/memorize/data/memorize_db.dart`) uses sqflite. Needs `sqflite_common_ffi` for host tests. It is not in `pubspec.yaml`. Add it only when you need DB-level tests.
- Notifications and background work (`lib/core/notifications.dart`, `lib/core/background.dart`) use platform channels. Test them on device, not in unit tests.

**What to mock (when you add a mock):** platform channels, network clients, and the clock (inject `DateTime? now` as `AnkiEngine` already does).

**What NOT to mock:** pure functions and value classes. Their inputs are cheap to build.

## Fixtures and Factories

**Test Data:**
- Inline factory functions returning `Map<String, dynamic>` or model instances. Shape them to match the production payload exactly; `test/intercede_store_test.dart` says so in its comment: "in the exact shape the `_query` GROQ returns".
- For models, construct directly with named parameters (`MemorizeVerse(id: ..., dueDate: ...)`) and derive variants with `copyWith` (`newVerse.copyWith(repetition: 4, interval: 14)`).
- Use real Arabic text, including diacritics (`'الرَّبُّ رَاعِيَّ'`), to exercise normalization (see `test/search_test.dart`, "harakat in the stored text do not block a plain query").

**Location:**
- Fixtures are defined in the test file that uses them. No shared `test/fixtures/` or `test/helpers/` directory exists. Move a fixture into `test/helpers/` only when two test files need it.

## Coverage

**Requirements:** none enforced. No coverage threshold in CI or config.

**View coverage (if needed):**

```bash
flutter test --coverage

# then, optionally, with lcov installed:

genhtml coverage/lcov.info -o coverage/html
```

**Current gaps (most significant first):**
- No widget tests (`testWidgets` count is 0). No screen or widget under `lib/features/*/ui/` is tested.
- `IntercedeStore.flush` and `refresh` retry/ordering logic is not exercised end to end. Only `applyMutation` is tested.
- `MemorizeRepository` (`lib/features/memorize/data/memorize_repository.dart`) has no tests. It has the most complex outbox and reconciliation logic in the app.
- `lib/features/memorize/data/audio_service.dart`, `lib/core/updater.dart`, `lib/core/background.dart`, and `lib/core/notifications.dart` have no tests.
- `lib/features/journal/` has no tests.

## Test Types

**Unit Tests:**
- Everything in `test/` today. Scope: one pure function or model per test file. Run in milliseconds. No device needed.

**Widget Tests:**
- Not used yet. When adding one, use `testWidgets` with `tester.pumpWidget(MaterialApp(home: ...))`. Wrap the widget with `Localizations` / `Directionality` for Arabic, or set `locale: const Locale('ar')` as `lib/app/app.dart` does. Keep `Settings.init()` and sqflite out of widget tests, or mock them.

**Integration Tests:**
- Not used. No `integration_test/` directory exists. For on-device checks, see the Argent tooling referenced in the project rules rather than adding `integration_test` by default.

**E2E Tests:**
- Not used in this repo.

## Continuous Integration

- `.github/workflows/release.yml` builds the signed release APK on tag push. It does not run `flutter test` or `flutter analyze`. A failing test will not block a release.
- Before tagging a release, run `flutter test` and `flutter analyze` locally. Consider adding a `flutter test` step to `release.yml` before the build step.

## Common Patterns

**Pure logic test with a fixed clock:**

```dart
test('Rating Good progresses interval according to repetitions and ease factor', () {
  final rev1 = AnkiEngine.calculateNextReview(
    verse: newVerse,
    rating: ReviewRating.good,
    now: DateTime(2026, 1, 1),
  );
  expect(rev1.repetition, 1);
  expect(rev1.interval, 1);
  expect(rev1.state, SrsState.review);
});
```

**Mutation replay (state change over a list):**

```dart
test('delete removes a nested prayer, and an entity with its prayers', () {
  final json = fixture();
  applyMutation(json, {'delete': {'id': 'p1'}});
  expect(json.first['prayers'], isEmpty);
});
```

**Idempotency check:** call the operation twice and assert the list length did not change (`createIfNotExists` in `test/intercede_store_test.dart`).

**Determinism check:** call a hashed or seeded function twice with the same input and assert equality (`pickIndex` in `test/widget_test.dart`).

**Boundary and time-sensitive assertions:** `test/intercede_test.dart` builds times from `DateTime.now().subtract(...)`. These tests pass today, but they can fail near midnight or across a DST change. Prefer injecting `now` into `relativeDate` and passing a fixed value, the way `AnkiEngine` does, when you touch this code.

**Error path test:** not yet established in this repo. For a new error path, assert the returned or published state instead of a thrown exception. `IntercedeStore.failed` is the model to follow.

**Async testing:** no async tests exist yet. Use `async` test bodies with `await` and `expect(() async => ..., throwsA(...))` for thrown `Exception`s from `lib/core/sanity/client.dart`. Use `fakeAsync` from `package:fake_async` only if you need to control timers (`refresh` and `flush` use `unawaited`).

## Sanity Studio tests

`sanity/` has no test files of its own. Its `node_modules/` contains third-party tests that are not part of this project. Do not run them as project tests.

---

*Testing analysis: 2026-11-02*
