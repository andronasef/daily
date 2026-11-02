---
last_mapped_commit: 988a5a4aa6f05076368c2d503e7e9348a013ae9f
last_mapped_at: 2026-11-02
---
# External Integrations

**Analysis Date:** 2026-11-02

## APIs & External Services

**Sanity Content Lake (headless CMS):**
- Project `kfme7y2v`, dataset `production`, API version `v2024-01-01` (`lib/core/sanity/client.dart`)
- Read: GROQ queries over HTTP GET. Reads use the CDN host `kfme7y2v.apicdn.sanity.io` when `cdn: true` (verses, god names, heavenly blessings in `lib/features/leyaana/data/repository.dart`), otherwise `kfme7y2v.api.sanity.io` (intercede entities and prayers in `lib/features/intercede/data/repository.dart`)
- Write: `POST` to `/data/mutate/production` (with `returnIds=true` variant) and `POST` to `/assets/files/production` for audio upload (`lib/core/sanity/client.dart`)
  - SDK/Client: none. Hand-rolled `package:http` calls.
  - Auth: Bearer token, from app Settings (SharedPreferences `sanityWriteToken`) or the `SANITY_WRITE_TOKEN` compile-time define. Writes throw if no token is set.
- Studio: `sanity/` project (`sanity/sanity.config.ts`) with schemas for verse, verseCategory, memorizeVerse, godName, heavenlyBlessing, intercedeEntity, intercedePrayer, pushSubscription (`sanity/schemaTypes/`)

**Google Gemini API:**
- Used to translate the daily "لليوم فقط" (Just For Today) reading into Egyptian Arabic
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent` (`lib/features/just_for_today/data/repository.dart`)
  - SDK/Client: none. Raw `package:http` POST.
  - Auth: API key passed as `?key=` query parameter, read from app Settings (SharedPreferences `geminiKey`). The key is stored on-device, never in source.
  - Called from the foreground loader and from the background prefetch (`lib/core/background.dart`). Skipped when no key is set.

**jftna.org (Just For Today source):**
- Scraped over HTTP GET from `https://www.jftna.org/jft/` (`lib/features/just_for_today/data/repository.dart`)
- Source text is then sent to Gemini for translation. Cached per day in SharedPreferences via `Settings.getCache`.

**GitHub Releases API:**
- `GET https://api.github.com/repos/andronasef/daily/releases/latest` (`lib/core/updater.dart`)
  - Compares `tag_name` to installed version from `package_info_plus`; picks the first `.apk` asset's `browser_download_url`
  - Auth: none (public repo API, unauthenticated)
- APK download and install is delegated to `ota_update` (`OtaUpdate().execute(...)` in `lib/core/updater.dart`), which triggers Android's package installer (`REQUEST_INSTALL_PACKAGES` in `android/app/src/main/AndroidManifest.xml`)

**Audio URLs:**
- `lib/features/memorize/data/audio_service.dart` plays either local files or `http(s)` URLs stored on verse records. Sanity-hosted audio files are uploaded via the assets endpoint above.

**Google Fonts:**
- `google_fonts` package downloads Cairo and Amiri at runtime and caches them (`lib/app/theme.dart`, `lib/features/cross_work/cross_work_screen.dart`). Falls back to system Arabic font offline.

## Data Storage

**Local databases (on-device, SQLite via sqflite):**
- Memorization DB: `lib/features/memorize/data/memorize_db.dart`, schema version 2
- Journal DB: `lib/features/journal/data/journal_db.dart`, schema version 1. Local only. The source comment states there is no cloud sync.
- Audio recordings are written under the app documents directory (`path_provider`, `lib/features/memorize/data/audio_service.dart`)

**Key-value storage:**
- `shared_preferences` via `lib/core/settings.dart`. Holds name, theme, onboarding flag, notification time, Sanity token, Gemini key, and cached JSON payloads (`getCache`/`setCache`).

**Remote storage:**
- Sanity Content Lake (see above). Only the studio and the verse, prayer, and audio content types are written from the app.

**Caching:**
- Local SharedPreferences caches for daily content (`lib/features/just_for_today/data/repository.dart`, `jftCachedForToday()`)
- Sanity CDN for read-only Leya Ana content (`cdn: true` in `lib/core/sanity/client.dart`)
- Google Fonts on-disk cache

## Authentication & Identity

**Auth Provider:**
- None for end users. The app is single-user with no login.
- Sanity: API token auth as described above.
- Gemini: API key auth, user-supplied.
- GitHub: unauthenticated public API.

## Monitoring & Observability

**Error Tracking:**
- None detected. No Sentry, Crashlytics, or similar SDK in `pubspec.yaml`.

**Logs:**
- No logging framework. Errors surface as thrown exceptions shown in the UI or swallowed in background code (`lib/core/background.dart` returns `false` to retry).

## CI/CD & Deployment

**Hosting / distribution:**
- GitHub Releases on `andronasef/daily`: CI attaches `daily-<tag>.apk` (`.github/workflows/release.yml`)
- Sanity Studio: `sanity deploy` (`sanity/package.json`), with `autoUpdates` enabled (`sanity/sanity.cli.ts`)

**CI Pipeline:**
- GitHub Actions. Single workflow `.github/workflows/release.yml`:
  - Triggers: push of tag `v[0-9]+.[0-9]+.[0-9]+`, or `workflow_dispatch`
  - Runs on `ubuntu-latest`, Temurin JDK 17, `subosito/flutter-action@v2` (stable, cached)
  - Restores the Android keystore from secret `KEYSTORE_BASE64` and writes `android/key.properties`
  - `flutter build apk --release` with `--build-name` from the tag and `--build-number` from the run number
  - Publishes via `gh release create` using the built-in `GITHUB_TOKEN`
- No test step in CI. No analysis step in CI.

## Environment Configuration

**Required at build time:**
- `SANITY_WRITE_TOKEN` (optional, `--dart-define`); otherwise token is entered in-app
- Android release secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` (GitHub Actions secrets)

**Required at runtime (user-entered in Settings):**
- Sanity write token (for the editor and intercede features)
- Gemini API key (for لليوم فقط translation)

**Secrets location:**
- GitHub Actions secrets for signing material
- On-device SharedPreferences for the Sanity and Gemini keys
- Keystore files and `android/key.properties` are created at CI time and are not committed. Their contents are not recorded in this document.

## Platform Permissions (external-facing)

**Declared in `android/app/src/main/AndroidManifest.xml`:**
- `INTERNET`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `USE_EXACT_ALARM` (scheduled reminders), `REQUEST_INSTALL_PACKAGES` (OTA install), `RECORD_AUDIO` (voice practice)

## Webhooks & Callbacks

**Incoming:**
- None. The app exposes no server endpoints.

**Outgoing:**
- None beyond the HTTP calls listed above. No webhook registration found.

**Schema note:**
- `sanity/schemaTypes/pushSubscription.ts` defines a `pushSubscription` document type, but no Dart code under `lib/` references it. Web push delivery is not implemented in the app.

---

*Integration audit: 2026-11-02*
