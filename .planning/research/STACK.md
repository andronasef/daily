# Stack Research

**Domain:** Interactive, offline Android home-screen widget in an existing Flutter app, plus a shared sort setting
**Researched:** 2026-11-02
**Confidence:** MEDIUM (primary sources throughout, nothing yet tested on a device)

**Verdict:** Add a second hand-written `AppWidgetProvider` using `RemoteViews`. No new packages, in `pubspec.yaml` or in Gradle. Each row gets its own immutable broadcast `PendingIntent`. A native queue holds taps, and a daily inexact alarm redraws the widget after local midnight. Current Android rules do not push this design toward Glance or `home_widget`.

**How to read the confidence levels.** The `classify-confidence` seam rates `webfetch` as LOW, even with `--verified`, because it scores the provider and not the source. No curated provider was available here (no Context7 MCP tool, no `ctx7` CLI), so the research cache stores every digest as LOW. The per-recommendation levels below are this researcher's judgment of the evidence:

- **HIGH:** official Android or Flutter docs, or AOSP source, agree with code read in this repo.
- **MEDIUM:** a single primary source, or an inference from source code with no device test.
- **LOW:** vendor behaviour or an untested assumption.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| `AppWidgetProvider` + `RemoteViews` | Platform, minSdk 24 | Widget UI and tap handling | `VerseWidgetProvider` already uses this pattern, so it adds no dependency. Docs steer new widgets toward Glance, but no page read deprecates this API. | HIGH |
| `setOnClickPendingIntent` on 5 fixed rows | Platform | One tap target per request | Fixed rows can use immutable intents. Collection items would force a mutable template (see Alternatives). | HIGH |
| `PendingIntent.getBroadcast` to an explicit component | Platform | Delivers the tap to the provider's `onReceive` | Works without Dart, network, or an open app. Android 12 and later forbid an unspecified mutability flag. | HIGH |
| Platform `SharedPreferences`, dedicated file | Platform | Durable native queue of taps | Only Kotlin writes it, so it avoids the Dart cache and the `flutter.` key prefix (see Pattern 2). | HIGH |
| `AlarmManager.setAndAllowWhileIdle` | Platform | Redraw after local midnight | No permission needed, fires during Doze, and one alarm a day stays well inside every quota. | HIGH |
| `aio/widget` `MethodChannel` | Existing | Refresh both widgets, peek and ack the queue | Already wired in `MainActivity`. | HIGH |
| `shared_preferences` legacy `SharedPreferences` API | 2.5.5 (locked) | Dart publishes widget JSON, stores the sort setting | The existing pattern depends on this backend writing to `FlutterSharedPreferences`. Do not migrate (see What NOT to Use). | HIGH |

### Supporting Libraries

No new libraries. Everything needed is already available:

| Need | Use | Instead Of |
|------|-----|-----------|
| JSON in Kotlin | `org.json`, platform, already in `VerseWidgetProvider` | kotlinx.serialization, Gson |
| Stable tap id | `java.util.UUID.randomUUID()` | A uuid package |
| Local day key in Kotlin | `SimpleDateFormat("yyyy-MM-dd", Locale.US)` with the default time zone | A date library |
| Next local midnight | `java.util.Calendar` | `java.time` (also available, because desugaring is on) |
| Daily seed hash in Dart | Small hand-written hash such as FNV-1a over `day + id` | `String.hashCode` and `Random(seed)`. Dart docs say `hashCode` is not stable across runs and the `Random` stream can change between releases, which confirms the existing project decision. |
| Sort setting | A new key in `lib/core/settings.dart` | A state-management package |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `flutter_test` | Sort and seed logic, queue parsing | Existing. Dart holds all the sort logic, so it is testable here. |
| Emulator and physical device QA | Provider behaviour | The repo has no Kotlin test setup. Do not add one for about 100 lines of glue. |
| `adb shell dumpsys alarm` | Confirm the midnight alarm is armed | Filter on `com.andro.daily` or `com.andro.daily.dev`. |
| `adb shell dumpsys deviceidle force-idle` | Force Doze for the midnight test | From the official Doze testing guide. |
| `adb shell am set-standby-bucket` | Test the rare and restricted buckets | From the official standby docs. |
| `adb shell am force-stop` | Test the greyed-out widget and its recovery | Android 15 and later. |

## Installation

```bash
# Nothing to install. No changes to pubspec.yaml, pubspec.lock, or android/app/build.gradle.kts dependencies.
```

Files this work adds or changes on the Android side:

```
android/app/src/main/kotlin/com/aio/aio/IntercedeWidgetProvider.kt   new
android/app/src/main/res/layout/intercede_widget.xml                 new
android/app/src/main/res/xml/intercede_widget_info.xml               new
android/app/src/main/AndroidManifest.xml                             add <receiver>
android/app/src/main/kotlin/com/aio/aio/MainActivity.kt              extend the channel
```

## Implementation Patterns

### Pattern 1: Row tap

```kotlin
private fun markIntent(context: Context, prayerId: String): PendingIntent =
    PendingIntent.getBroadcast(
        context, 0,
        Intent(context, IntercedeWidgetProvider::class.java)
            .setAction(ACTION_MARK)
            .setData(Uri.fromParts("aio", prayerId, null))
            .addFlags(Intent.FLAG_RECEIVER_FOREGROUND),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
```

- **Put the id in the data URI, not an extra.** `PendingIntent` identity ignores extras, so five rows differing only by an extra collapse into one intent. Read it back with `intent.data?.schemeSpecificPart`.
- **Prefer the URI to a row-index `requestCode`.** With a row-index code and `FLAG_UPDATE_CURRENT`, a tap landing during a redraw can fire the new id for that row and mark a different request. A URI ties each intent to its prayer.
- **Set `FLAG_RECEIVER_FOREGROUND`.** The official docs recommend it for tap-driven updates, because default broadcasts can be delayed under load.
- **Override `onReceive`, handle `ACTION_MARK`, and call `super.onReceive` for everything else.**
- **Manifest filter stays as is.** The intent names the class explicitly, so the filter needs only `APPWIDGET_UPDATE`, matching the docs' own custom-action sample.

### Pattern 2: Tap queue

In `onReceive`, on the main thread:

1. Append `{tapId, prayerId, tappedAtMillis}` to the queue with `commit()`.
2. Skip the append if that prayer already has a tap today, which absorbs double taps.
3. Redraw all instances.

Drain over the channel in two steps: `peek`, then persist through `logPrayed` and the outbox, then `ack(tapIds)`. Both the receiver and the channel handler run on the main thread, so they cannot interleave. A single `take` call would lose taps if the app died before the outbox write.

Why not read the queue from Dart with `reload()`? It is one line shorter, but the read and the later remove are separate steps that Kotlin can write between. Taps must not get lost, so this is a place not to cut the corner.

`commit()` is a small synchronous write. `apply()` is also safe in a receiver, because AOSP's `PendingResult.finish` waits for queued work, but `commit()` makes the guarantee obvious. No `goAsync()` or threads are needed.

### Pattern 3: Midnight reset

```kotlin
val next = Calendar.getInstance().apply {
    set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
    set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    add(Calendar.DAY_OF_YEAR, 1)
}.timeInMillis
context.getSystemService(AlarmManager::class.java)
    .setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, midnightIntent)
```

- Arm this inside `render()`. The same `PendingIntent` replaces the old alarm, so re-arming is idempotent and covers every recovery path.
- AOSP sends the provider an update on user unlock and on package replace, so reboots and OTA installs re-arm it through `onUpdate`. Launching the app also re-arms it through the channel.
- Cancel the alarm in `onDisabled`.
- `render()` must compare the payload's day to today, so any redraw after midnight shows a reset state. The alarm is only the trigger.
- Keep a nonzero `updatePeriodMillis` as a backstop. A value of a few hours matches the verse widget.

## Android Requirements

Project baseline: compileSdk 36, targetSdk 36, minSdk 24, on both the local Flutter 3.44.9 and CI's stable 3.47.9.

| Requirement | Applies From | Consequence | This Project | Confidence |
|-------------|--------------|-------------|--------------|------------|
| Declare `android:exported` on components with an intent filter | Target 31 | Build or install fails | Set `exported="false"`, as `VerseWidgetProvider` does. It also blocks other apps from forging taps. | HIGH |
| State mutability on every `PendingIntent` | Target 31 | Required at creation | `FLAG_IMMUTABLE` everywhere. | HIGH |
| `FLAG_MUTABLE` only when the intent must be modified | Docs guidance | Unneeded mutable intents widen the attack surface | Not needed. Fixed rows have nothing to fill in. | HIGH |
| Mutable `PendingIntent` with an implicit intent throws | Target 34 | Exception at creation | Not applicable: immutable and explicit. | HIGH |
| Implicit intents reach exported components only | Target 34 | Delivery fails | Always name the provider class. | HIGH |
| No manifest receivers for most implicit broadcasts | Target 26 | The broadcast never arrives | `ACTION_DATE_CHANGED` is not on the exception list. `TIME_SET` and `TIMEZONE_CHANGED` are. | HIGH |
| `onReceive` limit of about 10 seconds, on the main thread | All | ANR, and the process may die after return | Do only JSON, a prefs write, and `updateAppWidget`. No background threads. | HIGH |
| No foreground services started from a background receiver | Target 31 | `ForegroundServiceStartNotAllowedException` | None used. | HIGH |
| Background activity start limits | Android 10, tightened at 14, 15, 17 | Launch silently blocked | Launcher-initiated widget taps are exempt. Use `PendingIntent.getActivity` directly for "open app". Never `startActivity` from the receiver. | HIGH |
| Exact alarms need special access | Target 31 | `SecurityException` | Use inexact alarms. See Stack Patterns before going exact. | HIGH |
| Inexact alarm timing | Android 12 | Fires within an hour of the trigger, absent battery restrictions | The widget may stay stale for up to an hour after midnight. Taps still carry real timestamps. | HIGH |
| Doze defers standard alarms | Android 6 | Alarm waits for a maintenance window | `setAndAllowWhileIdle` fires anyway, limited to about once per nine minutes per app. | HIGH |
| Standby bucket alarm limits | Android 9 | Rare: 1 per hour. Restricted: 1 per day. | One alarm a day fits both. The app also gets no quota issue while charging. | HIGH |
| User-restricted battery | Android 9 | Alarm execution is restricted | Accepted. The redraw happens on the next `updatePeriodMillis` tick or app open. | MEDIUM |
| Force-stop cancels pending intents and greys the widget | Android 15, all apps | Widget unusable until the app is launched | Unavoidable. The queue survives on disk, and the launch redraws the widget. | HIGH |
| Hibernation of unused apps | Android 12 | Alarms stop, but alarms alone do not count as use | Widget interaction counts as use, so regular tapping keeps the app active. | HIGH |
| Safer Intents strict matching | Android 16, opt-in | Unmatched intents blocked when enabled | Do not set `intentMatchingFlags="enforceIntentFilter"`. | HIGH |
| `RemoteViews` bitmap memory limit | Android 17, enforced at target 37 | `IllegalArgumentException` at target 37, a warning log below it | No effect: the widget is text-only and targets 36. Still use `updateAppWidget`, not partial updates. | HIGH |

**Layout allow-list.** `RemoteViews` accepts `FrameLayout`, `LinearLayout`, `RelativeLayout`, `GridLayout`, `TextView`, `ImageView`, `Button`, `ImageButton`, `ProgressBar`, `Chronometer`, `AnalogClock`, `TextClock`, and collection views, but no subclasses or custom views. A bare `<View>` divider and `ConstraintLayout` are not on the list. Use a thin `FrameLayout` or `ImageView` for dividers.

## Project-Specific Traps

These came from reading this repo's code. Each will bite if `VerseWidgetProvider` is copied without thought.

1. **Do not copy the UTC day key.** `VerseWidgetProvider` deliberately uses a UTC day, to match Dart's `getPeriodKey`. `Prayer.prayedToday` in `lib/features/intercede/data/models.dart` uses the local day. A copied UTC key would reset the widget a few hours away from local midnight.
2. **Keep `Locale.US` for day keys.** The device may run in Arabic, and a default-locale formatter could produce non-Latin digits that no longer match the Dart-side key. Confidence: MEDIUM, from platform formatting behaviour, not tested here.
3. **Dart caches prefs.** The legacy API never sees native writes without `reload()`. This is a further reason to keep the queue behind the channel. Dart-to-Kotlin writes are unaffected.
4. **Drain on startup as well as on resume.** `app.dart` only calls `flush()` on `AppLifecycleState.resumed`. `IntercedeStore.load()` runs at startup from `main.dart`. Drain from both, because it is not established that a cold start delivers `resumed` to this observer.
5. **Publish more than 5 requests.** After an offline tap, Kotlin must backfill the row without sorting, so the JSON needs the ordered un-prayed list, not just the top 5.
6. **Drop unknown ids on drain.** A prayer can be deleted while a tap sits in the queue.
7. **Refresh both providers.** The channel's `update` handler currently renders only `VerseWidgetProvider`.

**Checked, not a problem:** the merged manifest has no `android:supportsRtl`, yet `verse_widget.xml` sets `layoutDirection="rtl"`. AOSP inflates `RemoteViews` under a wrapper around the host's context that does not override `getApplicationInfo()`, so `View.hasRtlSupport()` reads the launcher's flag. No manifest change is needed for widgets. Confidence: MEDIUM, from source reading. Confirm that a row actually mirrors on a device.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `RemoteViews` provider | Jetpack Glance 1.2.0 (stable, 2026-08-26) | A new native Android app that already uses Compose. Here it adds the Compose compiler plugin, `buildFeatures.compose`, and new AndroidX dependencies for 5 rows. Its updates run through WorkManager sessions, which Doze defers. Its `FontFamily` resolves system fonts and otherwise falls back, so the bundled Cairo font looks unreachable, which conflicts with a project constraint. |
| Native tap queue | `home_widget` 0.10.0 (2026-09-17) | An app needing cross-platform widgets, including iOS, or running Dart on each tap. Interactivity here goes through a non-expedited WorkManager job that starts a headless `FlutterEngine`. That makes taps deferrable in Doze, and it adds a second engine with its own `shared_preferences` cache, which the plugin README warns about. It also stores data in `HomeWidgetPreferences`, so the verse pattern would no longer match, and it adds `work-runtime-ktx` and coroutines. |
| Fixed rows | `RemoteCollectionItems` | Scrolling is needed later. It requires API 31, above this app's minSdk 24, and item clicks need a mutable template intent. Explicitly out of scope. |
| Row tap | `CheckBox` in `RemoteViews` | Minimum SDK of 31 or higher. It is API 31 only, so this app would need a second `res/layout-v31` layout. |
| Inexact alarm | `setExactAndAllowWhileIdle` | The reset must land within minutes. See Stack Patterns for the cost. |
| Alarm | WorkManager from Kotlin | Never for this. `workmanager_android` declares `androidx.work` as `implementation`, so it would be a new direct dependency, and JobScheduler does not run in Doze. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `SharedPreferencesAsync` or `SharedPreferencesWithCache` migration | The README encourages it, but on Android they default to DataStore, which `FlutterSharedPreferences` readers cannot see. Both widgets would silently lose their data. | Stay on the legacy API. If it is ever deprecated, set `SharedPreferencesAsyncAndroidOptions(backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences)`. |
| `FLAG_MUTABLE` | No fill-in is needed, and it weakens the intent. | `FLAG_IMMUTABLE` |
| Prayer id in an extra, or `requestCode = 0` with extras | All rows collapse into one `PendingIntent`. | Data URI per prayer |
| `android:exported="true"` on the provider | Any app could mark prayers. The Glance docs show both values, but the Android 12 guidance and this repo both use `false`. | `exported="false"` |
| `ACTION_DATE_CHANGED` manifest receiver | Not on the implicit broadcast exception list, so it will not be delivered to a manifest receiver. | Midnight alarm |
| `partiallyUpdateAppWidget` | Saves nothing here, and Android 17 docs warn against it for images. | `updateAppWidget` |
| Reshuffling or sorting in Kotlin | Project decision. Would duplicate sort logic in two languages. | Dart sorts, Kotlin displays |
| Headless Dart on tap | Slow cold start, a second isolate, and more failure modes offline. | Native queue |
| `startActivity` in the receiver | Background activity limits, and the docs discourage it. | `PendingIntent.getActivity` on the view |
| `updatePeriodMillis` as the midnight mechanism | Minimum 30 minutes, not aligned to midnight, and docs advise no more than hourly. AOSP runs it as an inexact repeating alarm. | Alarm, with this as the backstop only |

## Stack Patterns by Variant

**If the midnight reset must be exact:**
- Use `setExactAndAllowWhileIdle` guarded by `canScheduleExactAlarms()`.
- The manifest declares only `USE_EXACT_ALARM`, which exists from API 33. Devices on API 31 and 32 would also need `SCHEDULE_EXACT_ALARM`.
- `USE_EXACT_ALARM` has limited Play use cases. That does not matter for GitHub Releases, but it would for a future Play listing.

**If the app later targets API 37:**
- No widget change is needed while it stays text-only.
- Re-check before adding bitmaps.

**If the user changes time zone:**
- Add `TIME_SET` and `TIMEZONE_CHANGED` to the provider's filter, since both are on the exception list.
- Skipped for now. The day comparison in `render()` corrects the state on the next redraw.

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| Flutter, local | 3.44.9 (fvm default) | compileSdk 36, targetSdk 36, minSdk 24, from `FlutterExtension.kt` |
| Flutter, CI | `channel: stable`, currently 3.47.9 (2026-10-29) | Same SDK values on the `stable` branch. CI is unpinned, so it differs from local, but no widget API depends on the difference. |
| Android Gradle Plugin | 8.11.1 | Unchanged |
| Gradle | 8.14 | Unchanged |
| Kotlin | 2.2.20 | Unchanged |
| `shared_preferences` | 2.5.5 | Locked. Latest is 2.5.6, no upgrade needed. |
| `shared_preferences_android` | 2.4.23 | Locked. Legacy plugin writes to `FlutterSharedPreferences` with `commit()`. |
| `java.time` | Via `desugar_jdk_libs` 2.1.4 | Available but unnecessary. `Calendar` needs no desugaring. |

## Gaps

- **No device testing was done.** Delivery on the user's real launcher is unproven until the first phase runs on hardware.
- **OEM battery managers** can restrict alarms beyond AOSP rules, and the rules vary by vendor. Check on the user's actual phone. Confidence: LOW.
- **Cairo in Glance** is inferred from the `FontFamily` reference text and not tested. This does not affect the recommendation.
- **AOSP behaviour** was read from the `aosp-mirror` `main` branch, which may trail current releases.
- **Idempotent logging** depends on how Sanity handles a replayed `insert`. A stable tap id gives the key, but the fix itself belongs to the architecture work.

## Sources

Android documentation:
- [App widgets overview and guide](https://developer.android.com/develop/ui/views/appwidgets): components, stateful widgets, bitmap limits
- [Advanced widgets](https://developer.android.com/develop/ui/views/appwidgets/advanced): update types, 10-second rule, foreground broadcast flag
- [Collection widgets](https://developer.android.com/develop/ui/views/appwidgets/collections): mutable template, `RemoteCollectionItems`, custom action sample
- [Create an app widget with Glance](https://developer.android.com/develop/ui/compose/glance/create-app-widget): manifest, `updatePeriodMillis`, attributes
- [RemoteViews reference](https://developer.android.com/reference/android/widget/RemoteViews): allow-list
- [PendingIntent reference](https://developer.android.com/reference/android/app/PendingIntent): identity rules and flags
- [Broadcasts overview](https://developer.android.com/develop/background-work/background-tasks/broadcasts): process lifetime, `goAsync`, security
- [Implicit broadcast exceptions](https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions)
- [Alarms](https://developer.android.com/develop/background-work/services/alarms): timing and permissions
- [Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Power management limits](https://developer.android.com/topic/performance/power/power-details): bucket alarm limits
- [App hibernation](https://developer.android.com/topic/performance/app-hibernation)
- [Background activity starts](https://developer.android.com/guide/components/activities/background-starts)
- [Application manifest element](https://developer.android.com/guide/topics/manifest/application-element): `supportsRtl`, `intentMatchingFlags`
- Behavior changes: [12](https://developer.android.com/about/versions/12/behavior-changes-12), [14](https://developer.android.com/about/versions/14/behavior-changes-14), [15 target](https://developer.android.com/about/versions/15/behavior-changes-15), [15 all](https://developer.android.com/about/versions/15/behavior-changes-all), [16 target](https://developer.android.com/about/versions/16/behavior-changes-16), [16 all](https://developer.android.com/about/versions/16/behavior-changes-all), [17 target](https://developer.android.com/about/versions/17/behavior-changes-17), [17 all](https://developer.android.com/about/versions/17/behavior-changes-all)

Libraries:
- [Glance release notes](https://developer.android.com/jetpack/androidx/releases/glance): versions, setup, WorkManager sessions
- [Glance FontFamily](https://developer.android.com/reference/kotlin/androidx/glance/text/FontFamily)
- [home_widget on pub.dev](https://pub.dev/packages/home_widget) and the [pub.dev API](https://pub.dev/api/packages/home_widget): version and date
- [home_widget source](https://github.com/ABausG/home_widget): `HomeWidgetBackgroundWorker.kt`, `HomeWidgetPlugin.kt`, `build.gradle`
- `shared_preferences` 2.5.5 README and source, and `shared_preferences_android` 2.4.23 source, from the local pub cache

Platform source, via the [aosp-mirror](https://github.com/aosp-mirror/platform_frameworks_base) `main` branch:
- `AppWidgetServiceImpl.java`: update on unlock and package change, 30-minute minimum, inexact repeating alarm
- `BroadcastReceiver.java`: `PendingResult.finish` waits for queued work
- `RemoteViews.java`, `AppWidgetHostView.java`, `View.java`: inflation context and RTL support

Flutter and Dart:
- `FlutterExtension.kt`, local 3.44.9 and the `stable` branch on [flutter/flutter](https://github.com/flutter/flutter)
- [Flutter releases JSON](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json): current stable
- Dart SDK `math/random.dart` and `core/object.dart`, local 3.44.9

Repo code: `VerseWidgetProvider.kt`, `MainActivity.kt`, `AndroidManifest.xml`, `build.gradle.kts`, `verse_widget.xml`, `verse_widget_info.xml`, `models.dart`, `repository.dart`, `store.dart`, `app.dart`, `verse_surfaces.dart`, `pubspec.lock`, the debug APK manifest, `.github/workflows/release.yml`

---
*Stack research for: تشفع Android widget and shared sort*
*Researched: 2026-11-02*
