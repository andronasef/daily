---
last_mapped_commit: 988a5a4aa6f05076368c2d503e7e9348a013ae9f
last_mapped_at: 2026-11-02
---
# Technology Stack

**Analysis Date:** 2026-11-02

## Languages

**Primary:**
- Dart (SDK `^3.10.4`, declared in `pubspec.yaml`) - all app code under `lib/` and tests under `test/`
- Kotlin - Android host glue under `android/app/src/main/kotlin/` (Gradle script is Kotlin DSL)

**Secondary:**
- TypeScript - Sanity Studio content schemas and config under `sanity/` (`sanity/schemaTypes/*.ts`, `sanity/sanity.config.ts`, `sanity/sanity.cli.ts`)
- Java 17 - Android build target (`android/app/build.gradle.kts` `JavaVersion.VERSION_17`, CI uses Temurin 17)
- Python 3 - inline script in `.github/workflows/release.yml` that decodes the keystore secret

## Runtime

**Environment:**
- Flutter SDK, `stable` channel (`.metadata` revision `f6ff1529fd6d8af5f706051d9251ac9231c83407`, `project_type: app`)
- Android: `compileSdk`/`minSdk`/`targetSdk`/`ndkVersion` come from the Flutter SDK (`flutter.*` in `android/app/build.gradle.kts`)
- iOS: not present in the repository (no `ios/` directory checked in)
- Sanity Studio runtime: Node/Bun-driven project under `sanity/` (`sanity/bun.lock` present)

**Package Managers:**
- Pub (Dart) - `pubspec.yaml`, lockfile `pubspec.lock` present
  - Lockfile: present
- npm-compatible / Bun for the Sanity studio - `sanity/package.json`, lockfile `sanity/bun.lock` present
  - Lockfile: present
- Gradle wrapper 8.14 (`android/gradle/wrapper/gradle-wrapper.properties`)

## Frameworks

**Core:**
- Flutter (Material, `flutter_localizations`) - app UI, entry `lib/main.dart`, app shell `lib/app/app.dart`, theme `lib/app/theme.dart`
- Sanity Studio 6.x (`sanity` ^6.16.0, `@sanity/vision` ^6.16.0) - content editing UI for the `production` dataset, project `kfme7y2v`
- React 19 / styled-components 6 - pulled in only as Sanity Studio dependencies (`sanity/package.json`)

**Testing:**
- `flutter_test` (SDK) - unit and widget tests in `test/` (`anki_engine_test.dart`, `search_test.dart`, `intercede_store_test.dart`, `intercede_test.dart`, `widget_test.dart`)
- No separate test runner for the Sanity studio (`sanity/package.json` has no test script)

**Build/Dev:**
- `flutter_lints` ^6.0.0 - lint set via `analysis_options.yaml` (`include: package:flutter_lints/flutter.yaml`)
- `flutter_launcher_icons` ^0.14.4 - icon generation from `assets/icon/icon_full.png` and `assets/icon/icon_fg.png` (config in `pubspec.yaml`)
- `flutter_native_splash` ^2.4.7 - splash generation (config in `pubspec.yaml`)
- Android Gradle Plugin 8.11.1, Kotlin Android 2.2.20 (`android/settings.gradle.kts`)
- Core library desugaring `com.android.tools:desugar_jdk_libs:2.1.4` (`android/app/build.gradle.kts`, required by `flutter_local_notifications`)
- Prettier 3.5 (`sanity/package.json` `prettier` block: no semicolons, single quotes, width 100), ESLint 10 with `@sanity/eslint-config-studio` (`sanity/eslint.config.mjs`), TypeScript 5.8 (`sanity/tsconfig.json`)

## Key Dependencies

**Critical (runtime, from `pubspec.yaml`):**
- `http` ^1.6.0 - every HTTP call: Sanity API, GitHub API, jftna.org scrape, Gemini API (`lib/core/sanity/client.dart`, `lib/core/updater.dart`, `lib/features/just_for_today/data/repository.dart`)
- `sqflite` ^2.4.2+1 + `path` ^1.9.1 - local SQLite stores (`lib/features/memorize/data/memorize_db.dart` schema version 2, `lib/features/journal/data/journal_db.dart` schema version 1)
- `shared_preferences` ^2.5.5 - settings and cached payloads, wrapped by `lib/core/settings.dart`
- `flutter_local_notifications` ^22.1.0 + `timezone` ^0.11.1 + `flutter_timezone` ^5.1.0 - daily and verse reminders (`lib/core/notifications.dart`)
- `workmanager` ^0.10.10 - 24h periodic background prefetch of the لليوم فقط section (`lib/core/background.dart`)
- `ota_update` ^7.1.0 - in-app APK download and install from GitHub releases (`lib/core/updater.dart`)
- `package_info_plus` ^10.2.1 - reads installed version for update comparison (`lib/core/updater.dart`)
- `record` ^7.1.1 - microphone recording for memorization voice practice (`lib/features/memorize/data/audio_service.dart`, `lib/features/memorize/ui/practice/voice_recorder_view.dart`)
- `audioplayers` ^6.8.1 - playback of verse audio, local or URL (`lib/features/memorize/data/audio_service.dart`)
- `path_provider` ^2.1.6 - documents directory for recorded audio (`lib/features/memorize/data/audio_service.dart`)
- `google_fonts` ^8.2.0 - Cairo (app theme, `lib/app/theme.dart`) and Amiri (`lib/features/cross_work/cross_work_screen.dart`), fetched and cached at runtime
- `cupertino_icons` ^1.0.8 - icon font

**Dev-only:**
- `flutter_test`, `flutter_lints`, `flutter_launcher_icons`, `flutter_native_splash` (see Build/Dev above)

**Infrastructure / Sanity studio (`sanity/package.json`):**
- `sanity` ^6.16.0, `@sanity/vision` ^6.16.0, `react` / `react-dom` ^19.2.4, `styled-components` ^6.1.18
- Dev: `@sanity/eslint-config-studio` ^7, `eslint` ^10.8.1, `typescript` ^5.8, `prettier` ^3.5

**Lock-level pins:** see `pubspec.lock` (Dart) and `sanity/bun.lock` (Sanity). Do not hand-edit either.

## Configuration

**Environment:**
- No `.env` loading library. Configuration is compile-time or user-entered at runtime:
  - `SANITY_WRITE_TOKEN` read via `String.fromEnvironment` in `lib/core/sanity/client.dart` (build-time `--dart-define`); fallback is a token entered in app Settings and stored in SharedPreferences under key `sanityWriteToken`
  - Gemini API key entered in app Settings, stored under SharedPreferences key `geminiKey` (`lib/core/settings.dart`)
  - Sanity project ID `kfme7y2v`, dataset `production`, API version `v2024-01-01` are hardcoded constants in `lib/core/sanity/client.dart`
- Android signing: `android/key.properties` is read if present (`android/app/build.gradle.kts`). CI writes it and `android/app/release.jks` from secrets (`.github/workflows/release.yml`). Contents are not recorded here.
- Android application ID `com.andro.daily` (release), `com.andro.daily.dev` suffix for debug; namespace `com.aio.aio`
- App display name resources set per build type in `android/app/build.gradle.kts`

**Build:**
- `pubspec.yaml` - dependencies, launcher icon and splash config, `uses-material-design: true`
- `analysis_options.yaml` - analyzer and lint config
- `android/build.gradle.kts`, `android/settings.gradle.kts`, `android/gradle.properties`, `android/gradle/wrapper/gradle-wrapper.properties` - Android build
- `android/app/src/main/AndroidManifest.xml` - permissions: INTERNET, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, USE_EXACT_ALARM, REQUEST_INSTALL_PACKAGES, RECORD_AUDIO; includes an app widget provider
- `sanity/sanity.config.ts`, `sanity/sanity.cli.ts` - Studio config (autoUpdates enabled in CLI config)
- `.github/workflows/release.yml` - release pipeline (tag `v[0-9]+.[0-9]+.[0-9]+` or manual dispatch)

## Platform Requirements

**Development:**
- Flutter stable with Dart SDK `^3.10.4`
- JDK 17 for Android builds
- Node/Bun toolchain for `sanity/` (only if editing the Studio)
- `build/` and `.dart_tool/` are generated and git-ignored (`.gitignore`); not analyzed

**Production:**
- Android only. Distributed as a signed release APK attached to GitHub Releases (`.github/workflows/release.yml`, `gh release create`). versionName = git tag, versionCode = CI run number, so OTA installs upgrade in place.
- No iOS build target is checked in. `flutter_local_notifications` and `workmanager` have iOS hooks in their packages, but no `ios/` project exists in this repo.
- Sanity Studio is deployed separately through `sanity deploy` (`sanity/package.json` scripts).

---

*Stack analysis: 2026-11-02*
