---
last_mapped_commit: 988a5a4aa6f05076368c2d503e7e9348a013ae9f
last_mapped_at: 2026-11-02
---
<!-- refreshed: 2026-11-02 -->

# Architecture

**Analysis Date:** 2026-11-02

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                     Flutter UI (Arabic RTL, Material)                    │
│  `lib/app/app.dart` → onboarding OR `lib/features/home/home_screen.dart` │
├──────────────┬──────────────┬──────────────┬──────────────┬──────────────┤
│ عمل الصليب   │ ليا انا      │ حفظ الآيات   │ لليوم فقط    │ تشفع          │
│ cross_work   │ leyaana      │ memorize     │ just_for_today│ intercede     │
│ (bundled)    │ (Sanity)     │ (SRS+audio)  │ (jftna+Gemini)│ (Sanity+outbox)│
└──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┘
       │              │              │              │              │
       ▼              ▼              ▼              ▼              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Shared core: `lib/core/settings.dart` (SharedPreferences KV + caches)   │
│               `lib/core/sanity/client.dart` (HTTP query/mutate/upload)    │
│               `lib/core/notifications.dart`, `lib/core/background.dart`  │
│               `lib/core/updater.dart`, `lib/core/format/*`               │
└───────┬─────────────────┬──────────────────┬───────────────────┬─────────┘
        ▼                 ▼                  ▼                   ▼
  SharedPreferences   sqflite            Sanity HTTP API     Gemini / jftna /
  (FlutterShared-     `memorize.db`      project kfme7y2v    GitHub releases API
   Preferences)       `journal.db`                           (http package)

Native (Android only, `android/app/src/main/`):
  MainActivity.kt ──MethodChannel "aio/widget"──▶ VerseWidgetProvider.kt
  (reads verse JSON from FlutterSharedPreferences key "flutter.verse-widget")
```

## Pattern Overview

**Overall:** Single-process, single-user, feature-sliced Flutter app. Each
feature under `lib/features/<name>/` is split into `data/` (models, repositories,
local DB) and `ui/` (screens and widgets). There is no state-management package.
State is held in `StatefulWidget`s, `setState`, and a few global singletons with
`ValueNotifier`s.

**Key Characteristics:**
- **Offline-first with an outbox:** the two Sanity-backed features (`intercede`,
  `memorize`) cache the last Sanity payload on disk and apply writes locally
  first, then queue Sanity mutations in an outbox that flushes in order.
  See `lib/features/intercede/data/store.dart` and
  `lib/features/memorize/data/memorize_repository.dart`.
- **Singleton services, no DI:** `Settings.instance` (initialised in `main()`),
  `IntercedeStore.instance`, `MemorizeRepository.instance`,
  `MemorizeDb.open()`, `JournalDb.open()`. No service locator or provider tree.
- **Thin UI over repositories:** screens call repository functions directly
  (`fetchEntitiesRaw`, `sanityQuery`, `dailyVersesFor`, `loadJft`). There is no
  use-case layer. Pure domain logic lives in one place only:
  `lib/features/memorize/domain/anki_engine.dart` (SM-2 scheduling).
- **Deterministic daily content:** `lib/features/leyaana/data/daily_pick.dart`
  reproduces the leyaana PWA hash (`hashValue`, `getPeriodKey`, `pickIndex`)
  so the same verse is chosen on the app, the widget, and scheduled notifications.
- **Single locale and direction:** `MaterialApp` forces `Locale('ar')` and wraps
  everything in `Directionality(TextDirection.rtl)` (`lib/app/app.dart`).

## Layers

**Entry / App shell:**
- Purpose: bootstrap services, theme, locale, first-run routing.
- Location: `lib/main.dart`, `lib/app/app.dart`, `lib/app/theme.dart`
- Contains: `main()`, `AioApp` / `AioAppState` (theme mode, lifecycle observer).
- Depends on: `core/settings.dart`, `core/notifications.dart`, feature entry screens.
- Used by: Flutter engine only.

**Core services (`lib/core/`):**
- Purpose: cross-feature infrastructure.
- Location: `lib/core/`
- Contains:
  - `settings.dart`: typed getters/setters over `SharedPreferences`, plus a generic
    string cache (`getCache` / `setCache`) used as the offline store for Sanity data.
  - `sanity/client.dart`: `sanityQuery` (CDN or live host), `sanityMutate`,
    `sanityUploadFile`. Write token comes from Settings or `--dart-define`.
  - `notifications.dart`: daily reminder plus per-day verse notifications
    (`zonedSchedule`, IDs 1 and 100-113).
  - `background.dart`: WorkManager callback that prefetches لليوم فقط every 24 h.
  - `updater.dart`: GitHub release check and in-app APK install via `ota_update`.
  - `format/arabic.dart`, `format/dates.dart`: formatting helpers.
- Depends on: `shared_preferences`, `http`, plugin packages.
- Used by: every feature.

**Features (`lib/features/`):**
- Purpose: user-facing sections. Each is independent except for the cross-links
  listed under "Cross-feature dependencies" below.
- Location: `lib/features/<name>/{data,ui,domain}/`

**Native bridge (Android):**
- Purpose: home-screen verse widget.
- Location: `android/app/src/main/kotlin/com/aio/aio/`
- Contains: `MainActivity.kt` (MethodChannel `aio/widget`, method `update`),
  `VerseWidgetProvider.kt` (AppWidgetProvider reading the JSON cache written by Dart).

## Feature Modules

| Feature | Entry screen | Data source | Local store | Write path |
|---------|--------------|-------------|-------------|-----------|
| عمل الصليب (cross_work) | `lib/features/cross_work/cross_work_screen.dart` | Bundled text | none | none |
| ليا انا (leyaana) | `ui/leyaana_screen.dart`, `ui/leyaana_admin_screen.dart` | Sanity CDN (`verse`, `godName`, `heavenlyBlessing`) | SharedPreferences cache `content-cache:<type>` | Sanity mutate, direct (`data/repository.dart`) |
| حفظ الآيات (memorize) | `ui/memorize_screen.dart` | Sanity (`memorizeVerse`) + local | sqflite `memorize.db` (table `memorize_items`) + outbox in Settings | Outbox → `sanityMutate` |
| لليوم فقط (just_for_today) | `ui/just_for_today_screen.dart` | jftna.org HTML → Gemini translation | SharedPreferences, one entry per day | none |
| تشفع (intercede) | `ui/intercede_screen.dart`, `entity_page.dart`, `prayer_page.dart`, `answered_page.dart` | Sanity (`intercedeEntity`, `intercedePrayer`) | SharedPreferences `intercede:entities` + `intercede:outbox` | Outbox via `IntercedeStore.apply` |
| مسلم (journal) | `ui/journal_screen.dart` (currently hidden from Home) | none | sqflite `journal.db` (table `entries`) | local only |

Settings and onboarding are not features in the same sense. They are reached from
`features/home/home_screen.dart` (settings icon) and `features/onboarding/onboarding_screen.dart`
(first run, gated by `Settings.onboarded`).

## Data Flow

### Primary Request Path: opening a Sanity-backed section (تشفع example)

1. `HomePage` pushes `IntercedeScreen` (`lib/features/home/home_screen.dart`).
2. Screen reads `IntercedeStore.instance.entities` (a `ValueNotifier`) for immediate paint
   (`lib/features/intercede/ui/intercede_screen.dart`).
3. `IntercedeStore.load()` (called at startup from `lib/main.dart`) paints the disk cache
   and then calls `refresh()` (`lib/features/intercede/data/store.dart`).
4. `refresh()` flushes the outbox, runs `fetchEntitiesRaw()` (live Sanity host, not CDN),
   replays pending outbox mutations on top, saves, and republishes.
5. On failure, `refresh()` keeps the cache and sets `failed` only when there is nothing cached.

### Write Path: optimistic outbox (تشفع / حفظ الآيات)

1. UI builds a Sanity mutation JSON (`createIfNotExists`, `patch`, ...).
2. `IntercedeStore.apply(mutations)` runs `applyMutation` against the in-memory raw list,
   appends to `_outbox`, persists both lists, and republishes `entities`.
3. `unawaited(flush())` sends `_outbox.first` via `sanityMutate`, one at a time, removing each
   on success and stopping on the first failure so create-before-patch order holds.
4. Flush is also triggered on app resume (`AioAppState.didChangeAppLifecycleState`) and on
   the next `refresh()`.

### Read Path: ليا انا daily verse → widget and notifications

1. `main()` calls `refreshVerseSurfaces()` (`lib/features/leyaana/data/verse_surfaces.dart`).
2. It computes verses for today + `Notifications.verseDays` (14) days via `dailyVersesFor`.
3. It writes a JSON map keyed by UTC day to SharedPreferences key `verse-widget`.
4. It invokes MethodChannel `aio/widget` → `MainActivity.kt` → `VerseWidgetProvider.render`,
   which reads `flutter.verse-widget` from `FlutterSharedPreferences` and renders the day's entry.
5. If verse notifications are enabled, it schedules one non-repeating local notification per day
   via `Notifications.scheduleVerses`.

### Background Path: لليوم فقط prefetch

1. `initDailyPrefetch()` (`lib/core/background.dart`) registers a 24 h WorkManager periodic task
   with `ExistingPeriodicWorkPolicy.keep`.
2. `callbackDispatcher` runs in a separate isolate, calls `Settings.init()`, checks `geminiKey`
   and the per-day cache, then calls `loadJft()`.
3. `prefetchJftNow()` does the same on launch as a fallback for Doze delays.

### Notification Path: daily reminder

1. `Notifications.init()` (called from `main()`) sets the local timezone with `flutter_timezone`
   and re-arms the daily schedule if `notifEnabled`.
2. `schedule(hour, minute)` cancels then calls `zonedSchedule` with `matchDateTimeComponents: time`.

**State Management:**
- Global prefs: `Settings` singleton over `SharedPreferences`. Every read is synchronous after init.
- Screen state: local `StatefulWidget` state.
- Cross-screen reactive state: `ValueNotifier` on `IntercedeStore.entities` and `failed`.
- Persistent caches and outboxes: JSON strings inside SharedPreferences (`Settings.setCache`).
- Relational data: sqflite (`memorize.db`, `journal.db`).

## Key Abstractions

**`Settings` (`lib/core/settings.dart`):**
- Purpose: typed access to all preferences and per-key caches.
- Examples: `Settings.instance.name`, `.personKey`, `.isMale`, `.sanityToken`, `.geminiKey`.
- Pattern: singleton, `Settings.init()` must run before use (throws `StateError` otherwise).

**`IntercedeStore` (`lib/features/intercede/data/store.dart`):**
- Purpose: offline-first cache plus outbox for تشفع.
- Pattern: `ValueNotifier` publish, JSON-as-mutation (the raw Sanity payload and the queued
  mutation JSON share one `applyMutation` path, no `copyWith`/`toJson` on models).

**`MemorizeRepository` (`lib/features/memorize/data/memorize_repository.dart`):**
- Purpose: sync between Sanity and `MemorizeDb`, outbox, SRS updates.
- Pattern: same outbox idea as `IntercedeStore`, but the outbox is kept in SharedPreferences
  and the cards in sqflite.

**`AnkiEngine` (`lib/features/memorize/domain/anki_engine.dart`):**
- Purpose: pure SM-2 spaced-repetition scheduling, unit-tested in
  `test/anki_engine_test.dart`.
- Pattern: stateless functions over `MemorizeVerse`. This is the only true domain layer in the app.

**Daily pick (`lib/features/leyaana/data/daily_pick.dart`):**
- Purpose: deterministic daily item selection shared with the leyaana PWA.
- Pattern: hash of `userKey + period key`, index into ordered list. Keep in sync with the PWA.

**Sanity client (`lib/core/sanity/client.dart`):**
- Purpose: the only HTTP gateway to Sanity. Read via `apicdn` when `cdn: true`, otherwise the live host.
- Pattern: GROQ strings live next to their repositories (e.g. `_query` in intercede,
  `_sanityVerseQuery` in memorize, `_queries` map in leyaana).

## Entry Points

**Application:**
- Location: `lib/main.dart`
- Triggers: app launch (Android launcher activity `MainActivity`).
- Responsibilities: `WidgetsFlutterBinding.ensureInitialized`, `Settings.init`,
  `Notifications.init`, `runApp(AioApp)`, then non-awaited `IntercedeStore.load`,
  `refreshVerseSurfaces`, `initDailyPrefetch`, `prefetchJftNow`.

**Background worker:**
- Location: `lib/core/background.dart` (`callbackDispatcher`, `@pragma('vm:entry-point')`).
- Triggers: WorkManager periodic task `jftPrefetch` every 24 h, network connected.

**Android widget:**
- Location: `android/app/src/main/kotlin/com/aio/aio/VerseWidgetProvider.kt`
  (declared in `android/app/src/main/AndroidManifest.xml`).
- Triggers: `APPWIDGET_UPDATE`, or `MainActivity` method `update` from Dart.

**Notification receivers:**
- `flutter_local_notifications` receivers declared in `AndroidManifest.xml` for scheduled alerts and boot/package-replace reschedule.

**Sanity Studio (separate project):**
- Location: `sanity/sanity.config.ts`, schemas in `sanity/schemaTypes/`.
- Triggers: `sanity dev` / `sanity build` from `sanity/` (Bun). It is not part of the Flutter build.

## Architectural Constraints

- **Threading:** Dart single isolate for the UI. WorkManager callback runs in its own background isolate
  and therefore cannot share in-memory state. It re-initialises `Settings`.
- **Global state:** `Settings._instance`, `IntercedeStore.instance`, `MemorizeRepository.instance`,
  `MemorizeDb._instance`, `JournalDb._instance`, and `Notifications._plugin` are module-level singletons.
  Tests that touch these need explicit setup.
- **Circular imports:** `lib/features/settings/settings_screen.dart` imports `lib/app/app.dart`
  (for `AioApp.of` theme switching). `app.dart` imports `onboarding_screen.dart`, which imports
  `home_screen.dart`, which imports `settings_screen.dart`. The cycle works in Dart but makes
  the import graph hard to reason about.
- **Hardcoded config:** Sanity project id and dataset are constants in `lib/core/sanity/client.dart`.
  The GitHub repo for updates is `_repo` in `lib/core/updater.dart`. The Sanity write token and Gemini key
  are per-device settings, with an optional `SANITY_WRITE_TOKEN` `--dart-define` fallback.
- **Platform:** Only `android/` is present in the repository. There is no `ios/`, `web/`, or desktop folder.
  Code paths guard iOS via `MissingPluginException` (widget) and `resolvePlatformSpecificImplementation`
  (notifications), but no iOS build exists here.
- **Locale:** Hardcoded `Locale('ar')` with forced RTL. English is supported but not a runtime choice.

## Anti-Patterns

### Unawaited startup work in `main()`

**What happens:** `main()` fires four unawaited startup tasks (`IntercedeStore.load`,
`refreshVerseSurfaces`, `initDailyPrefetch`, `prefetchJftNow`) right after `runApp`.
**Why it's wrong:** Failures are swallowed, ordering is undefined, and each task hits the network or the
disk independently with no shared coordination.
**Do this instead:** Keep the existing fire-and-forget pattern only for cheap, self-healing tasks
(as the code comments already justify). Put any new startup work behind the same
`unawaited` plus try/catch style in `lib/main.dart`, and do not add more blocking awaits before `runApp`.

### Duplicated outbox implementations

**What happens:** `IntercedeStore` (`lib/features/intercede/data/store.dart`) and `MemorizeRepository`
(`lib/features/memorize/data/memorize_repository.dart`) each implement their own outbox, flush loop,
and JSON decode helper, with different storage (SharedPreferences cache vs. outbox key).
**Why it's wrong:** Ordering and retry fixes need to be applied twice.
**Do this instead:** When adding another Sanity-backed feature, follow the closest existing pattern and extract
a shared helper only once a third copy appears.

### Stale README architecture

**What happens:** `README.md` lists files that no longer exist (`lib/leyaana_content.dart`, `lib/sections/*`,
`lib/home.dart`) and an old key location (`_geminiKey` in `just_for_today.dart`).
**Why it's wrong:** It misleads planners about where code lives.
**Do this instead:** Use `.planning/codebase/STRUCTURE.md` for paths. Keys are now read from `Settings`,
not compiled in.

## Error Handling

**Strategy:** Fail soft at the edges. Network and storage errors fall back to the last cached copy.
User-visible errors are shown only when nothing is cached.

**Patterns:**
- Sanity reads use `_fetchType` / `refresh()`: on error, return the cached JSON; rethrow only if no cache exists
  (`lib/features/leyaana/data/repository.dart`).
- Outbox flush stops at the first failure and leaves the item queued (`IntercedeStore.flush`).
- Background and startup tasks swallow exceptions (`prefetchJftNow`, `refreshVerseSurfaces`), with
  WorkManager retry and exponential backoff for the background task.
- Sanity HTTP errors are thrown as `Exception('Sanity <code>')` with a timeout on every call.

## Cross-Cutting Concerns

**Logging:** No logging framework. Errors are swallowed or surfaced through UI state. Default `print` is not used in lib.

**Validation:** Minimal. Name and gender are trimmed in `Settings`. Verse text is split on `---` for male/female
variants in `lib/features/leyaana/data/repository.dart`.

**Authentication:** None for users. Sanity writes use a bearer token stored in `Settings.sanityToken`
(entered in the Settings screen) or the `SANITY_WRITE_TOKEN` compile-time define. Gemini uses `Settings.geminiKey`.
No secrets are committed in code paths reviewed here.

**Localisation:** Arabic strings are inline in widgets and services. There are no ARB files.

---

*Architecture analysis: 2026-11-02*
