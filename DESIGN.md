# Masroufi Design Contract

Standing decisions for all UI work. Read first, obey always, extend never
contradict. Updated in the same commit as any decision change.

## Design Read

Reading this as: personal finance tracker for Tunisian adults on Android
phones, Minimal Swiss / Financial Trust style, calm and confident voice,
Utility register, dials V5 / M4 / D5.

## Resolved answers

- Style: Minimal Swiss with Financial Trust typography. Original identity,
  not a Revolut / Wise / Apple Wallet clone, not navy-and-gold finance.
- Primary theme: light-first. Dark mode fully derived after.
- Accent: deep petrol `#155E75` (single accent app-wide).
- Animation personality: calm and quiet. Press feedback plus standard
  sheet and navigation motion only.
- Copy voice: calm, plain, supportive. Verb-first buttons. No em-dashes
  in strings we generate.
- The ONE action: record an expense in seconds through the central +.

## Dials

- `DESIGN_VARIANCE` 5 (redesign-overhaul baseline, one bespoke
  composition allowed on the Transactions hero; navigation conventions
  untouched).
- `MOTION_INTENSITY` 4 (in-place state motion 150-250ms, standard sheet
  and navigation durations; no page-load choreography; every animation
  justifiable in one sentence).
- `VISUAL_DENSITY` 5 (comfortable data density, tabular figures for
  amounts).

## Palette (light-first, all body pairs verified 4.5:1 or better)

Light: paper `#FAF8F4`, card `#FFFFFF`, ink `#1C1917` (16.5),
muted `#57534E` (7.2), primary `#155E75` (7.3 on white, white text 7.3),
expense `#C2410C` (5.2), income `#15803D` (5.0), transfer `#1D4ED8` (6.7),
destructive `#B91C1C` (6.5).

Dark (derived, verified): base `#16130F`, card `#1E1A15`, text `#ECE5D8`
(14.8), muted `#A8A094` (7.2), primary `#6FC7B9`, on-primary `#06231F`
(8.3), expense `#F2A37E`, income `#7BD598`, transfer `#9DBCFF`,
destructive `#F0978A`.

## Type

One family: IBM Plex Sans (variable TTF bundled, SIL OFL). Arabic script
uses system fallback today plus bundled Amiri for brand and PDF moments.
Amounts always use tabular figures through `MoneyText`. Body 16 at height
1.5, display 32/28/24 at 1.15, labels 13-14 weight 500. Never ship the
default text theme.

## Rules

- Everything flows from `ThemeData`. Zero inline colors, sizes, or radii
  in screen files. Tripwires apply on every widget edit.
- Spacing scale `AppSpacing` (4/8/12/16/24/32/48). One radius family
  (`AppRadius` soft: interactive 16, cards 16, sheets 24 top).
- Surface-container ladder for depth, never drop shadows. No glassmorphism
  by default, no gradients, no side-stripe accents, no nested cards.
- Exactly one filled high-contrast action per screen. The + owns creation.
- Arabic is first-class: `MoneyText` or `Money.inline` for every amount,
  `Directionality` islands, directional widgets, no detached minus signs.

## Skill combination

- UI/UX Pro Max: palette and style authority (finance rules, contrast
  discipline). Web-only outputs (GSAP, landing patterns, web chart
  libraries, Phosphor/Heroicons) are ignored for Flutter.
- beautify-flutter: implementation authority (theme-first, references on
  demand, `hooks/design-check.sh` after UI edits, golden matrix).
- UX Designer: gate authority (WCAG 2.2 AA checklists, forms, writing,
  data-viz, ethical review per phase).

## Decisions log

- 2026-09-09: contract created (global skills installed). Light-first,
  new petrol palette replacing seed green `#0E7C5B` in app chrome,
  3-slot navigation kept, IBM Plex Sans adopted, Pro Max landing-page
  generator output rejected for mobile (dark glass + Caveat unsuitable).
- 2026-09-09: STEP 1 theme foundation (tokens, tuned schemes, type
  scale, component themes). Wallet card color identities unchanged
  (persisted user styling, DB defaults untouched).
