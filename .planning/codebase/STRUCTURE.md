---
last_mapped_commit: 988a5a4aa6f05076368c2d503e7e9348a013ae9f
last_mapped_at: 2026-11-02
---
# Codebase Structure

**Analysis Date:** 2026-11-02

## Directory Layout

```
daily/                                   # Flutter app "aio" (يومي), Android-only build
├── lib/                                 # All Dart source
│   ├── main.dart                        # Entry point, service bootstrap
│   ├── app/                             # MaterialApp shell and theme
│   ├── core/                            # Shared infrastructure (settings, Sanity, notifications, background, updater)
│   │   ├── sanity/                      # Sanity HTTP client
│   │   └── format/                      # Arabic and date formatting helpers
│   └── features/                        # One folder per user-facing section
│       ├── home/                        # Hub screen (section list)
│       ├── onboarding/                  # First-run name and gender
│       ├── settings/                    # Preferences screen
│       ├── cross_work/                  # عمل الصليب (static reflection)
│       ├── leyaana/                     # ليا انا (daily verse, name, admin editor)
│       ├── memorize/                    # حفظ الآيات (Anki SRS, audio, voice recorder)
│       ├── just_for_today/              # لليوم فقط (jftna + Gemini)
│       ├── intercede/                   # تشفع (prayer list, offline outbox)
│       └── journal/                     # مسلم (local journal, currently hidden)
├── test/                                # Flutter unit and widget tests
├── android/                             # Android host project (Kotlin, manifest, Gradle)
│   └── app/src/main/kotlin/com/aio/aio/ # MainActivity.kt, VerseWidgetProvider.kt
├── assets/                              # Icons and fonts referenced by pubspec
│   └── icon/                            # icon_full.png, icon_fg.png (launcher and splash)
├── sanity/                              # Sanity Studio (separate Node/Bun project, CMS schemas)
│   ├── schemaTypes/                     # Document schemas (verse, memorizeVerse, intercede*, ...)
│   ├── static/                          # Studio static assets (.gitkeep only)
│   └── dist/                            # Generated Studio build, do not edit
├── .github/workflows/release.yml        # Tag-triggered APK release build
├── .planning/codebase/                  # Generated codebase maps (this file lives here)
├── pubspec.yaml                         # Dependencies, assets, launcher/splash config
├── analysis_options.yaml                # Analyzer config (flutter_lints)
├── CHANGELOG.md                         # Release notes, update when shipping changes
└── README.md                            # Partly stale file paths, see ARCHITECTURE.md
```

Generated and ignored (do not read or edit): `build/`, `.dart_tool/`,
`.flutter-plugins-dependencies`, `sanity/node_modules/`, `sanity/dist/`,
`sanity/.sanity/`, and any `android/app/release.jks` or `android/key.properties`
written during CI.

## Directory Purposes

**`lib/app/`:**
- Purpose: root `MaterialApp`, locale and RTL wrapper, light/dark theme, app lifecycle hook.
- Contains: `app.dart` (`AioApp`, `AioAppState`), `theme.dart` (`buildTheme(Brightness)`, Cairo via `google_fonts`).
- Key files: `lib/app/app.dart`, `lib/app/theme.dart`.

**`lib/core/`:**
- Purpose: infrastructure every feature uses. Nothing here depends on a feature except `notifications.dart`
  and `background.dart`, which read leyaana and لليوم فقط repositories for scheduling.
- Contains: `settings.dart`, `notifications.dart`, `background.dart`, `updater.dart`.
- Key files: `lib/core/settings.dart`, `lib/core/sanity/client.dart`.

**`lib/core/sanity/`:**
- Purpose: the only Sanity HTTP gateway.
- Contains: `client.dart` with `sanityQuery`, `sanityMutate`, `sanityUploadFile`, and project constants.
- Key files: `lib/core/sanity/client.dart`.

**`lib/core/format/`:**
- Purpose: display helpers for Arabic numerals and dates.
- Key files: `lib/core/format/arabic.dart`, `lib/core/format/dates.dart`.

**`lib/features/<name>/data/`:**
- Purpose: models, repositories, local DB helpers, outbox logic, HTTP fetches.
- Typical files: `repository.dart`, `models.dart` or `*_models.dart`, `*_db.dart`, `store.dart`, `audio_service.dart`.

**`lib/features/<name>/ui/`:**
- Purpose: screens, pages, and widgets. Subfolders `widgets/` and `practice/` group reusable parts.
- Typical files: `*_screen.dart` (route entry), `*_page.dart` (secondary page), `widgets/*.dart`.

**`lib/features/<name>/domain/`:**
- Purpose: pure logic with no I/O.
- Present in: `memorize` only (`anki_engine.dart`).

**`lib/features/home/`:**
- Purpose: the Home hub, the one place sections are listed.
- Key file: `lib/features/home/home_screen.dart` (`_sections` list drives the cards).

**`lib/features/memorize/`:**
- Purpose: memorization deck with SM-2 scheduling, audio playback, and voice recording.
- Key files: `data/memorize_repository.dart`, `data/memorize_db.dart`, `data/memorize_models.dart`,
  `data/audio_service.dart`, `domain/anki_engine.dart`, `ui/memorize_screen.dart`,
  `ui/add_verse_sheet.dart`, `ui/audio_playlist_screen.dart`,
  `ui/practice/` (`practice_flow_screen.dart`, `flashcard_view.dart`, `typing_challenge_view.dart`,
  `reveal_challenge_view.dart`, `voice_recorder_view.dart`), `ui/widgets/` (`verse_item_tile.dart`, `srs_stat_card.dart`).

**`lib/features/leyaana/`:**
- Purpose: daily verse, god name, and blessing from Sanity, plus the content editor and widget sync.
- Key files: `data/repository.dart` (Sanity queries, cache, mutate), `data/daily_pick.dart` (deterministic pick),
  `data/verse_surfaces.dart` (widget and notification refresh), `ui/leyaana_screen.dart`,
  `ui/leyaana_admin_screen.dart`.

**`lib/features/intercede/`:**
- Purpose: prayer-for-others list with entities, prayers, logs, and answered prayers, offline-first.
- Key files: `data/store.dart` (cache plus outbox, `IntercedeStore`), `data/repository.dart` (`parseEntities`,
  GROQ `_query`, mutation builders), `data/models.dart`, `ui/intercede_screen.dart`, `ui/entity_page.dart`,
  `ui/prayer_page.dart`, `ui/answered_page.dart`, `ui/widgets/prayer_editor_page.dart`,
  `ui/widgets/prayer_menu.dart`, `ui/widgets/prayer_card.dart`.

**`lib/features/just_for_today/`:**
- Purpose: fetch and translate the daily reading, cache it once per day.
- Key files: `data/repository.dart` (`fetchSource`, `Jft`, `loadJft`, `jftCachedForToday`),
  `ui/just_for_today_screen.dart`.

**`lib/features/cross_work/`:**
- Purpose: static reflection text.
- Key file: `lib/features/cross_work/cross_work_screen.dart`.

**`lib/features/journal/`:**
- Purpose: one local journal entry per day in sqflite. Not reachable from Home now.
- Key files: `data/journal_db.dart`, `ui/journal_screen.dart`.

**`lib/features/settings/` and `lib/features/onboarding/`:**
- Key files: `settings/settings_screen.dart` (reminder, dark mode, Sanity token, Gemini key, update check),
  `onboarding/onboarding_screen.dart` (name and gender, then the Home route).

**`android/app/src/main/kotlin/com/aio/aio/`:**
- Purpose: Android-only native code. Package is `com.aio.aio`.
- Key files: `MainActivity.kt` (MethodChannel `aio/widget`), `VerseWidgetProvider.kt` (home-screen widget).

**`android/app/src/main/res/`:**
- Purpose: widget layout and drawables (`layout/verse_widget.xml`, `xml/verse_widget_info.xml`), theme colors and styles for light and night, launch background, and FileProvider paths (`xml/filepaths.xml`).

**`test/`:**
- Purpose: unit tests for the SM-2 engine, search, and intercede store, plus a default widget test.
- Key files: `test/anki_engine_test.dart`, `test/intercede_store_test.dart`, `test/intercede_test.dart`,
  `test/search_test.dart`, `test/widget_test.dart`.

**`sanity/`:**
- Purpose: content model for the Sanity project `kfme7y2v`, dataset `production`.
- Key files: `sanity/sanity.config.ts`, `sanity/schemaTypes/index.ts` (schema registry),
  `sanity/schemaTypes/*.ts` (`verse`, `godName`, `heavenlyBlessing`, `pushSubscription`, `intercedeEntity`,
  `intercedePrayer`, `memorizeVerse`, `verseCategory`).

## Key File Locations

**Entry Points:**
- `lib/main.dart`: app bootstrap and startup tasks.
- `lib/app/app.dart`: root widget and first-run routing.
- `android/app/src/main/kotlin/com/aio/aio/MainActivity.kt`: Android activity and widget channel.

**Configuration:**
- `pubspec.yaml`: dependencies, launcher icon, native splash, and `flutter` section.
- `analysis_options.yaml`: lint rules.
- `android/app/build.gradle.kts`: Android build config (applicationId `com.aio.aio`).
- `android/app/src/main/AndroidManifest.xml`: permissions, receivers, widget and FileProvider declarations.
- `.github/workflows/release.yml`: tag-based release APK build and signing.
- `sanity/sanity.config.ts`: Studio config.

**Core Logic:**
- `lib/core/settings.dart`: all persisted preferences and caches.
- `lib/core/sanity/client.dart`: Sanity access.
- `lib/features/intercede/data/store.dart`: offline-first store.
- `lib/features/memorize/domain/anki_engine.dart`: SRS logic.
- `lib/features/leyaana/data/daily_pick.dart`: daily selection parity with the PWA.

**Testing:**
- `test/`: all Dart tests. There are no Android instrumentation tests.

## Naming Conventions

**Files:**
- `snake_case.dart` throughout `lib/` and `test/`. Example: `memorize_repository.dart`, `just_for_today_screen.dart`.
- Suffixes by role: `*_screen.dart` (route entry), `*_page.dart` (secondary route), `*_view.dart` (embedded
  practice or pane), `*_sheet.dart` (bottom sheet), `*_db.dart` (sqflite), `*_models.dart` or `models.dart`,
  `repository.dart`, `store.dart`.
- Feature folders are `snake_case` English names (`just_for_today`, `cross_work`) even though the UI text is Arabic.
- Sanity schema files are `camelCase.ts` (`intercedePrayer.ts`), exported by name from `schemaTypes/index.ts`.
- Kotlin: PascalCase `.kt` files under package `com.aio.aio`.

**Directories:**
- Features under `lib/features/` use one snake_case name each. Sub-layers are always `data/`, `ui/`, `domain/`.
- `ui/` may hold `widgets/` and `practice/` subfolders.

**Identifiers:**
- Classes: `PascalCase` (`IntercedeStore`, `MemorizeRepository`, `AioApp`).
- Private singletons: `_instance` with a `static` getter `instance`.
- Sanity document types: `camelCase` strings (`intercedeEntity`, `memorizeVerse`).
- SharedPreferences keys: camelCase or kebab-case literals in `settings.dart` and repositories, prefixed by feature (`intercede:outbox`, `memorize:outbox`, `content-cache:<type>`, `verse-widget`).
- Notification channels: `daily_reminder`, `daily_verse`.

## Where to Add New Code

**New feature section:**
- Primary code: `lib/features/<name>/ui/<name>_screen.dart` (entry), `lib/features/<name>/data/repository.dart` (I/O).
- Pure logic, if any: `lib/features/<name>/domain/`.
- Register on Home: add a `_Section` entry in `lib/features/home/home_screen.dart`.
- Tests: `test/<name>_test.dart` (flat, as in the existing `test/` folder).
- If it needs Sanity content, add a schema file in `sanity/schemaTypes/` and export it from `sanity/schemaTypes/index.ts`.

**New Sanity-backed write path:**
- Follow `lib/features/intercede/data/store.dart` (offline-first with outbox) for user-facing edits.
- Use `sanityMutate` from `lib/core/sanity/client.dart` for the HTTP call. Do not create a new client.

**New persisted preference:**
- Add a key constant and typed getter or setter in `lib/core/settings.dart`.

**New shared utility:**
- Formatting: `lib/core/format/`.
- Cross-feature infrastructure: `lib/core/`.
- Do not put shared code inside one feature folder and import it from another. The one existing exception is
  `lib/features/leyaana/data/daily_pick.dart`, used by `core/notifications.dart`.

**New Android native capability:**
- Method channel handler in `android/app/src/main/kotlin/com/aio/aio/MainActivity.kt`.
- Widget or receiver code in the same `kotlin/com/aio/aio/` package, declared in `AndroidManifest.xml`.

**New test:**
- Dart unit test in `test/` named `<subject>_test.dart`. Import via `package:aio/...`.

## Special Directories

**`build/`:**
- Purpose: Flutter and Gradle build output.
- Generated: Yes. Committed: No. Do not read.

**`.dart_tool/`:**
- Purpose: pub and tooling cache.
- Generated: Yes. Committed: No. Do not read.

**`sanity/dist/` and `sanity/.sanity/`:**
- Purpose: Sanity Studio build and runtime output.
- Generated: Yes. Committed: depends on `.gitignore`. Do not edit.

**`sanity/node_modules/`:**
- Purpose: Studio dependencies (Bun).
- Generated: Yes. Committed: No.

**`android/app/release.jks` and `android/key.properties`:**
- Purpose: release signing material, written by CI from secrets.
- Generated: Yes in CI. Committed: No. Never read or quote these files.

**`.planning/codebase/`:**
- Purpose: this codebase map, consumed by GSD planning commands.
- Generated: Yes. Committed: Per project policy.

---

*Structure analysis: 2026-11-02*
