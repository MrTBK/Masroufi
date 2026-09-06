# MVP_COMPLETION_REPORT — Masroufi v1.0 (2026-09-06)

## Completed features
- Onboarding (language -> first wallet + balance -> optional name/theme)
- Wallets (create/rename/archive, derived balances, per-wallet history)
- 20 Tunisian default categories + custom create/rename/archive
- Expense / Income / Transfer (atomic single-row transfer, never counted as spend)
- History (search, type filter, wallet/category/date filters, edit/delete/duplicate,
  swipe-to-delete)
- Dashboard (total, month in/out/remaining, budget bar, recent, top categories,
  dominant Expense action)
- Overall monthly budget (spent/remaining/%, over-budget warning)
- Basic reports (monthly total, income-vs-expense, by-category bars)
- Versioned JSON backup + validated restore (destructive-confirm) + UTF-8 BOM CSV export
- ar/fr/en + RTL, light/dark/system, fully offline, original icon + splash

## Test results
- `flutter analyze`: No issues found.
- `flutter test`: 27/27 pass (money parse/format/precision, finance calc,
  backup codec incl. Arabic CSV, full MVP money flow on in-memory Drift DB,
  widget smoke incl. RTL).
- MVP money scenario verified in DB test: 100 -> -12.500 = 87.500 -> -8 =
  79.500 -> +500 = 579.500 -> transfer 100 (Cash 479.500, Bank 100.000,
  total conserved, transfer excluded from income/expense sums).

## Build results
- `flutter build apk --debug`: SUCCESS (rebuilt 2026-09-06 with all QA fixes)
- `flutter build appbundle --release`: SUCCESS (59.9 MB, signed with local
  release key `~/.masroufi/masroufi-release.jks`; verified via jarsigner,
  cert CN=Masroufi Local Release). Debug-signing fallback kept when
  `android/key.properties` is absent.

## Track A — on-device QA (emulator Pixel API 36, 2026-09-06)
- 5/5 integration tests pass on device: Arabic onboarding (Cash 100),
  expenses 12.500 + 8, income 500, transfer 100 conservation, budget 250,
  FR switch, dark-brightness assertion.
- On-device file I/O test passes: backup JSON + Arabic CSV round-trip.
- Physical `masroufi.sqlite` pulled: exact QA end-state
  (Cash 100000, Bank 0, expenses 20500, income 500000, transfer 100000,
  budget 250000, 20 categories, ar/dark/onboarded).
- Persistence: force-stop + cold start shows intact Arabic dark dashboard
  (total 579.500, remaining 479.500, budget 8%).
- Offline: no network permission in manifest; all flows exercised offline-capable.
- QA blockers found and fixed: MainActivity package mismatch (startup crash),
  zero-balance wallet creation blocked, FAB hero-tag collision on tab switch.
- Play assets prepared in `store/` (listings EN/FR/AR, privacy policy,
  release checklist). Nothing published; no Play Console account.

## Known minor issues / limitations
- On-device QA not performed (no Android device/emulator connected).
- Dropdown initial values rely on FormField initialValue sync (works, minor).
- cupertino_icons tree-shake notice during AAB build (harmless).
- No app lock, no PDF, no cloud sync (all post-MVP by design).

## Deferred (see ROADMAP.md)
Debts, recurring transactions, savings goals, salary mode, category budgets,
PDF export, reminders, app lock, cloud sync, AI, bank/e-Dinar integrations.

## V1.1 recommendation
On-device smoke test -> recurring transactions -> debts -> savings goals ->
category budgets -> PDF -> app lock.
