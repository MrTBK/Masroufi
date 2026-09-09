# Database

Drift + SQLite, MVP tables only.

## Tables

- `wallets(id TEXT pk, name, icon, initial_millimes INT, currency='TND',
  is_archived BOOL, created_at, updated_at)`
  Current balance is **derived**: initial + sum(income) - sum(expense) + net transfers.
- `categories(id TEXT pk, name_key, custom_name, icon, kind, priority,
  parent_id NULLABLE, is_archived, sort_order, created_at)` — defaults
  seeded by `name_key` (l10n lookup), user categories use `custom_name`.
  Archiving never deletes history. `parent_id` builds a single-level
  hierarchy (null = top-level parent, plain-text ref, no FK): 10 default
  parents (Food & Drinks, Transport, Bills, Shopping, Home,
  Health & Fitness, Lifestyle, Education, Family, Earnings) group the
  20 expense + 7 income defaults (`cat_other` stays a top-level catch-all);
  archiving a parent cascades to children; delete is blocked while
  children exist; `CategoryHierarchy.remapParents` (run from
  `seedDefaults`) moves stale system links after taxonomy upgrades while
  preserving user moves under custom parents; `sortOrder` backs manual
  reorder (`CategoriesRepo.move`).
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

Drift `schemaVersion = 7`:
- v2: recurring, category budgets, savings, debts tables +
  `transactions.recurring_rule_id`.
- v3: `wallets.is_balance_hidden` + `categories.kind` (expense|income).
- v4: `categories.priority` (important|normal|fun) + per-key backfill.
- v5: `categories.parent_id` (nullable hierarchy ref) + backfill linking
  known default children to their parents by `name_key`; customs stay
  top-level. Stable UUID ids + timestamps throughout.
- v6: `wallets.color_key` + `wallets.design` (display-only card styling
  keys, defaults teal/classic). Hiding stays mask-only: math never reads
  `is_balance_hidden`. Backup codec v6 accepts v1-v5 (styling defaults
  on restore).
- v7: `txn_templates` table (id, name, type, amount, wallet/toWallet/
  category refs as plain text, note, sortOrder). No backfill, no data
  touched; old backups restore with an empty template list. Backup
  codec v7 accepts v1-v6.
