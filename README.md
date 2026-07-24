# يومي (Daily AIO)

A personal, offline-friendly **Flutter** app that gathers four daily spiritual
practices behind one home hub, with a single daily reminder notification at a
time you choose. Arabic, RTL, light/dark.

<p align="center"><img src="assets/icon/icon_full.png" width="120" alt="يومي icon"></p>

## Sections

| # | Section | What it is | Source of truth |
|---|---------|------------|-----------------|
| 1 | **عمل الصليب** | A static spiritual reflection by شادي حبيش, rendered in a quiet Amiri-serif, centered, airy layout. Works fully offline. | Bundled text (from `god-work-on-me.vercel.app`) |
| 2 | **ليا انا** | The daily verse / اسم من أسماء الله / بركة, personalized by name + gender, plus an add/edit/delete content manager. | Sanity CMS (`kfme7y2v`) |
| 3 | **لليوم فقط** | The NA "Just For Today" reading fetched from jftna.org and translated to Egyptian Arabic with Gemini, in-app, cached once per day. | jftna.org + Gemini |
| 4 | **مسلم** | A daily journal — one surrender note to the Holy Spirit per day, with editable history. Local only. | Local sqflite |

The daily notification (`flutter_local_notifications`) fires once a day at the
time set in Settings.

## Architecture

- **All native Flutter** — no WebViews, no HTML rendering anywhere.
- **State:** `setState` + `shared_preferences` (single user, no state-management package).
- **Section 2 parity:** `lib/leyaana_content.dart` ports leyaana's exact daily-pick
  hash (`hashValue` / `getPeriodKey` / `pickIndex`) and name/gender personalization,
  so the app lands on the same daily item as the leyaana PWA. Reads come from the
  Sanity CDN; writes go straight to the Sanity **mutate API**.
- **Section 3:** fetch + Gemini translate happen in Dart; result cached per day.
- **Section 4:** `sqflite` table `entries(date PK, body, updated_at)`.

### Key files
```
lib/
  main.dart              app root, theme mode, routing
  theme.dart             blue palette + Cairo (google_fonts)
  settings.dart          shared_preferences wrapper
  onboarding.dart        first name + gender
  home.dart              4-card hub
  notifications.dart     daily local reminder
  settings_screen.dart   reminder time, dark mode, re-edit identity
  leyaana_content.dart   Sanity read + daily pick + personalization + mutate (write)
  sections/
    cross_work.dart      1 · عمل الصليب
    leyaana.dart         2 · ليا انا (daily view)
    leyaana_admin.dart   2 · ليا انا (add/edit/delete)
    just_for_today.dart  3 · لليوم فقط
    journal.dart         4 · مسلم
```

## Configuration (embedded keys)

This is a personal build, so credentials are compiled in. For a public release,
move them behind a proxy.

| What | Where | Notes |
|------|-------|-------|
| Gemini API key | `_geminiKey` in `lib/sections/just_for_today.dart` | Or `--dart-define=` a build var. |
| Sanity write token | `_writeToken` in `lib/leyaana_content.dart` | Needed only for ليا انا editing. Reads work without it; the edit screen shows a hint until it's set. Pass via `--dart-define=SANITY_WRITE_TOKEN=...` to avoid committing it. |

Sanity read config (`projectId: kfme7y2v`, `dataset: production`) is public and
already wired.

## Run & build

```bash
flutter pub get
flutter run                                  # debug
flutter build apk --release                  # release APK (debug-signed)
flutter install                              # install to attached device
```

The Android manifest declares `INTERNET`, `POST_NOTIFICATIONS`,
`RECEIVE_BOOT_COMPLETED`, `USE_EXACT_ALARM`, plus the boot-reschedule receiver.
Core-library desugaring is enabled for `flutter_local_notifications`.

First launch needs internet (Sanity, Gemini, and google_fonts fetching Cairo/Amiri).

## Design

One palette (blue `#1877F2`) across the app. Each section keeps the *vibe* of its
origin, not its colors: عمل الصليب = serif/centered/airy; ليا انا = rounded soft
cards; لليوم فقط = card with a colored top border, side-bordered quote, and an
emphasized closing box; مسلم = clean editor + history. Icon is a white cross on a
blue gradient; the splash matches (with a dark-mode variant).

## Tests

```bash
flutter test
```
`test/widget_test.dart` guards the leyaana daily-pick hash port (matches the PWA
byte-for-byte).

## Platforms

Android is fully set up (icon, splash, permissions). iOS builds but its icon and
splash aren't customized yet.
