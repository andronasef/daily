---
last_mapped_commit: 988a5a4aa6f05076368c2d503e7e9348a013ae9f
last_mapped_at: 2026-11-02
---
# Codebase Concerns

**Analysis Date:** 2026-11-02

## Tech Debt

**Hand-rolled outbox in `MemorizeRepository` (lost-write race):**
- Issue: `flushOutbox()` reads the outbox into a local list once, then after each successful Sanity call writes that local list back with `_saveOutbox(outbox)`. `_queueMutation()` (called by `addVerse`, `toggleMastered`, `removeVerse`) appends to a fresh read of storage. If a mutation is queued while a flush is awaiting the network, the flush's next `_saveOutbox(outbox)` overwrites storage with its stale copy and the new mutation is silently dropped.
- Files: `lib/features/memorize/data/memorize_repository.dart` (`flushOutbox`, `_queueMutation`, `_getOutbox`, `_saveOutbox`)
- Impact: A user-created verse, a mastered toggle, or a delete can disappear from the sync queue and never reach Sanity. The local SQLite row still shows it, so the loss is invisible until the next refresh, which then drops it or restores the server version.
- Fix approach: Make the outbox a single source of truth. Re-read storage inside the loop and remove the head by id (not by index), or serialize all outbox mutations through one async lock. The `IntercedeStore` pattern (in-memory list shared by `apply` and `flush`, saved after each change) avoids this race and is the model to copy.

**Three different sync strategies for the same problem:**
- Issue: `IntercedeStore` (`lib/features/intercede/data/store.dart`) and `MemorizeRepository` (`lib/features/memorize/data/memorize_repository.dart`) each implement their own outbox with near-identical code. `leyaana` (`lib/features/leyaana/data/repository.dart`) has no outbox at all: `createDoc`, `updateDoc`, `deleteDoc` call Sanity directly and fail hard when offline.
- Files: `lib/features/intercede/data/store.dart`, `lib/features/memorize/data/memorize_repository.dart`, `lib/features/leyaana/data/repository.dart`, `lib/features/leyaana/ui/leyaana_admin_screen.dart`
- Impact: Bugs fixed in one outbox (see the race above) are not fixed in the others. Admin edits in `leyaana` are lost-on-failure with no queue, unlike the other two features that the CHANGELOG describes as offline-first.
- Fix approach: Extract one generic `SanityOutbox` (queue, flush, persist, serialized access) in `lib/core/sanity/` and have all three features use it. Keep `applyMutation` local to `intercede` because it is the only feature that needs an optimistic local model.

**Intercede outbox `insert` is not idempotent:**
- Issue: `flush()` sends `_outbox.first` and only removes it after the response and a save. If the app is killed between the server accepting the write and the save, the mutation is resent on next launch. `patch.insert` (append to `logs`) then duplicates the entry. The same duplication happens when `refresh()` replays the outbox over fresh server data that already contains the appended item (the server applied it, but the outbox has not been pruned yet).
- Files: `lib/features/intercede/data/store.dart` (`flush`, `refresh`, `_applyPatch`)
- Impact: Duplicate prayer log entries. Low frequency, but silent and persistent.
- Fix approach: Give each queued mutation a client-generated id and an `_outbox` marker, or add a Sanity-side guard (a `_key` on each log item, then `insert` with a dedupe check in `applyMutation` by `_key`). The comment "append is the whole story" in `_applyPatch` documents the assumption; it does not protect against retries.

**Silent failure swallowing in sync paths:**
- Issue: `uploadPendingRecordings()` wraps everything in `catch (_) {}`. `uploadRecordingToSanity()` sets the local `sanityUrl` before the verse patch and downgrades a failed link to a `debugPrint`, so local state says "uploaded" while Sanity has no `audioFile` reference. `prefetchJftNow()` and `IntercedeStore.refresh()` also swallow errors.
- Files: `lib/features/memorize/data/memorize_repository.dart` (`uploadPendingRecordings`, `uploadRecordingToSanity`), `lib/core/background.dart`, `lib/features/intercede/data/store.dart`
- Impact: A recording can be marked as uploaded yet never linked to its verse. Nothing retries that link, because `isUploadedToSanity` is now true. Users have no visible signal.
- Fix approach: Only set `sanityUrl` after the link patch succeeds (or link via the outbox). Track a `linked` flag separately from `uploaded`. Surface a count of pending sync items in the UI.

**Local-state read-modify-write races in SQLite:**
- Issue: `refreshFromSanity()` reads `db.getAll()` once, then upserts each verse built from that snapshot (`repetition`, `interval`, `easeFactor`, `lapses`, `streak` copied from `existing`). `addRecordingToVerse()` and `deleteRecordingFromVerse()` do get-then-upsert without a transaction. A review saved between the snapshot and the upsert is overwritten with stale SRS values.
- Files: `lib/features/memorize/data/memorize_repository.dart` (`refreshFromSanity`, `uploadRecordingToSanity`), `lib/features/memorize/data/memorize_db.dart` (`addRecordingToVerse`, `deleteRecordingFromVerse`, `upsert`)
- Impact: Lost spaced-repetition progress for a verse, which breaks the review schedule. The window is small (per-verse await) but `refreshFromSanity()` runs on every launch in the background.
- Fix approach: Wrap read-modify-write in `db.transaction(...)`, or have the refresh update only Sanity-owned columns (`title`, `verse`, `translation`, `isMastered`) with an UPDATE statement instead of a full-row replace.

**Full-row `ConflictAlgorithm.replace` on every write:**
- Issue: `MemorizeDb.upsert` replaces the whole row, so any caller holding a stale `MemorizeVerse` silently reverts other columns.
- Files: `lib/features/memorize/data/memorize_db.dart`
- Impact: Same class of bug as the race above, across all callers (`reviewVerse`, `toggleMastered`, `updateRecordingInVerse`).
- Fix approach: Use targeted UPDATE statements for each mutation type, or keep the single-writer rule and document it.

**Legacy starter-card cleanup runs on every launch:**
- Issue: `ensureInitialized()` calls `db.deleteStarterVerses()` each launch to remove rows from an old built-in seed (`starter_%` ids and `source = 'builtin'`). The seed no longer exists.
- Files: `lib/features/memorize/data/memorize_repository.dart` (`ensureInitialized`), `lib/features/memorize/data/memorize_db.dart` (`deleteStarterVerses`)
- Impact: Small, but it is a destructive query that will keep running indefinitely, and it can match a user-created row if an id ever starts with `starter_`.
- Fix approach: Run it once behind a settings flag (`memorize:starterCleanupDone`) and delete the function after one release.

**Duplicate and unused schema in Sanity `memorizeVerse`:**
- Issue: The schema defines both `category` (string) and `categoryRef` (reference to `verseCategory`), and a `voiceRecordings` array. The app writes only `category` as a string and uses a single `audioFile`. Nothing in `lib/` reads `voiceRecordings` or `categoryRef`.
- Files: `sanity/schemaTypes/memorizeVerse.ts`, `sanity/schemaTypes/verseCategory.ts`, `lib/features/memorize/data/memorize_repository.dart`
- Impact: Editors in Sanity Studio can fill fields the app never displays, and the data drifts from what the app syncs.
- Fix approach: Remove `voiceRecordings` and `categoryRef` or wire them up in the app. Pick one category model.

**Hard-coded personal-build assumptions and stale docs:**
- Issue: `CHANGELOG.md` 1.0.0 says "API keys/tokens are compiled into this personal build" and 1.0.0 says "iOS builds". The current code stores both keys in SharedPreferences via Settings, and the repo has no `ios/`, `macos/`, or `web/` folder at all.
- Files: `CHANGELOG.md`, `lib/core/sanity/client.dart` (`String.fromEnvironment('SANITY_WRITE_TOKEN')`), `lib/core/settings.dart`
- Impact: Misleading for anyone (including future you) reading the changelog. The iOS claim cannot be verified from this repo.
- Fix approach: Correct the 1.0.0 notes in `CHANGELOG.md` to match what shipped. Either restore an iOS project or drop iOS from the README.

**Monolithic screens:**
- Issue: Several UI files are large and mix state, data calls, and layout: `lib/features/memorize/ui/practice/voice_recorder_view.dart` (721 lines), `lib/features/intercede/ui/intercede_screen.dart` (589 lines), `lib/features/leyaana/ui/leyaana_screen.dart` (407 lines), `lib/features/memorize/ui/practice/typing_challenge_view.dart` (384 lines), `lib/features/leyaana/ui/leyaana_admin_screen.dart` (373 lines).
- Files: as listed
- Impact: Hard to change safely. Dialogs and their data logic live inside `build` trees (for example the add/edit dialogs in `intercede_screen.dart` around lines 317-370 and 532).
- Fix approach: Move dialog bodies into their own widgets (the `prayer_editor_page.dart` and `prayer_menu.dart` files already show the pattern). Move data calls out of widgets into the repositories.

**Misnamed test file:**
- Issue: `test/widget_test.dart` contains no widget tests. It tests `getPeriodKey` / `hashValue` from `lib/features/leyaana/data/daily_pick.dart`.
- Files: `test/widget_test.dart`
- Impact: Misleads anyone looking for widget coverage; the default Flutter template name is kept.
- Fix approach: Rename to `test/daily_pick_test.dart`.

## Known Bugs

**Gemini key is sent in the request URL:**
- Symptoms: The API key is part of the query string (`?key=...`) of the Gemini `generateContent` call. Any exception that includes the request URL (the `http` package's `ClientException`, or a proxy or crash log that records the URI) exposes the key.
- Files: `lib/features/just_for_today/data/repository.dart` (`translate`)
- Trigger: Network error during `translate()`, or any HTTP-level logging.
- Workaround: None in code. Move the key to the `x-goog-api-key` request header, which Google's API accepts, so it stays out of URLs.

**Daily verse key uses UTC, notification time uses local time:**
- Symptoms: For users east of UTC, a reminder set between 00:00 and the UTC offset can pick the previous day's verse, because `_nextInstance` builds a local `TZDateTime` and `getPeriodKey` converts it to UTC before keying the map.
- Files: `lib/core/notifications.dart` (`scheduleVerses`, `_nextInstance`), `lib/features/leyaana/data/daily_pick.dart` (`getPeriodKey`)
- Trigger: Reminder time set to an hour that falls on a different UTC date from the local date (e.g. 01:00 in UTC+2).
- Workaround: Set the reminder after the UTC offset boundary. Proper fix: key the verse map by the local date the notification fires on, and keep the widget keyed the same way (see `lib/features/leyaana/data/verse_surfaces.dart`, `android/app/src/main/kotlin/com/aio/aio/VerseWidgetProvider.kt`, both UTC).

**Reading is silently truncated for translation:**
- Symptoms: `translate()` cuts the source text at 8000 characters without telling the user. The translated "Just For Today" can be missing its end.
- Files: `lib/features/just_for_today/data/repository.dart` (`translate`)
- Trigger: Source page longer than 8000 characters after HTML stripping.
- Workaround: None. Log when truncation happens and show a notice, or split the source into chunks.

**Gemini safety/empty responses produce a generic crash path:**
- Symptoms: `data['candidates'][0]['content']['parts'][0]['text']` throws a `RangeError` / `TypeError` when Gemini returns no candidates (blocked or empty response). The user sees the generic failure path.
- Files: `lib/features/just_for_today/data/repository.dart` (`translate`)
- Trigger: Model blocks output or returns an empty candidate list.
- Workaround: None. Check for `candidates` and `finishReason` before indexing.

**Verse widget and cached data depend on the `flutter.` SharedPreferences prefix:**
- Symptoms: The native widget reads `FlutterSharedPreferences` / `flutter.verse-widget`. If the Flutter plugin changes its key prefix, or the cache key is renamed in `refreshVerseSurfaces`, the widget silently shows the fallback text "افتح التطبيق لتحميل آية اليوم".
- Files: `android/app/src/main/kotlin/com/aio/aio/VerseWidgetProvider.kt`, `lib/features/leyaana/data/verse_surfaces.dart`, `lib/core/settings.dart`
- Trigger: Plugin upgrade or key rename.
- Workaround: Open the app to refresh. Put the key name in one shared constant and cover it with a test.

**Recording file reuse on rapid re-record (low risk):**
- Symptoms: `AudioService.startRecording()` deletes any existing file at the target path before recording. Paths are derived from ids with millisecond timestamps (`custom_<ms>`, `<verseId>_<ms>`), so collisions are unlikely but possible if two takes start in the same millisecond.
- Files: `lib/features/memorize/data/audio_service.dart`, `lib/features/memorize/ui/add_verse_sheet.dart`, `lib/features/memorize/ui/practice/voice_recorder_view.dart`
- Trigger: Two recordings started within the same millisecond.
- Workaround: None needed in practice. Use a UUID for take ids.

## Security Considerations

**Sanity write token grants full write access and is stored in plaintext:**
- Risk: The token in Settings is written to SharedPreferences (`lib/core/settings.dart`, key `sanityWriteToken`), which on Android is an unencrypted XML file in app data. The token authorizes create, patch, and delete on the production dataset (`kfme7y2v` / `production`), and `sanityMutate` / `sanityUploadFile` use it for all writes. The `delete` operation in `leyaana` (`deleteDoc`) can remove any document type in the dataset.
- Files: `lib/core/settings.dart`, `lib/core/sanity/client.dart`, `lib/features/settings/settings_screen.dart`, `lib/features/leyaana/data/repository.dart`
- Current mitigation: Obscured text field in Settings (`_SecretField`, `obscureText`). Autocorrect and suggestions are disabled.
- Recommendations: Use `flutter_secure_storage` (Android Keystore-backed) for the token and the Gemini key. Create a Sanity token with the narrowest role that works (editor on the three content types). Rotate it if it has ever been displayed, exported, or pasted into a shared place.

**Gemini API key in SharedPreferences and in the URL:**
- Risk: Same storage issue as above, plus the URL exposure described under Known Bugs. The key is read by `_geminiKey` and by the background isolate in `lib/core/background.dart`.
- Files: `lib/core/settings.dart`, `lib/features/just_for_today/data/repository.dart`, `lib/core/background.dart`
- Current mitigation: Entered by the user in Settings and stored only on-device.
- Recommendations: Move to secure storage and the header-based auth. Restrict the key in Google AI Studio / Cloud Console to the Generative Language API and to the Android app signature (package `com.andro.daily` plus SHA-1 of the release certificate).

**OTA self-update installs an APK fetched from GitHub with no integrity check:**
- Risk: `checkForUpdate()` takes the first `.apk` asset from the latest GitHub release and `installUpdate()` downloads and installs it. There is no checksum, no signature check in app code, and no pin on the expected signing certificate. Android enforces the same-signature rule on install, which limits the damage, but a compromised release or a hijacked GitHub account could ship an APK that is signed with a different key and is rejected, or a same-key APK that was built from different source.
- Files: `lib/core/updater.dart`, `lib/features/settings/settings_screen.dart` (`_update`), `android/app/src/main/AndroidManifest.xml` (`REQUEST_INSTALL_PACKAGES`)
- Current mitigation: Android package-signature enforcement on install. Update is user-initiated from the Settings screen.
- Recommendations: Publish a SHA-256 checksum alongside the APK in the release and verify it before install. Pin the expected `apk` name pattern (`daily-v*.apk`) instead of `endsWith('.apk')`. Keep the install user-initiated.

**Release signing: fallback to debug key and non-fatal verification:**
- Risk: `android/app/build.gradle.kts` falls back to the debug signing config when `android/key.properties` is absent, so a local or misconfigured release build is signed with the debug key. In CI, `.github/workflows/release.yml` only prints a `keytool` failure as a notice, and it filters non-base64 characters out of the secret silently, so a corrupt secret can reach the build step. The keystore password is also passed as a command-line argument to `keytool` (visible to other processes on the runner).
- Files: `android/app/build.gradle.kts`, `.github/workflows/release.yml`
- Current mitigation: CI fails when `KEYSTORE_BASE64` is empty and when the decoded file is empty. `android/.gitignore` excludes `key.properties`, `*.jks`, and `*.keystore`.
- Recommendations: Make the release build fail when `key.properties` is missing (`throw GradleException` in the release branch). Make the `keytool` check fail the job. Do not echo or pass secrets on the command line: have `keytool` read the password from an environment variable with `-storepass:env`.

**Unsanitised user text in Sanity upload filename:**
- Risk: `sanityUploadFile` puts `filename` straight into the query string without URL-encoding (`?filename=$filename`). Current callers pass ids of the form `voice_<id>_<rec>.m4a` with safe characters only, so this is latent.
- Files: `lib/core/sanity/client.dart` (`sanityUploadFile`), `lib/features/memorize/data/memorize_repository.dart` (`uploadRecordingToSanity`)
- Current mitigation: Ids are generated by the app with alphanumeric characters.
- Recommendations: Wrap the filename in `Uri.encodeQueryComponent` or pass it through `Uri(queryParameters:)`.

**Scraped remote HTML is rendered as text:**
- Risk: `fetchSource()` strips tags with regexes from `https://www.jftna.org/jft/` and sends the text to Gemini. Content is shown as plain text, so XSS is not a concern, but a changed or hostile page can inject prompt text into the translation request.
- Files: `lib/features/just_for_today/data/repository.dart` (`fetchSource`, `translate`)
- Current mitigation: Output must parse as the expected JSON schema; `translate` extracts the object and fails otherwise.
- Recommendations: Accept only the expected structure and validate string lengths before saving to cache.

**Android permissions broader than used:**
- Risk: `USE_EXACT_ALARM` is declared, but notifications are scheduled with `AndroidScheduleMode.inexactAllowWhileIdle` (`lib/core/notifications.dart`). `RECORD_AUDIO` and `REQUEST_INSTALL_PACKAGES` are needed; `USE_EXACT_ALARM` is not.
- Files: `android/app/src/main/AndroidManifest.xml`, `lib/core/notifications.dart`
- Current mitigation: None needed for the in-use permissions.
- Recommendations: Remove `USE_EXACT_ALARM` unless exact timing is required. Play policy restricts it for most apps.

## Performance Bottlenecks

**Large JSON payloads stored in SharedPreferences:**
- Problem: The Intercede entity list (`intercede:entities`), its outbox (`intercede:outbox`), the Leyaana content caches (`content-cache:*`), the verse-widget map (`verse-widget`), and the Memorize outbox are all JSON strings in SharedPreferences. Every save rewrites the whole value.
- Files: `lib/core/settings.dart` (`setCache`, `getCache`), `lib/features/intercede/data/store.dart` (`_save`), `lib/features/memorize/data/memorize_repository.dart` (`_saveOutbox`), `lib/features/leyaana/data/repository.dart` (`_fetchType`), `lib/features/leyaana/data/verse_surfaces.dart`
- Cause: SharedPreferences is a key-value XML file, not a database. `IntercedeStore.apply` re-encodes the full list on every edit, and each outbox flush step does the same.
- Improvement path: Move entity and outbox caches to the existing sqflite setup (`lib/features/memorize/data/memorize_db.dart` already uses it). Keep SharedPreferences for small flags only.

**Full-table reads on every refresh:**
- Problem: `refreshFromSanity()` loads all memorize rows and all Sanity documents, then upserts every row one at a time. `dailyVersesFor()` re-fetches and re-sorts the full verse list on each launch.
- Files: `lib/features/memorize/data/memorize_repository.dart` (`refreshFromSanity`), `lib/features/leyaana/data/repository.dart` (`dailyVersesFor`), `lib/features/leyaana/data/verse_surfaces.dart` (`refreshVerseSurfaces`)
- Cause: No incremental sync (no `_updatedAt` filter, no transaction around the per-row upserts).
- Improvement path: Wrap the per-row upserts in a sqflite batch (`MemorizeDb.upsertAll` already exists and is unused by the refresh path). Use `_updatedAt` to fetch only changes once the list grows.

**Blocking launch work:**
- Problem: `main()` in `lib/main.dart` awaits `Notifications.init()` before `runApp`, and that call re-schedules up to 14 notifications and reads timezone data. It also starts several background tasks on launch.
- Files: `lib/main.dart`, `lib/core/notifications.dart`
- Cause: Notification re-arming on every launch.
- Improvement path: Re-arm only when the reminder settings change or after a reboot (the boot receiver in `AndroidManifest.xml` already covers reboot). Move the rest to unawaited work.

**Large widgets rebuilt on each state change:**
- Problem: Screens with many inline controllers and whole-list `setState` calls (for example the `setState` in `lib/features/settings/settings_screen.dart`, and the audio-player progress streams in `lib/features/memorize/ui/audio_playlist_screen.dart`) rebuild entire lists.
- Files: `lib/features/memorize/ui/audio_playlist_screen.dart`, `lib/features/intercede/ui/intercede_screen.dart`
- Cause: No state management layer; `ValueNotifier` is used in some places and `setState` in others.
- Improvement path: Scope rebuilds with `ValueListenableBuilder` on the per-item state that changes.

## Fragile Areas

**`IntercedeStore` local replay (`applyMutation`):**
- Files: `lib/features/intercede/data/store.dart`, `test/intercede_store_test.dart`
- Why fragile: The optimistic local model re-implements a subset of Sanity's patch semantics (`set`, `unset`, `setIfMissing`, `insert after logs[-1]`). Any new mutation shape emitted by the UI silently does nothing locally (`applyMutation` ignores unknown operations).
- Safe modification: Add a test for each new operation before emitting it. Keep the outbox shape in sync with `lib/features/intercede/data/repository.dart`.
- Test coverage: Covered by `test/intercede_store_test.dart` for the current operations. No test covers the flush/refresh interleaving described under Known Bugs.

**`MemorizeRepository` sync logic:**
- Files: `lib/features/memorize/data/memorize_repository.dart`
- Why fragile: Mixes outbox replay, Sanity reconciliation, deletion of local rows that the server no longer has (`source == 'sanity'` only), and recording upload in one 376-line class. The reconciliation step deletes local rows when the server response omits them, so a partial or empty server response would delete data.
- Safe modification: Change one step at a time and verify with the outbox replayed by hand. Consider guarding the deletion branch: skip it when the server result is empty and the local set is non-empty.
- Test coverage: None. `test/` has no test for `memorize_repository.dart` or the outbox.

**Verse selection and date keys:**
- Files: `lib/features/leyaana/data/daily_pick.dart`, `lib/features/leyaana/data/repository.dart`, `lib/core/notifications.dart`, `lib/features/leyaana/data/verse_surfaces.dart`, `android/app/src/main/kotlin/com/aio/aio/VerseWidgetProvider.kt`
- Why fragile: The verse for a day must match the PWA byte-for-byte (per the comments). The key format and the UTC rule are duplicated in Dart and Kotlin, and in `dailyVersesFor` the personalised text depends on `Settings.isMale` and `personKey`. Changing the name or gender re-keys the picks.
- Safe modification: Change `getPeriodKey` and `hashValue` only with the existing tests in `test/widget_test.dart` updated. Update `VerseWidgetProvider.kt` in the same change.
- Test coverage: `test/widget_test.dart` covers the hash and key format but not the notification or widget paths.

**Background isolate (`callbackDispatcher`):**
- Files: `lib/core/background.dart`
- Why fragile: Runs in its own isolate without app state. It reads `Settings` and uses the Gemini key, so any change to the key name or cache key changes its behaviour. Errors are swallowed to `return true` when the key is missing.
- Safe modification: Keep it calling only top-level functions. Test with the WorkManager debug trigger on a device after any change.
- Test coverage: None.

**Native/Dart contract for the widget:**
- Files: `android/app/src/main/kotlin/com/aio/aio/MainActivity.kt` (`aio/widget` channel), `android/app/src/main/kotlin/com/aio/aio/VerseWidgetProvider.kt`, `lib/features/leyaana/data/verse_surfaces.dart`
- Why fragile: The method channel name, the SharedPreferences key, and the JSON shape (`t`, `v`, keyed by day) are shared by string literal in two languages.
- Safe modification: Change all three together. Keep the `MissingPluginException` fallback in `verse_surfaces.dart` in mind for iOS.
- Test coverage: None.

**Release pipeline:**
- Files: `.github/workflows/release.yml`, `android/app/build.gradle.kts`
- Why fragile: Versions come from the git tag (`versionName`) and the run number (`versionCode`). OTA updates require every release to keep the same signing key and a monotonically increasing run number. A change to `flutter.versionCode` or to the keystore breaks installed copies.
- Safe modification: Never change the keystore. Do not add manual `--build-number` values.
- Test coverage: None. CI does not run `flutter analyze` or `flutter test`.

## Scaling Limits

**Single-user, single-tenant design:**
- Current capacity: One user, one Sanity dataset, one device.
- Limit: Settings, caches, and outboxes are keyed globally (`Settings` is a process-wide singleton). A second profile on the same device would share all state.
- Scaling path: Not needed for a personal app. If multi-user is ever wanted, namespace every SharedPreferences key by user id and move the caches into sqflite.

**Sanity and Gemini request volume:**
- Current capacity: Each launch triggers Sanity queries (`intercede` `load`/`refresh`, `memorize` `refreshFromSanity`, `leyaana` `_fetchType` x3, `verse` daily picks), plus one Gemini call per day and one GitHub API call per settings check.
- Limit: Sanity API request quotas and Gemini rate limits (plan limits not verified from the repo). No backoff exists for Sanity queries; each refresh is a full fetch.
- Scaling path: Reduce launch-time fetches (cache TTL per type), use `cdn: true` consistently for read-only queries (`memorize` and `intercede` use `cdn: false`, so they bypass the CDN), and add exponential backoff for `sanityQuery`.

**Audio storage on device:**
- Current capacity: Recordings are stored as AAC 128 kbps, 44.1 kHz, in `verses_voices/` under the app documents directory (`lib/features/memorize/data/audio_service.dart`). Roughly 1 MB per minute.
- Limit: No cap, no cleanup of orphaned files (files whose verse was removed from the DB but not from disk), and every recording is uploaded to Sanity without a size check.
- Scaling path: Add a periodic orphan sweep, and warn on uploads above a size threshold.

## Dependencies at Risk

**Gemini model is a preview identifier:**
- Risk: `const _model = 'gemini-3-flash-preview'` in `lib/features/just_for_today/data/repository.dart`. Preview models are retired on short notice.
- Impact: The "Just For Today" translation fails for every user until the model string is updated; the cached copy keeps working for the current day only.
- Migration plan: Move the model name into Settings (or a remote config) so it can be changed without a release, and fall back to a stable model on a 404.

**`ota_update` and `workmanager` are pinned loosely:**
- Risk: `ota_update: ^7.1.0` and `workmanager: ^0.10.10` in `pubspec.yaml`. `workmanager` runs Dart code in a background isolate and its behaviour differs across Android versions. `ota_update` drives APK install with `REQUEST_INSTALL_PACKAGES`.
- Impact: A minor upgrade can change background scheduling or install behaviour without a test.
- Migration plan: Pin exact versions in `pubspec.lock` (already present) and test the update and background paths manually after each bump.

**`flutter_local_notifications` API churn:**
- Risk: Calls use named parameters (`zonedSchedule(id: ..., title: ...)`, `cancel(id: ...)`) that differ between major versions.
- Impact: A major bump breaks `lib/core/notifications.dart` at compile time; the scheduled reminders and boot-restore path are the thing to verify.
- Migration plan: Check the plugin changelog and re-test a scheduled notification after reboot.

**Dart SDK constraint is recent:**
- Risk: `environment: sdk: ^3.10.4` in `pubspec.yaml`. Contributors on older Flutter stable channels cannot build.
- Impact: CI uses `subosito/flutter-action` with `channel: stable`, so CI picks whatever is current. Local and CI can diverge.
- Migration plan: Pin the Flutter version in the workflow (`flutter-version`) and in `.metadata` (already present).

## Missing Critical Features

**No CI test or analysis gate:**
- Problem: `.github/workflows/release.yml` builds and publishes the APK on tag push, but nothing runs `flutter analyze` or `flutter test` before publishing.
- Blocks: A regression in `anki_engine`, `intercede_store`, or `daily_pick` can ship in a release, and OTA installs reach users automatically on the next "check for update".

**No crash or error reporting:**
- Problem: Errors go to `debugPrint` or are swallowed (see Tech Debt). There is no crash reporter (no Crashlytics, Sentry, or equivalent in `pubspec.yaml`).
- Blocks: Diagnosing sync failures on a device that is not connected to a debugger, including the lost-write race above.

**No Sanity outbox visibility in the UI:**
- Problem: Pending mutations exist (`hasPending` in `IntercedeStore`; the Memorize outbox has no public accessor) but are not shown to the user.
- Blocks: The user cannot tell whether an edit has reached Sanity.

**No data export or backup:**
- Problem: The journal (`lib/features/journal/data/journal_db.dart`), Memorize SQLite data, and local recordings have no export path. Settings and tokens are device-only.
- Blocks: Recovery after a device loss, unless the Sanity side holds the data (it does for verses and prayers, not for journal entries or SRS progress).

## Test Coverage Gaps

**Sync and outbox behaviour:**
- What's not tested: Queuing during an in-flight flush (the lost-write race), recovery after a crash between send and save, and the `insert` duplication on replay.
- Files: `lib/features/memorize/data/memorize_repository.dart`, `lib/features/intercede/data/store.dart`
- Risk: Silent data loss or duplicate entries that only appear on a real device with a flaky network.
- Priority: High

**Memorize repository reconciliation:**
- What's not tested: `refreshFromSanity()` deletion of local rows, recording upload and link, and `ensureInitialized()`.
- Files: `lib/features/memorize/data/memorize_repository.dart`, `lib/features/memorize/data/memorize_db.dart`
- Risk: Deleting local verses or SRS progress on an empty or partial server response.
- Priority: High

**Leyaana content and admin writes:**
- What's not tested: `createDoc`, `updateDoc`, `deleteDoc`, `_fetchType` cache fallback, and `dailyVersesFor`.
- Files: `lib/features/leyaana/data/repository.dart`, `lib/features/leyaana/ui/leyaana_admin_screen.dart`
- Risk: Admin edits fail with no retry and no offline queue; cache fallback behaviour is untested.
- Priority: Medium

**Just For Today pipeline:**
- What's not tested: `fetchSource` HTML stripping, `translate` JSON extraction, the 8000-character truncation, and the Gemini error paths.
- Files: `lib/features/just_for_today/data/repository.dart`
- Risk: Silent breakage when the source site or Gemini response shape changes.
- Priority: Medium

**Updater:**
- What's not tested: `_isNewer` / `_parts` version comparison (ignores build number, and `firstWhere` throws when no APK asset exists), and `checkForUpdate` error paths.
- Files: `lib/core/updater.dart`
- Risk: An update check that throws instead of reporting "up to date" when a release has no APK.
- Priority: Medium

**Background tasks and notifications:**
- What's not tested: `callbackDispatcher`, `initDailyPrefetch`, `Notifications.scheduleVerses`, and the boot restore path.
- Files: `lib/core/background.dart`, `lib/core/notifications.dart`
- Risk: Reminders stop firing after an app update or reboot without any visible error.
- Priority: Medium

**Native widget:**
- What's not tested: `VerseWidgetProvider.render` day-key lookup and fallback text.
- Files: `android/app/src/main/kotlin/com/aio/aio/VerseWidgetProvider.kt`
- Risk: The widget shows the fallback text for every user after a key change, with no failing test.
- Priority: Low

---

*Concerns audit: 2026-11-02*
