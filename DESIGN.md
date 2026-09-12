# DESIGN.md — Masroufi standing design contract

Reading: finance trust-first utility app for Tunisian users, en/fr/ar (RTL), Android+iOS. Petrol identity, PlexSans voice, light-first + designed dark. Register: utility. Dials V3/M3/D5.

## Decisions

- Accent: petrol `0xFF155E75` light, `0xFF6FC7B9` dark. One accent app-wide.
- Semantics: expense `0xFFC2410C`, income `0xFF15803D`, transfer `0xFF1D4ED8`, destructive `0xFFB91C1C`. Dark companions desaturated in `AppColors`.
- Surfaces: container ladder, hairline borders, elevation 0. Dark base warm near-black `0xFF16130F`, never pure black.
- Type: PlexSans only, bundled. Body >=14, headings tuned heights (>=1.15). Max 2 weights per screen.
- Spacing: 4pt scale (`AppSpacing`), one radius family (`AppRadius` 8/16/24).
- Motion: press 140ms, state 220ms, sheet 320ms, nav 420ms. No page-load choreography.
- #1 action per screen owns thumb zone. Destructive never adjacent to frequent controls.
- Touch targets >=48dp. `SafeArea` always. 320dp floor, 130% text scale, 200% functional.
- Copy: verb-first buttons, no em-dashes, no "Oops!". tr key parity en/fr/ar.

## Rules

- Zero inline colors/sizes/radii in widget code. Theme or tokens only.
- Dark mode designed per token, never inverted. Toggle-test both directions.
- Cards only for real hierarchy. No nested cards. No side-stripe accents.
- Loading: skeleton matching layout over 300ms, inline button spinners. Empty/error states always with next action.
- RTL: `EdgeInsetsDirectional`, verified ar pass per changed screen.

## Log

- 2026-09-12: contract created from existing `AppColors`/theme (preserve-brand). Rebuild branch `rebuild/ui-ux`.
