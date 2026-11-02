# Architecture Research

**Domain:** Interactive Android home-screen widget and shared sort on an offline-first Flutter app
**Researched:** 2026-11-02
**Confidence:** HIGH for everything read in this repo and the pinned plugin sources, or executed locally. MEDIUM for the one thing only a live Sanity call can settle (see Open Questions).

**Evidence labels used below:**
- **[source]** read directly in this repo or the pinned package (`shared_preferences` 2.5.5, `shared_preferences_android` 2.4.23, Flutter 3.44.9).
- **[ran]** executed during this research.
- **[docs]** official docs. The confidence classifier rates web sources LOW alone and MEDIUM when cross-checked; every [docs] claim below was cross-checked against source or a second official page unless marked otherwise.

## Direct Answers

### 1. Does Dart's cached SharedPreferences see values Kotlin writes?

**No, not while the process is alive.** [source]

- `SharedPreferences.getInstance()` fills `_preferenceCache` once. `getString()` reads only that map. `Settings.init()` uses `??=`, so `Settings._prefs` is the same instance for the life of the process.
- The plugin README says so directly: a value written by native code is not seen until `reload()`.
- A cold start does see native writes, because `getInstance()` calls `getAll`. That makes this a trap: tap the widget with the process dead and it works; tap it with the app in the background and Dart reads stale data. A quick test can pass while the bug is real.
- The opposite direction is safe, and the verse widget already relies on it. Dart's `await setString()` returns after a native `commit()`, and Android keeps one `SharedPreferences` instance per file per process, so Kotlin in the same process sees the value at once.
- The Dart cache does not clobber Kotlin's keys. Writes are per key, never whole-map.

**Is a reload needed on resume? Do not design around one. Keep the tap queue out of `FlutterSharedPreferences` and read it over the `aio/widget` channel.** `reload()` would work for reading, but it has two real failure modes:

| Hazard | How it happens | Result |
|--------|----------------|--------|
| Lost tap | Dart reloads, reads the queue, then calls `remove()`. A tap landing between read and remove is deleted unread. | Violates the Core Value |
| Cached value regresses | `reload()` clears the cache and refills it from a `getAll` snapshot. Any `setString` issued while that call is in flight is overwritten in the cache by the older value. The disk stays right, but the cache stays wrong until that key is written again. Resume runs `flush()`, which calls `_save()`, so this overlap is realistic. | Every `Settings` reader is exposed, including `memorize_repository.dart`, which re-reads its outbox from `getCache` |

The channel avoids both. Kotlin method-channel handlers and `BroadcastReceiver.onReceive` both run on the Android main thread, so enqueue, peek and ack never interleave. No locking is needed. [source for handlers: existing `MainActivity`; main-thread dispatch is standard Android behaviour]

### 2. How do we make log replay idempotent?

**The identity already exists. Two consumers ignore it.** `_key()` is called once inside the mutation literal (`repository.dart:170`) and the whole mutation is persisted in the outbox, so a retry resends the same `_key`. [source] What is missing:

| Layer | Today | Fix |
|-------|-------|-----|
| Sanity | `insert after logs[-1]` appends regardless | Add `unset: ['logs[_key=="<key>"]']` to the same patch |
| Local replay | `_applyPatch` appends (`store.dart:192-201`) | Skip items whose `_key` is already in the list |
| Widget taps | No key yet | Kotlin generates the `_key` at tap time and it travels with the tap |

One patch holding `setIfMissing`, a keyed `unset` and `insert` means "remove this key if present, then append it". Applying it N times leaves exactly one entry. Unset runs before insert in both the documented server order and the `@sanity/mutator` order. [docs + source]

Result of running this through Sanity's own `@sanity/mutator` 6.16.0 from `sanity/node_modules`: [ran]

```text
keyed: no logs field, 1x   [abc123def456]
keyed: no logs field, 3x   [abc123def456]
keyed: empty logs, 2x      [abc123def456]
keyed: other logs, 2x      [old1, old2, abc123def456]
current shape, 2x          [abc123def456, abc123def456]   <-- the known bug
```

`@sanity/client`'s README documents `reviews[_key=="abc123"]` as a valid `unset` path. [source] The mutator is not the production server, so run the one `dryRun` check under Open Questions before this ships.

**Rejected alternatives:**
- `ifRevisionID` needs a tracked revision and turns a safe retry into a 409.
- Reading before writing costs a round trip and only narrows the race.
- `transactionId`: the docs do not say a retry is deduplicated, so it cannot be relied on.
- `insert replace` on a keyed path is rejected on reasoning, not a test: with no match there is nothing to replace.

## Corrections to PROJECT.md Decisions

Three pending decisions need changing. Each came from checking the plan against the code.

| Decision as written | Problem | Change to |
|---------------------|---------|-----------|
| Random seeded by day + id using "a small stable hash" | The obvious hash, `hashValue` in `daily_pick.dart`, barely reshuffles. Measured below. | Dedicated FNV-1a over `'$day:$id'`, day first |
| Taps "consumed on app resume" | Cold start can miss it. `readInitialLifecycleStateFromNativeWindow()` runs during binding init, before `AioAppState` adds its observer, so the initial state may never reach it. [source] | Consume in `load()` **and** on resume. Both are safe because replay is idempotent. |
| `logPrayed` "gains an optional time parameter" | Time alone is not enough. A tap replayed after a lost ack would get a fresh `_key` and defeat the fix. | Tap time and tap key both travel with the tap. Share one mutation builder. |

**Hash measurement** [ran] over 30 realistic ids and 30 consecutive days, comparing each day to the next:

| Scheme | Adjacent pairs kept | Top-5 overlap |
|--------|---------------------|---------------|
| `hashValue('$id:$day')` | 1.000 (exact rotation) | 1.000 |
| `hashValue('$day:$id')` | 0.736 | 0.931 |
| `fnv1a('$id:$day')` | 0.669 | 0.890 |
| **`fnv1a('$day:$id')`** | **0.032** | **0.172** |
| `Random(hashValue(...))` | 0.030 | 0.145 |
| *Truly random, expected* | *0.034* | *0.167* |

`hashValue` is polynomial, and every app-created id has the same length, so a change of day shifts all ids by nearly the same amount. The top five widget rows would look almost identical every morning, and no test of "same order within a day" would catch it. Unit-test this: consecutive days must not keep the same top five.

`Random(seed)` also mixes well, but Dart documents that its sequence may change between SDK releases. FNV-1a is three lines and fixed forever.

## Standard Architecture

### System Overview

```text
┌───────────────────────────── Dart (only while the app runs) ──────────────────┐
│                                                                               │
│  IntercedeScreen / search      Settings.intercedeSort                         │
│        │ reads                        │                                       │
│        ▼                              ▼                                       │
│  openPrayers(entities, sort)  <── one sort, in models.dart (pure)             │
│        ▲                              ▲                                       │
│  ValueNotifier entities               │                                       │
│        ▲                              │                                       │
│  IntercedeStore ──_publish()──> widget_bridge.dart (encodes snapshot)         │
│    _json, _outbox                     │         ▲                             │
│        │ flush                        │         │ peek / ack                  │
└────────┼──────────────────────────────┼─────────┼─────────────────────────────┘
         ▼                              │         │
     Sanity API          setCache +     │         │ MethodChannel "aio/widget"
                         "update"       │         │
┌───────────────────────────── Kotlin (runs without Dart) ──────────────────────┐
│                                       ▼         │                             │
│  FlutterSharedPreferences         MainActivity ─┘                             │
│  "flutter.intercede-widget"           │ renderAll / peek / ack                │
│  (written by Dart, read by Kotlin)    ▼                                       │
│        └───────────────────> IntercedeWidgetProvider <──── AlarmManager       │
│                                  │         ▲               (next midnight)    │
│  "intercede_widget" prefs file <─┘         │                                  │
│  queue of taps (Kotlin only)           row tap PendingIntent                  │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Owns | Must not |
|-----------|------|----------|
| `openPrayers()` in `models.dart` | The only ordering logic, pure | Touch `Settings` or `DateTime.now()` for the day key without a test seam |
| `IntercedeStore` | `_json`, `_outbox`, when to publish, when to consume taps | Know the Kotlin or snapshot format |
| `widget_bridge.dart` (new) | Snapshot encoding, channel calls | Hold state |
| `Settings` | Persisting the sort choice as a plain string | Import feature types; `core` must not depend on features |
| `MainActivity` | Routing channel calls | Hold widget logic |
| `IntercedeWidgetProvider` (new) | Rendering, tap queue, midnight alarm, the local "prayed today" check | Sort anything, or talk to the network |

**Trust boundary:** the provider is `exported="false"`, its `PendingIntent`s are immutable, and the queue file is private. Dart still rechecks each tap's prayer id against `_json`, since a stale id is expected (see Pattern 3).

## Recommended Project Structure

```text
lib/
├── core/settings.dart                       # + intercedeSort (String)
├── app/app.dart                             # resume calls IntercedeStore.onResume()
└── features/intercede/
    ├── data/
    │   ├── models.dart                      # + IntercedeSort, dailyRank, openPrayers(sort:)
    │   ├── repository.dart                  # + _logMutation, logWidgetTaps; _createdAt in _query
    │   ├── store.dart                       # + key dedupe, takeWidgetTaps, onResume, republish
    │   └── widget_bridge.dart               # NEW: mirrors leyaana/data/verse_surfaces.dart
    └── ui/intercede_screen.dart             # + sort menu; two openPrayers calls pass sort
android/app/src/main/
├── AndroidManifest.xml                      # + receiver
├── kotlin/com/aio/aio/
│   ├── IntercedeWidgetProvider.kt           # NEW
│   └── MainActivity.kt                      # update renders both; + peekTaps, ackTaps
└── res/
    ├── layout/intercede_widget.xml          # NEW: header + 5 fixed rows
    └── xml/intercede_widget_info.xml        # NEW
test/
├── intercede_store_test.dart                # + retry, replay, ack-loss cases
└── intercede_test.dart                      # + every sort mode, pinned, prayed-today, reshuffle
CHANGELOG.md                                 # one entry per shipped phase
```

### Structure Rationale

- **`widget_bridge.dart` stays separate from `store.dart`:** the store's file comment describes one job, and `verse_surfaces.dart` is the precedent for a thin Dart-to-widget file.
- **One new Kotlin file:** no shared base class with `VerseWidgetProvider`. The only overlap is the `getSharedPreferences` call. `render` needs a small shared entry point in `MainActivity`, nothing more.
- **`main.dart` does not change:** `load()` already runs there, and consuming taps belongs inside it.

## Architectural Patterns

### Pattern 1: Snapshot Holds Facts, Kotlin Derives "Today"

**What:** Dart publishes every open prayer in sorted order with its last-prayed time as epoch ms. Kotlin works out prayed-today at render time from the device's current local day.

**When to use:** Any widget state that has to change while Dart is not running.

**Trade-offs:** About 10 lines of Kotlin judgment, but no sort logic. This is the reason midnight reset needs no Dart.

```json
{"items":[{"id":"intercedePrayer.x","t":"صحتها","e":"ماما","last":1762063200000,"c":true}]}
```

| Field | Meaning | Note |
|-------|---------|------|
| `items` | **All** open prayers, not five | Otherwise five offline taps empty the widget while more remain |
| `last` | `lastPrayedAt` in epoch ms, or absent | Not a boolean: a boolean cannot reset at midnight |
| `c` | Counts toward the header | Matches the in-app rule at `intercede_screen.dart:140`: pinned only, if any are pinned |

Kotlin's rule, with queued taps folded in:

```kotlin
val last = maxOf(item.last, queuedAt[item.id] ?: 0L)
val done = last != 0L && localDay(last) == localDay(now)
val rows = items.filterNot(::done).take(5)          // snapshot order preserved
```

Use the **local** day here. `VerseWidgetProvider` uses UTC on purpose to match the PWA; copying that line would reset this widget at 02:00 or 03:00 Egypt time and disagree with `Prayer.prayedToday`.

### Pattern 2: At-Least-Once Queue With an Idempotent Consumer

**What:** Peek, make it durable in Dart, then ack by key.

**When to use:** Here, because the requirement is "never gets lost". Ack-before-save loses taps on a crash; save-before-ack can only redeliver, and redelivery is harmless because of the keyed patch.

**Trade-offs:** One more channel method than a destructive `takeTaps`.

```dart
// store.dart
Future<void> takeWidgetTaps() async {
  if (_json.isEmpty) return;              // cache unreadable: keep taps, retry later
  final taps = await peekWidgetTaps();    // [] on any channel error
  if (taps.isEmpty) return;
  await logWidgetTaps([
    for (final t in taps)
      if (_findDoc(_json, t.prayerId) != null) t,
  ]);                                     // returns after _save(), which is a native commit()
  await ackWidgetTaps([for (final t in taps) t.key]);
}

Future<void> onResume() async {
  await takeWidgetTaps();
  if (_json.isNotEmpty) _publish();       // also picks up a new day's order
  await flush();
}
```

`load()` calls `takeWidgetTaps()` between decoding the caches and the existing publish, so a cold start paints taps and `refresh()` sends them.

Ack **by key**, never "clear all", so a tap arriving mid-consume survives.

```dart
// repository.dart: the single place a log mutation is built
Map<String, dynamic> _logMutation(String id, {String? note, DateTime? at, String? key}) {
  final k = key ?? _key();
  return {
    'patch': {
      'id': id,
      'setIfMissing': {'logs': []},
      'unset': ['logs[_key=="$k"]'],
      'insert': {
        'after': 'logs[-1]',
        'items': [
          {
            '_key': k,
            '_type': 'prayerLog',
            'prayedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
            if (note != null && note.isNotEmpty) 'note': note,
          },
        ],
      },
    },
  };
}
```

`logWidgetTaps` passes the whole list to one `apply()`, giving one `_save` and one publish however many taps queued.

Local dedupe in `_applyPatch`, replacing the current insert block:

```dart
final existing = current is List ? current : const [];
final seen = {for (final x in existing) if (x is Map) x['_key']};
doc[field] = [
  ...existing,
  ...(insert['items'] as List? ?? const []).where(
    (i) => i is! Map || i['_key'] == null || !seen.contains(i['_key']),
  ),
];
```

The `null` check matters: without it, one key-less item would suppress another. `doc.remove('logs[_key=="..."]')` in the existing unset loop is a harmless no-op, so `unset` needs no parsing locally. List position may differ from the server after a retry, which does not matter because `_parseLogs` sorts by date.

### Pattern 3: Tap Handling Without Dart

**What:** `onReceive` writes one queue entry and re-renders. No `goAsync`, no worker.

```kotlin
override fun onReceive(ctx: Context, intent: Intent) {
    when (intent.action) {
        ACTION_PRAY -> { enqueue(ctx, intent.data!!.schemeSpecificPart); renderAll(ctx) }
        ACTION_MIDNIGHT -> renderAll(ctx)
        else -> super.onReceive(ctx, intent)   // required, or onUpdate never fires
    }
}
```

Five details that each cause a real bug if missed:

| Detail | Why |
|--------|-----|
| Put the prayer id in the Intent **data URI**, e.g. `Uri.fromParts("intercede", id, null)` | `PendingIntent` matching ignores extras. With extras only, every row fires the same prayer: **wrong person logged, silently**. [docs] A slot-based `requestCode` also fixes that, but `FLAG_UPDATE_CURRENT` then swaps the id under an on-screen row during a refresh. A URI per prayer cannot do that. |
| Use `commit()`, not `apply()` | `apply()` returns before disk. [docs] This write is the Core Value, and the separate small file keeps it cheap. |
| Use a separate prefs file, `intercede_widget` | `FlutterSharedPreferences.xml` holds every cache in the app, and Android rewrites the entire file on each commit. Being outside it also removes the cache question entirely. |
| Ignore the tap if already `done` today | Stops a double tap before the row re-renders. Both run on the main thread, so the check is sound. |
| Generate `_key` as 12 chars from `[a-z0-9]` | Same alphabet as Dart `_key()`, and safe to interpolate into the `unset` path |

Queue entry: `{"k":"<12 chars>","id":"intercedePrayer.x","at":1762063200000}`.

### Pattern 4: Midnight Alarm Armed From Render

**What:** Every `renderAll` arms one `setAndAllowWhileIdle` alarm for the next local midnight, using a fixed `PendingIntent` so it replaces the previous one.

**Why not the alternatives:**

| Option | Verdict |
|--------|---------|
| `updatePeriodMillis` alone | 30-minute floor, and 48 wake-ups a day to do one job. Keep the 6-hour value from the verse widget as a fallback only. [docs, unverified-tier] |
| `ACTION_DATE_CHANGED` in the manifest | Not on the implicit-broadcast exemption list, so it likely never fires on current targets [docs, unverified-tier] |
| `setExactAndAllowWhileIdle` | **Avoid.** `USE_EXACT_ALARM` only exists from API 33, while `minSdk` is 24 and API 31-32 need `SCHEDULE_EXACT_ALARM`, so the call can throw `SecurityException` there. Exact timing is not needed. |
| `setAndAllowWhileIdle` | Needs no permission and only fires late, never early. If the phone is dozing nobody is looking at the widget, and the alarm runs once it wakes. |

Alarms do not survive reboot, but the system sends `APPWIDGET_UPDATE` after boot, which reaches `onUpdate`, which re-renders and re-arms. Cancel in `onDisabled`.

### Pattern 5: Sort as One Pure Function

**What:** Extend `openPrayers` rather than adding a second function. Keep today's partition: pending, then done.

```dart
enum IntercedeSort { random, neglected, oldest, newest, alpha }

/// FNV-1a. Day first: `id:day` barely reshuffles (see ARCHITECTURE.md).
int dailyRank(String day, String id) {
  var h = 0x811c9dc5;
  for (final c in '$day:$id'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}
```

| Rule | Implementation |
|------|----------------|
| Prayed today goes last in every mode | The existing partition, untouched. So a pinned prayer prayed today sinks; "prayed today" beats "pinned", matching current behaviour. |
| Pinned first in every mode | The first comparator line in `pending.sort`, already there |
| Random is stable while ticking off | Rank depends only on day and id, never on list position, so finishing or adding a prayer moves nothing else. This rules out `list.shuffle(Random(seed))`. |
| Day key | Local date, same as `prayedToday`. **Do not reuse `getPeriodKey`**: it is UTC and would reshuffle mid-night local time. |
| Total ordering | Tie-break on id in every mode, so app and widget cannot disagree |
| Default parameter | `sort = IntercedeSort.neglected` keeps `test/intercede_test.dart` passing and makes intent explicit. UI callers pass the saved setting, whose default is random. |

**Oldest and newest:** `Prayer.startedAt` is nullable and optional in the Sanity schema. Add `_createdAt` to the prayer projection in `_query` and parse `m['startedAt'] ?? m['_createdAt']`, the same pattern `_parseEntity` uses at `repository.dart:60`.

**Sort setting:** `Settings.intercedeSort` holds a plain string (default `'random'`). Parse in the feature with `IntercedeSort.values.asNameMap()[s] ?? IntercedeSort.random`, so `core` keeps not importing features.

**Scope note:** `Entity.active`, used by the person page, is a separate per-person list and stays as it is. The requirement names the in-app list, search, and the widget.

## Data Flow

### Key Data Flows

**1. Publish (Dart to widget).**
```text
apply() / refresh() / onResume() / republish()
  → _publish(): entities.value = parseEntities(_json)
  → unawaited(publishIntercedeWidget(entities))
      → openPrayers(entities, sort) → JSON
      → await setCache('intercede-widget', json)   // committed before the next line
      → invokeMethod('update')
          → VerseWidgetProvider.render + IntercedeWidgetProvider.renderAll
```
The whole bridge call sits in a `catch (_)`, like `refreshVerseSurfaces`. It covers `MissingPluginException` and `flutter test`, where the channel has no handler.

**2. Tap (no Dart involved; the process may be cold).**
```text
Row tap → explicit broadcast → onReceive (main thread)
  → already done today? stop
  → append {k, id, at} to prefs file "intercede_widget", commit()
  → renderAll: row disappears, next un-prayed fills in, count moves
```

**3. Consume (Kotlin to Dart to Sanity).**
```text
load() [cold start]  or  onResume() [warm]
  → peekTaps over the channel
  → drop taps whose prayer is not in _json
  → apply([...]): optimistic update, outbox, await _save(), publish, flush
  → ackTaps(keys): Kotlin removes those keys only
```

Failure at each step:

| Dies after | State | Recovery |
|------------|-------|----------|
| Peek | Queue intact | Next consume repeats it |
| Saving `_cacheKey`, before `_outboxKey` | Local log saved, not queued, no ack | Replay: local dedupe, outbox gains it |
| `_save`, before ack | Saved and queued, not acked | Replay: second outbox entry is harmless |
| Server accepted, before outbox prune | Same mutation resent | Keyed patch leaves one entry |
| Ack | Queue empty, snapshot possibly old | Next launch republishes |

**4. Midnight.** Alarm → `renderAll` → yesterday's rows are un-prayed again, in yesterday's order. The new order arrives when the app opens, as PROJECT.md accepts.

**5. Sort change.** Menu → `Settings.intercedeSort = x` → `IntercedeStore.instance.republish()` → flow 1. The in-app list rebuilds from the same `ValueNotifier` update, so no `setState` is needed.

### State Ownership

| State | Owner | Direction |
|-------|-------|-----------|
| Prayers, logs, outbox | `IntercedeStore` (Dart) | Dart → Sanity |
| Sorted snapshot | Dart writes, Kotlin reads | Dart → Kotlin only |
| Tap queue | Kotlin writes, Dart peeks and acks | Kotlin → Dart only |
| Sort choice | `Settings` (Dart) | Kotlin never needs it |

No value has two writers. That is why neither side needs to coordinate with the other.

## Scaling Considerations

This is a single-user app, so the realistic ceilings are:

| Concern | Ceiling | Action |
|---------|---------|--------|
| `_save()` encodes all of `_json` on each change | Fine for hundreds of prayers | None |
| Tap queue size | Days of offline taps, one per prayer per day | None |
| Widget with the app unopened for days | Order frozen, marking and reset still work, queue grows slowly | Accepted in PROJECT.md |

### Scaling Priorities

1. **First to hurt:** a stuck outbox, not volume. See Anti-Pattern 4.
2. **Second:** a person prays while the app sits foreground in split-screen. Taps wait for the next resume. `ponytail:` add a push from `onReceive` over the channel if that ever matters.

## Anti-Patterns

### Anti-Pattern 1: Queue in `flutter.*` Keys With `reload()` on Resume

**What people do:** Kotlin appends to `flutter.intercede-taps`; Dart reloads, reads and removes.
**Why it's wrong:** The read-then-remove window drops taps, and `reload()` can regress unrelated cached values.
**Do this instead:** Private prefs file, peek and ack over the channel.

### Anti-Pattern 2: Publishing Only What the Widget Shows

**What people do:** Send the first five rows, or a `prayedToday` boolean, because that is what renders.
**Why it's wrong:** Tapping through five rows offline empties the widget, and a boolean cannot reset at midnight.
**Do this instead:** Send all open prayers and timestamps.

### Anti-Pattern 3: Sorting or Deciding in Two Languages

**What people do:** Port the comparator to Kotlin to reshuffle at midnight.
**Why it's wrong:** Two implementations drift, and PROJECT.md rules it out.
**Do this instead:** Kotlin filters and takes five. The one thing it derives, prayed-today, must stay a date comparison.

### Anti-Pattern 4: Queueing a Patch for a Document That May Be Gone

**What people do:** Convert every tap straight into a mutation.
**Why it's wrong:** A patch fails if its document does not exist. [docs] `flush()` stops at the first failure and keeps the item at the head, so **one bad patch blocks every later تشفع sync, permanently and silently.** `_applyPatch` also returns quietly for a missing doc, so nothing shows locally. The widget raises the odds because tap ids come from a snapshot. This is not listed in `.planning/codebase/CONCERNS.md`, and it applies to in-app taps today.
**Do this instead:** Filter taps against `_json` at consume time (covers an in-app delete). For a delete made in Studio while the outbox is pending, `flush()` needs to discard a permanently rejected mutation. Decide this once the real status code is known; see Open Questions. Do not treat all 4xx as permanent: a 401 or 403 from a bad token must keep the queue.

### Anti-Pattern 5: Relying on `resumed` Alone

**What people do:** Add the consumer to `didChangeAppLifecycleState` and stop.
**Why it's wrong:** The observer can miss the initial state, so the first launch after a tap would not drain the queue until the next resume.
**Do this instead:** Consume in `load()` too. `load()` decodes both caches before its first `await`, and no Dart event can run between `runApp` and that call, so a resume event always finds them loaded.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Sanity mutate | Existing outbox, one mutation per request | Each `flush` request is atomic, so the single patch holding `unset` and `insert` is safe |
| Sanity schema | **No change** | `_key` is standard on array items; `prayerLog` needs no new field |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Dart ↔ `MainActivity` | `aio/widget`: `update`, `peekTaps`, `ackTaps` | `configureFlutterEngine` runs before Dart `main`; the verse path proves it |
| WorkManager isolate | None | It never touches `IntercedeStore`, and the channel is registered only on the Activity's engine. Keep it that way. |
| Provider ↔ Dart | Prefs only, one writer per key | A provider cannot reach Dart directly |
| `IntercedeScreen` ↔ widget | Both go through `_publish()` | `intercede_screen.dart`'s existing `_reload()` calls need no change |
| `core` ↔ `features` | `Settings` stores a string | Keeps the dependency direction |

## Suggested Build Order

Each step can ship alone. Verified dependencies:

```text
1. Idempotent logs ──────────────────────────┐
2. Sort ──────────────┐                      │
                      ▼                      ▼
              3. Display-only widget ──> 4. Tap queue and consumer
```

| # | Phase | Why here | Testable by |
|---|-------|----------|-------------|
| 1 | **Idempotent log path:** `_logMutation`, `_applyPatch` dedupe, tap time and key params, `dryRun` check, outbox-poison decision | Fixes a live bug and everything in step 4 depends on it. No native code. | `flutter test`: retry, replay over server data, redelivery with same key, key-less items |
| 2 | **Shared sort:** enum, `dailyRank`, `openPrayers(sort:)`, setting, menu, `_createdAt` | Pure Dart, independently useful, and step 3 needs the order | `flutter test`: all five modes, pinned, prayed-today, stable through ticking, consecutive days differ |
| 3 | **Display-only widget:** bridge, snapshot, provider, layout, manifest, `update` renders both, local-day check, midnight alarm | Proves the Dart-to-Kotlin path and RTL layout before taps add risk. A row tap can open the app for now. | Emulator: add widget, change sort, set device clock past midnight |
| 4 | **Marking from the widget:** data-URI `PendingIntent`s, queue, `peekTaps`/`ackTaps`, `takeWidgetTaps`, `onResume`, queue-aware render | Depends on 1 for safe replay and 3 for rendering | Emulator, airplane mode: tap with process dead **and** with app backgrounded, then reopen; confirm the time and that exactly one log reaches Sanity |

**Why 1 is first despite being invisible:** if 4 shipped first, every redelivered tap could create a permanent duplicate in production data, and those are not cleaned up by the fix.

**Phase 3 and 4 could merge** if preferred, but keeping them apart gives a working widget even if tap handling slips, and the first Kotlin bug is then only ever a display bug.

**Testing limit:** the repo has no Kotlin test setup, and adding one is not worth it for about 100 lines. The Kotlin side is covered by a manual emulator script; keep all branching logic in Dart where `flutter test` reaches it.

## Open Questions

1. **Live confirmation of the keyed patch (required in Phase 1).** The mutator and the client README agree, but production is a different implementation. Run once, with a real prayer id and `dryRun=true` so nothing is persisted:

   ```bash
   curl -s -X POST \
     "https://kfme7y2v.api.sanity.io/v2024-01-01/data/mutate/production?dryRun=true&returnDocuments=true" \
     -H "Authorization: Bearer $SANITY_WRITE_TOKEN" -H 'Content-Type: application/json' \
     -d '{"mutations":[{"patch":{"id":"<prayer id>","setIfMissing":{"logs":[]},"unset":["logs[_key==\"<existing key>\"]"],"insert":{"after":"logs[-1]","items":[{"_key":"<existing key>","_type":"prayerLog","prayedAt":"2026-11-02T06:00:00.000Z"}]}}}]}'
   ```

   Expect the returned document to hold that key once. `dryRun` support comes from a search result and memory, so confirm it behaves that way on a harmless call first.

2. **Status code for a patch on a missing document.** Unknown. Repeat the same call with a fake id to learn it, then decide the `flush()` discard rule. `sanityMutate` currently throws an untyped `Exception('Sanity <code>: ...')`, so `flush` cannot see the code without a small change.

3. **What the widget header counts.** The in-app header counts pinned prayers only when any are pinned; PROJECT.md says "prayed/total". The `c` field assumes they should match. Confirm with the user.

4. **Widget behaviour with no Sanity token.** The in-app pray button is hidden without a token. A widget tap would still log locally and sync once a token is added, which seems acceptable, and is the simpler option. Confirm.

## Sources

**Primary, read or executed:**
- This repo: `lib/features/intercede/data/{store,models,repository}.dart`, `ui/intercede_screen.dart`, `lib/features/leyaana/data/{verse_surfaces,daily_pick}.dart`, `lib/core/{settings,sanity/client}.dart`, `lib/app/app.dart`, `lib/main.dart`, `android/app/src/main/kotlin/com/aio/aio/`, `AndroidManifest.xml`, `sanity/schemaTypes/intercedePrayer.ts`, `.planning/codebase/CONCERNS.md`
- `shared_preferences` 2.5.5: `lib/src/shared_preferences_legacy.dart`, `README.md`
- `shared_preferences_android` 2.4.23: `LegacySharedPreferencesPlugin.java`, `Messages.java`
- Flutter 3.44.9: `services/binding.dart`, `scheduler/binding.dart`, `widgets/binding.dart`, `FlutterExtension.kt` (minSdk 24, targetSdk 36)
- `@sanity/mutator` 6.16.0 (`parsePatch` order, plus the retry simulation above) and the `@sanity/client` README (keyed `unset`)
- Hash reshuffle measurement, run locally in Dart

**Official documentation:**
- [SharedPreferences.Editor](https://developer.android.com/reference/android/content/SharedPreferences.Editor): `apply` vs `commit`, per-process singletons
- [PendingIntent](https://developer.android.com/reference/android/app/PendingIntent): extras are not part of matching
- [Sanity HTTP mutations](https://www.sanity.io/docs/http-reference/mutation): failure on a missing document, atomic transactions, `transactionId`
- [Sanity HTTP patches](https://www.sanity.io/docs/content-lake/http-patches): JSON paths in `unset`, `insert` forms
- [Sanity HTTP API archive](https://www.sanity.io/docs/archive/http-mutations): patch operation order
- [Implicit broadcast exceptions](https://developer.android.com/guide/components/broadcast-exceptions)
- [AlarmManager](https://developer.android.com/reference/android/app/AlarmManager)
- [Advanced app widgets](https://developer.android.com/develop/ui/views/appwidgets/advanced): `updatePeriodMillis` floor, receiver time limits

---
*Architecture research for: تشفع Android widget and shared sort*
*Researched: 2026-11-02*
