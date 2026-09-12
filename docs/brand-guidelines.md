# Brand guidelines — Masroufi (مصروفي)

Source of truth for voice, identity, assets. Preserve-brand mode: systematizes
existing identity, no overhaul.

## Identity

- Names: Masroufi (en), Masroufi (fr), مصروفي (ar). App ID `com.masroufi.app`.
- Currency: TND. Tunisia-first categories (Cafe, Taxi, Louage, STEG, SONEDE).
- Personality: calm, trustworthy, plain-spoken. Numbers exact, no fake precision.

## Voice

- Buttons verb-first, outcome-specific. Errors state what happened + how to fix.
- No humor in errors. No em-dashes in generated copy. No "Oops!".
- tr/fr/ar parity required for every user-visible string.

## Visuals

- Primary petrol `#155E75`, accent dark `#6FC7B9`. Full ramps in `AppColors`.
- Type: PlexSans bundled, Amiri for Arabic display where needed.
- Motion restrained (see DESIGN.md dials M3). No decorative animation on money flows.

## Assets

- Fonts: `assets/fonts/`. Launcher icon + splash: branded, not defaults.
- Store listings: `store/listing-{en,fr,ar}.md`. Privacy: `store/privacy-policy.md`.
- Ads use Google test IDs in debug; prod IDs via `--dart-define` only, never committed.
