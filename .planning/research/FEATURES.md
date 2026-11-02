# Feature Research

**Domain:** Android home-screen checklist widget and shared daily-stable list sort, for a single-user Arabic RTL prayer app
**Researched:** 2026-11-02
**Confidence:** MEDIUM overall. Findings about this codebase are HIGH (read directly or measured). Android rules are LOW by the classify-confidence seam (webfetch) even though they come from official pages; treat them as strong guidance and check on the device. Competitor behaviour is LOW.

Scope is settled in `PROJECT.md`. This file does not reopen those decisions. It sorts them into categories, flags what the Active list misses, and names the points where two requirements or existing code conflict.

## Gaps in the Active List

Ranked by what breaks if the gap is ignored. Each one is a proposed requirement or a decision for the user.

### Will visibly break the feature

| # | Gap | Evidence | Proposed requirement |
|---|-----|----------|----------------------|
| G1 | **The existing `hashValue` does not reshuffle.** A seed of `hashValue('$day:$id')` keeps about 4.9 of yesterday's top 5 today. The widget would show the same five requests every day. | Measured below. `hashValue` is `h*31+c`, so changing the day shifts every id by nearly the same offset. | Sort key is `Random(hashValue('$localDay:$id')).nextInt(1 << 32)`, tie-broken by id. Add one test on day-to-day top-5 overlap. |
| G2 | **Widget data must be the whole ordered list, not 5 rows.** With only 5 rows, the widget is empty after 5 taps with the app closed, and midnight has nothing left to bring back. | "Dart sorts, Kotlin displays", and Dart does not run on a widget tap. | Payload holds every open prayer in order (`id`, `title`, `entity`, `pinned`, `lastPrayedLocalDay`). Kotlin shows the first N that are not prayed today and not queued, so rows backfill and the count updates without Dart. |
| G3 | **"Pinned on top in every mode" conflicts with "prayed today at bottom in every mode".** A pinned request prayed today cannot be in both places. | Today's code settles it: `openPrayers` splits `pending`/`done` first, so prayed wins. No test covers this case. | Prayed wins. Pinned applies among un-prayed only. Add a test. "Up to 5 un-prayed" already implies this. |
| G4 | **"prayed/total" has no defined denominator, and the app already has one.** If any request is pinned, the app counts only pinned requests. | `intercede_screen.dart:139-142`. With 2 pinned of 20, the app says "فاضل 2 من 2". A plain count on the widget would say 0/20 for the same state. | Move the `counted` rule into `models.dart` and use it for both. Kotlin needs it too (`pinned` is in the payload; G2). The two surfaces must never show different numbers. |
| G5 | **"Done" and "no rows left" are different states once pins exist.** The app can say "خلصت كل صلوات النهاردة ✓" while unpinned requests are still listed. | Same lines as G4. | Header shows the done text when the counted set is complete. Rows keep showing whatever is un-prayed. The all-done body appears only when no rows remain. |
| G6 | **Empty, all-done and no-data states are missing.** The widget otherwise renders five blank rows or stale text. | Google's checklist sample ships separate `EmptyListContent` and `NoDataContent`. Quality rule WT-1 requires zero and empty states to fill larger bounds. | Four states, listed under [Widget States](#widget-states). |
| G7 | **"Today" must be the local date on both sides. The closest existing code is UTC.** Copying it moves the reshuffle and the Kotlin reset to about 02:00-03:00 local in Egypt, while `Prayer.prayedToday` stays local. | `getPeriodKey` and `VerseWidgetProvider.render` are explicitly UTC. `prayedToday` uses local time. | Add a local-day helper in Dart. Kotlin uses the default time zone. Do not reuse `getPeriodKey`. |

### Will feel wrong in use

| # | Gap | Evidence | Proposed requirement |
|---|-----|----------|----------------------|
| G8 | **A mistaken widget tap cannot be undone anywhere.** The app has no way to remove a log, and in-app marking has a cancellable note dialog (`askNote`) that the widget skips. Backfill also moves the next request under the thumb, so a double-tap marks two requests. | No log-removal mutation exists; `prayer_page.dart` only lists logs. | **Decision needed:** split the row (see [Decisions](#decisions-needed)). Regardless, ignore taps within about 600 ms of the last one, and dedupe by id + local day. |
| G9 | **Row content is unspecified, and a title alone can be meaningless.** Every in-app row shows the person: `'${entity.name} · ...'`. | `intercede_screen.dart:169`. | Row shows title (1 line, ellipsized) and entity name (smaller). Single-line truncation only as a fallback. |
| G10 | **Keeping the app in memory overnight leaves everything stale.** `resumed` only calls `flush()`, so nothing republishes. The in-app list and the widget keep yesterday's order until something else fires. | `app.dart:39-40`. `load()` runs once in `main()`. | On resume, consume taps, and if the local day changed, republish. |
| G11 | **Changing the sort does not touch the widget.** `_publish()` runs on mutation and refresh, not on a settings change. | `store.dart:97`. | Changing the sort republishes immediately. |
| G12 | **Tap consumption has three failure paths.** (a) Resume alone may miss a cold start, which is the normal case because a widget tap does not start the app. (b) Dropping unknown ids while the cache is empty loses taps, breaking Core Value. (c) Keeping a tap for a deleted prayer can block the outbox: Sanity documents that a patch on a missing document fails, and `flush()` stops at the first failure. | `store.dart:77-93`. Sanity HTTP mutation docs. Cold-start ordering not confirmed. | Consume in `load()` and on resume. Drop an id only when the cache is non-empty and lacks it. Clear the native queue only after local state is saved, and give each log a `_key` derived from the tap so replay is a no-op. |
| G13 | **Resizing is unspecified, and the verse widget's sizing cannot be copied.** Its `minResizeHeight="40dp"` would crop rows. Five rows at 48dp plus header and padding need about 300dp; 2 cells gives about 220dp, so three rows fit. | Formula from Android docs: portrait height about `118m - 16`. Quality rules WL-4.1, WL-4.2, WT-4. | Default 4x3. Row count comes from the current height, clamped to 1-5, and unused rows are `GONE`. Set `maxResizeHeight` because a taller widget only adds blank space. |
| G14 | **Text contrast fails if the verse colours are copied.** See the table below. Failing contrast is a Tier 3 (low quality) trait. | Calculated. `verse_widget_bg.xml` is fixed `#1877F2`. | Add `widget_bg`: `#1565C0` in `values/`, `#0D47A1` in `values-night/`. White text. No translucent white on row text. |

### Small and cheap, easy to forget

| # | Gap | Evidence | Proposed requirement |
|---|-----|----------|----------------------|
| G15 | **Two widgets named the same in the picker.** The verse receiver has no `android:label`, so it falls back to the app name, and neither widget has a preview. | `AndroidManifest.xml:53`, `verse_widget_info.xml`. WD-4.3 and WD-4.5. | Give the new receiver `android:label="تشفع"`, a description and `previewLayout`. Label the verse receiver too, since it is one attribute. |
| G16 | **Dark mode has two meanings here.** The app uses its own `Settings.isDark` toggle, while `values-night` follows the system. | `app.dart:55`. | Follow the system. The widget sits on the launcher, not in the app. A widget that mismatches the in-app toggle is expected, not a bug. |
| G17 | **Alphabetical is wrong for Arabic with plain `compareTo`.** أ, إ, آ and ا sort apart, so the same name lands in different places. | `openPrayers` uses `title.compareTo`. `normalizeArabic` already exists in `core/format/arabic.dart`. | Compare `normalizeArabic(title)`, tie-break by id. |
| G18 | **"Added" sort has a missing-data case.** `startedAt` is nullable and the query does not fetch `_createdAt` for prayers, so documents made in Studio may have no date. | `repository.dart:18-20`. | Add `_createdAt` to the query, use `startedAt ?? _createdAt`, sort any remaining nulls last, tie-break by id. |
| G19 | **The sort control has no specified place, and one list is not covered.** `Entity.active` (the per-person list) has its own order. | `models.dart:58`. Active names only the list, search and the widget. | Sort icon in the تشفع app bar, with the current choice marked. Say explicitly that the per-person page keeps most-neglected order. |
| G20 | **Accessibility and tap feedback on rows.** | Quality rule WL-4.2 (48dp). | 48dp target, a pressed state on rows, and `setContentDescription` such as "صليت: <title>" on the check target. |

## Measured: Daily-Stable Random

Method: 300 random sets of `intercedePrayer.<12 chars>` ids, consecutive days of November 2026, Dart VM. Ordering by each key, then comparing adjacent days. "Top-5 kept" is how many of today's first five were also in yesterday's first five, which matters most for the widget. A true shuffle gives about 5²/n.

| Sort key | n=12: top-5 kept | n=30: top-5 kept | n=30: rank correlation | Verdict |
|----------|------------------|------------------|------------------------|---------|
| `hashValue('$id:$day')` | 5.00 | 5.00 | 1.00 | Never reshuffles |
| `hashValue('$day:$id')` | 4.92 | 4.80 | 0.99 | Effectively never reshuffles |
| FNV-1a `'$id:$day'` | 4.66 | 4.42 | 0.90 | Too weak; day must come first |
| FNV-1a `'$day:$id'` | 2.08 | 0.83 | 0.15 | Good |
| `Random(hashValue('$day:$id')).nextInt(1 << 32)` | 2.10 | 0.84 | 0.15 | Good, one line, reuses existing code |

**Use the last row.** It reuses `hashValue`, and `dart:math` provides the mixing. An SDK release could change `Random`'s output, which would at worst change one day's order. A per-id key also keeps the order stable when a request is added or ticked, which shuffling a list would not do. This is still within the Key Decision ("day + request id, using a small stable hash").

Expected behaviour of daily-stable ordering:

- Ticking a request moves only that request.
- Adding one inserts it without disturbing the others.
- The same day gives the same order on every rebuild.
- The new order arrives at local midnight in the app, and on next app open for the widget, as `PROJECT.md` already accepts.
- A manual reshuffle is out, because the order is meant to hold for the day.

## Measured: Widget Text Contrast

WCAG AA needs 4.5:1 for body text.

| Background | Source | White text | White at 80% (`#CCFFFFFF`) | Verdict |
|------------|--------|------------|----------------------------|---------|
| `#1877F2` | Verse widget | 4.23 | 3.27 | Fails for row text |
| `#1976D2` | Candidate | 4.60 | 3.54 | Passes solid white only |
| `#1565C0` | Candidate, light | 5.75 | 4.28 | Passes; keep secondary text solid or larger |
| `#0D47A1` | Existing night `splash_bg` | 8.63 | 6.12 | Passes both |

## Widget States

Kotlin picks the state on each render. Reads are local and synchronous, so there is no loading state to design. `initialLayout` shows the no-data text.

| State | Condition | Shows | Tap |
|-------|-----------|-------|-----|
| No data | Payload key missing or JSON invalid (fresh install, cleared data) | "افتح التطبيق لتحميل الصلوات", following the verse widget's fallback | Opens app |
| Empty | Payload has zero open prayers | "لسه مفيش صلوات", shortened from the app's existing text | Opens app |
| Active | At least one un-prayed row | Header count, 1-5 rows, unused rows `GONE` | Marks prayed (see G8) |
| All done | Payload non-empty, no un-prayed rows | "خلصت كل صلوات النهاردة ✓" (existing app text), centred to fill the widget | Opens app |

A stale payload is not a separate state. The day comparison in Kotlin handles it, and the widget stays usable for days without the app.

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Count plus up to 5 un-prayed rows | Core of a checklist widget; Google's canonical checklist layout | MEDIUM | Active. Needs G2, G4, G9. |
| Mark from the widget, offline, app closed | Android lists marking items done as a core collection-widget use | MEDIUM | Active. Quality rule: updating after a widget action is mandatory (WT-3.1). |
| Widget updates right after a tap | A tap with no change reads as broken | LOW | The row leaves and the count moves in the same receiver call. |
| Widget updates after in-app changes | WT-3.2 | LOW | `_publish()`. `MainActivity`'s `update` must also render the new provider. |
| Real tap time on logs | Without it, "most neglected" and history are wrong | LOW | Active. Optional time parameter on `logPrayed`. |
| Prayed state resets after midnight | A checklist that stays ticked is wrong by morning | MEDIUM | Active. See the midnight note under Dependency Notes. |
| No duplicate logs on retry | Counts and history are visible (`${p.logs.length} مرة`) | MEDIUM | Active. Includes consuming the same tap twice (G12). |
| Empty, all-done and no-data states | WT-1 | LOW | G5, G6. |
| Resizable without cropping | WL-4, WT-4 | LOW | G13. One layout plus row visibility. |
| Readable contrast, dark-mode safe | WC-3 is a Tier 3 failure | LOW | G14, G16. |
| Picker name and preview | WD-4.3, WD-4.5 | LOW | G15. |
| RTL, Cairo font, ellipsis | Already the app's standard | LOW | `layoutDirection="rtl"`, `@font/cairo`, as in `verse_widget.xml`. |
| 48dp targets, pressed state, content description | WL-4.2; accessibility is not optional | LOW | G20. |
| More than one widget instance stays in sync | Normal launcher behaviour | LOW | Existing pattern renders all ids. |
| Five sort modes, persisted, default random | Active | LOW | `openPrayers(entities, mode)` with a default keeps the existing test valid. |
| Search follows the chosen sort | Active | LOW | Search filters `openPrayers` output, so it inherits the order. |
| Pinned first, prayed last, in every mode | Active | LOW | One shared wrapper around the mode comparator. G3. |
| Deterministic tie-breaks | Otherwise rows swap between rebuilds | LOW | By id in every mode. |

### Differentiators (Competitive Advantage)

These support Core Value. The first three are already in Active and are the point of this work.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Random order that holds all day, same in app and widget | No prayer widget found combines list, tick-off and a day-stable order. Episcopal Prayer List changes one item hourly. | LOW | Needs G1 and G7. |
| Marking is never lost and keeps the real time | Sets it apart from "open the app to sync" widgets | MEDIUM | Native queue plus outbox. |
| Same count in app and widget | The two surfaces read as one list | LOW | G4. |
| Closing moment when all done | Reuses text the user already knows | LOW | Same as the all-done state. |
| Undo the last tap from the widget | Removes the main risk of one-tap marking | MEDIUM | Header "تراجع" shown while the queue is non-empty; removes the last queued tap. Works only before the app consumes it. Suggested alongside G8. |
| Row text opens تشفع directly | Long requests are ellipsized, so reading one needs the app | MEDIUM | Opening `MainActivity` is LOW. Reaching the section needs an intent extra plus Dart routing. |
| Pin marker on rows | Matches `PrayerCard` | LOW | Small vector icon. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Scrollable list | Tier 1 rule WL-5 expects it | Already out of scope; `RemoteViewsService` adds a service and a factory for no real need | 5 rows with backfill. Tier 1 is not the goal here. |
| Per-widget sort or configuration screen | Common in task widgets | Contradicts the one shared setting decision | Change the sort in the app. |
| Sort control on the widget | Convenient | Adds rows of chrome and a second writer of the setting | App bar only. |
| Note entry from the widget | The app asks for a note | Needs an activity or dialog and undoes the one-tap value | Log without a note. Notes stay in the app. |
| Spinner or loading state | Common with network widgets | Data is local and reads are synchronous | `initialLayout` shows no-data text. |
| Refresh button on the widget | WT-2 | WT-2 applies when data outpaces the UI; here the UI updates on every change | Tap to open the app, which refreshes. |
| Sync status or pending badge | Reassurance | Noise; the app shows none either (`hasPending` is not displayed) | Trust the outbox. |
| Reshuffle button | Variety | Breaks "holds for the day" | None. |
| Rotating single request (Echo, Episcopal style) | Calm, one at a time | Conflicts with the stable order and the count | 5 rows. |
| Streaks | PrayerList Pro offers them | Scoring prayer does not fit the app, and a missed day adds guilt | Count for today only. |
| Per-request cadence (Echo) | Good for long lists | Needs schema and scheduling; most-neglected sort covers much of the need | Most-neglected mode. |
| Lock-screen placement | Glanceable | Exposes people's names and requests | Keep `widgetCategory="home_screen"`. |
| Material You dynamic colour | WC-1 (Tier 1) | Diverges from the verse widget and adds theme work for one user | Brand blue with a night variant. |
| Jetpack Glance | Google's recommended path | New dependency, which the Constraints rule out | `RemoteViews`, as the verse widget does. |
| Android 12 compound buttons | Real checkbox | `minSdk` is 24, so a second code path is needed | `ImageView` with `PendingIntent` on every API. |
| Custom day boundary | Praying after midnight | Everything else uses the calendar day, including `prayedToday` | Calendar day. |

## Feature Dependencies

```
Shared local-day helper
    ├──required by──> Daily-stable random key (G1)
    ├──required by──> Prayed-today check in Kotlin
    └──required by──> Day-change republish on resume (G10)

Sort function (openPrayers + mode)
    ├──requires──> Random key, Arabic folding (G17), added date (G18)
    ├──required by──> In-app sort control ──> Search order
    └──required by──> Widget payload (G2)

Counted-set rule moved to models.dart (G4)
    └──required by──> Widget payload ──> Header count, all-done state (G5)

Widget payload ──required by──> Widget render ──> States, row count, backfill

Idempotent log (deterministic _key)
    └──required by──> Native tap queue consumption (G12)
                          ├──requires──> logPrayed time parameter
                          └──required by──> Mark from widget
                                                └──enhanced by──> Last-tap undo

Midnight trigger ──requires──> Payload with lastPrayedLocalDay

Scrollable list ──conflicts──> Fixed-rows layout (out of scope)
Reshuffle button ──conflicts──> Stable daily order
Per-widget config ──conflicts──> One shared sort setting
```

### Dependency Notes

- **Sort before widget:** the widget payload is sort output, so the Dart sort ships first and can be tested without Android.
- **Idempotency before widget marking:** the widget's consume path is a new replay path, and the outbox issue is already known. `_applyPatch` inserts without checking `_key`, so the dedupe has to happen there. `logPrayed` currently generates a random `_key`; a key derived from the tap keeps a replayed tap identical.
- **Native writes and Dart reads:** Dart's `SharedPreferences` reads from a cached copy, so a queue written by Kotlin may not be visible without `reload()`, or the queue can be read through the `aio/widget` channel. To verify in the architecture work.
- **Midnight needs a real trigger:** `updatePeriodMillis` has a 30-minute floor, and `ACTION_DATE_CHANGED` is not on Android's implicit-broadcast exception list, so a manifest receiver for it should not be relied on. `TIME_SET` and `TIMEZONE_CHANGED` are on the list. A next-local-midnight alarm re-armed on each render, with `onUpdate` as a backstop, fits. An inexact alarm is enough, because a few minutes' lag is invisible overnight.
- **After midnight without the app:** the widget uses yesterday's order, and requests prayed yesterday return at the end, because the payload put them there. That is acceptable and consistent with the Out of Scope reshuffle entry.

## MVP Definition

### Launch With (v1)

- [ ] Sort function with five modes, pinned-then-prayed wrapper and tie-breaks — every surface depends on it
- [ ] Random key from G1, on the local day — without it, "reshuffles daily" is false
- [ ] Arabic-folded alphabetical, added-date fallback — otherwise two modes are subtly wrong
- [ ] App-bar sort control, persisted, republishes to the widget
- [ ] Shared counted-set rule — the numbers must match
- [ ] Idempotent logs and `logPrayed` time parameter
- [ ] Full-list payload, native queue, consumption in `load()` and on resume, with the safe-drop rule
- [ ] Widget with count, 1-5 rows showing title and entity, four states, height-based row count
- [ ] Midnight trigger, day-change republish on resume
- [ ] Tap debounce and per-day dedupe
- [ ] Contrast-safe colours with a night variant
- [ ] Picker label, description, preview; pressed state and content descriptions

### Add After Validation (v1.x)

- [ ] Last-tap undo — add if mis-taps happen, unless the row split in G8 is rejected, in which case move it to v1
- [ ] Deep link to تشفع from the widget — add when opening at the hub feels like one tap too many
- [ ] Pin marker on rows — add if pinned requests are hard to tell apart
- [ ] Normalized in-app search — `_PrayerSearch` uses raw `contains`, while `normalizeArabic` already exists; it is a one-line change, separate from this work
- [ ] Remove a log inside the app — add if mistaken logs need fixing after consumption

### Future Consideration (v2+)

- [ ] Dart background republish through the existing `workmanager` job, so the widget gets the new order without opening the app — only if a stale order bothers the user; it needs the store to run in a second isolate
- [ ] Scrollable list — only if five rows prove too few

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Random key and local day (G1, G7) | HIGH | LOW | P1 |
| Pinned and prayed rules, tie-breaks (G3) | HIGH | LOW | P1 |
| Sort modes, persistence, control (G17-G19) | HIGH | LOW | P1 |
| Idempotent logs and tap time | HIGH | MEDIUM | P1 |
| Full-list payload and backfill (G2) | HIGH | LOW | P1 |
| Native queue and safe consumption (G12) | HIGH | MEDIUM | P1 |
| Shared count (G4, G5) | HIGH | LOW | P1 |
| Widget states (G6) | HIGH | LOW | P1 |
| Title and entity on rows (G9) | HIGH | LOW | P1 |
| Midnight reset, resume republish (G10) | HIGH | MEDIUM | P1 |
| Tap debounce, dedupe (G8) | HIGH | LOW | P1 |
| Height-based rows (G13) | MEDIUM | LOW | P1 |
| Contrast and night colour (G14, G16) | MEDIUM | LOW | P1 |
| Picker name and preview (G15) | MEDIUM | LOW | P1 |
| Pressed state, content description (G20) | MEDIUM | LOW | P1 |
| Last-tap undo | MEDIUM | MEDIUM | P2 |
| Deep link to تشفع | MEDIUM | MEDIUM | P2 |
| Pin marker | LOW | LOW | P3 |
| Dart background republish | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Decisions Needed

1. **Whole-row tap or split row (G8)?** Recommendation: the check target (start side, 48dp) marks, and the text opens the app. It matches the convention found in TickTick and Todoist reports, reduces accidental marks, and gives a way to read a long request. It narrows the Active wording "tap a request". If the user prefers whole-row marking, make last-tap undo a v1 item.
2. **Confirm prayed beats pinned (G3).** Recommendation: yes; it is today's behaviour.
3. **Confirm alphabetical means by prayer title (G17).** Recommendation: title, because `openPrayers` already tie-breaks on it. Sorting by person is the likely alternative.
4. **Confirm the widget follows the system theme (G16).** Recommendation: yes.

## Competitor Feature Analysis

All LOW confidence: reviews and listings, not hands-on testing. No source documented widget-level undo for any app.

| Feature | Echo Prayer | PrayerList Pro (iOS) | Episcopal Prayer List (iOS) | Loop Habit Tracker | TickTick / Todoist | Our Approach |
|---------|-------------|----------------------|-----------------------------|--------------------|--------------------|--------------|
| Widget content | One request | List and streak | One random request, hourly | Per-habit checkmark | Task list | Count plus up to 5 requests |
| Mark from widget | Not documented | Not documented | Not documented | Yes | TickTick checkbox marks (iPhone report) | Yes, offline |
| Tap on text | Not documented | Not documented | Not documented | Not documented | Opens the task (TickTick, Todoist) | Opens app, pending decision 1 |
| Ordering | Per-request cadence | Not documented | Random, changes hourly | Fixed per habit | User-defined | Shared sort, random stable for the day |
| Undo | Not documented | Not documented | Not applicable | In-app calendar edit | Not documented | Debounce; last-tap undo later |

Abide's widget is a launcher into the daily meditation, not a list. No source confirmed that PrayerMate has a widget. Prayer-app widgets found are mostly iOS, so **Android checklist guidance is a better reference for this feature than prayer apps**.

## Confidence by Area

| Area | Confidence | Basis |
|------|------------|-------|
| G1 hash result | HIGH | Measured in this session; the script was temporary and not kept |
| Contrast figures | HIGH | Calculated with the WCAG formula |
| Code-based gaps | HIGH | Read in the repo at the cited lines |
| Android quality rules, sizing, broadcast list | LOW by seam (webfetch) | Official pages; the seam does not rate webfetch higher. Check on the device. |
| Sanity patch on a missing document | LOW | Archived Sanity docs state it fails; the exact response was not seen |
| Flutter cold-start lifecycle | LOW | Not confirmed, so G12 avoids depending on it |
| Row height with Cairo, `values-night` refresh on a live widget | LOW | Needs a device check; Cairo's tall line height may need rows above 48dp |
| Competitors | LOW | Reviews and listings |

## Sources

Project code (read directly):
- `.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md`
- `lib/features/intercede/data/{models,store,repository}.dart`
- `lib/features/intercede/ui/intercede_screen.dart`, `ui/widgets/prayer_card.dart`
- `lib/features/leyaana/data/{daily_pick,verse_surfaces}.dart`, `lib/core/format/arabic.dart`, `lib/core/background.dart`
- `lib/app/app.dart`, `lib/main.dart`, `test/intercede_test.dart`
- `android/app/src/main/` manifest, `VerseWidgetProvider.kt`, `MainActivity.kt`, widget layout, info and colour resources

Android:
- [Widget quality](https://developer.android.com/develop/adaptive-apps/quality-guidelines/widget-quality) (also fetched at the design guide URL)
- [Canonical widget layouts](https://developer.android.com/design/ui/mobile/guides/widgets/layouts)
- [Widget sizing](https://developer.android.com/design/ui/mobile/guides/widgets/sizing)
- [Flexible widget layouts](https://developer.android.com/develop/ui/views/appwidgets/layouts)
- [Enhance your widget](https://developer.android.com/develop/ui/views/appwidgets/enhance)
- [Advanced widget updates](https://developer.android.com/develop/ui/views/appwidgets/advanced)
- [Implicit broadcast exceptions](https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions)

Sanity and Flutter:
- [Sanity HTTP mutations (archived)](https://www.sanity.io/docs/archive/http-mutations)
- [AppLifecycleListener.didChangeAppLifecycleState](https://api.flutter.dev/flutter/widgets/AppLifecycleListener/didChangeAppLifecycleState.html)

Competitors:
- [Echo Prayer review](https://learnofchrist.com/resources/echo-prayer)
- [PrayerList Pro](https://apps.apple.com/cd/app/prayerlist-pro/id6758590684)
- [Episcopal Prayer List](https://apps.apple.com/app/id1483408224)
- [Abide widget help](https://help.abide.com/hc/en-us/articles/360057970173)
- [PrayerMate](https://apps.apple.com/us/app/-/id434815549)
- [Best Android habit widgets, SlashGear](https://www.slashgear.com/1232500/the-best-android-widgets-for-tracking-habits)
- [Loop Habit Tracker discussion on editing days](https://github.com/iSoron/uhabits/discussions/689)
- [Todoist Android widget help](https://www.todoist.com/it/help/articles/use-a-todoist-widget-on-your-android-device-632pZA)
- [Google Tasks widget guide, TasksBoard](https://tasksboard.com/blog/google-tasks-widget-guide)

---
*Feature research for: Android prayer-list home-screen widget and shared list sort*
*Researched: 2026-11-02*
