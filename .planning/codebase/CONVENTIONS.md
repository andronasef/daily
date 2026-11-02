---
last_mapped_commit: 988a5a4aa6f05076368c2d503e7e9348a013ae9f
last_mapped_at: 2026-11-02
---
# Coding Conventions

**Analysis Date:** 2026-11-02

## Scope

The app is a Flutter/Dart application (`pubspec.yaml`, name `aio`, SDK `^3.10.4`) in `lib/`. A secondary Sanity Studio project lives in `sanity/` (TypeScript, see the last section). Code comments are English; user-facing strings are Arabic (Egyptian dialect in places, e.g. `'دلوقتي'` in `lib/core/format/dates.dart`). The app's locale is set to `Locale('ar')` in `lib/app/app.dart`.

## Naming Patterns

**Files:**
- `snake_case.dart` everywhere: `lib/features/memorize/domain/anki_engine.dart`, `lib/features/intercede/ui/prayer_editor_page.dart` (ui files often end in `_screen.dart`, `_page.dart`, `_view.dart`, `_sheet.dart`).
- Feature folders follow a fixed split: `data/` (repositories, stores, models, DB), `domain/` (pure logic, e.g. `lib/features/memorize/domain/anki_engine.dart`), `ui/` (screens and widgets), with reusable widgets in `ui/widgets/` (e.g. `lib/features/intercede/ui/widgets/prayer_card.dart`) and sub-screens in `ui/practice/` (memorize).
- Models live in `*_models.dart` or `models.dart` (`lib/features/memorize/data/memorize_models.dart`, `lib/features/intercede/data/models.dart`).
- Repositories are `*_repository.dart` (`lib/features/memorize/data/memorize_repository.dart`, `lib/features/intercede/data/repository.dart`). Persistence is `*_db.dart` (`lib/features/memorize/data/memorize_db.dart`) or `store.dart` (`lib/features/intercede/data/store.dart`).

**Classes:**
- `UpperCamelCase`. Widgets are named by role: `VerseItemTile`, `PrayerCard`, `FlashcardView`, `RevealChallengeView`.
- Private helper classes use a leading underscore (about 35 `class _` declarations under `lib/`).
- Enums use lowerCamel values: `enum SrsState { newCard, learning, review, mastered }`, `enum ReviewRating { again, hard, good, easy }` (`lib/features/memorize/data/memorize_models.dart`). User-facing labels are a `String get label` with an exhaustive `switch` on `this`.

**Functions and methods:**
- `lowerCamelCase`. Private members are prefixed with `_`: `_parsePrayer`, `_applyPatch`, `_queueMutation`, `_stateColor`.
- Top-level private helpers are common in data files (`lib/features/intercede/data/repository.dart`: `_parseDate`, `_nowUtc`, `_key`, `_query`).
- Async write helpers are named as verbs on the entity: `addEntity`, `editEntity`, `deleteEntity`, `prayFor`, `refreshFromSanity`, `flushOutbox`.

**Variables and constants:**
- Module-level constants are `lowerCamelCase` with `const`, not `SCREAMING_CASE`: `const sanityProjectId = 'kfme7y2v';`, `const _cacheKey = 'intercede:entities';`, `const _envToken = String.fromEnvironment(...)` in `lib/core/sanity/client.dart`.
- Static constants inside a class are `lowerCamel` too: `AnkiEngine.minEaseFactor`, `Notifications.verseDays` (`lib/core/notifications.dart`).
- Storage keys are private `static const` strings: `static const _notifHour = 'notifHour';` in `lib/core/settings.dart`.
- Storage keys for caches use a `namespace:name` shape: `'intercede:outbox'`, `'memorize:outbox'`.

**Types:**
- No type aliases were observed in `lib/`. Models are hand-written classes with `final` fields (no `freezed`, no `json_serializable`; neither is in `pubspec.yaml`).
- Prefer `Map<String, dynamic>` for raw Sanity payloads and parse into typed models at the edge (`_parseEntity`, `_parsePrayer` in `lib/features/intercede/data/repository.dart`).

## Code Style

**Formatting:**
- `dart format` defaults (no custom `.dart` formatter config). Code is wrapped near 80 columns, with trailing commas on multi-line argument lists so the formatter splits them one per line.
- Use `const` constructors and `const` literals wherever possible: `const EdgeInsets.symmetric(vertical: 6)`, `const SnackBar(...)`, `const Duration(seconds: 15)`.
- Widget constructors use `super.key` and `required` named parameters (`lib/features/memorize/ui/widgets/verse_item_tile.dart`):
  ```dart
  const VerseItemTile({
    super.key,
    required this.verse,
    required this.onTap,
    this.onRecordVoice,
  });
  ```
- Multi-line strings for GROQ and SQL use triple-single-quoted raw strings (`const _query = '''...''';` in `lib/features/intercede/data/repository.dart`, `lib/features/memorize/data/memorize_repository.dart`).
- Indentation is 2 spaces.

**Linting:**
- `analysis_options.yaml` includes only `package:flutter_lints/flutter.yaml` (`flutter_lints: ^6.0.0`). The custom `linter.rules` section is entirely commented out. No extra rules are enabled or disabled.
- Run `flutter analyze` to check. There is no lint step in CI (`.github/workflows/release.yml` only runs `flutter pub get` and `flutter build apk --release`).
- `avoid_print` is not disabled, and the codebase has zero `print(` calls. Use `debugPrint` for diagnostics (7 uses, e.g. `lib/features/memorize/data/memorize_repository.dart`).

## Import Organization

**Order (observed in `lib/features/intercede/data/store.dart` and `lib/features/memorize/data/memorize_repository.dart`):**
1. `dart:` SDK imports (`dart:async`, `dart:convert`, `dart:io`)
2. `package:` imports (`package:flutter/foundation.dart`, `package:http/http.dart as http`, `package:sqflite/sqflite.dart`)
3. Relative imports, with siblings first in a separate group only when the file mixes layers (`import '../../../core/sanity/client.dart';` then `import 'models.dart';`).

Groups are separated by a blank line. Dart files do not use `part` directives (0 found).

**Path Aliases:**
- Inside `lib/`, use relative imports (`../../../core/settings.dart`).
- In `test/`, use the package URI: `import 'package:aio/features/memorize/domain/anki_engine.dart';`.
- Re-exports are used sparingly to keep a model's shared helpers reachable: `export '../../../core/format/dates.dart';` at the top of `lib/features/intercede/data/models.dart`.

## Error Handling

The codebase uses three deliberate patterns. Match the one that fits the call site.

**1. Offline-first, never throw to the UI.** Background refresh and flush paths swallow errors and leave work queued in an outbox:

```dart
// lib/features/intercede/data/store.dart
Future<void> refresh() async {
  await flush();
  try {
    final fresh = await fetchEntitiesRaw();
    ...
  } catch (_) {
    failed.value = _json.isEmpty;
  }
}
```

Flush loops stop at the first failure so ordering holds (`break` inside `while (_outbox.isNotEmpty)`).

**2. Throw an `Exception` with a readable message for user-initiated network calls.** `lib/core/sanity/client.dart` throws `Exception('Sanity ${res.statusCode}')` and surfaces Arabic messages when config is missing: `throw Exception('مفيش Sanity write token متظبط.');`. HTTP calls always use `.timeout(...)` (15 s for reads, 20 s for writes).

**3. Silent catch for best-effort operations.** Schema migrations and optional parsing use an empty catch:

```dart
// lib/features/memorize/data/memorize_db.dart
try {
  await db.execute('ALTER TABLE memorize_items ADD COLUMN recordings_json TEXT;');
} catch (_) {}
```

Use `catch (_)` only for best-effort work where failure is expected and harmless. There are 14 `catch (_)` sites versus 24 typed `catch (e)` sites. Prefer a typed catch with `debugPrint` when the failure is worth seeing.

**Parsing untrusted JSON:** wrap `jsonDecode` in a try and return an empty default. `_decode` in `lib/features/intercede/data/store.dart` returns `[]` on any failure. Use `whereType<Map>()` before casting.

**User feedback:** errors shown to the user go through `ScaffoldMessenger.of(context).showSnackBar(const SnackBar(...))` (22 call sites, e.g. `lib/features/settings/settings_screen.dart`). Use the `failed` `ValueNotifier` pattern for "could not load and nothing cached" states instead of a snackbar.

## Logging

**Framework:** `package:flutter/foundation.dart` `debugPrint`. No logging package is in `pubspec.yaml`.

**Patterns:**
- Log only in the outbox flush failure path, and keep messages short: `debugPrint('Sanity mutate outbox flush stopped: $e');`.
- Do not add logging to success paths.

## Comments

**When to comment:**
- Explain the why, especially for ordering, offline behaviour, and parity with the PWA. Examples: "Re-arm on launch so the schedule survives reboots / app updates." (`lib/core/notifications.dart`), and "Guards the port of temp/leyaana's daily-pick hash" (`test/widget_test.dart`).
- Mark deliberate simplifications with a `ponytail:` tag that names the ceiling and the upgrade path. 7 such tags exist, for example in `lib/features/intercede/data/store.dart`:
  ```dart
  /// ponytail: the Sanity mutation JSON is both the optimistic update and the
  /// queue entry ... Ceiling: [applyMutation] only understands the operations this app emits.
  ```
  Use the same form when you cut a corner: `// ponytail: <what was simplified>. Ceiling: <limit>. Upgrade when <condition>.`
- Section dividers in longer files use `// ---- name ----` lines (`lib/features/intercede/data/store.dart`, `lib/features/intercede/data/repository.dart`).

**JSDoc/TSDoc (Dart doc comments):**
- Use `///` on public classes and non-obvious functions. Start with a one-sentence summary. Multi-line doc comments wrap at about 80 columns.
- Do not write docs that restate the signature.
- No TODO or FIXME comments exist in `lib/` (0 found). Track open work elsewhere.

## Function Design

**Size:** Keep pure logic in `domain/` short and single-purpose (`AnkiEngine.calculateNextReview`). Large UI files (for example `lib/features/intercede/ui/intercede_screen.dart`) are split into `ui/widgets/` and sub-page files rather than kept as one long build method. Extract a private `_buildX` method or a widget class when a `build` method passes about 80 lines.

**Parameters:**
- Named parameters with `required` for anything not obvious: `calculateNextReview({required MemorizeVerse verse, required ReviewRating rating, DateTime? now})`.
- Inject time for testable logic. Pass `DateTime? now` and fall back to `DateTime.now()` inside the function (see `AnkiEngine.calculateNextReview`).
- Callbacks are typed `VoidCallback` (`final VoidCallback onTap;`), and optional callbacks are nullable.

**Return values:**
- Return immutable value objects. Use `copyWith` for updates to models (`verse.copyWith(repetition: 4, interval: 14)`).
- Return `Future<void>` for fire-and-forget writes and `unawaited(...)` for background flushes (`unawaited(flush());`).

## Module Design

**Exports:** Each file exposes top-level functions and classes. There are no barrel `index.dart` files in `lib/`.

**Singletons:**
- Use `static final instance = X._();` with a private constructor for stateful repositories and stores (`IntercedeStore.instance`, `MemorizeRepository.instance`, `AudioService.instance`).
- `Settings` uses an explicit `init()` that must be awaited before use. It throws `StateError` if `instance` is read before init. Call `await Settings.init()` in `main()` before `runApp`.
- Use `ValueNotifier<T?>` for observable state that the UI listens to (`IntercedeStore.entities`, `IntercedeStore.failed`). `null` means "not loaded yet"; an empty list is a valid loaded value. Only 2 files use `ValueNotifier`/`ChangeNotifier`, so state is mostly local `StatefulWidget` state (18 `StatefulWidget` vs 13 `StatelessWidget`).

**Widgets:**
- Prefer `StatelessWidget` with explicit callbacks. Lift state up to the screen.
- Keep theme access through `Theme.of(context)` and `Theme.of(context).colorScheme` (93 uses), not hard-coded colors, except for the SRS state palette (`Colors.blue`, `Colors.orange`, etc. in `verse_item_tile.dart`).
- Use `withValues(alpha: ...)` on colors, not the deprecated `withOpacity`.

**Reusing existing helpers:** before writing new formatting or text utilities, check `lib/core/format/` (`arabic.dart` for search and normalization, `dates.dart` for relative dates) and `lib/core/settings.dart` for persisted state.

---

## Sanity Studio (`sanity/`)

A separate TypeScript project. Its conventions are different from the Flutter app.

- Prettier config is in `sanity/package.json`: `semi: false`, `singleQuote: true`, `bracketSpacing: false`, `printWidth: 100`.
- ESLint uses `@sanity/eslint-config-studio` via `sanity/eslint.config.mjs`.
- Schema files live in `sanity/schemaTypes/*.ts`, one `defineType` per file, exported through `sanity/schemaTypes/index.ts`:
  ```ts
  import {defineField, defineType} from 'sanity'

  export const verse = defineType({
    name: 'verse',
    title: 'Verse',
    type: 'document',
    fields: [defineField({name: 'title', type: 'string'})],
  })
  ```
- Schema `name` values are camelCase and match the `_type` strings the Flutter app queries (`intercedeEntity`, `intercedePrayer`, `memorizeVerse`).
- Do not edit `sanity/node_modules/` or `sanity/dist/`.

---

*Convention analysis: 2026-11-02*
