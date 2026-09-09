# Product (MVP v1.0)

Tunisia-first offline personal finance. Answers: how much do I have, where did
it go, monthly spend, remaining, basic budget status.

## MVP scope

Onboarding (language, first wallet+balance, optional name/theme) -> Dashboard
(total, month in/out/remaining, recent, top categories, Expense/Income/Transfer
actions with Expense dominant) -> Wallets (create/edit/archive) -> Tunisian
default categories (Cafe, Taxi, Louage, STEG, SONEDE...) + custom -> Expense /
Income / Transfer (atomic, transfer not counted as spend) -> History (search,
wallet/category/date/type filters, edit/delete/duplicate) -> Monthly overall
budget -> Basic reports -> JSON backup/restore -> CSV export -> Settings
(language, theme, backup).

## Out of MVP (V1.1+)

Debts, recurring transactions, savings goals, salary mode, category budgets,
PDF, cloud sync, AI, bank/e-Dinar integrations (see README Roadmap).

## Upgrade decisions (Track 3)

- Savings ↔ wallets: documented as designed — savings goals are a
  separate ledger (default unlinked). Contributing/withdrawing never
  moves wallet money; wallet balances stay derived from the transaction
  ledger only. No auto-link; shown inline in the savings page.
- Exact alarms + boot receiver: stay OFF on demand. Notifications use
  inexact 20:00 digest scheduling only; a reboot clears alerts until the
  next launch (documented limitation). No `SCHEDULE_EXACT_ALARM` /
  `RECEIVE_BOOT_COMPLETED` unless reminders are explicitly enabled.
