# Masroufi Design System (Master)

Generated from UI/UX Pro Max finance rules (Personal Finance Tracker:
calm blue plus success green plus alert red plus chart accents, Financial
Dashboard pattern, transaction lists with swipe actions, budget progress
bars, donut and trend charts), adapted to mobile, light-first, Arabic
first-class. Full spec; page files (if added later) override only their
deviations.

## Color tokens

| Role | Light | Dark |
|---|---|---|
| primary | `#155E75` | `#6FC7B9` |
| onPrimary | `#FFFFFF` | `#06231F` |
| background | `#FAF8F4` | `#16130F` |
| surface / card | `#FFFFFFFF` / `#FFFFFF` | `#1E1A15` |
| ink (onBackground) | `#1C1917` | `#ECE5D8` |
| muted | `#57534E` | `#A8A094` |
| border (hairline) | `#E4DED3` | `#38322A` |
| expense | `#C2410C` | `#F2A37E` |
| income | `#15803D` | `#7BD598` |
| transfer | `#1D4ED8` | `#9DBCFF` |
| destructive | `#B91C1C` | `#F0978A` |

Verified body-text ratios (light): ink 16.5, muted 7.2, primary 7.3,
expense 5.2, income 5.0, transfer 6.7, destructive 6.5. Dark: text 14.8,
muted 7.2, on-primary 8.3, expense 9.1, income 10.4, transfer 9.8,
destructive 8.4. Finance semantics keep warm-expense, green-income, and
blue-transfer hues in both modes, recalibrated per mode, never color-only
(pair each with a glyph or label).

## Type tokens

Family `PlexSans` (IBM Plex Sans variable, bundled). Display 32/28/24
weight 700 height 1.15 letterSpacing -0.5. Title 20/18/16 weight 600
height 1.25. Body 16/14 weight 400/500 height 1.5. Label 13/12 weight 500
letterSpacing 0.3. Amounts: body-large weight 700 with tabular figures.
Arabic: system fallback plus Amiri for brand moments.

## Spacing, radius, motion

Spacing 4/8/12/16/24/32/48 (`AppSpacing`). Radius soft family 8/16/24
(`AppRadius`): interactive 16, cards 16, sheets 24 top. Motion: press
100-160ms, in-place state max 300ms, sheets and dialogs 250-400ms,
navigation max 500ms, exits at half speed. Entering uses emphasized
decelerate, exiting emphasized accelerate. Respect reduced motion.

## Component map

Buttons (filled high-contrast 52dp, tonal secondary, text tertiary),
inputs (outlined 16 radius, persistent labels, inline errors with fix
guidance), AppBar (flat surface, hairline on scroll), cards (16 radius,
ladder elevation, no nesting), sheets and dialogs (24 top radius,
drag handle), snackbars (action-first, undo within 10s), 3-slot nav with
dominant central plus, list rows (48dp targets, leading avatar, trailing
tabular amount), BudgetBar (80 percent approaching state, over state),
MoneyText (LTR island, sign attached), HiddenBalance mask, EmptyState
with next action, skeletons matching layout for content screens.

## Page order (per approved plan)

Theme foundation, then navigation restyle, Transactions, creation flow,
details, Wallets, Mizania, Dashboard, settings-hub split, RTL pass, dark
verification, accessibility and responsive pass, polish. Gate every step:
UX checklist, design-check greps, analyzer, tests, commit.
