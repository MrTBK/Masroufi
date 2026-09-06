# Architecture

MVP v1.0 — actual implementation.

```
lib/
  main.dart            # bootstrap: provider scope, DB, settings, router
  app/app.dart         # MasroufiApp (Material 3, locale, theme mode)
  core/
    config/brand.dart  # single source: app name EN/AR/FR, IDs
    theme/             # light/dark/system, colors/type/spacing/radius
    routing/router.dart# go_router shell: dashboard/history/add/wallets/more
    l10n/strings.dart  # hand-rolled EN/FR/AR map (no codegen), RTL via Directionality
    money/money.dart   # int millimes arithmetic + TND formatting
    utils/             # ids (uuid), dates, result type
    widgets/           # empty/loading/error states, amount field
  features/
    onboarding/        # language -> wallet+balance -> optional name/theme
    dashboard/         # totals, month in/out/remaining, recent, top cats
    transactions/      # add/edit expense+income+transfer, history+filters
    wallets/           # CRUD + archive + per-wallet txns
    categories/        # defaults seed + create/rename/archive
    budgets/           # overall monthly budget
    reports/           # category breakdown, in-vs-out, monthly total
    settings/          # language, theme, backup/restore entry
    backup/            # versioned JSON backup/restore + CSV export
  data/
    database/app_db.dart # Drift tables: wallets/categories/transactions/budgets/settings
    repositories/      # wallet/category/transaction/budget/settings repos
```

Flow: UI (widgets) -> Riverpod providers -> repositories -> Drift/SQLite.
No business logic in widgets. No backend. Fully offline.

Future cloud: repositories expose stable UUID ids + createdAt/updatedAt so a
sync layer can be added later without schema rewrites.
