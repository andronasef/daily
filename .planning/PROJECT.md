# يومي (Daily AIO): تشفع widget and shared sort

## What This Is

يومي is a personal, single-user, offline-friendly Flutter app (Arabic, RTL, light/dark) that gathers daily spiritual practices behind one home hub. This work adds an Android home-screen widget for تشفع (intercession) and a sort setting shared by the in-app prayer list and the widget.

## Core Value

Intercession requests come to the user from the home screen, in a random order that holds for the day, and marking one as prayed never gets lost, even offline.

## Requirements

### Validated

- ✓ Home hub with عمل الصليب, ليا انا, حفظ الآيات, لليوم فقط and تشفع sections — existing
- ✓ تشفع entities and prayers stored in Sanity, with an offline-first store and outbox (`lib/features/intercede/data/store.dart`) — existing
- ✓ Daily checklist via `openPrayers()`: pinned first, then most neglected, with prayed-today items last — existing
- ✓ Home-screen verse widget fed by SharedPreferences and the `aio/widget` channel (`VerseWidgetProvider.kt`) — existing

### Active

- [x] User can add a تشفع home-screen widget showing a prayed/total count and a scrollable list of all un-prayed requests
- [x] User can tap a request on the widget to mark it prayed, without opening the app and while offline
- [x] Widget taps are logged with the time of the tap, not the time the app is next opened
- [x] Widget's prayed-today state resets after midnight without opening the app
- [x] User can sort the in-app list by random (default), most neglected, oldest added, newest added, or alphabetical
- [x] Sort choice persists and applies to the in-app list, search, and the widget
- [x] Random order is stable for a calendar day and reshuffles once a day
- [x] Pinned requests stay on top in every sort mode, including random
- [x] Requests prayed today sort to the bottom in every sort mode
- [x] Retried or replayed prayer logs never create duplicate entries

### Out of Scope

- iOS widget — the repo has no `ios/` target
- Reshuffling in Kotlin at midnight — would duplicate the sort logic in two languages; the widget takes the new order when the app next opens

## Validation

Implemented in quick task 261102-wr9. All 46 tests pass, static analysis is clean, and Android debug APK builds. Emulator install/launch passed; widget placement/taps and midnight behavior remain unverified because the mandated device input tool failed. The reset alarm is inexact. See the quick-task summary for evidence and limitations.

## Context

- Brownfield Flutter app; see `.planning/codebase/` for the full map.
- Android only. The new widget follows the `VerseWidgetProvider` pattern: Dart writes JSON to SharedPreferences (native key prefix `flutter.`), then calls `aio/widget` → `update`.
- `IntercedeStore._publish()` runs after every mutation and refresh, so it is the single place to write widget data.
- `MainActivity`'s `update` handler currently refreshes only the verse widget.
- Marking from the widget goes through `logPrayed` on app resume, then the existing outbox.
- Known issue that this work touches: the outbox `insert` into `logs` is not idempotent (`.planning/codebase/CONCERNS.md`).
- `README.md` file paths are stale; `CHANGELOG.md` is maintained and must be updated.

## Constraints

- **Tech stack**: Flutter/Dart plus Kotlin `AppWidgetProvider`; no new packages — the existing widget pattern already covers this.
- **Compatibility**: Keep `setState` + `shared_preferences`; no state-management package.
- **Offline**: All marking must work with no network and sync later through the outbox.
- **Localization**: Arabic RTL UI using the bundled Cairo font.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| One sort setting shared by app and widget, default random | User asked for both to behave the same | Implemented (quick 261102-wr9) |
| Random seeded by day + request id, using a small stable hash | Prevents reshuffling on rebuild or while ticking items off; `hashCode` is not guaranteed stable | Implemented (quick 261102-wr9) |
| Pinned requests stay on top in random mode | User decision | Implemented (quick 261102-wr9) |
| Dart sorts; Kotlin only displays | Avoids duplicating sort logic in two languages | Implemented (quick 261102-wr9) |
| Widget taps queue natively and are consumed on cold load and resume | Works offline without running Dart in the background | Implemented (quick 261102-wr9) |
| Prayer events preserve the original time and stable key | Keeps the real tap time | Implemented (quick 261102-wr9) |
| Fix duplicate-log replay in this work | Widget marking depends on that path | Implemented (quick 261102-wr9) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-02 after initialization*
