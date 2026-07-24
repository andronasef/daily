# Changelog

All notable changes to **يومي** (Daily AIO).

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
