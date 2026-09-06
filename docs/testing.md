# Testing

- `test/money_test.dart` — millime parse/format, add/subtract, no-float proof
  (0.1+0.2 style cases), transfer conservation.
- `test/finance_logic_test.dart` — wallet balance derivation, month aggregates,
  budget spent/remaining/percent, transfer exclusion from income/expense.
- `test/backup_test.dart` — backup serialize/validate/restore round-trip,
  version rejection, corrupt-file rejection.
- Widget tests: onboarding flow, dashboard renders real totals, add-expense form
  validation, history filter.
- Manual MVP matrix (12 tests): fresh install, 100 TND wallet, 12.500 expense,
  8.000 expense, 500 income, 100 transfer Cash->Bank, 250 budget, restart
  persistence, offline, ar/fr/en switch, backup/restore, CSV export.

Run: `flutter test`. Android: `flutter build apk --debug`, `flutter build appbundle`.
