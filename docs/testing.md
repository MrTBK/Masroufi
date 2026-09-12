# Testing

36 files, 275 tests. Run: `flutter test`.

- Money + calc: millime parse/format, no-float proof, transfer conservation.
- Repos + DB: balances, aggregates, budgets, backup round-trip, v1→v8
  migration, codec upgrades, finance v11 checks.
- Analytics + BI: periods, stats, insights, KPI, ForecastV2, seasonality,
  snapshot, scoped sums, exports, budget intel, movers, hierarchy.
- Safety: lock/PIN, auto-backup, duplicate guard, data health, notify.
- UX: redesign + refinement widgets, small-screen 360×640, 200% text
  scale, RTL, ads gate, nudge schedule, PRO codes, nav back buttons.
- Manual matrix: fresh install, 100 TND wallet, expenses + income +
  transfer, budget, restart persistence, offline, ar/fr/en switch,
  backup/restore, CSV + PDF export, PRO code activation.

Android: `flutter build apk --debug`, `flutter build appbundle --release`.
Release APK via `tool/release_apk.sh` (see `docs/release.md`).
