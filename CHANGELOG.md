# Changelog

All notable changes to **يومي** (Daily AIO).

## [1.1.0] — 2026-09-28

### Added
- **حفظ الآيات (Scripture Memorization)** — Anki SM-2 spaced repetition system to memorize Bible verses effectively.
  - Interactive practice flow with 4 modes: Anki Flashcards, Voice Recording Studio, Reveal Challenge, and First-Letter Typing.
  - Multi-take voice recorder with individual playback, duration tracking, and delete option.
  - One-tap "تم حفظها خلاص ✅" (Mastered) toggle to mark verses as memorized or return them to review.
  - Continuous audio playlist player to listen to all recorded verses sequentially.
  - Instant search and status filtering (Due today, Learning, Mastered, With voice recording).
  - Optional verse translation on creation.
- **Sanity-First & Offline-First Architecture**:
  - Full Sanity CMS integration (`memorizeVerse` and `verseCategory` schemas).
  - Outbox queue pattern (matching `تشفع` / `IntercedeStore`) for 100% offline support — add, edit, delete, and grade verses without network connectivity with automatic background sync to Sanity.
  - Automatic and instant cloud upload for voice recordings to the Sanity Assets API (`audioFile`).
  - Automatic cleanup of local audio files upon verse deletion.
- **تشفع (Intercede)** — persistent prayer list and intercession tracker with offline-first caching, outbox mutations, and home hub integration.
- **OTA Updates & Signing** — in-app OTA updater checking GitHub releases, signed release automation via GitHub Actions.

### Changed
- Streamlined Memorize screen to a single direct "آياتي" view.
- Upgraded Android toolchain build support with OpenJDK 17.

## [1.0.0] — 2026-07-24

First release. Native Flutter app, Android.

### Added
- **Home hub** with four daily sections and a Settings screen.
- **1 · عمل الصليب** — static reflection (Amiri serif, centered, airy), fully offline.
- **2 · ليا انا** — daily verse / اسم من أسماء الله / بركة from Sanity, personalized
  by name + gender, matching the leyaana PWA's daily pick byte-for-byte.
  - Add / edit / delete content manager, writing directly to the Sanity mutate API.
  - Offline cache of fetched content.
- **3 · لليوم فقط** — NA "Just For Today" fetched from jftna.org and translated to
  Egyptian Arabic via Gemini, in-app, cached once per day.
- **4 · مسلم** — daily journal (one entry per day) with editable history, stored
  locally in sqflite.
- **Daily reminder** — one local notification at a user-chosen time; survives reboot.
- **Onboarding** — first name + gender.
- **Theme** — light/dark, RTL, Cairo font; blue `#1877F2` palette across the app,
  each section styled to match its source's vibe.
- **Branding** — app named يومي; white-cross-on-blue icon and matching splash
  (light/dark), generated into Android resources.

### Notes
- API keys/tokens are compiled into this personal build.
- iOS builds but its icon/splash are not yet customized.
