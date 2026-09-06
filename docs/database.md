# Database

Drift + SQLite, MVP tables only.

## Tables

- `wallets(id TEXT pk, name, icon, initial_millimes INT, currency='TND',
  is_archived BOOL, created_at, updated_at)`
  Current balance is **derived**: initial + sum(income) - sum(expense) + net transfers.
- `categories(id TEXT pk, name_key, custom_name, icon, kind, is_archived,
  sort_order, created_at)` — defaults seeded by `name_key` (l10n lookup),
  user categories use `custom_name`. Archiving never deletes history.
- `transactions(id TEXT pk, type TEXT [expense|income|transfer], amount_millimes INT,
  wallet_id FK, to_wallet_id NULLABLE (transfer dest), category_id NULLABLE FK,
  occurred_at, note, created_at, updated_at)`
  Transfers: one logical transfer = single row with `wallet_id` (from) +
  `to_wallet_id`; counted in NEITHER income NOR expense aggregates.
- `budgets(id TEXT pk, year INT, month INT, amount_millimes INT, created_at, updated_at)`
  One overall monthly budget (MVP). Unique index on (year, month).
- `app_settings(key TEXT pk, value TEXT)` — language, theme, onboarding_done, name.

## Precision

All money columns are `INTEGER` millimes. No REAL columns for money.

## Indexes

`transactions(occurred_at)`, `(wallet_id)`, `(category_id)`, `(type)`.

## Migrations

Drift `schemaVersion = 1`. Future tables (debts, recurring, savings) arrive as
v2+ migrations; stable UUID ids + timestamps already in place.
