# Pitfalls Research

**Domain:** Interactive Android RemoteViews widget plus a date-seeded stable sort, in a Flutter app that uses SharedPreferences as the Dart/Kotlin bridge
**Researched:** 2026-11-02
**Confidence:** MEDIUM overall. Repo, plugin, and date findings are strong because they were run or read directly. Sanity idempotency is the weak spot and needs a spike.

**Evidence tags used below:**

- `[RAN]` reproduced locally
- `[SRC]` read in this repo, the pub cache, or the Flutter SDK
- `[DOCS]` vendor documentation fetched directly. The `classify-confidence` seam tiers the `webfetch` provider LOW whatever the source, so don't treat these as authoritative without the listed check.
- `[INFER]` reasoning from the above, not confirmed

**Phase names are provisional** because no roadmap exists yet: **Sync Hardening**, **Shared Sort**, **Widget Display**, **Widget Marking**. Sync Hardening must finish before Widget Marking.

## Decisions This Research Challenges

Four items change something already recorded in `PROJECT.md`, or need a decision from the user:

1. **"Small stable hash" as the shuffle.** The obvious reuse, `hashValue`, gives nearly the same order every day (Pitfall 1). The seed needs a mixing step.
2. **The outbox `insert` is more than a duplicate risk.** A queued patch for a deleted prayer can block every later mutation forever (Pitfall 7).
3. **`_key` must be created at tap time in Kotlin**, not in `logPrayed` at drain time, or the dedupe fix cannot work for widget taps (Pitfall 5).
4. **"Pinned on top in every mode" and "prayed today at the bottom in every mode" conflict** for a pinned request prayed today. `openPrayers()` puts it at the bottom today. Keep that unless the user decides otherwise.

## Critical Pitfalls

### Pitfall 1: The daily shuffle does not shuffle

**What goes wrong:**
Reusing `hashValue` from `lib/features/leyaana/data/daily_pick.dart` as the sort key gives the same order almost every day. `[RAN]` with 12 ids in the app's real format (`intercedePrayer.` + 12 chars), over the 8 days from Oct 30 to Nov 6:

| Sort key | Distinct orders (of 8) | Distinct top-5 sets (of 8) |
|----------|------------------------|----------------------------|
| `hashValue('$day:$id')` | 3 | 2 |
| `hashValue('$id:$day')` | 1 | 1 |
| FNV-1a of `'$id:$day'` | 5 | 3 |
| FNV-1a of `'$day:$id'` | 8 | 8 |
| `Random(hashValue('$day:$id')).nextDouble()` | 8 | 8 |

Nov 2 through Nov 5 were byte-identical under `hashValue('$day:$id')`. The widget shows only five rows, so the user would see the same five requests all month.

**Why it happens:**
`hashValue` is the polynomial `31*h + c`, so it is linear. For same-length ids, changing the day adds one constant to every id's hash. `[RAN]` measured a single delta, 11316127, across all 12 ids. Adding a constant keeps the sorted order, except for ids near the wrap-around. It looks correct in a quick test: stable within a day and deterministic. The failure is that it never changes.

**How to avoid:**
- Sort by `Random(hashValue('$day:$id')).nextDouble()`. It is one line and uses only `dart:math` plus the existing hash. Compute the keys once per sort; don't call it inside the comparator.
- Mark it with a `ponytail:` comment. The Dart docs say the `Random` stream "can change between releases" `[SRC]`, so the ceiling is one extra reorder on the day an SDK upgrade lands. That is harmless here because Kotlin only displays what Dart wrote.
- Do not use a seeded Fisher-Yates. The `_query` GROQ has no `order()` `[SRC]`, so input order is not guaranteed, and one new request would reshuffle everything. Per-id keys keep other items' relative order when the list changes.

**Warning signs:**
The widget looks the same on consecutive mornings. Only a test can catch this early, by eye it reads as random.

**Phase to address:** Shared Sort. Add a check that fails on `hashValue` alone: over 7 consecutive days, a fixed list of same-length ids yields at least 5 distinct top-5 sets.

---

### Pitfall 2: Two definitions of "today"

**What goes wrong:**
The shuffle or the widget reset uses the UTC day while `prayedToday` uses the local day, so the shuffle changes hours after midnight. `getPeriodKey` (`daily_pick.dart`) and `VerseWidgetProvider.kt` are both UTC, and `Prayer.prayedToday` (`models.dart`) is local `[SRC]`.

In `Africa/Cairo`, the timezone of this dev machine (confirm it matches the phone), the UTC day lags local by 2 to 3 hours. From 00:00 to 02:00 or 03:00 local, a UTC key still returns yesterday. Prayed-today items would reset at midnight while the shuffle holds yesterday's order until around 03:00.

**Why it happens:**
`getPeriodKey` is the nearest date helper, and copying `VerseWidgetProvider.render` brings along `timeZone = TimeZone.getTimeZone("UTC")`. Don't "fix" `getPeriodKey` itself: its UTC rule must match the PWA byte for byte, and `CONCERNS.md` flags it as fragile.

Daylight saving makes arithmetic shortcuts wrong too `[RAN]`:

- 2026-04-24 has no 00:00 in Cairo. Clocks jump to 01:00, so `DateTime(2026,4,24)` returns 01:00 and the day has 23 hours.
- 2026-10-29 repeats 23:00 to 23:59, so the day has 25 hours.
- `now.add(Duration(days: 1))` from 00:30 on Oct 29 lands on the same local date.
- `millisecondsSinceEpoch ~/ 86400000` counts UTC days, not local ones.

**How to avoid:**
- Add one new helper, `localDayKey(DateTime)`, returning local `yyyy-MM-dd`. Use it for the seed and the payload.
- Add days only with `DateTime(y, m, d + n)`.
- In Kotlin, use `SimpleDateFormat("yyyy-MM-dd", Locale.US)` and drop the UTC line. Keep `Locale.US`: without it an Arabic device locale may produce Arabic-Indic digits and never match the Dart key `[INFER]`.
- Compute the alarm with `Calendar` (add one `DAY_OF_MONTH`, zero the fields), never `now + 24h`.

**Warning signs:**
The order changes while the phone is unattended around 02:00 to 03:00. Items still look prayed just after midnight. The word `UTC` appears in the new provider.

**Phase to address:** Shared Sort for the helper. Widget Display for the Kotlin side. Tests pass an explicit `DateTime` for 00:30 local.

---

### Pitfall 3: Dart cannot see what Kotlin wrote to `flutter.*` keys

**What goes wrong:**
If Kotlin writes taps to a `flutter.` key, Dart never reads them until the process restarts. Taps look lost, then appear after a force close.

**Why it happens:**
`Settings` wraps the legacy `SharedPreferences.getInstance()`, on `shared_preferences` 2.5.5 and `shared_preferences_android` 2.4.23 `[SRC]`. It loads everything once into `_preferenceCache`, and `Settings.init` holds that instance for the process lifetime. `getString` reads only that cache, and nothing in `lib/` calls `reload()` `[SRC]`. A warm resume keeps the old cache.

`reload()` isn't a clean fix. It awaits a full read, then clears and refills the cache `[SRC]`, so a `setString` issued during that await can vanish from the Dart cache even though it reached disk `[INFER]`.

Migrating to `SharedPreferencesAsync` would be worse. It defaults to DataStore on Android `[SRC]`, so `VerseWidgetProvider` would silently stop finding `flutter.verse-widget`. The README calls the legacy API a future deprecation `[SRC]`, but it is not deprecated yet. `PROJECT.md` already says to keep it.

**How to avoid:**
Keep the tap queue out of the Dart-visible file:

- Store taps in a separate native file, such as `intercede_widget`.
- Have Dart read them through `aio/widget`, with new `peekTaps` and `ackTaps(keys)` methods.

No `reload()` is needed, and the plugin's cache and type-coercion rules no longer apply. The separate file also keeps the tap `commit()` small (see Performance Traps).

Dart still writes the display payload to `flutter.*` with the existing pattern. Kotlin only reads that key, so it is safe. Native reads see Dart writes at once because both sides share one process `[DOCS]`.

**Warning signs:**
Taps appear only after swiping the app away. Someone adds `reload()` to fix "sometimes" bugs.

**Phase to address:** Widget Marking.

---

### Pitfall 4: Kotlin and Dart writing the same key

**What goes wrong:**
Kotlin edits the display JSON to mark a row prayed. Dart then publishes from its own state and overwrites the edit, so the row reappears and the tap can be lost.

**Why it happens:**
The optimistic edit is the shortest path to hiding a row. But Android applies editors last-writer-wins on each key `[DOCS]`, and `_publish()` runs after every mutation and refresh.

**How to avoid:**
Keep one writer per key. Dart owns the payload. Kotlin owns the queue. Kotlin derives the hidden rows at render time as payload rows prayed on the payload's day, plus queued taps whose tap day is today. It never edits the payload.

Keep the Kotlin queue work synchronous on the main thread. `onReceive` and the `MethodChannel` handler already run there, so peek, ack, and tap cannot interleave `[INFER]`. Don't add `goAsync` or a coroutine around it.

**Warning signs:**
A tapped row comes back after opening the app. Any `prefs.edit()` in Kotlin touches a key that Dart writes.

**Phase to address:** Widget Marking.

---

### Pitfall 5: The handoff from native queue to outbox loses or doubles taps

**What goes wrong:**
Draining crosses two stores, so a kill between steps either loses the tap or logs it twice. This is the Core Value failure.

**Why it happens:**
Three separate traps here:

1. **`_key` is generated too late.** `logPrayed` generates `_key` and `prayedAt` inside Dart `[SRC]`. If each drain attempt generates a new `_key`, retry can't be recognized.
2. **`_save()` writes two keys non-atomically.** It writes `_cacheKey`, then `_outboxKey` `[SRC]`. A kill between them leaves the log in `_json` but not in `_outbox`. A dedupe of "skip if the key is in `logs`" then treats that tap as done, it never reaches Sanity, and the next refresh erases it.
3. **Clearing the queue instead of acking by key.** A tap arriving between peek and clear gets dropped.

**How to avoid:**
- Generate the log `_key` (a UUID) and epoch `tappedAt` in Kotlin at tap time, and pass both through. Extend `logPrayed` to accept them. It currently takes neither.
- `commit()` the tap before re-rendering. Don't hide the row if it returns false. Android's `commit()` is synchronous and reports success; `apply()` reports no failures `[DOCS]`.
- Drain in this order: peek, apply, await `_save()`, publish, then `ackTaps(keys)`. Ack by key, never clear.
- Skip a re-drained tap only when its key is already in `_outbox`. If it is missing from `_outbox`, queue it again and rely on the idempotent send from Pitfall 6. That gives at-least-once delivery with an idempotent receiver.
- Write the outbox first in `_save()`, then the entity cache.
- Filter out taps for prayers that no longer exist or are done (Pitfall 7), and ack them so they don't replay.
- Guard against concurrent drains with a `_draining` flag, as `_flushing` does for flush.

**Warning signs:**
A prayer shows as prayed, then un-prays after pull-to-refresh. Duplicates appear after a crash.

**Phase to address:** Widget Marking, on top of Sync Hardening. Test by faking a kill at each step: replay the same taps and assert exactly one log, with the outbox and queue both correct.

---

### Pitfall 6: Replayed logs duplicate, and the obvious fix has traps

**What goes wrong:**
`patch.insert` appends on every retry, so a killed or timed-out request that did reach Sanity logs twice. This is already in `CONCERNS.md`. Duplicates show directly in `logs.length` at `prayer_page.dart:17` and `answered_page.dart:54` `[SRC]`.

**Why it happens:**
- `flush()` removes a mutation only after the response and save `[SRC]`.
- `refresh()` replays the outbox over fresh server data, which can already contain the item `[SRC]`.
- `refresh()` calls `await flush()`, but `flush()` returns immediately if `_flushing` is set, so the fetch can overlap an in-flight send `[SRC]`.
- Sanity's docs don't say duplicate `_key` values are rejected `[DOCS]`. Assume they are not.
- `transactionId` "must be unique in the dataset" `[DOCS]`, but the docs don't describe reuse, so don't build on it.

**How to avoid:**
Make both sides idempotent by `_key`.

- **Local:** `_applyPatch` skips any `items` entry whose `_key` is already in the target list. Add a test first, as `CONCERNS.md` advises for `applyMutation`.
- **Server:** the leading option is a guarded patch by query, which is documented with `query` plus `params` `[DOCS]`:

```json
{"patch": {
  "query": "*[_id == $id && count(coalesce(logs[_key == $k], [])) == 0]",
  "params": {"id": "...", "k": "..."},
  "setIfMissing": {"logs": []},
  "insert": {"after": "logs[-1]", "items": [{"_key": "..."}]}
}}
```

Two traps in that guard:

- **Null logs.** A plain `count(logs[_key == $k]) == 0` likely evaluates to null for a prayer with no `logs` field `[INFER]`, because GROQ functions "return `null` if arguments have invalid types" `[DOCS]`. That would silently drop the first log ever on a prayer. The `coalesce` is deliberate.
- **Local replay crash.** `_applyPatch` does `patch['id'] as String` `[SRC]`, so a query-shaped entry would throw. Keep `id` in the stored outbox entry and build the guarded form only when sending.

**Needs a spike before committing to this:** Sanity's docs don't state what a query patch matching nothing returns. Test against a throwaway document:

- first insert
- repeat with the same `_key`
- document with no `logs` field
- missing document

`dryRun=true` exists but validates without executing `[DOCS]`, so it may not prove the outcome.

**Fallback if the guard misbehaves:** before sending a queued log, query whether `_key` already exists and drop the entry if so. This costs one extra read per log. Single-user use makes the check-then-send race negligible.

**Warning signs:**
A log count jumps by two. Two identical `prayedAt` lines appear on the prayer page.

**Phase to address:** Sync Hardening.

---

### Pitfall 7: One dead mutation blocks the outbox forever

**What goes wrong:**
A queued log for a deleted prayer fails on every flush. `flush()` stops at the first failure to preserve order and never removes it `[SRC]`, so every later mutation, including all widget taps, stops syncing. The user sees nothing, because `flush()` is silent and no pending count exists in the UI.

**Why it happens:**
Sanity says a patch fails if the document does not exist, while a delete succeeds `[DOCS]`. `catch (_) { break; }` treats a permanent rejection like a network failure. Today, deleting after logging is ordered safely in the queue. Widget taps break that: a tap can sit in the native queue while the prayer is deleted in the app or in Studio.

`_applyPatch` hides it locally by returning when the document is missing `[SRC]`, and the tap is added to `_outbox` anyway.

**How to avoid:**
- Drop taps for missing or completed prayers at drain time (Pitfall 5).
- Throw a typed exception with the status from `sanityMutate`, which currently throws a bare `Exception` `[SRC]`.
- In `flush()`, treat permanent rejections differently from transient failures. Don't discard them: move the mutation to an `intercede:outbox-dead` key so nothing is silently lost, then continue.
- Keep 401, 403, 408, 429, 5xx, and timeouts as "stop and retry". A bad token must never empty the queue.
- The docs don't list a status for a missing document `[DOCS]`, so confirm the real code in the spike from Pitfall 6. A guarded query patch would also make this case a no-op.

**Warning signs:**
`hasPending` stays true while online. Sanity stops receiving anything after one specific day.

**Phase to address:** Sync Hardening.

---

### Pitfall 8: PendingIntent collisions between rows

**What goes wrong:**
All five rows mark the same request, usually the last one rendered.

**Why it happens:**
PendingIntents match on `Intent.filterEquals`, which ignores extras `[DOCS]`. Five intents differing only by a `prayerId` extra are one PendingIntent, and `FLAG_UPDATE_CURRENT` replaces its extras each time. Android's docs call this a common mistake. It passes a one-row test.

A repo-specific collision: `VerseWidgetProvider` uses `getActivity(context, 0, Intent(context, MainActivity::class.java), ...)` `[SRC]`. A new "open app" intent with the same request code and only added extras would be the same PendingIntent, so it would change the verse widget's tap target too.

**How to avoid:**
- Give each tap intent a distinct `data` URI, such as `intercede://tap/<prayerId>`, which `filterEquals` compares. Don't derive the request code from a hash, because collisions come back.
- Carry the prayer id, not the row index. The id is what the user saw; resolving an index at tap time reads a list that may have changed.
- Use `FLAG_IMMUTABLE`. Target SDK is 36 `[SRC]`, and only collection templates need mutable intents, which this design doesn't use.
- Use a distinct action or request code for the open-app intent.
- Every render must set or clear every row's click target, because `updateAppWidget` replaces the whole view tree.

**Warning signs:**
Tapping row 2 marks row 5. The verse widget opens something different after the new widget ships.

**Phase to address:** Widget Marking. Device test: tap rows 1 and 3, then confirm those two ids reach the queue.

---

### Pitfall 9: A double tap marks the next request

**What goes wrong:**
The first tap hides the row, and the rows below shift up. The second tap lands on a different request and logs a prayer that was never prayed.

**Why it happens:**
Standard dedupe keys on the id, and these two taps have different ids. Fast rendering makes this more likely, not less. Widget marking has no undo: nothing in `repository.dart` removes a log `[SRC]`. A mis-tap stays in the history permanently.

**How to avoid:**
- Drop any tap within about 700 ms of the previous one, measured with `SystemClock.elapsedRealtime()` and kept in the native prefs file so a process restart doesn't reset it. Treat the value as a tuning knob.
- Also ignore a tap for an id already queued for today. This covers a repeat on the same row before re-render.
- Dedupe only taps, by id and day. Logging twice in a day is allowed in the app, so don't add a guard to `logPrayed`.

Keep the row-collapse behaviour. Showing a checked row in place until the next render would avoid the shift, but five tapped rows would then fill the widget with nothing left to tap.

**Warning signs:**
The history shows two requests prayed within a second. Taps feel unresponsive, which means the window is too long.

**Phase to address:** Widget Marking. Device test with a real fast double tap on the launcher.

---

### Pitfall 10: Publishing only what the widget shows

**What goes wrong:**
Dart publishes the top five un-prayed items. After five taps the widget is empty while more requests remain. After midnight it can't restore anything, because prayed items were never published. Reset then shows a blank widget until the app opens.

**Why it happens:**
"Show 5" reads like a payload size. But Kotlin deliberately has no sort logic, so it can only pick from what Dart gave it.

**How to avoid:**
Publish every open request in final order, each with `id`, `title`, a prayed-on-payload-day flag, and a `counted` flag, plus the payload's `day`. Kotlin takes the first five visible rows.

If `payload.day != today`, Kotlin ignores all prayed flags.

The `counted` flag matters because the app's count has a rule: "Pinned prayers are today's list; with none pinned, everything counts" (`intercede_screen.dart`) `[SRC]`. Move that rule to a shared Dart function and use it for both surfaces, or the widget's count will disagree with the app whenever anything is pinned. Don't reimplement it in Kotlin.

**Warning signs:**
An empty widget with requests remaining. Different counts in the app and widget.

**Phase to address:** Widget Display.

---

### Pitfall 11: Relying on `updatePeriodMillis` for the midnight reset

**What goes wrong:**
Yesterday's prayed state stays on the widget well into the morning.

**Why it happens:**
`updatePeriodMillis` is a period, not a time of day. It can't be delivered more than once every 30 minutes `[DOCS]`, and the docs advise at most hourly `[DOCS]`. The verse widget uses 6 hours `[SRC]`, so copying it could mean a reset up to 6 hours late.

`ACTION_DATE_CHANGED` looks like the answer but is not on the implicit-broadcast exception list `[DOCS]`, so a manifest receiver won't get it on target SDK 36. `TIME_SET` and `ACTION_TIMEZONE_CHANGED` are on the list `[DOCS]`.

**How to avoid:**
- Arm a one-shot alarm for the next local midnight using `setWindow(AlarmManager.RTC, midnight, 10min, pi)`. It is inexact, needs no exact-alarm permission, and doesn't wake the phone, since it only needs to be right when the screen is on.
- Plain `set()` can be up to an hour late on API 31 and up `[DOCS]`. Don't lean on the unneeded `USE_EXACT_ALARM`, which `CONCERNS.md` recommends removing.
- Alarms die on reboot `[DOCS]`. Arm it inside the shared render path, so every `onUpdate`, tap, and app publish re-arms it. Setting the same PendingIntent replaces the earlier alarm `[DOCS]`.
- Cancel it in `onDisabled`.
- Keep `updatePeriodMillis` at 6 hours as a backstop, and always compare `payload.day` to today at render.
- **Do not clear the tap queue at midnight.** Yesterday's unsynced taps must still reach Sanity. They stop counting as hidden rows by tap day, not by deletion.

**Warning signs:**
The widget resets only after a tap. The reset stops working after a reboot.

**Phase to address:** Widget Display. Test by setting the device clock across midnight, and by rebooting before midnight.

---

### Pitfall 12: Assuming "app opens" runs `load()`

**What goes wrong:**
After a warm resume, taps aren't consumed, the shuffle keeps yesterday's day, and the widget keeps yesterday's order. It all works in testing because `flutter run` is a cold start.

**Why it happens:**
`load()` runs once from `main()`. `didChangeAppLifecycleState` only calls `flush()` on `resumed` `[SRC]`. `_publish()` isn't called there, so a resume after midnight re-sorts nothing. A cold start may not deliver a `resumed` callback at all, depending on when the observer registers `[INFER]`, so draining only on resume can miss launch.

**How to avoid:**
- Add one method, for example `IntercedeStore.syncWithWidget()`, that drains taps and always publishes. Call it from both `load()` and the `resumed` branch.
- Keep the synchronous cache decode as the first thing in `load()`. `main()` calls `load()` straight after `runApp`, so `_json` is populated before any lifecycle callback runs `[SRC]`. An `await` placed before the decode would let a drain apply to an empty `_json`, then `_save()` would overwrite the real cache with that empty list.
- If the app stays open across midnight, nothing re-sorts until the next resume. Accept that.

**Warning signs:**
Taps appear only after a force close. The list order changes after pull-to-refresh but not on reopening.

**Phase to address:** Widget Marking for draining. Shared Sort for republishing on resume.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `Random` stream as the sort key | One line, good mixing | One extra reorder after an SDK upgrade | Acceptable; mark with `ponytail:` |
| Widget keeps yesterday's order after midnight | No sort logic in Kotlin | Stale order until the app opens | Acceptable and already decided. If it matters later, publish per-day id lists like the `verse-widget` map, which reshuffles without Kotlin sort logic |
| JSON tap queue in a prefs string | No new storage | Whole queue rewritten per tap | Acceptable; it stays tiny |
| Separate display key string in two languages | Follows existing pattern | Silent fallback after a rename | Acceptable with one Dart constant and a matching Kotlin constant, plus a note on each |
| Drop stale taps at drain with no notice | Simple | A tap on a just-deleted request vanishes | Acceptable; the request no longer exists |
| Discard permanently rejected outbox items | Unblocks sync | Silent data loss | Never; move to a dead-letter key |
| Skip the Sanity spike and ship the guard | Saves an hour | Could silently drop first logs | Never |
| Copying `VerseWidgetProvider.render` wholesale | Fast start | Brings the UTC day and request code 0 | Copy the structure only |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `aio/widget` channel | `MainActivity` refreshes only the verse widget `[SRC]` | Update handler calls both providers |
| Dart publish then `update` | Calling `update` without awaiting the write, since the two use different channels with no ordering guarantee `[INFER]` | `await setCache(...)` first, as `verse_surfaces.dart` does |
| `_publish()` being sync `void` | Making it throw, which breaks `apply` and `refresh` | Fire a guarded `unawaited` write. Catch `MissingPluginException`. Keep pure logic out of the singleton: tests call only `applyMutation` today `[SRC]` |
| `prayedAt` from a tap | `DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String()` omits the zone, so it reads as UTC elsewhere | `isUtc: true`, or `.toUtc()`, then `toIso8601String()`, matching `_nowUtc()` |
| `logPrayed` signature | Only adding `DateTime? at` | Also accept the tap's `_key` (Pitfall 5) |
| `AppWidgetProvider.onReceive` | Handling the custom action and dropping others | Handle the action, otherwise call `super.onReceive` |
| Native prefs value types | `putInt` or `putStringSet` under `flutter.*`; the plugin migrates Sets and has its own encodings `[SRC]` | Dart-visible keys are written only by Dart |
| Sanity `autoGenerateArrayKeys` | Assuming it helps retries | Keep client-made keys; a generated key differs per retry |
| `.dev` build | Testing the tap on one, widget placed from the other | The debug `applicationId` differs, so the two have separate prefs `[SRC]` |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Tap `commit()` to `FlutterSharedPreferences` | Laggy tap | Native file. That XML holds entity, outbox, and content caches `[SRC]`, and each `commit()` rewrites the whole file `[INFER]` | Once caches reach several hundred KB |
| Cold receiver parses the full XML to read the payload | First render after process death is slow | Accept for now; keep the payload compact. If it hurts, pass the payload through the channel into the native file | Multi-MB `content-cache:*` |
| Work in `onReceive` | ANR | Only prefs and render; receivers have a 10-second limit `[DOCS]`. No network in Kotlin | Any network call |
| Sorting on every `_publish` | None at this scale | Nothing needed | Not realistic for one user |
| `updatePeriodMillis` of 30 minutes | Battery use with no benefit | Keep 6 hours; the alarm handles midnight | Immediately, on battery |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Adding an `intent-filter` for the tap action, or `exported="true"` | Another app could forge prayer logs | Keep `exported="false"` like the verse receiver; send via explicit intents only `[SRC]` |
| Mutable PendingIntents | A host can alter the intent | `FLAG_IMMUTABLE` on every one |
| Trusting `prayerId` from the intent | A stale or malformed id enters the outbox | Validate against `_json` at drain time |
| Giving Kotlin the Sanity token | Widens exposure of a full-write token already flagged in `CONCERNS.md` | Kotlin has no network path at all |
| Sensitive request text on the home screen | Names and health details visible to anyone holding the phone | Inherent to the feature. Keep `home_screen` only and don't add `keyguard` |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Count shown as `3/7` in RTL | Bidi order reads ambiguously | Reuse the app's wording, for example `3 من 7` |
| English title in an Arabic row | With `firstStrong` text direction, rows align differently `[INFER]` | Set `android:textDirection="rtl"` and `textAlignment` on row text |
| Accidental tap, no undo | Permanent wrong log | Accept for v1 with the debounce. Flag for the user; log removal is a separate feature |
| Empty state with all done | Blank widget looks broken | Reuse `خلصت كل صلوات النهاردة ✓` |
| No write token set | Widget marks locally but nothing syncs, because `flush()` returns early `[SRC]` | Queue is fine; document it, and consider a small notice |
| Rows clipped at small sizes | Five rows and a header exceed the verse widget's 110dp min height | Set `minHeight`/`minResizeHeight` for all rows, with tap rows around 40dp+ |
| Alphabetical via `compareTo` | Code units split أ ا إ آ apart `[INFER]` | Compare on `normalizeArabic` from `core/format/arabic.dart`, already present `[SRC]` |

## "Looks Done But Isn't" Checklist

- [ ] **Shuffle:** Passes "stable today". Verify the top five differ across a week of dates.
- [ ] **Midnight:** Works with the app open. Verify with the app force-closed, and after a reboot.
- [ ] **Local day:** Works at noon. Verify 00:30 local, using an injected clock. `prayedToday` calls `DateTime.now()` directly, so `openPrayers` needs an optional `now` parameter to be testable.
- [ ] **Offline tap:** Works online. Verify in airplane mode, with the app killed, then reopened hours later: the log carries the tap time.
- [ ] **Tap time:** Verify a tap at 23:50, consumed at 00:10, counts for the previous day.
- [ ] **Five rows:** Row 1 works. Verify every row marks its own request, and two widget instances stay in sync.
- [ ] **After five taps:** Verify more requests fill in with the app closed.
- [ ] **Deleted prayer:** Verify a tap, then deleting that prayer in the app, doesn't stall the outbox.
- [ ] **Dedupe:** Verify a prayer with no `logs` field still gets its first log through the guarded patch.
- [ ] **Release build:** Debug works. Verify `flutter run --release`, since R8 and resource shrinking are on by default and CI builds without `--no-shrink` `[SRC]`.
- [ ] **OTA:** Verify the widget still renders after an in-app update, not only after a fresh install.
- [ ] **Changelog:** `CHANGELOG.md` updated, per `PROJECT.md`.

## Moderate Pitfalls (Implementation Detail)

| Pitfall | What Goes Wrong | Prevention | Phase |
|---------|-----------------|------------|-------|
| Plain `<View>` divider | Not a supported RemoteViews class `[DOCS]`; the likely result is a "can't load widget" error | Use `ImageView` or `FrameLayout`. No custom views or subclasses | Widget Display |
| `getIdentifier("row_$i", ...)` | Dynamic resource lookup can break under the release shrinker `[INFER]`. Static `R.id` use is otherwise low risk: manifest-declared receivers and layout-referenced fonts are retained | Use a plain `intArrayOf(R.id.row0, ...)` | Widget Display |
| RTL relies on `layoutDirection` | The manifest has no `android:supportsRtl` `[SRC]`. Community sources tie start/end behaviour to that flag, but whether a launcher-hosted widget is affected is unconfirmed | Set explicit RTL attributes, then check on a device with an English system locale. Add `supportsRtl="true"` if needed | Widget Display |
| `@font/cairo` | `cairo.ttf` is a variable font (`fvar` table) `[RAN]`, so `textStyle="bold"` may not give true bold `[INFER]`. Framework XML fonts need API 26; minSdk is 24 `[SRC]` | Check weight on device. Accept fallback below API 26 | Widget Display |
| Non-total comparator | `List.sort` isn't guaranteed stable `[SRC]`, so ties flicker between rebuilds | End every comparator with an `id` tie-break, including `oldest` and `newest` | Shared Sort |
| Null dates in oldest/newest | `startedAt` is nullable `[SRC]` | Define a null rule and test it | Shared Sort |
| Persisting the sort as an index | Reordering the enum changes the user's setting | Store `.name`; unknown values fall back to random | Shared Sort |
| Search list out of step | `_PrayerSearch` receives `openPrayers(entities)` `[SRC]` | Pass the same sorted result | Shared Sort |
| Row order mutated by `done.sort` semantics | Newest-first for done items could conflict with a new mode | Keep it for the done section in all modes, or decide explicitly | Shared Sort |

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Weak shuffle shipped | LOW | Replace the key function; no data involved |
| Blocked outbox | LOW | Ship the typed-failure fix; the head moves to dead-letter and the queue resumes |
| Duplicate logs in Sanity | MEDIUM | Script a pass grouping `logs` by `_key` and removing repeats. Identical `_key` makes them exact. Check first that older logs have keys |
| Lost taps | HIGH | Unrecoverable once acked. This is why ack comes last |
| Wrong-row marks | MEDIUM | No undo exists; remove the log in Sanity Studio |
| Tap queue format change | LOW | Version the JSON and tolerate unknown fields, so an OTA over queued taps doesn't lose them |
| Widget shows "can't load" | LOW | Fix the layout; the next update re-renders. Older placed widgets refresh on the package update |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 6. Duplicate logs | Sync Hardening | Spike results recorded; replay test yields one log |
| 7. Dead mutation blocks outbox | Sync Hardening | Failing head moves aside; later items send; 401 and timeouts keep the queue |
| 1. Shuffle doesn't shuffle | Shared Sort | 7-day top-5 test fails on bare `hashValue` |
| 2. Two definitions of today (Dart) | Shared Sort | Injected-clock test at 00:30 local and on Apr 24 / Oct 29 |
| 12. Resume republish | Shared Sort | Order changes on resume after a date change |
| 2. Two definitions of today (Kotlin) | Widget Display | No UTC in the new provider; reset at local midnight |
| 10. Publishing only five | Widget Display | Five taps refill rows; counts match the app with pins present |
| 11. Midnight reset | Widget Display | Clock-change and reboot tests with the app closed |
| 3. Dart stale cache | Widget Marking | Native file, no `reload()`; warm-resume drain works |
| 4. Same-key writes | Widget Marking | No Kotlin write to any Dart-owned key |
| 5. Handoff | Widget Marking | Fake-kill test at each step |
| 8. PendingIntent collisions | Widget Marking | Each row marks its own id; verse widget unchanged |
| 9. Double tap | Widget Marking | Real double tap logs one prayer |
| 12. Drain on launch and resume | Widget Marking | Both paths consume taps |

## Open Questions

- **Sanity no-match behaviour.** Does a query patch matching nothing return 200 with no effect? What status does a missing-document patch return? Resolve in the Sync Hardening spike.
- **Phone timezone.** `Africa/Cairo` comes from the dev machine. The local-day fix holds in any zone, but the DST dates apply only to Cairo.
- **Pinned and prayed precedence.** Confirm that keeping current behaviour (prayed wins) is right.
- **Undo.** Is a permanent widget mis-tap acceptable for v1?
- **RTL under a launcher.** Only a device check can settle this.
- **Android behaviour on specific launchers.** Not tested. Android 17's RemoteViews memory cap covers bitmaps `[DOCS]`, so a text-only widget should be unaffected. No Android 16 rate limit was found, which is not proof that none exists.

## Sources

**Repo and local tools (strongest evidence):**

- `lib/features/intercede/data/store.dart`, `repository.dart`, `models.dart`
- `lib/core/settings.dart`, `lib/core/sanity/client.dart`, `lib/app/app.dart`, `lib/main.dart`
- `lib/features/leyaana/data/daily_pick.dart`, `verse_surfaces.dart`
- `android/app/src/main/kotlin/com/aio/aio/VerseWidgetProvider.kt`, `MainActivity.kt`, `AndroidManifest.xml`, `android/app/build.gradle.kts`, `res/layout/verse_widget.xml`, `res/xml/verse_widget_info.xml`
- `.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md`
- `shared_preferences` 2.5.5 source and README, `shared_preferences_android` 2.4.23 `LegacySharedPreferencesPlugin.java` (pub cache)
- Flutter 3.44.9 `FlutterPlugin.kt`, `FlutterPluginUtils.kt`, `FlutterExtension.kt`; Dart SDK `math/random.dart`, `core/list.dart`
- Local runs: Dart sort-key experiment; `zdump -v Africa/Cairo`; Python `zoneinfo` day lengths; `cairo.ttf` table listing

**Vendor documentation:**

- [Android app widgets](https://developer.android.com/develop/ui/views/appwidgets)
- [Glance app widget setup (update frequency, receiver limits)](https://developer.android.com/develop/ui/compose/glance/create-app-widget)
- [AppWidgetProviderInfo](https://developer.android.com/reference/android/appwidget/AppWidgetProviderInfo)
- [RemoteViews](https://developer.android.com/reference/android/widget/RemoteViews)
- [PendingIntent](https://developer.android.com/reference/android/app/PendingIntent)
- [SharedPreferences.Editor](https://developer.android.com/reference/android/content/SharedPreferences.Editor)
- [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms)
- [Implicit broadcast exceptions](https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions)
- [Android 17 behavior changes](https://developer.android.com/about/versions/17/behavior-changes-17)
- [Sanity mutation API](https://www.sanity.io/docs/http-reference/mutation)
- [Sanity patches](https://www.sanity.io/docs/content-lake/http-patches)
- [GROQ functions](https://www.sanity.io/docs/groq-functions)
- [GROQ operators](https://www.sanity.io/docs/specifications/groq-operators)

**Community (LOW, directional only):**

- [Turning Back to RTL, CommonsWare](https://commonsware.com/Jetpack/pages/chap-cl-012)
- [Egypt DST discussion, tz mailing list](https://mm.icann.org/pipermail/tz/2023-March/057639.html)

---
*Pitfalls research for: interactive Android widget and date-seeded sort in a Flutter app*
*Researched: 2026-11-02*
