# MASROUFI — Done vs Next (2026-09-06)

## DONE (MVP v1.0, verified, committed)

- Environment: Flutter 3.47.2, Dart 3.13.2, JDK 17, Android SDK 36, NDK 28.2
- App: onboarding, wallets, 20 Tunisian categories, expense/income/atomic-transfer,
  history (search/filters/edit/delete/duplicate), dashboard, monthly budget,
  basic reports, versioned backup/restore, BOM CSV export
- i18n: ar/fr/en + RTL, light/dark/system, fully offline, original icon + splash
- Money: integer millimes everywhere; transfer never counted as spend
- Quality gates: `flutter analyze` clean, `flutter test` 27/27 pass,
  debug APK + release AAB (debug-signed) built
- Docs: README, docs/, PRIVACY.md, ROADMAP.md, MVP_COMPLETION_REPORT.md,
  MASROUFI_MASTER_TASKS.txt (+ skills audit section)
- Skills audit: no usable Flutter/Dart/Drift skill exists anywhere reachable;
  nothing installed; built-ins cover all needs

## NOT DONE / NEXT (needs your authorization)

1. On-device QA (needs phone/emulator): 12-test MVP matrix
2. Real release signing (needs your keystore — never commit keys)
3. V1.1 roadmap: recurring txns → debts → savings goals → category budgets →
   PDF export → reminders → app lock
4. V1.2+: cloud sync, receipt OCR, family budgets

## Next step

Tell me which of 1–4 to start, or say "V1.1" to begin with recurring transactions.
