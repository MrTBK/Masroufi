# Architecture

v1.3: actual implementation.

```
lib/
  main.dart            # bootstrap: provider scope, DB, settings, ads warm-up, router
  app/                 # MasroufiApp (Material 3, locale, theme mode) + providers
  core/
    config/brand.dart  # single source: names EN/AR/FR, IDs, ad units, sales contacts
    theme/             # light-first + derived dark, colors/type/spacing/radius
    routing/router.dart# go_router StatefulShell: home / dashboard / wallets / mizania + /settings/* hub
    l10n/strings.dart  # hand-rolled EN/FR/AR map (no codegen), RTL via Directionality
    money/             # int millimes arithmetic + TND formatting
    utils/             # ids (uuid), dates, haptics
    widgets/           # design primitives, states, tiles, bars, avatars
    ads/               # AdMob gate/service/banner, PRO service, donate nudge
    analytics/         # Periods, Stats, Insights, Kpi, ForecastV2, BiSnapshot engine
    security/          # PIN store, biometrics, hidden-balance gate (PRO-gated)
  features/
    onboarding/        # language -> wallet+balance -> optional name/theme
    transactions/      # Today-first home, history + filters, form + sheets
    dashboard/         # page + widgets/ parts, category detail
    wallets/           # CRUD + archive + per-wallet txns
    categories/        # defaults seed + create/rename/archive
    budgets/           # Mizania: monthly + per-category budgets
    reports/           # time documents: income-vs-expense, savings, net worth, year review, PDF
    recurring/ debts/ savings/ backup/ lock/ settings/  # managers + hubs
  data/
    database/app_db.dart # Drift tables (schema v8)
    repositories/      # one repo per aggregate + settings
```

Flow: UI (features) -> Riverpod providers -> repositories -> Drift/SQLite.
No business logic in widgets. No backend. Ledger fully offline; network
only for ads (automatic) and opt-in cloud AI.

Future cloud: repositories expose stable UUID ids + createdAt/updatedAt so a
sync layer can be added later without schema rewrites.
