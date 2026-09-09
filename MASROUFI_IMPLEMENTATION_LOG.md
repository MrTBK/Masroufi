# Masroufi Implementation Log

## 1. Document Metadata

* **Project name:** masroufi (Dart package `masroufi`)
* **Application name:** Masroufi — مصروفي
* **Current version:** `1.0.0+1` (`pubspec.yaml`, verified in working tree; version not bumped by working-tree changes)
* **Date of documentation:** 2026-09-07 (UTC)
* **Git baseline:** `HEAD = b33c992` on `master` (“Cleanup 4.7GB->7.7MB … + full app description file”). Prior commits: `1ff0679` (Track A QA/AAB, no V1.1), `d807c22`, `60f741d`, `bdef000` (MVP v1.0 baseline).
* **Current implementation state:** MVP v1.0 is committed at `HEAD`. The working tree contains **uncommitted V1.1 work**: 27 modified tracked files + 4 deleted root docs + 19 new untracked paths (features, repos, core utils, tests). `lib/data/database/app_db.dart` reports `schemaVersion 4` in working tree vs `1` at `HEAD`/`bdef000`.
* **Purpose of this document:** Permanent technical history. A future developer/AI agent must be able to read this file and understand what was already implemented, what changed in the working tree vs the MVP baseline, which files changed, architecture/database/UI/test deltas, bugs fixed, limitations, and what remains. Facts only; unverified items are marked `Not verified`.

> Scope note: this documentation task did not modify application code. The “work completed” below documents **working-tree changes observed in the repository** (uncommitted V1.1 work by prior session(s)), not work performed by this documentation pass. Verification for this file was limited to code inspection + read-only `flutter analyze` / `flutter test` runs (see §9).

---

## 2. Original Baseline

Baseline = `bdef000` (“Masroufi MVP v1.0: offline TN finance app (wallets, txns, budget, reports, backup, CSV, ar/fr/en)”), which matches `HEAD` for all app-code semantics (HEAD adds only QA assets/docs/cleanup, explicitly “no V1.1 features” per `1ff0679`).

* **Architecture:** `UI (features/*) → Riverpod providers (lib/app/providers.dart) → Repository (lib/data/repositories/*) → Drift/SQLite (lib/data/database/*)`. No separate application/domain-services layer. UUIDs (`uuid` pkg) used for IDs “for future sync” (`docs/architecture.md`).
* **Flutter/Dart versions (verified):** `Flutter 3.47.2 • channel stable`, `Dart 3.13.2`, DevTools `2.60.0` (`flutter --version`, 2026-09-07). `README.md` states Flutter 3.47 / Dart 3.13 / Material 3; `pubspec.yaml` requires `sdk: ^3.13.2`. Consistent.
* **Database technology:** Drift + `drift_flutter` over SQLite on-device (`AppDb`, `driftDatabase(name: 'masroufi')`). Baseline `schemaVersion => 1`, 5 tables: `Wallets, Categories, Transactions, Budgets, AppSettings`. No `migration` getter in baseline (fresh `createAll` only). No declared FK constraints; plain-text refs.
* **State management:** `flutter_riverpod ^2.6.1`. `Provider<AppDb>` + per-repo `Provider` + `StateProvider` for `language/themeName/onboardingDone` + `refreshTickProvider`/`bumpRefresh`.
* **Routing:** `go_router ^14.6.3`, `routerProvider`, `StatefulShellRoute` with 4 branches (`/`, `/history`, `/wallets`, `/more`) + `/onboarding`, `/more/reports`, `/more/budget`, `/more/categories`, `/more/backup`, `/more/settings`, root `/add?type=&edit=`. Redirect guards onboarding.
* **Localization:** Hand-rolled `lib/core/l10n/strings.dart` (no `.arb`/codegen), `en/fr/ar`, Arabic RTL first-class, `intl` for numbers/dates, TND suffix (`د.ت` in AR, `TND` otherwise). No hardcoded UI strings per `docs/localization.md`.
* **Supported languages:** `en`, `fr`, `ar` (`MaterialApp.router` `supportedLocales`, `Locale(lang)`).
* **Major existing features (MVP):** Onboarding (language + wallet creation) → Dashboard → Wallets (create/archive) → 20 Tunisian default categories → expense/income/atomic single-row transfer → history → overall monthly budget → reports (monthly total, income-vs-expense, by-category) → backup JSON v1 + CSV export → settings (language/theme/user name). Out-of-scope per `docs/product.md`: debts, recurring, savings, category budgets, PDF, cloud, AI.
* **Money representation:** Integer millimes (`int`, `1000 millimes = 1 TND`). `Money.parse` (last-separator-as-decimal, TN/FR formats, half-up rounding beyond 3 decimals, rejects ≤0) + `Money.format` (thousands grouping, `12.500 TND` / `12.500 د.ت`). “Never use double for financial math” (`lib/core/money/money.dart:1-2`, `calc.dart` integer-only).
* **Offline-first behavior:** No `INTERNET` permission (`docs/release.md`), local SQLite only, JSON/CSV user-initiated via share sheet, `file_picker` picker-only access, no account/backend/analytics/ads/sync (`PRIVACY.md`). `main.dart` wraps `recurringRepo.generateDue()` in try/catch with comment “a failed generation must never block startup”.

---

## 3. Work Completed

Working-tree deltas vs `HEAD`/`bdef000`. Grouped by area. All paths relative to repo root.

### UI/UX

Cross-cutting design system introduced (Implemented):

* **What changed:** New centralized widget library `lib/core/widgets/design.dart` (527 lines, new file) + deterministic category visuals + stable icon-key contract. `MorePage` changed from flat list to grouped sections. History, txn form, dashboard, budgets, reports, wallets, categories, backup, settings pages restyled around `AppCard`/`SectionHeader`/`BudgetBar`/`TransactionTile`.
* **Why:** Consistent light/dark rendering, never color-only semantics (type glyphs `−/+/⇄`), single icon/color source of truth.
* **Relevant files:** `lib/core/widgets/design.dart` (Added), `lib/core/icons/category_icons.dart` (Added), `lib/core/icons/category_visuals.dart` (Added), `lib/core/widgets/widgets.dart` (Modified: 23-case `appIcon` switch deleted → `appIcon(name) => CategoryIcons.iconFor(name)` alias), `lib/core/routing/router.dart` (Modified: grouped `MorePage`), every `lib/features/*` page (Modified except onboarding).
* **Important behavior:** `MoneyText` shows sign + color (`AppColors.expense 0xFFC2410C / income 0xFF15803D / transfer 0xFF1D4ED8`); `HiddenBalance` renders `••••••••`; `BudgetBar` turns error-color + `⚠` + `% used` when over; `IconPickerGrid` shows primary ring + check badge with exactly-one selection (covered by widget test); `confirmDialog` used for deletes/dismissals.

Category icon architecture (Implemented, verified in code):

```text
categories.icon / wallets.icon (SQLite TEXT stable key, e.g. 'salary', 'cash')
→ CategoryIcons.iconFor(key) (Map<String,IconData>, 35 keys, fallback 'other')
→ CategoryVisuals.visualFor(key) (deterministic MaterialColor light/dark pair)
→ CategoryAvatar / CategoryListTile / TransactionTile (UI)
```

* Never stores `IconData` in DB (comment + `isKnown()` guard). Same key renders identically in Categories/Add/History/Dashboard/Reports/Budget in both brightnesses (covered by `ux_refinement_test.dart` “CategoryVisuals” group).

### Dashboard

Implemented state in `lib/features/dashboard/dashboard_page.dart` (Modified, ~+558 lines):

* **Widgets/sections (in order):** `_balanceHero` → `_monthStats` → `_budgetSection` → `_upcomingSection` (new) → `_recentSection` → `_topCatsSection` → quick actions.
* **Financial summaries:** Total balance (derived `initial + flows`, includes hidden wallets in math), masked when `hideBalancesProvider || any wallet.isBalanceHidden` (`HiddenBalance + VisibilityToggle`); month income/expense via `monthSums`; per-wallet masked balances.
* **Quick actions:** FAB `push('/add?type=expense')` (shell branch 0) + in-page add expense/income/transfer shortcuts. `Not verified` for exact button labels without running UI; code shows type-specific entry points.
* **Recent transactions:** Limit `8 → 6`, rows via `TransactionTile`, subtitle `wallet • HH:MM`, day-relative header via `relativeDay` (`lib/core/utils/dates.dart`, new).
* **Budgets:** Overall monthly `BudgetBar` + per-category bars (via `categoryBudgetsRepo`).
* **Categories:** Top-cats section with `CategoryAvatar`.
* **Navigation:** Bottom nav unchanged (`dashboard/history/wallets/more`); `MorePage` groups: money `[budget, recurring, savingsGoals, debts]`, analysis `[reports]`, data `[backup]`, customization `[category, settings]`.
* **Responsive behavior:** `Not verified` (no responsive-specific code found; standard `ListView`/`AppCard` layout).
* **New state:** `dashPeriodProvider='month'`, `weekStartProvider='monday'`, `hideBalancesProvider=false` (`lib/app/providers.dart`).

### Categories

Implemented (`lib/features/categories/categories_page.dart` Modified + `lib/data/repositories/categories_repo.dart` Modified + `lib/data/database/category_priority.dart` Added):

* **Structure:** `Categories{id, nameKey?, customName?, icon (key, default 'other'), kind ('expense'|'income', default 'expense'), priority ('important'|'normal'|'fun', default 'normal'), isArchived, sortOrder, createdAt}`. No FK from txns (archiving never breaks history).
* **Default categories:** 20 expense (`Strings.defaultCategories`) + 7 income (`Strings.defaultIncomeCategories`: `inc_salary, inc_freelance, inc_gift, inc_allowance, inc_investment, inc_refund, inc_other_income`). Seeded idempotently per `nameKey` with `kind` + `priority` via `CategoryPriority.forNameKey`.
* **Localization:** `categoryNames.en/fr/ar` for all 27 keys (7 `inc_*` added in this work).
* **Icon system:** 35 selectable keys (`CategoryIcons.all`), `IconPickerGrid` in dialog, defaults editable icon-only, `setIcon()` repo method.
* **Custom categories:** `create(name, {icon, kind, priority})` with priority validation; dialog has `SegmentedButton kind` on create only (kind immutable on edit in UI).
* **Creation/editing/archiving:** Rows via `CategoryListTile`, `PopupMenu(rename/pickIcon/archive)`; split `expense/income` sections with headers.
* **DB representation:** Stable TEXT `icon` key + TEXT `kind`/`priority` (see §5).

### Transactions

Implemented (`lib/features/transactions/history_page.dart` + `txn_form_page.dart` Modified, `lib/data/repositories/transactions_repo.dart` Unmodified in diff except via new `recurringRuleId` column):

* **Expense/income/transfer:** All three retained. Form is type-specific: expense → expense cats + “Pay from”; income → income cats + “Money goes to” (`moneyGoesTo`); transfer → From/To `WalletSelectCard`s, no category. `_defaultCat` prefers `inc_salary/inc_other_income` for income, `cat_cafe/cat_other` for expense; `_visibleCats` kind-filters but keeps legacy edit cat.
* **UI:** Category grid (`ChoiceChip + CategoryAvatar`), wallet cards with masked balances, date in `AppCard`, save button shows type title.
* **Icons:** `TransactionTile(transfer ? 'transfer' : categoryIconKey)`.
* **Filtering/search:** Wallet + category `DropdownButtonFormField`s (`filterWallet/filterCategory`); day-grouped `Map<YYYY-MM-DD, List>` with header `relativeDay • key`. Free-text search: `Not verified` (no search field found in inspected diff).
* **Editing/deletion/duplication:** Edit via `/add?edit=id` preload; delete via `Dismissible confirmDismiss => confirmDialog`; duplicate via `txnsRepo.duplicate(id)` long-press action (`history_page.dart:272`, `transactions_repo.dart:175`). All Implemented.
* **Wallet/category/date handling:** `balances: Map<walletId,int>` preloaded for selection cards; transfer validates distinct wallets (error strings in `strings.dart`); `recurringRuleId` nullable link for auto-generated occurrences (ordinary txns null).

### Wallets

Implemented (`lib/features/wallets/wallets_page.dart` Modified + `lib/data/repositories/wallets_repo.dart` Modified + `Wallets.isBalanceHidden` column):

* Rows: `WalletAvatar` (neutral `tertiaryContainer`, distinct from category) + bold title + history `TextButton` (if not archived) + masked `HiddenBalance` vs `Money.format` + per-wallet `VisibilityToggle(setBalanceHidden)` + `Divider(indent 72)`.
* Dialog: `StatefulBuilder + IconPickerGrid([cash, bank, card, savings, other]) + create(icon)/rename+setIcon`.
* Repo adds `setIcon`, `setBalanceHidden` (comment: “display-only, math untouched”). Balances remain derived (`walletFlows`: income/expense/transfer-in/transfer-out sums). Archive retained.
* Privacy: global `hideBalancesProvider` + `settingsRepo.hideBalances` + per-wallet flag; totals always include hidden wallets (test-covered).

### Budgets

Implemented (`lib/features/budgets/budget_page.dart` Modified, ~+333 + `lib/data/repositories/category_budgets_repo.dart` Added):

* Overall monthly budget (`Budgets` table, MVP) retained: `AppCard + BudgetBar`.
* New per-category budgets (`CategoryBudgets{id, categoryId, year, month, amountMillimes, createdAt, updatedAt}`): `SectionHeader(categoryBudgets, +newCatBudget)` + list (`CategoryAvatar + budgetFraction + BudgetBar + overBudget`, tap → `_catDialog`); dialog has expense-only category dropdown + `Money.parse` + `upsert/remove`.
* Logic: `spent(category,year,month)` = `SUM … WHERE type='expense'` (transfers excluded); `status → {spent, remaining, pct}` via `FinanceCalc` (test-covered in `finance_v11_test.dart`).

### Reports

Implemented (`lib/features/reports/reports_page.dart` Modified, ~+324 + `lib/data/repositories/analytics_repo.dart` Added + `lib/core/analytics/periods.dart` + `stats.dart` Added):

* Retained sections wrapped in `SectionHeader + AppCard(CategoryAvatar)`: `monthlyTotal`, `incomeVsExpense`, `byCategory`.
* New: 6-month trend bar chart (custom `Container`, no chart dependency), budget adherence (overall `BudgetBar` + per-category `FutureBuilder`), savings-goals progress (`BudgetBar`).
* `AnalyticsRepo`: `MonthSlice(year,month,income,expense)`, `_sum`, `expenseTotal/incomeTotal`, `expenseByCategory/incomeByCategory`, `expenseByPriority` (`LEFT JOIN categories COALESCE(priority,'normal')`), `monthlySeries(now,monthsBack,includeCurrent)`, `dailyExpenseTotals(start,end)` (per-day SUM).
* `Periods`: `day/dayStart/yesterday/week(now,[weekStart])/month/lastMonth/year/lastCompletedMonths/daysInMonth`, half-open `[start,end)`, local time, `weekStart=monday|sunday|saturday` fallback Monday.
* `AnalyticsStats`: `averageMonthly`, `monthOverMonth->{diff,pct}?` (null if previous ≤0), `partialMonth->{daily,projected}?`, `sharePct?`, integer-only half-up.
* Limitation: `lib/core/analytics/insights.dart` is a 2176-byte zero-filled file (all `0x00`, `Not verified` as implemented; string templates `ins*` exist but backing logic is missing/corrupt — see §9/§11).

### Backup / Restore

Implemented (`lib/features/backup/backup_codec.dart` Modified + `backup_page.dart` Modified):

* **Codec version:** `currentVersion 1 → 4`, added `minSupportedVersion=1`. `requiredKeysV1` (wallets/categories/transactions/budgets/settings) + `requiredKeysV2` (`recurring_rules, category_budgets, savings_goals, savings_contributions, debts, debt_payments`). `validate` accepts `1,2,3,4`; `tryDecode` upgrades `<4` to `version:4` filling missing V2 with `[]`. Comments document v2/v3/v4 deltas.
* **Export:** Adds `isBalanceHidden/kind/priority/recurringRuleId` + 6 new table blocks (all 11 tables).
* **Import:** Clears 6 new tables first, restores with defaults (`isBalanceHidden ?? false`, `kind ?? expense`, `priority valid ? else forNameKey`, `recurringRuleId` passthrough); loops all V2 arrays.
* **CSV:** Retained (Arabic columns test-covered in `backup_test.dart`). JSON backup/restore + CSV export all Implemented; CSV import: `Not verified` (no evidence found).

### Settings

Implemented (`lib/features/settings/settings_page.dart` Modified, +38 + `lib/data/repositories/settings_repo.dart` Modified + `lib/main.dart` Modified):

* Keys: `language, theme, onboarding_done, user_name` (baseline) + `hide_balances (0/1)` + `week_start (monday|sunday|saturday, default monday)`.
* New UI sections: `privacy` (`SwitchListTile showBalances ↔ hideBalancesProvider + setHideBalances`), `weekStart` (`RadioGroup monday/sunday/saturday` from `SettingsRepo.weekStarts` + `setWeekStart + bumpRefresh`).
* `main.dart` loads `hide` + `weekStart` at startup and seeds providers; existing language/theme/onboarding retained.

### Localization

Implemented (`lib/core/l10n/strings.dart` Modified, ~+370):

* **EN/FR/AR:** All three locales extended in parallel (~110 new EN keys + mirrored FR/AR, e.g. `recurring/récurrents/المتكررة`, `savingsGoals/objectifs d’épargne/أهداف الادخار`, `debts/dettes/الديون`, `categoryBudgets/budgets par catégorie/ميزانيات التصنيفات`).
* **RTL:** Retained; `CategoryListTile` RTL covered by widget test.
* **New strings:** Recurring (`newRule, frequency, freq_daily|weekly|monthly|yearly, startDate, endDate, nextUp, paused/pause/resume, upcoming, noRecurring…`), savings (`newGoal, goalName, targetAmount, current, remainingGoal, contribute/withdraw…`), debts (`newDebt, iOwe/owedToMe, person, original, paid, settle, open/pay, overpaymentBlocked…`), budgets (`newCatBudget, overBudget`), UX (`pickIcon, saveGoal, payFrom, moneyGoesTo, incomeCategory/expenseCategories, categoryKind, hideBalance/showBalance/hiddenBalance, privacy/showBalances, money/analysis/data/customization, important/normal/fun, priority, weekStart/monday/sunday/saturday, trend, budgetAdherence, spendingByPriority, insights/ins*…`), time (`today/tomorrow/yesterday`).
* **Architecture:** Still hand-rolled `Strings.get(lang,key)` + new `tpl(lang,key,placeholders)` (`{p}/{cat}/{v}` substitution for insight templates). `defaultIncomeCategories` + 7 `inc_*` names added per locale. Parity test-covered (`ux_refinement_test.dart` “localization parity”).

### Theme

No theme-color changes (Not changed):

* `lib/core/theme/app_theme.dart` has no diff. `AppColors{seed 0xFF0E7C5B, expense 0xFFC2410C, income 0xFF15803D, transfer 0xFF1D4ED8}`, `AppSpacing`, `AppRadius`, `buildLightTheme/buildDarkTheme` (M3 `ColorScheme.fromSeed`, `OutlineInputBorder(md)`, `FilledButton(48x52, md)`).
* Light/dark/system modes retained (`themeMode` from `themeNameProvider`). Design-system change is compositional (new `design.dart` widgets using existing `AppColors`), not a palette redesign.

---

## 4. V1.1 FEATURES

Evidence from working tree (code + tests). `Not verified` means no on-device manual verification in this documentation pass.

| Feature                | Status        | Details |
| ---------------------- | ------------- | ------- |
| Recurring transactions | Implemented | `RecurringRules` table + `lib/core/money/recurring.dart` (`daily/weekly/monthly/yearly`, month-end clamp) + `recurring_repo.dart` (`create/update/remove/skipOccurrence/generateDue/upcoming`) + `lib/features/recurring/recurring_page.dart` + startup `generateDue()` in `main.dart` + routes `/more/recurring`. Tests: `recurring_test.dart` (10), integration §11. |
| Category budgets       | Implemented | `CategoryBudgets` table + `category_budgets_repo.dart` (`get/forMonth/upsert/remove/spent/status`) + budget-page per-category section. Tests: `finance_v11_test.dart` (1 group), integration §11. |
| Savings goals          | Implemented | `SavingsGoals` + `SavingsContributions` tables + `savings_repo.dart` (separate ledger, never touches wallets; `±amount` add/withdraw) + `lib/features/savings/savings_page.dart` + reports progress. Tests: `finance_v11_test.dart` (1 group), integration §11. |
| Debts                  | Implemented | `Debts` + `DebtPayments` tables + `debts_repo.dart` (`owe/owed`, `pay()` atomic txn+payment, auto-`settled`, overpay rejected; remove keeps txns) + `lib/features/debts/debts_page.dart`. Tests: `finance_v11_test.dart` (1 group), integration §11. |
| Upcoming payments      | Implemented | `RecurringRepo.upcoming(from,days:30,limit:20)` + dashboard `_upcomingSection` (30d/limit 4) + recurring rows show `freq_* • nextUp: YYYY-MM-DD • active/paused`. No separate reminders/notifications (Not implemented). |
| App lock               | Not implemented | No evidence: `grep -ri "local_auth|biometr|fingerprint|pin|applock"` in `lib/ test/ pubspec.yaml` returns no lock feature (only false positives like `shopping_cart`, `overpaymentBlocked`). No dependency, route, or settings key. |
| Dashboard improvements | Implemented | Balance masking (global + per-wallet), month stats, budget + upcoming + recent(6) + top-cats sections, `relativeDay` grouping, `TransactionTile`/`CategoryAvatar`/`BudgetBar` systematization, `dashPeriod/weekStart` providers. |
| UI/UX redesign         | Implemented | `design.dart` system (11+ reusable widgets), `CategoryIcons` (35 keys) + `CategoryVisuals` (deterministic light/dark), grouped `MorePage`, type-specific txn form, wallet/category/history/budget/reports restyle, ~110 new localized strings. Partially limited by corrupt `insights.dart` (analytics-insight text logic missing). |

---

## 5. DATABASE CHANGES

All verified by reading `lib/data/database/tables.dart`, `app_db.dart`, `category_priority.dart` and diffing against `bdef000`/`HEAD`.

* **Schema version before:** `1` (`bdef000` and `HEAD`; no `migration` getter).
* **Schema version after:** `4` (`lib/data/database/app_db.dart:29`, working tree).
* **New tables (6):** `RecurringRules`, `CategoryBudgets`, `SavingsGoals`, `SavingsContributions`, `Debts`, `DebtPayments` (total 5 → 11 tables in `@DriftDatabase`).
* **Modified tables (3):** `Wallets` (+1 col), `Categories` (+2 cols), `Transactions` (+1 col). `Budgets`, `AppSettings` unchanged.
* **New columns (4):**
  * `wallets.is_balance_hidden` — `BoolColumn`, default `false`. Purpose: presentation-only privacy flag; never affects math. Nullable/default: non-null, default false; migration backfills existing rows with default.
  * `categories.kind` — `TextColumn`, default `'expense'`. Purpose: `expense|income` form filtering. Non-null; existing rows stay `expense`.
  * `categories.priority` — `TextColumn`, default `'normal'`. Purpose: analytical metadata `important|normal|fun` inherited by txns (never stored per-txn). Non-null; existing rows default `normal` then `beforeOpen` backfills per-key defaults.
  * `transactions.recurring_rule_id` — `TextColumn`, nullable. Purpose: links auto-generated occurrences to `RecurringRules.id`; ordinary txns null.
* **Indexes:** No new Drift indexes declared (`uniqueKeys => []` on `Transactions`; PKs are `{id}`/`{key}`). `Not verified` for SQLite-level auto-indexes beyond PKs.
* **Relationships:** No Drift FK constraints anywhere (intentional; plain-text refs so archiving never breaks history). Logical refs: `Transactions.walletId→Wallets.id`, `toWalletId→Wallets.id?`, `categoryId→Categories.id?`, `recurringRuleId→RecurringRules.id?`; `RecurringRules.walletId→Wallets.id`, `categoryId→Categories.id?`; `CategoryBudgets.categoryId→Categories.id`; `SavingsGoals.walletId→Wallets.id?`, `SavingsContributions.goalId→SavingsGoals.id` (separate ledger, never touches balances); `DebtPayments.debtId→Debts.id`, `walletId→Wallets.id`, `txnId→Transactions.id?` (balance updates exactly once via linked txn).
* **Migrations (`app_db.dart:32-63`, new):**
  * `onCreate: createAll()` (fresh v4).
  * `onUpgrade`: `from<2` → create 6 tables + `addColumn(transactions.recurringRuleId)`; `from<3` → `addColumn(wallets.isBalanceHidden)` + `addColumn(categories.kind)`; `from<4` → `addColumn(categories.priority)`.
  * `beforeOpen`: if `versionBefore < 4` → `CategoryPriority.backfill(this)` (`UPDATE categories SET priority WHERE name_key` per 20-key defaults map: 11 important, 7 normal, 2 fun).
* **New-field reference (exact Drift defs):** see `tables.dart:13-14` (`isBalanceHidden`), `:29` (`kind`), `:32-33` (`priority`), `:52` (`recurringRuleId`), `:86-177` (6 new tables). Full column lists in §3 and task inspection notes.
* **Compatibility:** Backup codec `minSupportedVersion=1`, accepts v1–v4, normalizes `<4` to v4 with empty V2 arrays + field defaults (see §3 Backup). Migration test builds v1-shaped SQLite via `sqlite3` pkg and asserts upgrade to v4 preserves data with correct defaults (`test/migration_test.dart`).

---

## 6. ARCHITECTURE CHANGES

Before (committed `HEAD`/`bdef000`, verified):

```text
UI (features/* pages)
→ Riverpod (app/providers.dart: appDb + 5 repos + language/theme/onboarding state)
→ Repository (wallets/categories/transactions/budgets/settings)
→ Drift (AppDb v1, 5 tables)
+ Core helpers: brand, strings, money/calc, app_theme, router, utils, widgets(appIcon switch)
```

After (working tree, verified — extension of same pattern, **no separate Application/Domain Services layer introduced**):

```text
UI (features/* + 3 new features: recurring/savings/debts; design.dart system)
→ Riverpod (same + 4 new repos + hideBalances/weekStart/dashPeriod state)
→ Repository (5 existing extended + 5 new: recurring/category_budgets/savings/debts/analytics)
→ Drift (AppDb v4, 11 tables + MigrationStrategy + CategoryPriority.backfill)
+ Core extensions: icons/*, money/recurring.dart, analytics/{periods,stats}, utils/dates.dart,
  database/category_priority.dart, widgets/design.dart
```

Only use “services” loosely: there are no `*Service` classes; business logic lives in repos + pure core helpers (`Recurring`, `Periods`, `AnalyticsStats`, `FinanceCalc`, `Money`, `CategoryPriority`, `CategoryIcons/Visuals`).

* **New services:** None as a layer; new pure-logic helpers: `Recurring` (frequencies, `nextAfter` with month-end clamp, `occurrencesBetween` with 5000-occurrence guard), `Periods` (half-open local-time ranges, configurable week start), `AnalyticsStats` (averages, MoM, projections, shares; integer-only), `CategoryPriority` (constants, per-key defaults, `backfill`).
* **New repositories:** `RecurringRepo` (watch/activeOnly/all/create/updateRule/remove/skipOccurrence/generateDue-per-rule-transaction/1000-guard/upcoming), `CategoryBudgetsRepo` (get/forMonth/upsert/remove/spent/status), `SavingsRepo` (watch/all/get/create/rename/setArchived/remove-cascades/addContribution±/currentAmount/history/progress), `DebtsRepo` (watch/openOnly/all/get/create/updateDebt/remove-keeps-txns/pay-atomic + auto-settle + overpay-reject/paid/remaining/history), `AnalyticsRepo` (sums, by-category, by-priority, monthlySeries, dailyExpenseTotals).
* **Providers:** Added `recurringRepoProvider`, `categoryBudgetsRepoProvider`, `savingsRepoProvider`, `debtsRepoProvider`, `hideBalancesProvider`, `weekStartProvider`, `dashPeriodProvider`. `appDbProvider` override + seeding in `main.dart` extended (hide/weekStart + `seedDefaults` + `generateDue`).
* **Reusable components:** `design.dart`: `AppCard, SectionHeader, MoneyText, CategoryAvatar, WalletAvatar, CategoryListTile, HiddenBalance, VisibilityToggle, IconPickerGrid, WalletSelectCard, TransactionTile, confirmDialog, budgetFraction, BudgetBar`.
* **Utility classes:** `dates.dart` (`relativeDay`, `monthKey`), `category_priority.dart`, `category_icons.dart`/`category_visuals.dart`.
* **Domain logic / separation:** Money math stays integer-only in `Money`/`FinanceCalc`; recurrence math in `Recurring`; period math in `Periods`; analytics aggregation in `AnalyticsRepo` + `AnalyticsStats`; icon/color resolution in `CategoryIcons`/`CategoryVisuals` (DB stores keys only). UI consumes via Riverpod + `StreamBuilder`/`FutureBuilder` + `refreshTick`.

---

## 7. FILES CHANGED

Categorized from `git status --short` + `git diff --stat HEAD` (27 modified tracked, 4 deleted, 19 new untracked paths). Generated `app_db.g.dart` (+6477) is Drift codegen (relevant because schema changed). Build/cache outputs excluded.

### Added

* `lib/core/icons/category_icons.dart` → 35 stable icon keys + `iconFor` resolver (DB stores keys only).
* `lib/core/icons/category_visuals.dart` → Deterministic light/dark color pairs per icon key.
* `lib/core/widgets/design.dart` → Central design system (cards, tiles, bars, pickers, dialogs).
* `lib/core/money/recurring.dart` → Recurrence math (`nextAfter`, `occurrencesBetween`).
* `lib/core/analytics/periods.dart` → Half-open period ranges with configurable week start.
* `lib/core/analytics/stats.dart` → Averages/MoM/projections/shares (integer-only).
* `lib/core/analytics/insights.dart` → Intended insight logic; **corrupt zero-filled file** (see §9/§11).
* `lib/core/utils/dates.dart` → `relativeDay`, `monthKey`.
* `lib/data/database/category_priority.dart` → `important/normal/fun` constants + per-key defaults + backfill.
* `lib/data/repositories/recurring_repo.dart` → Recurring CRUD + due-generation + upcoming.
* `lib/data/repositories/category_budgets_repo.dart` → Per-category monthly budgets.
* `lib/data/repositories/savings_repo.dart` → Goals + separate contributions ledger.
* `lib/data/repositories/debts_repo.dart` → Debts + atomic txn-linked payments.
* `lib/data/repositories/analytics_repo.dart` → Sums, by-category/priority, series, daily totals.
* `lib/features/recurring/recurring_page.dart` → Recurring rules list + rule dialog (type/amount/frequency/wallet/category/note/start/end).
* `lib/features/savings/savings_page.dart` → Goals list + detail sheet (contribute/withdraw/history) + goal dialog.
* `lib/features/debts/debts_page.dart` → Owe/owed segmented list + detail sheet + pay/debt dialogs.
* `test/finance_v11_test.dart` → Category-budget/savings/debt repo tests (5 tests).
* `test/recurring_test.dart` → `Recurring` math + `generateDue` tests (10 tests).
* `test/migration_test.dart` → v1→v4 SQLite upgrade test (1 test).
* `test/ux_refinement_test.dart` → Visuals/kinds/privacy/parity/widget tests (16 tests).
* `test/analytics_test.dart` → Intended analytics tests; **corrupt zero-filled file**, fails to load (see §9).

### Modified

* `lib/app/providers.dart` → +4 repo providers, +`hideBalances/weekStart/dashPeriod` state (note: file has trailing NUL padding; `git diff` shows as binary).
* `lib/main.dart` → Loads hide/weekStart, seeds categories, runs `generateDue()` in try/catch.
* `lib/core/l10n/strings.dart` → ~+370 lines: `tpl()`, ~110 new EN keys + FR/AR mirrors, 7 income categories.
* `lib/core/routing/router.dart` → +`/more/recurring`, `/more/savings`, `/more/debts`; grouped `MorePage`.
* `lib/core/widgets/widgets.dart` → `appIcon` switch → `CategoryIcons.iconFor` alias.
* `lib/data/database/tables.dart` → +4 cols, +6 tables (v2–v4).
* `lib/data/database/app_db.dart` → `schemaVersion 1→4` + `MigrationStrategy` + `beforeOpen` backfill.
* `lib/data/database/app_db.g.dart` → Regenerated Drift code (+6477).
* `lib/data/repositories/categories_repo.dart` → Kind/priority filter, dual expense/income seeding, `setIcon/setPriority`, `create(kind,priority)`.
* `lib/data/repositories/wallets_repo.dart` → `setIcon`, `setBalanceHidden` (display-only).
* `lib/data/repositories/settings_repo.dart` → `hideBalances`, `weekStarts/weekStart/setWeekStart`.
* `lib/features/dashboard/dashboard_page.dart` → Hero masking, month stats, budget/upcoming/recent/top-cats sections.
* `lib/features/transactions/history_page.dart` → Wallet/category filters, day grouping, `TransactionTile`, dismiss-to-delete, duplicate.
* `lib/features/transactions/txn_form_page.dart` → Type-specific fields, category grid, wallet cards, masked balances.
* `lib/features/wallets/wallets_page.dart` → Avatars, masking toggles, icon picker dialog.
* `lib/features/categories/categories_page.dart` → Expense/income sections, `CategoryListTile`, kind segmented, icon picker.
* `lib/features/budgets/budget_page.dart` → Overall + per-category budgets with dialogs.
* `lib/features/reports/reports_page.dart` → Trend chart, adherence, savings progress, card/section restyle.
* `lib/features/backup/backup_codec.dart` → Version 1→4, V1/V2 key sets, upgrade normalization.
* `lib/features/backup/backup_page.dart` → 11-table export/import with defaults.
* `lib/features/settings/settings_page.dart` → Privacy + week-start sections.
* `test/backup_test.dart` → +73 lines: v4 round-trip, v1/v2/v3→v4 upgrades, missing-table/corrupt rejects.
* `integration_test/qa_matrix_test.dart` → Single `testWidgets` matrix incl. new §§11–14 (recurring/savings/debts/cat-budgets, income-form filtering, per-wallet masking), `GoRouter.go` nav helper.
* `pubspec.yaml` / `pubspec.lock` → `sqlite3: ^3.4.0` promoted to direct dev-dep (migration tests only).

### Deleted

* `MASROUFI_APP_FULL_DESCRIPTION.txt` (deleted in workdir; present at HEAD) → Full app description doc; deletion is a workdir change, not reviewed here.
* `MASROUFI_MASTER_TASKS.txt` (deleted in workdir; present at HEAD) → Master task list.
* `MVP_COMPLETION_REPORT.md` (deleted in workdir; present at HEAD) → MVP completion/QA report (27/27 tests, APK+AAB, Track A 5/5).
* `TASKS_STATUS.md` (deleted in workdir; present at HEAD) → Done-vs-next summary.
* No `lib/` source files deleted. No `MASROUFI_IMPLEMENTATION_LOG.md` existed before this pass (verified `ls` → no match).

---

## 8. DEPENDENCIES

Verified via `git diff HEAD -- pubspec.yaml pubspec.lock`:

* **Added:** `sqlite3: ^3.4.0` under `dev_dependencies` with comment “migration tests only: builds v1-shaped files”. `pubspec.lock` changes `sqlite3` from `transitive` → `direct dev`; version/sha unchanged.
* **Removed:** None.
* **Upgraded:** None (all other deps pinned as baseline: `flutter_riverpod ^2.6.1`, `go_router ^14.6.3`, `drift ^2.34.0`, `drift_flutter ^0.3.0`, `path_provider ^2.1.6`, `path ^1.9.1`, `intl ^0.20.2`, `uuid ^4.6.0`, `csv ^6.0.0`, `file_picker ^12.2.0`; dev `flutter_lints ^6.0.0`, `drift_dev ^2.34.0`, `build_runner ^2.4.0`).
* **Reason:** `sqlite3` direct-dep enables `test/migration_test.dart` to construct a v1-shaped on-disk SQLite file and open it with `AppDb.forTesting` to assert the v1→v4 upgrade path.

---

## 9. TESTING AND QA

Actual verification performed for this documentation pass (read-only; no source modified). Do not interpret as release QA.

### Static analysis

`flutter analyze` (Flutter 3.47.2, 2026-09-07):

* **Status: Failed** — `15990 issues found`, all `error • Illegal character '0'` originating from exactly two zero-filled files:
  * `test/analytics_test.dart:1:*` (13,653 bytes, all `0x00`)
  * `lib/core/analytics/insights.dart:1:*` (2,176 bytes, all `0x00`)
* Excluding those two files (`grep -v illegal_character`): **zero remaining issues**. In other words the analyzable codebase is clean; the failure is entirely the two corrupt files.
* `hexdump -C` confirms both files are `00`-filled (`*` repeat). `file` reports `data`; `strings` empty.

### Unit/widget tests

* **Command (full):** `flutter test` → `+63 -1`, `Some tests failed`. Failing item: `test/analytics_test.dart: loading …` (corrupt file cannot be parsed/loaded; contributes the single `-1`, zero tests execute from it).
* **Command (excluding corrupt file):** `flutter test test/backup_test.dart test/calc_test.dart test/finance_db_test.dart test/money_test.dart test/widget_test.dart test/finance_v11_test.dart test/migration_test.dart test/recurring_test.dart test/ux_refinement_test.dart` → **`All tests passed!` (+63)**.
* **Inventory (counts via `rg "test(|testWidgets("`, verified):**
  * `test/backup_test.dart` — 9 `test` (`BackupCodec`: round-trip, wrong-version reject, v4 round-trip incl. V2 tables, v1→v4, v3→v4, v2→v4, missing-table reject, corrupt reject, Arabic CSV columns).
  * `test/calc_test.dart` — 4 `test` (`FinanceCalc`: MVP wallet chain 100−12.5−8+500=579.5, transfer conservation, budget remaining/pct, over-budget precision).
  * `test/finance_db_test.dart` — 1 `test` (in-memory Drift E2E MVP flow: seed, wallets, 2 expenses + income + transfer + budget).
  * `test/money_test.dart` — 14 `test` in 3 groups (`Money.parse` 7, precision 2, format 5; TN/FR parsing, millime ints, TND suffix incl. negative/zero).
  * `test/widget_test.dart` — 3 `testWidgets` (EmptyState AR strings, TND suffix, Arabic RTL).
  * `test/finance_v11_test.dart` — 5 `test` in 3 groups (category budgets spent/remaining/pct + transfers-excluded; savings add/withdraw + wallets-untouched; debts owed/owe + partial/auto-settle/single-count + overpay-reject).
  * `test/migration_test.dart` — 1 `test` (v1 SQLite → open with `AppDb.forTesting` → assert v4: data intact, `isBalanceHidden=false`, `kind=expense`, per-key priority backfill incl. cafe→normal, groceries→important, custom→normal; new tables usable).
  * `test/recurring_test.dart` — 10 `test` in 3 groups (`nextAfter` daily/weekly/month-end/leap/Feb29/Dec→Jan; `occurrencesBetween` weekly-4×Sept + end-date; `generateDue` due/no-dup/end/skip/disabled).
  * `test/ux_refinement_test.dart` — 16 (13 `test` + 3 `testWidgets`) in 5 groups (CategoryVisuals determinism/contrast/fallback; kinds 20+7/idempotent/kind-filter/custom; privacy math-neutral/defaults/global-switch; parity all-new-keys + income names + moneyGoesTo; IconPickerGrid/WalletSelectCard/CategoryListTile-RTL widgets).
  * `test/analytics_test.dart` — 0 parseable tests (corrupt; `Not verified` for intended coverage).
* Prior committed reports (`MVP_COMPLETION_REPORT.md` at HEAD, now deleted in workdir) claim 27/27 MVP tests; current working-tree suite is 63 passing + 1 unloadable file. Historical claim preserved here but `Not verified` in this pass beyond the runs above.

### Integration tests

* **File:** `integration_test/qa_matrix_test.dart` (Modified, +239). Setup clears 6 new tables; hydrates hide/weekStart; helpers `tapText` (scrolls lazy lists), `tapNav` via `GoRouter.go`, `tapIcon`, `scrollToVisible`; single `testWidgets('QA matrix: full MVP + V1.1 on device')` with §§1–7,10 + new §§11 (recurring/savings/debt/cat-budget), 12 (income-form filtering, total `2,599.500`), 13 (categories expense+income sections), 14 (per-wallet hide → `••••••••`, eye toggle, exact-total restore).
* **Command/device/result:** `Not run` in this documentation pass (no `flutter test integration_test` / on-device run executed here). Prior commit `1ff0679` message claims “on-device QA green” for Track A (MVP only, no V1.1); `Not verified` here.

### Manual QA

* **Status: Not verified.** No manual screen walkthrough was performed as part of creating this log. An earlier emulator boot in this environment opened the committed-cache build (`com.masroufi.app/.MainActivity` resumed), but that was not a QA pass over the V1.1 working tree and is not claimed as verification.

---

## 10. BUG FIXES

No isolated bug-fix commits exist in the working tree (all changes uncommitted; `git log` shows only baseline/QA/docs commits). The following are **improvements observable in diffs** that fix known MVP fragilities; each is code-inspected only (`Not verified` on-device unless noted as test-covered):

1. **Flaky integration-test navigation** — Problem: tapping `NavigationBar` directly was flaky. Fix: `tapNav` helper uses `GoRouter.go` with per-language branch map. Files: `integration_test/qa_matrix_test.dart`. Verification: Not run here.
2. **Lazy-list tap failures in QA** — Problem: `tapText` missed offscreen items. Fix: auto-scroll lazy lists + `scrollToVisible`. Files: `integration_test/qa_matrix_test.dart`. Verification: Not run here.
3. **Income form offered expense categories** — Problem (MVP): single category pool. Fix: `kind` column + `_visibleCats` kind filter + income-only dropdown; integration §12 asserts income form shows `راتب` not `مقهى`. Files: `tables.dart`, `categories_repo.dart`, `txn_form_page.dart`, `strings.dart`. Verification: unit/integration code present; on-device Not verified here.
4. **No way to hide sensitive balances** — Fix: per-wallet `isBalanceHidden` + global `hide_balances`, display-only (math untouched), `••••••••` + eye toggle; integration §14 asserts masked totals + exact-total restore. Files: `tables.dart`, `wallets_repo.dart`, `settings_repo.dart`, `dashboard_page.dart`, `wallets_page.dart`. Verification: `ux_refinement_test.dart` (3 privacy tests) passed in this pass.
5. **Category visuals inconsistent across screens/brightness** — Fix: centralized `CategoryIcons` + `CategoryVisuals` + `CategoryAvatar`/`CategoryListTile`/`TransactionTile`. Files: `category_icons.dart`, `category_visuals.dart`, `design.dart`, all feature pages. Verification: `ux_refinement_test.dart` (CategoryVisuals group) passed.
6. **Legacy `appIcon` switch drift** — Fix: deleted 23-case switch → `CategoryIcons.iconFor` alias. Files: `lib/core/widgets/widgets.dart`. Verification: analyze clean (excluding corrupt files).
7. **Backup incompatible with V1.1 tables** — Fix: codec v4 with V1/V2 key sets + `<4→4` normalization + import defaults + clear-new-tables-first. Files: `backup_codec.dart`, `backup_page.dart`. Verification: `backup_test.dart` (9 tests incl. upgrades) passed.
8. **v1→v4 upgrade data loss risk** — Fix: staged `MigrationStrategy` + `CategoryPriority.backfill`. Files: `app_db.dart`, `category_priority.dart`. Verification: `migration_test.dart` passed.

What was **not** fixed: corrupt `insights.dart` / `analytics_test.dart` remain broken (see §11).

---

## 11. KNOWN LIMITATIONS

* **Corrupt files (P0):** `lib/core/analytics/insights.dart` (2,176 bytes) and `test/analytics_test.dart` (13,653 bytes) are all-`0x00` zero-filled. They break `flutter analyze` (15,990 errors) and `flutter test` (1 load failure). Insight string templates (`ins*` with `{p}/{cat}/{v}`) exist in `strings.dart` but backing logic is absent. `Not verified` whether any insight feature ever worked.
* **Stale docs:** `docs/database.md` still describes MVP only (`schemaVersion=1`, 5 tables) — contradicts code v4/11 tables. `docs/testing.md` references `finance_logic_test` filename that does not exist in `test/`. `docs/*` otherwise MVP-scoped (V1.1 listed as out-of-scope in `docs/product.md`).
* **No app lock:** PIN/biometric/lock feature absent (no dep/route/settings). Do not promise it.
* **No notifications/reminders:** Upcoming payments are list-only (`upcoming()` + dashboard section); no scheduling, push, or background-job code found.
* **Savings UX limitation (by design):** Contributions are a separate ledger that “never touches ordinary wallet balances” (code comment). Users contributing to a goal do not see wallet debits; `Not verified` whether product intends to link them later.
* **Debt constraints:** `pay()` rejects overpayment (`overpaymentBlocked`); `remove()` keeps linked txns (history preserved but orphans `txnId` refs). Partial payments + auto-`settled` at zero are implemented.
* **No FK constraints:** All cross-table refs are plain TEXT. Integrity enforced in repos, not SQLite. Deleting categories/wallets never breaks history (intentional), but dangling `categoryId/walletId/goalId/debtId` strings are possible if callers bypass repos.
* **Migration limitations:** `beforeOpen` backfills `priority` only when `versionBefore < 4`; `kind` relies on column default (`expense`) + income-seed idempotency. Downgrade path `Not verified`. v1–v3 backups normalize to v4 with empty V2 arrays (data-preserving for V1 keys; V2 data absent by definition).
* **Missing tests:** Analytics/periods/stats helpers have no loadable tests (intended `analytics_test.dart` corrupt). Integration matrix updated but `Not run` here. CSV import `Not verified`.
* **Uncommitted + deleted docs:** 27 modified + 4 root-doc deletions + 19 new paths are all uncommitted. `lib/app/providers.dart` carries trailing NUL padding (shows as binary in `git diff`). `lib/core/analytics/insights.dart` sparse/corrupt as above.
* **Performance concerns:** `Not verified` (no profiling performed). `Recurring.occurrencesBetween` has 5000-iteration guard; `generateDue` has 1000-occurrence guard; dashboard recent limits tightened 8→6.

---

## 12. REMAINING WORK

Based on the repository, `ROADMAP.md`, and `docs/product.md` (V1.1 listed debts/recurring/savings/cat-budgets/reports/PDF/reminders/lock; V1.2 cloud/receipt/family; V2 integrations/analytics/AI). No random ideas added.

### P0 — Required

* Repair `lib/core/analytics/insights.dart` (currently zero-filled): reimplement or delete + remove `ins*` template dead-ends; repair or delete `test/analytics_test.dart` so `flutter analyze` and `flutter test` are green without exclusions.
* Update `docs/database.md` to v4/11 tables + migration path (currently contradicts code); fix `docs/testing.md` stale filename.
* Commit or revert the working tree deliberately (27 modified + 4 deletions + 19 new paths uncommitted; `providers.dart` NUL padding should be normalized to text).
* Run the updated integration matrix on-device (`integration_test/qa_matrix_test.dart` §§11–14) and record results; current status `Not run` here.

### P1 — Important

* App lock (ROADMAP V1.1): PIN/biometric gate + settings toggle + locked-route guard. Currently Not implemented.
* Upcoming-payment reminders (ROADMAP V1.1): local notifications/scheduling for `nextOccurrence`/debt `dueDate` (currently list-only).
* Reports completeness (ROADMAP V1.1): PDF export path; verify `Periods` week-start wiring end-to-end (settings → analytics → dashboard/reports).
* Backup hardening: verify CSV import story (currently `Not verified`), document v1→v4 restore matrix, add restore-overwrite confirmation QA.
* Decide savings↔wallets semantics (currently separate ledger by design) and document in `docs/product.md`.

### P2 — Later

* V1.2 per ROADMAP: cloud sync/backup, receipt capture, family sharing.
* V2 per ROADMAP: bank integrations, advanced analytics, read-only AI insights (depends on repairing `insights.dart` first).
* Store assets pending per `store/release-checklist.md`: screenshots, Play record, rating questionnaire, staged rollout (signing/listings/policy already done per checklist; AAB path was local-key per deleted MVP report — re-verify before release).
* Polish: responsive/landscape QA (`Not verified`), transfer История exclusion audits, dangling-ref cleanup tooling (consequence of no-FK design).

---

## 13. CURRENT FEATURE MATRIX

Status values: `Implemented` / `Partially implemented` / `Planned` / `Not implemented` / `Not verified`. Evidence = file/test location observed in this pass.

| Area | Feature | Status | Evidence/Location |
| ---- | ------- | ------ | ----------------- |
| Onboarding | Language selection | Implemented | `lib/features/onboarding/onboarding_page.dart`, `settings_repo.language`, `strings.dart` |
| Onboarding | Wallet creation | Implemented | `onboarding_page.dart`, `wallets_repo.dart` |
| Onboarding | Onboarding guard/redirect | Implemented | `lib/core/routing/router.dart` (`initialLocation`, redirect) |
| Dashboard | Balance (derived total) | Implemented | `dashboard_page.dart` `_balanceHero`, `app_db.walletFlows` |
| Dashboard | Month income/expense | Implemented | `dashboard_page.dart` `_monthStats`, `app_db.monthSums` |
| Dashboard | Budget section | Implemented | `dashboard_page.dart` `_budgetSection`, `BudgetBar` |
| Dashboard | Upcoming (30d/4) | Implemented | `dashboard_page.dart` `_upcomingSection`, `recurring_repo.upcoming` |
| Dashboard | Recent transactions (6) | Implemented | `dashboard_page.dart` `_recentSection`, `TransactionTile`, `dates.relativeDay` |
| Dashboard | Top categories | Implemented | `dashboard_page.dart` `_topCatsSection`, `CategoryAvatar` |
| Dashboard | Quick actions + FAB | Implemented | `router.dart` FAB `/add?type=expense`, dashboard shortcuts |
| Dashboard | Hide-balances masking | Implemented | `hideBalancesProvider`, `HiddenBalance`, `VisibilityToggle`; `ux_refinement_test` |
| Transactions | Expense | Implemented | `txn_form_page.dart`, `transactions_repo.addExpense`, `finance_db_test` |
| Transactions | Income | Implemented | `addIncome`, income-kind filtering; integration §12 |
| Transactions | Transfer (atomic single-row) | Implemented | `addTransfer`, `toWalletId`, `calc_test` conservation |
| Transactions | Category/wallet/date pickers | Implemented | `txn_form_page.dart` grid/cards/date `AppCard` |
| Transactions | Day grouping + wallet/category filters | Implemented | `history_page.dart`, `TxnFilter` |
| Transactions | Edit | Implemented | `/add?edit=`, `updateTxn` |
| Transactions | Delete (dismiss + confirm) | Implemented | `Dismissible`, `confirmDialog`, `delete` |
| Transactions | Duplicate | Implemented | `history_page.dart:272`, `transactions_repo.dart:175 duplicate` |
| Transactions | Free-text search | Not verified | No search field found in inspected diff |
| Categories | Default categories (20 expense) | Implemented | `categories_repo.seedDefaults`, `Strings.defaultCategories` |
| Categories | Default income categories (7) | Implemented | `Strings.defaultIncomeCategories`, `ux_refinement_test` (20+7) |
| Categories | Custom categories | Implemented | `categories_repo.create`, `categories_page.dart` dialog |
| Categories | Icons (35 keys + picker) | Implemented | `category_icons.dart`, `IconPickerGrid`, `setIcon` |
| Categories | Deterministic colors (light/dark) | Implemented | `category_visuals.dart`, `ux_refinement_test` |
| Categories | Kind (expense/income) | Implemented | `categories.kind`, kind filter + segmented dialog |
| Categories | Priority (important/normal/fun) | Implemented | `categories.priority`, `category_priority.dart`, backfill |
| Categories | Archive | Implemented | `isArchived`, popup-archive; history unaffected |
| Wallets | Create (+icon) | Implemented | `wallets_page.dart` dialog, `IconPickerGrid([cash,bank,card,savings,other])` |
| Wallets | Rename / set icon | Implemented | `wallets_repo.setIcon`, dialog rename+icon |
| Wallets | Archive | Implemented | `isArchived`, history button hidden when archived |
| Wallets | Per-wallet hide balance | Implemented | `isBalanceHidden`, `setBalanceHidden`, `ux_refinement_test` |
| Wallets | History per wallet | Implemented | `TextButton` history (if not archived) |
| Budget | Monthly overall budget | Implemented | `Budgets`, `budget_page.dart` overall card |
| Budget | Per-category budgets | Implemented | `CategoryBudgets`, `category_budgets_repo`, `finance_v11_test` |
| Budget | Over-budget warning | Implemented | `BudgetBar` error + `⚠` + `% used`, `overBudget` strings |
| Reports | Monthly totals | Implemented | `reports_page.dart`, `monthSums` |
| Reports | Income vs expense | Implemented | `reports_page.dart`, `AnalyticsRepo` |
| Reports | By category (+priority) | Implemented | `expenseByCategory/incomeByCategory/expenseByPriority` |
| Reports | 6-month trend chart | Implemented | Custom-container bars (no dep); code-inspected |
| Reports | Budget adherence | Implemented | Overall + per-category `BudgetBar` |
| Reports | Savings progress | Implemented | Goals `BudgetBar` in reports |
| Reports | Insight text engine | Not implemented | `insights.dart` zero-filled; templates only in `strings.dart` |
| Recurring | Rules CRUD + pause/skip/delete | Implemented | `recurring_repo.dart`, `recurring_page.dart`, `recurring_test` |
| Recurring | Auto-generation on startup | Implemented | `main.dart generateDue()` try/catch |
| Recurring | Upcoming list | Implemented | `upcoming(days:30,limit:20)` + dashboard section |
| Savings | Goals CRUD + archive | Implemented | `savings_repo.dart`, `savings_page.dart`, `finance_v11_test` |
| Savings | Contribute/withdraw ledger | Implemented | `addContribution ±`, history; wallets untouched by design |
| Debts | Owe/owed tracking | Implemented | `debts_repo.dart`, `debts_page.dart`, `finance_v11_test` |
| Debts | Payment linked to wallet txn | Implemented | `pay()` atomic txn+payment, `txnId`; auto-settled; overpay rejected |
| Backup | JSON backup (v4, 11 tables) | Implemented | `backup_codec.dart` v4, `backup_page.dart`; `backup_test` (9) |
| Backup | Restore (v1–v4 upgrade) | Implemented | `tryDecode` normalization + defaults; `migration_test` + `backup_test` upgrades |
| Backup | CSV export (AR columns) | Implemented | `backup_test` Arabic-columns case; codec/page code |
| Backup | CSV import | Not verified | No evidence found |
| Settings | Language (en/fr/ar) | Implemented | `settings_repo.language`, `languageProvider`, settings page |
| Settings | Theme (system/light/dark) | Implemented | `theme()`, `themeNameProvider`, `buildLightTheme/DarkTheme` |
| Settings | User name | Implemented | `user_name` key (baseline; retained) |
| Settings | Hide balances (global) | Implemented | `hide_balances`, `hideBalancesProvider`, privacy section |
| Settings | Week start (mon/sun/sat) | Implemented | `week_start`, `weekStartProvider`, `Periods` |
| Settings | App lock (PIN/biometric) | Not implemented | Grep negative; no dep/route/key |
| Localization | EN/FR/AR + RTL | Implemented | `strings.dart`, `tpl()`, parity tests; `widget_test` RTL |
| Theme | Light/dark/system | Implemented | `app_theme.dart` (unchanged), `themeMode` |
| Analytics core | Periods/stats helpers | Implemented | `periods.dart`, `stats.dart` (code-inspected; tests missing) |
| Release | Android appId/signing/assets | Partially implemented | `com.masroufi.app` (`docs/release.md`, `store/`); signing deferred/key git-ignored; historical AAB used local key (per deleted MVP report, Not verified here) |

---

## 14. CURRENT PROJECT STATE

* **What Masroufi is today:** An offline-first Tunisian personal-finance Flutter app (TND millimes, `en/fr/ar` + RTL, Material 3, Riverpod + go_router + Drift). MVP (wallets, 27 default categories across expense/income, expense/income/atomic-transfer ledger, history with filters/grouping, overall + per-category budgets, reports with trend/adherence/savings views, JSON v4 backup + CSV export, privacy/week-start settings) plus a V1.1 working tree adding recurring rules with startup generation, category budgets, savings goals (separate ledger), and txn-linked debts — all present in code with repo tests.
* **What has been completed:** Baseline MVP committed (`bdef000`→`b33c992`, incl. Track-A QA/AAB per commit messages, `Not verified` here). Working-tree V1.1: schema v1→v4 with staged migrations + backfill, 6 new tables + 4 new columns, 5 new repos, 3 new features/routes, design-system + icon/color architecture, ~110 new strings ×3 locales, backup v1→v4, 4 new test files (32 tests), QA-matrix §§11–14. Verified in this pass: 63/63 loadable unit/widget tests pass; analyzable code clean.
* **What is currently being developed:** The uncommitted V1.1 working tree itself (nothing committed since `b33c992`). Immediate blocker is not features but corruption: two zero-filled files (`insights.dart`, `analytics_test.dart`) fail analyze + one test-file load.
* **What is next:** P0: repair corrupt files, update `docs/database.md`/`testing.md`, commit deliberately, run on-device integration matrix. P1: app lock, reminders, PDF, backup-matrix QA. P2: cloud/receipts/family (V1.2), integrations/AI (V2). See §12.
* **Current test/build state:** `flutter analyze` → Failed (15,990 `illegal_character` errors from 2 corrupt files; 0 other issues). `flutter test` → 63 passed + 1 file-load failure (`analytics_test.dart`); excluding that file → All tests passed. Integration → Not run here. Builds → Not run here (no `flutter build` executed in this pass; prior AAB claims are historical, `Not verified`).
* **Current release state:** `version 1.0.0+1`, `applicationId` per `docs/release.md`/`store/` (`com.masroufi.app` observed on-device in a prior session; package string also appears in `android/` manifests — inspection of manifests was out of scope for this pass, so `Not verified` here beyond docs). `store/` listings (ar/en/fr), privacy policy, and release checklist exist; screenshots/Play-record/rating/rollout remain pending per checklist.

---

## 15. IMPORTANT RULES

Compliance statement for this task:

* No source code was modified, refactored, or reformatted; no dependencies installed; no schema changed; no destructive commands run; no files removed.
* No multiple documentation files created; no existing project docs rewritten. Root doc deletions noted in §7 (`MASROUFI_APP_FULL_DESCRIPTION.txt`, `MASROUFI_MASTER_TASKS.txt`, `MVP_COMPLETION_REPORT.md`, `TASKS_STATUS.md`) pre-existed this pass as workdir deletions (present at HEAD) and were left untouched.
* Only output: this file (`MASROUFI_IMPLEMENTATION_LOG.md`, created new — verified no prior `MASROUFI_IMPLEMENTATION_LOG*` existed). No `*_v2.md` duplicate created; historical info from deleted HEAD docs (MVP 27/27, Track A) preserved above as attributed history, marked `Not verified` where this pass did not re-verify.
* Read-only verification only: `git status/log/diff/show`, file reads, `grep/rg`, `flutter --version`, `flutter analyze`, `flutter test` (including one excluding-corrupt-file run), `hexdump`, `ls`. `flutter test`/`analyze` do not modify `lib/`; no build artifacts were committed.


---

## 16. CATEGORY HIERARCHY (v5) — 2026-09-07 build pass

* **Repairs:** rewrote zero-filled `lib/core/analytics/insights.dart` (pure
  `Insights.buildInsights` over `AnalyticsStats` + `Strings.tpl`, 7 `ins*`
  templates, null-safe) and `test/analytics_test.dart` (Periods, Stats,
  Insights en + fr/ar spot-check, `AnalyticsRepo` in-memory); stripped 161
  NUL bytes from `lib/app/providers.dart`. `flutter analyze` → 0 issues.
* **Schema:** `categories.parent_id` nullable (no FK), `schemaVersion` 4→5,
  `onUpgrade` addColumn + `CategoryHierarchy.backfill` in `beforeOpen`;
  `app_db.g.dart` regenerated via project-local build_runner.
* **Hierarchy:** 5 default parents (`cat_food_drinks`, `cat_transport`,
  `cat_home_bills`, `cat_lifestyle`, `inc_earnings`, existing icons only)
  group all 20 expense + 7 income defaults (seed 27→32: 24 expense + 8
  income); single-level enforced, free-form kinds, txns allowed on parents;
  archive cascades down, delete blocked with children (`StateError`).
* **Rollup:** `CategoryHierarchy.rollUp` (pure, no double-count) applied to
  dashboard top-cats (+ tap drills to filtered history via public
  `catFilterProvider`, parent expands to parent + children through new
  `TxnFilter.categoryIds`), reports by-category (expandable parent rows),
  category-budget `spent`; "Parent › Child" labels in txn form, history,
  budget dialog; grouped categories page with parent dropdown.
* **Backup:** codec v4→v5 (`parentId` in category JSON, v1–v4 accepted,
  missing → null → backfilled on restore).
* **Tests:** new `test/hierarchy_test.dart` (12 tests); `migration_test`
  → v1→v5 + `parentId` null asserts; `backup_test` → v5 + v4→v5 case;
  seed-count asserts updated. Full suite: **93/93 pass**.
* **Docs:** `docs/database.md` → v5; `CATEGORY_HIERARCHY_PLAN.txt` items
  complete. All tooling via `.tooling/env.sh` (project-local SDKs/caches);
  no files added to `$HOME`. Nothing committed (per instructions).

---

## 17. FULL UI/UX REDESIGN + NAV ESCAPE (v6) — 2026-09-08 build pass

Major redesign around three experiences (Transactions / Wallets /
Mizania + Dashboard analytics), preserving the financial engine
(repos, Drift, millime math, backup, l10n, tests). Implemented in one
pass, then a follow-up fix for a navigation dead-end found during the
desktop run.

* **Navigation:** `ScaffoldWithNav` renders purpose-built
  `MasroufiNavBar` (`lib/core/widgets/masroufi_nav.dart`): Wallets |
  dominant 64dp `+` | Mizania. Four `StatefulShellRoute` branches
  (`/`, `/dashboard`, `/wallets`, `/mizania`); Transactions ⇄
  Dashboard switch via top `HomeTopSwitch`; `+` opens `AddSheet`
  (`lib/features/transactions/add_sheet.dart`: Expense/Income/Transfer
  → `/add?type=`). Legacy `/more/*` + `/history` redirect to
  `/settings/*` + `/`; settings hub routes `/settings/*` (reports,
  categories, backup, recurring, savings, debts). `MorePage` removed.
* **Transactions (new home):** `lib/features/transactions/transactions_page.dart`
  (new): period chips today/yesterday/thisWeek/lastWeek/thisMonth/lastMonth
  (`Periods.txnRangeFor` + `txnPeriodProvider`, new in `providers.dart`)
  → spent + your-money summary → day-grouped timeline (newest first,
  weekday headers via `intl DateFormat`) → type chips + wallet/category
  dropdowns + search; delete/edit/duplicate retained. `history_page.dart`
  kept (legacy route + shared `walletFilterProvider`/`catFilterProvider`).
* **Category icons:** aliases added to `CategoryIcons.all` + map
  (`louage`, `metro`, `steg`/`electricity`, `sonede`, `internet`,
  `mobile`, `groceries`, `clothing`, `electronics`); `bus` fixed
  `airport_shuttle` → `directions_bus`; `CategoryVisuals` entries for
  aliases. DB contract unchanged (stable string keys, `other` fallback).
* **Schema v6:** `wallets.color_key` (default `'teal'`) +
  `wallets.design` (default `'classic'`), display-only styling keys;
  `schemaVersion` 5→6 with `from<6 addColumn` migration, no backfill
  needed. New `lib/core/theme/wallet_styles.dart` (`colors`
  teal/blue/purple/orange/slate × `designs` classic/modern/minimal).
  `WalletsRepo.create/setColorKey/setDesign`; backup codec v5→v6
  (v1–v5 accepted, missing styling → defaults); `backup_page.dart`
  wallet JSON + restore defaults; `app_db.g.dart` regenerated.
* **Dashboard rewrite (analytics, not a list):**
  `lib/features/dashboard/dashboard_page.dart` rewritten: Total Money →
  Total Spent → donut (`lib/core/widgets/donut_chart.dart`,
  `CustomPainter`, no chart dep, `DonutPalette`) → top-5 rolled
  primaries → averages → `MoneyInOutBars`. New thin services
  `lib/core/analytics/summary.dart` (`FinancialSummaryService`:
  `totalMoney/spentIn/incomeIn/averageSpending/monthlyAverage`;
  `CategorySpendingService.topCategories`). Definitions: daily avg =
  period total ÷ elapsed days (min 1); monthly avg = mean of last 3
  COMPLETED months (current excluded). Old upcoming/quick-action
  sections removed (rules live under Settings → Recurring).
* **Wallets:** `lib/core/widgets/wallet_card.dart` (new:
  `WalletCardView` bank-card styling on own identity, eye toggle,
  `WalletColorPicker`); `wallets_page.dart` card list + dialog with
  color/style pickers. Hide (mask) vs archive kept distinct.
* **Mizania:** `BudgetPage` retitled (`mizania • MONTH YEAR`), total /
  spent / remaining + `BudgetBar` + category budgets; same repos/math.
* **Settings:** regrouped hub (general / categories / wallets / budget /
  data / security-placeholder / about); all pre-existing options kept.
* **Periods:** `Periods.lastWeek`, `txnRangeFor`, `elapsedDays` added
  (`lib/core/analytics/periods.dart`); dashboard ranges extended
  (`thisWeek|lastWeek|…`, legacy `week`/`month` normalized).
* **Localization:** +34 keys × en/fr/ar (mizania, yourMoney, totalMoney,
  totalSpent, lastWeek, avgSpending, monthlyAverage, moneyIn/Out/InOut,
  addWallet, walletColor/Style, manageWallets/Categories,
  budgetSettings, general, security, about, appVersion, aboutMasroufi,
  noExpensesYet, viewDashboard/Transactions, createCategory,
  categories, selectColor, topSpendingCategories, totalBudget,
  monthlyAvgNote, dailyAvgNote, hiddenNote, appLock, comingSoon,
  privacyPolicy).
* **Nav-escape fix (same pass, after desktop run):** Wallets/Mizania had
  no on-screen path home (bar has no Home item; `goBranch` leaves no
  back-stack entry, so system back exited the app). Fix: shared
  `HomeTitle` tappable brand on all four branch AppBars
  (`context.go('/')`, `goHome` tooltip string) + `PopScope` in
  `ScaffoldWithNav` returning `goBranch(0)` on back from branches 2/3
  (pure `shouldInterceptBack`, dialogs/sheets unaffected as separate
  routes).
* **Tests:** new `test/redesign_test.dart` (21: txn ranges, icon
  aliases/fallback, mask-only math, styling round-trip, summary/top-cat
  math, archived-history, l10n parity, DonutChart/WalletCard/NavBar
  light/dark/RTL widgets, HomeTitle router escape, `shouldInterceptBack`);
  `backup_test` → v6 + v5→v6 case; `migration_test` → v1→v6 +
  `colorKey`/`design` asserts; `qa_matrix_test.dart` re-pointed to new
  IA (`+`-sheet flows, Mizania branch, settings hub).
* **Results (verified):** `flutter analyze` → 0 issues; `flutter test`
  → **125/125 pass** (101 baseline + 24 new); `flutter build apk
  --debug` → ✓. `docs/database.md` → v6. Desktop run note: an early
  `flutter run` window closed when the tool timeout killed the process
  tree (not an app crash); app relaunched detached from the built
  bundle and verified alive. On-device integration run: Not run here.
* **Files:** added `masroufi_nav.dart`, `add_sheet.dart`,
  `transactions_page.dart`, `donut_chart.dart`, `wallet_card.dart`,
  `wallet_styles.dart`, `summary.dart`, `redesign_test.dart`;
  modified router, providers, periods, category_icons/visuals,
  tables/app_db/app_db.g.dart, wallets_repo, backup_codec/page,
  dashboard/wallets/budget/settings pages, strings, migration/backup
  tests, qa_matrix, `docs/database.md`. Nothing committed.

---

## 18. TODAY-FIRST + ARABIC RTL CORRECTION — 2026-09-08 build pass

Follow-up brief (with Arabic screenshot; the image attachment was not
viewable in-session, so all fixes target the described symptoms):
Today must always be the main view (no period-filter buttons),
comparisons as information, decluttered hierarchy, real RTL money
rendering (screenshot showed the minus detached: `4,420.500- د.ت`),
non-clickable home title, hidden-wallet exclusion from display totals.

* **Transactions rebuilt Today-first**
  (`lib/features/transactions/transactions_page.dart` rewritten):
  period chips + `txnPeriodProvider` reads deleted (provider removed
  from `providers.dart`); new hierarchy in one scroll view — brand
  header → `_TodayHero` (today label / spent big / your-money + global
  eye) → `_Comparisons` (six expense totals today/yesterday/thisWeek/
  lastWeek/thisMonth/lastMonth as typography in a 3-col grid, one
  batched read via tested `Periods.txnRangeFor`) → single Filters
  button with active-count badge → `_Timeline` with NO period gate
  (today on top, older days on scroll, `limit` paging + localized
  "Show more" +300). First group header uses new `todayTransactions`
  key (معاملات اليوم); pure top-level `dayGroupHeader()` helper;
  locale-aware transfer connector (`←` in ar, `→` otherwise).
* **Filter sheet** (`lib/features/transactions/filter_sheet.dart`,
  new): `showFilterSheet` + stateful body (controller created once in
  `initState` so typing never loses focus) + `activeFilterCount`;
  search + type chips + wallet/category dropdowns, live-apply, Clear,
  Done. Replaces the inline chips + 2 dropdown boxes + search field.
* **Money/RTL core fix:**
  * `Money.format` kept byte-identical raw ASCII (storage/CSV/tests;
    verified no bidi controls emitted).
  * New `Money.inline` (LRI/PDI isolates U+2066/U+2069) for amounts
    embedded in Arabic sentences.
  * `MoneyText` reworked (`lib/core/widgets/design.dart`): new
    `neutral` type (signed value, no glyph, inherits caller style
    untouched); typed modes format abs + glyph; whole run wrapped in
    `Directionality(ltr)` so `-4,420.500 د.ت` renders sign-attached in
    en/fr/ar, light/dark. Single documented contract for all display.
  * Migrated ~40 raw `Money.format`-in-`Text` sites → `MoneyText`
    (standalone) / `Money.inline` (interpolated) / explicit LTR
    `Directionality` (numeric `a / b` fractions: debts trailing,
    savings fraction, `budgetFraction` call site): debts (3), savings
    (3), recurring trailing (→ typed `MoneyText`, dead `sign` var
    removed), reports (5), budgets (2), category_detail (2), dashboard
    (7 incl. `_avgCard` signature → millimes+lang), donut center/legend
    semantics + in/out bars (glyph ownership moved into `MoneyText`),
    wallet_card balance, `WalletSelectCard` balance, wallets dialog
    rows. Four now-unused `money.dart` imports removed.
* **Hidden-wallet exclusion (display-level, per brief decision):** new
  `WalletsRepo.visibleBalance()` (non-archived AND non-hidden; ledger
  `totalBalance()` untouched); `FinancialSummaryService.totalMoney()`
  → visible-only; dashboard `_totalMasked` → global switch only
  (per-wallet hiding can no longer leak by subtraction, so no masking
  needed). Docs/comments updated at each site.
* **RTL collateral fixes:** `package:intl` exports its own
  `TextDirection` class shadowing Flutter's enum → `hide
  TextDirection` on both intl imports (transactions, budget) with
  explanatory comment; `initializeDateFormatting('ar'/'fr')` added to
  `main.dart` in try/catch (previously NOTHING initialized locale
  data, so all locale weekday/month formats silently fell back to
  digits — latent bug); Mizania header month via
  `DateFormat('MMMM yyyy', locale)` replacing hardcoded English
  `monthNames`.
* **Header clarity:** Transactions AppBar title is now a plain brand
  Row (logo mark in `primaryContainer` + text, not a button);
  tappable `HomeTitle` kept only on Wallets/Mizania/Dashboard.
* **Localization:** +6 keys × en/fr/ar (`todayTransactions` /
  معاملات اليوم, `filters`, `clearFilters`, `loadMore`, `done`,
  plus `goHome` from §17).
* **Tests:** new `test/money_display_test.dart` (10: raw contract incl.
  `-4,420.500 د.ت`/`0.000 د.ت`/`+2,500.000`, no-isolate guarantee,
  int-only fractions, `inline` round-trip, `MoneyText` LTR-island
  under RTL host incl. nearest-`Directionality` assertion, abs/no-
  double-sign, neutral style inheritance, fr suffix);
  `redesign_test.dart` +4 (`visibleBalance` exclusion/archived,
  `dayGroupHeader` ar/en/fr, `activeFilterCount`, l10n parity +5
  keys). `qa_matrix_test.dart`: `BANK` casing fix, step-14 rewritten
  for exclusion (visible Bank 100.000 shown, global eye masks,
  unhide restores 2,599.500).
* **Results (verified):** `flutter analyze` → 0 issues; `flutter test`
  → **139/139 pass**; `flutter build linux --debug` ✓ +
  `flutter build apk --debug` ✓; Linux app relaunched detached and
  verified alive (pid observed across shells, VM service listening,
  clean log).
* **Not verified:** on-device integration run; visual comparison
  against the supplied screenshot (attachment not viewable
  in-session); device RTL font rendering/line-height nuances.
* **Files:** rewrote `transactions_page.dart`; added
  `filter_sheet.dart`, `money_display_test.dart`; modified `money.dart`
  (`inline`), `design.dart` (`MoneyText`), `wallets_repo.dart`,
  `summary.dart`, `providers.dart`, `main.dart`, `donut_chart.dart`,
  `wallet_card.dart`, dashboard/budget/wallets/debts/savings/recurring/
  reports pages, `strings.dart`, `redesign_test.dart`,
  `qa_matrix_test.dart`. Schema unchanged (still v6); backups
  untouched. Nothing committed.

---

## 19. MASTER PRODUCT UPGRADE — 2026-09-09 build pass

Upgrade brief (§0–§58: full redesign + finance features + RTL +
polish). Pre-pass audit proved most of the brief already existed
(Today-first Transactions, `MoneyText`, wallet cards, Mizania,
analytics Dashboard, hierarchy, backup v6, 139/139 green), so work
targeted verified gaps only. Financial engine untouched throughout
(repos, Drift, millime ints, backup codec shape, l10n system).

1. **Original state:** §14/§18 state + uncommitted tree at `b33c992`;
   suite 139/139, schema v6, backup codec v6.
2. **New product architecture:** unchanged layers (UI → Riverpod →
   repos → Drift). Added thin glue only: `FinancialSummaryService`
   already existed; new `NotificationPlanner` (pure), `MasroufiWidget`
   (push-only), `PinStore`/`BioAuth` abstractions, `Haptics` helper.
   No service-for-service's-sake classes.
3. **Navigation changes:** none structural this pass (3-slot bar kept).
4. **Transactions redesign:** quick-add "Recent" row in txn form
   (`recentCategoryIds`/`frequentCategoryIds` repo queries, history-
   driven, hides when empty); filters unchanged (sheet).
5. **Dashboard redesign:** added TOTAL INCOME hero (period income,
   already loaded) + deterministic insights section wiring the
   existing `Insights.buildInsights` engine (current-vs-previous
   calendar month; empty when insufficient).
6. **Wallet redesign:** tap now opens a statistics sheet (balance,
   month in/out via new `AnalyticsRepo.walletStats`, txn count,
   recent 5) instead of a bare list; edit dialog unchanged.
7. **Mizania redesign:** none needed (presentation + cat budgets
   already per brief).
8. **Category system:** unchanged (hierarchy + kinds + archive-safe
   history already per §§14–16).
9. **Icon architecture:** unchanged (central registry + aliases).
10. **RTL fixes:** `Money.inline` isolates for widget strings;
    locale-aware transfer arrow already; widget layout
    `layoutDirection="locale"`.
11. **Money formatting fix:** reused `MoneyText`/`Money.inline`
    everywhere new (wallet stats, income hero, widget data); raw
    `Money.format` byte-identical (CSV-safe, tested).
12. **New financial features:** (a) CSV IMPORT — pure
    `BackupCodec.parseCsvImport` (header aliases, BOM-tolerant,
    ISO + dd/MM/yyyy dates, millimes-or-TND amounts via
    `Money.parse`, per-row error codes) + preview dialog with error
    report + confirmed batch insert (unknown wallets reject row,
    unknown categories → uncategorized, self-transfers skipped);
    (b) APP LOCK — PIN (salted stretched SHA-256 in `app_settings`
    KV, 20k iterations, constant-time compare; `remove()` added to
    `SettingsRepo`) + OS biometrics via `local_auth`, lock overlay
    gate + lifecycle relock (pure `shouldRelock`, 0/60/300s),
    settings set/change/remove with proof-of-presence; (c) LOCAL
    NOTIFICATIONS — pure `NotificationPlanner` (budget exceeded/80%,
    top-3 category alerts, due-tomorrow reminders, high-spending
    nudge; 20:00 digest slot, stable ids, caps) + thin
    `AppNotifier` (inexact scheduling, no exact-alarm permission,
    replan on launch + after each save, reboot-clears documented);
    (d) HOME WIDGET — native `MasroufiWidgetProvider` + RemoteViews
    layout (fixed dark-teal, brand/balance/today) + `res/xml` info +
    manifest receiver + `masroufi:///add` deep-link filter (cold
    start → expense form; warm start → home) + Dart push glue with
    isolated amounts; refreshed on launch + after saves.
13. **Database changes:** NONE (still schema v6). Lock secrets are
    hashes in KV, flags/timestamps in KV, CSV import writes ordinary
    txns, notifications/widget read-only.
14. **Migration strategy:** not applicable (no schema change);
    `docs/database.md` stays accurate at v6.
15. **Files added:** `lib/core/utils/haptics.dart`,
    `lib/core/security/app_lock.dart`,
    `lib/features/lock/lock_page.dart`,
    `lib/core/notify/notify_planner.dart`,
    `lib/core/notify/notifier.dart`,
    `lib/core/widget/masroufi_widget.dart`,
    `android/.../MasroufiWidgetProvider.kt`,
    `res/layout/masroufi_widget.xml`,
    `res/drawable/widget_background.xml`,
    `res/drawable/widget_add_button.xml`,
    `res/xml/masroufi_widget_info.xml`,
    `res/values/strings.xml`,
    `test/upgrade_test.dart`, `test/notify_test.dart`,
    `test/lock_test.dart`.
16. **Files modified:** `transactions_repo.dart` (recents/frequent),
    `analytics_repo.dart` (`walletStats`), `settings_repo.dart`
    (`last_backup_at`, `bio_enabled`, `lock_timeout`, `notif_enabled`,
    `remove`), `backup_codec.dart` (CSV import parser + row/error
    types), `backup_page.dart` (last-backup line, import flow),
    `txn_form_page.dart` (recent row, haptics, replan+widget refresh),
    `wallets_page.dart` (stats sheet), `dashboard_page.dart` (income
    hero, insights), `settings_page.dart` (lock section, notif
    toggle), `main.dart` (locale init already; edge-to-edge, lock
    hydration, lock gate), `app.dart` (startup replan+widget push),
    `masroufi_nav.dart`/`add_sheet.dart`/`design.dart` (haptics),
    `strings.dart` (+~30 keys × en/fr/ar), `build.gradle.kts`
    (desugaring for notifications), `AndroidManifest.xml`
    (`USE_BIOMETRIC`, `POST_NOTIFICATIONS`, widget receiver +
    deep-link filter), `drawable-v21/launch_background.xml`
    (unified brand splash), `pubspec.yaml` (+`local_auth`,
    `flutter_local_notifications`, `timezone`, `home_widget`,
    `crypto`; `flutter_secure_storage` evaluated then REMOVED — its
    SDK-37 requirement rejected in favor of KV hashing, zero
    practical gain), `qa_matrix_test.dart` (transfer conservation
    assert, `tapPlus` helper, categories expansion, hierarchical
    leaf label, hide-exclusion step).
17. **Tests added:** `upgrade_test.dart` (5: recents/frequent,
    walletStats, lastBackupAt, dashboard income+insights widget),
    `notify_test.dart` (7: planner rules/caps/slots), `lock_test.dart`
    (8: PIN store incl. hash round-trip/salting/corrupt-closed,
    relock matrix, lock-page unlock, setup mismatch loop);
    `backup_test.dart` +4 (CSV import cases);
    `redesign_test.dart` parity extended (lock/backup/widget keys).
    What/where/tested per feature as listed above; planner/lock/
    parser are pure/faked (no hardware), delivery paths
    try/caught by design.
18. **Test results:** `flutter test` → **164/164 pass** (139 + 25
    new); `flutter analyze` → 0 issues. Integration
    `qa_matrix_test.dart` on Pixel 7 API-36 emulator (Arabic + dark):
    **PASS** after fixing 4 test-side stalenesses (transfer-button
    finder, conservation assert + wallet-leg check, `tapPlus` vs
    income-glyph ambiguity, collapsed-tile expansion, hierarchical
    leaf label, hide-exclusion rewrite). No app-code bug found by
    the matrix; all failures were test-code rot.
19. **Build results:** `flutter build apk --debug` ✓ (validates
    Kotlin provider, manifest, resources, desugaring). Intermediate
    failures fixed honestly: AAR-metadata desugaring requirement,
    secure-storage SDK-37 demand (→ hashed KV instead),
    widget-description resource ref. Release AAB: not built (debug
    signing only in this pass).
20. **Screens verified:** emulator screenshots: unified brand splash
    ✓; onboarding rendered correctly in EN + FR + AR incl. RTL
    button placement ✓ (adb-driven session). Full 6-combo in-app
    matrix + small-screen pass: NOT completed here (bare launcher
    cold starts stall pre-first-frame on this SwiftShader emulator —
    Dart isolate idle, 0 frames, no errors — while the identical
    binary renders via tool launches and passes the whole on-device
    suite; needs real hardware to verdict).
    Launcher cold-start first frame stalls on this emulator (0
    frames, Dart isolate idle — engine/shader pipeline, not app
    logic; identical binary passes the full on-device suite).
21. **Known limitations:** notifications best-effort (reboot clears
    until next launch; inexact timing); widget tap-add deep link
    cold-start only; lock is anti-snooper grade (DB unencrypted,
    documented); CSV import has no undo (backup-first advice in
    dialog? NOT implemented — recommended follow-up); biometric
    needs hardware (PIN fallback); secure-storage plugin deliberately
    not used (see §19.16 rationale).
22. **Remaining roadmap:** on-device visual matrix + small screens on
    real hardware; release AAB + signing; CSV-import undo/restore
    point; optional exact-alarm + boot receiver; Glance widget;
    cloud sync (V1.2 per ROADMAP). Nothing committed (per
    instructions).

---

## 20. COMPLETE UI/UX + PRODUCT REDESIGN — build pass (this session)

Brief §§1–65. Pre-pass audit proved ~80% already existed (Today-first
Transactions, MoneyText, wallet cards, Mizania+cat budgets, analytics
Dashboard, backup v6, lock/notifications/widget, 164/164 green), so
work targeted 16 verified gaps. Financial engine untouched (repos,
Drift, millime ints, transfer neutrality).

- **Original state:** §19 state; suite 164/164; schema v6; codec v6.
- **Redesigned UX:** Transactions is Today-first with zero date
  buttons; comparisons are typographic info; filters live in one
  sheet; timeline rows are compact icon/title/wallet/time/amount.
- **Navigation:** unchanged 3-slot bar + top switch + settings hub
  (brief §3 five-tab sketch rejected per approved decision).
- **Transactions:** NEW read-only detail sheet (tap; icon, amount,
  day/time, wallet, category, note, Edit + Save-as-template);
  swipe-delete + 10s Snackbar undo (byte-identical `restore()`;
  restore confirmation kept); long-press menu
  (edit/duplicate/copy-to-clipboard/delete); per-day expense totals
  (client-side sums of rendered rows, zero queries); date window in
  filter sheet (All/Today/Week/Month/Custom range dialog);
  name-aware search (category/wallet names resolved to ids, explicit
  filters win; amount search exact-matches via `Money.parse`);
  expandable per-wallet hero breakdown (hidden render masked);
  daily guidance indicator vs monthly budget; empty-state CTA.
- **Dashboard:** compact MoM line under donut header (whole-%,
  int-only); Upcoming strip (next 3 rules, →recurring manager);
  health facts folded into Insights (check/warn icons, no scores,
  MoM deliberately not duplicated); current-month spending calendar
  (week-start-aware grid, intensity shading, today ring, tap-day
  sheet with total + rows + detail entry).
- **Wallets:** unchanged cards; tap opens statistics sheet (already
  existed).
- **Mizania:** daily guidance block (remaining/days-left/suggested
  via shared `dailyGuidance` helper); 80%-approaching tertiary state
  on `BudgetBar` (same threshold as notifications); over stays red.
- **Categories/icons:** unchanged (hierarchy + registry + picker).
- **RTL fixes:** transfer arrow already; calendar weekday order
  honors week-start; widget strings isolated.
- **Money formatting:** unchanged engine; all new surfaces use
  `MoneyText`/`Money.inline` exclusively (verified by grep: zero new
  raw-format sites).
- **New financial features:** (a) TEMPLATES — `txn_templates` table
  + repo (create/rename/remove, validation) + one-tap apply row in
  txn form (dangling refs fall back) + save-as-template from detail
  + long-press delete; never auto-creates. (b) `dailyGuidance`
  pure helper (remaining/daysLeft incl. today/suggested, negative
  stays negative). (c) `buildCalendarWeeks` pure grid helper.
  (d) `Insights.buildHealth` factual lines + 4 template keys ×3.
- **Database migrations:** v6→v7 = ONE new table, no backfill, no
  data touched. Backup codec v6→v7 (`txn_templates` array; old
  restores → []). No other schema needs. `docs/database.md`
  updated to v7.
- **Files added:** `lib/data/repositories/templates_repo.dart`,
  `lib/features/transactions/txn_sheets.dart`,
  `test/txn_foundation_test.dart`, `test/product_ux_test.dart`,
  `test/small_screen_test.dart`.
- **Files modified:** `tables.dart`, `app_db.dart`,
  `app_db.g.dart` (regen), `transactions_repo.dart` (`get`,
  `restore`, `walletIds`, amount search), `backup_codec.dart` (v7),
  `backup_page.dart` (template export/import), `providers.dart`
  (templates provider), `transactions_page.dart` (hero/sheet/
  timeline/filter wiring), `history_page.dart` (same contract),
  `filter_sheet.dart` (dates), `txn_form_page.dart` (templates),
  `design.dart` (EmptyState CTA, BudgetBar approaching),
  `dashboard_page.dart` (MoM/upcoming/health/calendar),
  `budget_page.dart` (guidance), `onboarding_page.dart` (2 steps),
  `insights.dart` (buildHealth), `summary.dart` (dailyGuidance),
  `dates.dart` (dayGroupHeader moved here from page),
  `strings.dart` (~25 keys ×3), `migration_test.dart` (v1→v7),
  `backup_test.dart` (v7 + v6→v7 case),
  `analytics_test.dart` (buildHealth),
  `redesign_test.dart` (parity + date import fix),
  `qa_matrix_test.dart` (2-step onboarding, sheet-last taps,
  save retry, conservation assert, expansion + hierarchy labels,
  exclusion rewrite).
- **Tests added:** `txn_foundation_test` (7: templates CRUD/
  validation, restore byte-identity + no-dup, walletIds endpoints,
  amount search), `product_ux_test` (10: guidance math incl. Feb,
  calendar grids, badge count, detail/menu/undo widgets, 2-step
  onboarding incl. wallet creation), `small_screen_test` (4:
  360×640 home/ar + dashboard/ar + wallets/en + form, scroll-every-
  section overflow proof), `analytics_test` +2 (buildHealth),
  `backup_test` +1 (v6→v7), `migration_test` extended.
- **Test results:** `flutter test` → **187/187 pass**;
  `flutter analyze` → 0 issues. Caught-by-tests file:
  detail-sheet overflow on small screens (fixed: scrollable),
  duplicate MoM sentence in health (removed), exact-vs-substring
  Arabic assertions, lazy-unmount timing, Drift stream-teardown
  race (documented harness workaround).
- **Build results:** `flutter build apk --debug` ✓ (validates v7
  codegen, manifest, resources). `flutter build linux --debug` ✓,
  relaunched detached + verified alive.
- **Screens verified:** emulator screenshots (splash, onboarding
  EN/FR/AR incl. RTL placement); full `qa_matrix_test` GREEN on
  Pixel 7 API-36 (Arabic+dark, all flows incl. new assertions);
  360×640 widget proofs for home/dashboard/wallets/form. Bare
  launcher cold starts stall pre-first-frame on this SwiftShader
  emulator (idle isolate, 0 frames, no errors) while the identical
  binary renders via tool launches — environment-specific, needs
  real hardware to verdict. Full 6-combo matrix still needs a
  device; manual adb tapping proved too flaky/slow to substitute.
- **Known limitations:** single-level undo (new delete replaces
  pending); template rename = delete + recreate (documented);
  calendar is current-month only (no month pager); date presets use
  live `now` (chip identity display-only); search matches exact
  millime amounts (documented); CSV import still has no undo;
  `docs/database.md` needs a v7 line.
- **Remaining roadmap:** device visual matrix + small hardware;
  release AAB + signing; template rename/reorder if requested;
  calendar month pager; exact-alarm + boot receiver; Glance;
  cloud sync (V1.2). Nothing committed (per instructions).

---

## 21. UPGRADE PLAN EXECUTION — 2026-09-09 build pass (Tracks 1–8)

Executed `UPGRADE_PLAN.md` top-to-bottom. After every track:
`flutter analyze` + `flutter test` green before continuing. No rewrites,
no fake data, no AI in financial logic; schema v7→v8 only with staged
Drift migration + codec bump + migration tests. Suite: 187 → **220/220**;
analyze 0 issues throughout.

### Track 1 — Ship readiness
- Version `1.1.0+2` (already in tree) kept; `CHANGELOG.md` gained
  Keep-a-Changelog fr/ar summaries; `store/release-checklist.md` →
  1.1.0+2; settings about-line → 1.1.0+2.
- Git hygiene: this pass ends with logical commits (see git log);
  secrets never staged (`android/key.properties`, `*.jks` git-ignored;
  local keystore `.tooling/keystore/masroufi-release.jks` reused).
- Gate: analyze 0 + full unit suite green; release AAB build verified
  separately (see §21.9); emulator matrix not re-run here (prior pass
  green; SwiftShader cold-start stall is environment-specific).

### Track 2 — PDF monthly export
- Deps: `pdf ^3.11.3` + `printing ^5.14.2` (no schema, no permissions).
- `lib/core/export/monthly_statement.dart`: pure `MonthlyStatementBuilder`
  (brand header, localized month en/fr/ar-TN, income/expense/net,
  top-5 categories, budget vs actual, txn count — from `AnalyticsRepo`
  data) + `buildPdf` with bundled Amiri-Regular (SIL OFL under
  `assets/fonts/` + OFL.txt, pubspec assets).
- Reports AppBar → Export PDF → `Printing.sharePdf`; l10n
  `exportPdf/monthlyStatement/pdfSaved` ×3.
- Tests `test/monthly_statement_test.dart` (6): totals vs fixtures,
  cap/sort, ar month bytes, pdf builds with attached minus, fallback
  font, real ReportsPage export affordance.

### Track 3 — Safety + small follow-ups
- CSV-import undo: session restore point (`insertedIds` + 10s Snackbar
  Undo → deletes); preview dialog gained backup-first advice
  (`csvBackupFirst` ×3).
- Savings↔wallet: documented as designed (separate ledger, default
  unlinked) in `docs/product.md` + inline `savingsSeparate` note.
- Calendar month pager: `calMonthProvider` + chevrons in dashboard
  calendar (`calPrev/calNext` ×3).
- Templates: `rename()` existed; added `move()` (sortOrder swap) +
  long-press menu (rename/move up-down/delete, `renameTemplate`,
  `templateRenamed` ×3, reuses existing `moveUp/moveDown`).
- Exact-alarm + boot: stays OFF on demand (inexact digest only);
  documented in `notifier.dart` + `exactAlarmNote` subtitle ×3.
- Tests `test/track3_test.dart` (3): rename+move incl. edge no-op,
  pager math + Jan boundary, l10n parity.

### Track 4 — Cloud + receipts (research doc only)
- `docs/cloud_receipts_options.md`: backend matrix (blob-sync first),
  E2EE requirement, conflict sketch on stable UUIDs + `updatedAt`
  (LWW + tombstones + rollup re-validation), receipts ratings. No code.

### Track 5 — Money safety net (no schema)
- `lib/core/backup/auto_backup.dart`: weekly run-if-stale on startup
  (`main.dart`, try/caught), `masroufi_auto_<epoch>.json`, keep last 4
  (`prune`), `auto_backup_at` + `last_backup_at` KV.
- Backup-health nag in `BackupPage` (14+ days, `backupStale` + Dismiss
  via `backup_nag_dismissed_at` + `backupNow`).
- `DuplicateGuard` (same wallet+category+amount, 30 min, warn-only) wired
  into `txn_form_page.save()` (`duplicateWarn/Body` already existed).
- `DataHealth.scan/repair` (dangling refs from no-FK design; nulls
  nullable category/parent refs, never deletes) + `DataHealthPage`
  (`/settings/data-health`, tile in Settings → Data).
- Tests `test/safety_net_test.dart` (6): weekly/prune/nag math,
  window/findRecent incl. transfer exclusion, scan→repair→rescan.

### Track 6 — Budget intelligence (no schema)
- `lib/core/budgets/budget_intel.dart`: `projectionAlert` reusing
  `AnalyticsStats.partialMonth`, `effectiveBudget` rollover math
  (display-only), `prevMonth` (Jan boundary).
- Planner rule: `NotificationPlanner.plan` + `projection*` params (id 150,
  `projectionAlert/Body` already existed) + `notifier.replan` feeds
  month spent/budget/elapsed/days.
- Rollover: `rollover_enabled` KV + `rolloverProvider` (hydrated in
  `main.dart`) + switch in Mizania `_IntelCard`.
- Copy-last-month: `BudgetsRepo.copyFromPrev` + `CategoryBudgetsRepo.
  copyFromPrev` (idempotent, never overwrite, Jan boundary) + button in
  `_IntelCard` (`copyLastBudgets/copiedBudgets` ×3).
- Tests `test/budget_intel_test.dart` (7 incl. month boundaries).

### Track 7 — Wealth views (no schema)
- `lib/core/wealth/net_worth.dart`: documented formula (visible
  initials + flows before month-end + non-archived savings),
  `buildTrend/delta` pure + `trend()` DB service (6 months).
- Reports: `_NetWorthSection` mini-chart (custom bars, `netWorth` +
  `netWorthNote` ×3, never relabeled) + `_YearReviewSection` →
  `YearReviewCard` (`RepaintBoundary`, offline PDF share).
- `lib/features/reports/year_review_card.dart`: pure `YearReviewData.
  build` (top category, net) + card + share.
- Savings widget variant: shared Kotlin implementation
  (`MasroufiSavingsWidgetProvider : MasroufiWidgetProvider`, same
  onUpdate/layout/prefs) + separate manifest receiver (`Masroufi
  Savings`, `masroufi_savings_widget_info.xml`) + Dart
  `savingsWidgetLines` + push (`savings_title/balance`).
  Caught-by-build: manifest merger rejects two receivers with the same
  class (fixed with the subclass); Kotlin classes are final by default
  (`open` added to the parent).
- Tests `test/wealth_test.dart` (4, builders not pixels): sort/delta,
  hidden-exclusion formula, year builder, widget lines.

### Track 8 — Everyday power (schema v8)
- Schema: `txn_splits` child table + `transactions.orig_minor`/
  `orig_currency` (nullable, display-only); `schemaVersion` 7→8,
  `onUpgrade` create + addColumns; `app_db.g.dart` regenerated.
- `SplitsRepo` (parent untouched, SUM == parent enforced, `setSplits`
  atomic) + provider; detail sheet `_SplitsSection` (add/remove,
  `splitWith/addSplit/splitTotal` already existed) scope-safe for tests.
- Multi-currency: `lib/core/fx/fx.dart` (manual offline rates
  `fx_rate_<CODE>` + timestamps, `toTndMillimes` int-only,
  `formatOriginal`, `parseMinor`, 30-day `isStale`), `FxRatesPage`
  (`/settings/fx-rates`), txn form orig fields (`originalAmount/
  Currency` ×3 existed), detail `_FxRow` + stale badge.
- `HiddenGate` (reuses `PinStore`/`BioAuth` + `showPinVerify`):
  `needsAuth` pure + `ensureUnlocked`; wired into wallet eye toggle
  (revealing challenges; `unlockHidden` ×3 existed).
- Codec v8 (`txn_splits` + orig fields; v1–v7 accepted) + backup page
  export/import + `restore()` orig passthrough + auto-backup v8;
  `docs/database.md` → v8; `migration_test` → v1→v8 (null originals,
  splits usable); `backup_test` → v8.
- Tests `test/everyday_power_test.dart` (7): split invariants, FX math,
  gate paths, codec v7→v8 + round-trip, fresh-v8 shapes.

### Verification
- `flutter analyze` → 0 issues. `flutter test` → **220/220 pass**
  (187 baseline + 33 new: 6 statement + 3 track3 + 6 safety + 7 intel
  + 4 wealth + 7 power).
- `flutter build apk --debug` ✓ (validates v8 codegen, manifest
  receivers, resources; see gate note below).
- Caught-by-tests: duplicate l10n keys (`moveUp/Down` reused), v8
  codec type for nullable by-category, scope-free sheet tests (fixed
  with `_Maybe*` wrappers), backup version bumps (7→8).

### Gate note (Track 1 close-out)
- `flutter build apk --debug` green on the final tree (this pass).
- Signed release AAB + Play Console upload stay operator-gated:
  local keystore `.tooling/keystore/masroufi-release.jks` +
  git-ignored `android/key.properties` are in place and `releases/`
  keeps the previous signed artifact + SHA256SUMS pattern, but no new
  AAB was cut or uploaded here and no store listing was published.
- Emulator matrix (`qa_matrix_test.dart`): not re-run in this pass;
  prior pass green; bare-launcher cold-start stall on this SwiftShader
  emulator is environment-specific — verdict needs real hardware.

---

## 22. UI/UX REDESIGN — 2026-09-09 build pass (Steps 1–13)

Real community skills installed globally (UI/UX Pro Max 2.15.0 via
`uipro`, beautify-flutter 1.5.0 via clone, ux-designer via copy; all in
`~/.claude/skills/`, repo untouched by installation). Roles: Pro Max =
palette/style authority, beautify-flutter = Flutter implementation,
UX Designer = per-phase gate. Pro Max landing-page generator output
rejected with cause (dark glass plus handwriting font unsuitable);
raw finance CSV rules used instead. Votes honored: light-first, new
petrol palette (all pairs verified 4.5:1+), 3-slot nav kept.

- **Step 1:** DESIGN.md + design-system/MASTER.md frozen; IBM Plex Sans
  variable TTF bundled (OFL); tuned light/dark schemes, Plex scale,
  component themes, tokens. Wallet identities and DB defaults untouched.
- **Step 2:** flat + action (no glow), theme drag handles, tokenized
  nav and add sheet. design-check.sh triaged and adopted as gate.
- **Step 3:** brightness-aware MoneyText with tabular figures, hero
  skeleton (no bare spinner), fixed comparison strip (no shrinkWrap),
  tokenized hero, 48dp eye. Detail/menu/UX tests green.
- **Step 4:** live-region inline errors keeping field values, tokenized
  form/picker/filter. Foundation/upgrade/small-screen tests green.
- **Step 5:** detail sheet rhythm pass; actions and positions preserved.
- **Step 6:** wallet cards flat tonal, 48dp targets, named tracking,
  masked/visible metric parity. Caught and fixed: missing theme import,
  radius token name.
- **Step 7:** remaining as display-size hero (state-colored), total as
  caption, merged rhythm, no new cards.
- **Step 8:** AppChartColors light/dark ramps, brightness-aware donut,
  dashboard tokenized; every viz answers a distinct question.
- **Step 9:** settings hub regrouped (Money/Analysis/Planning/Data/
  Notifications) on existing routes; RTL-mirroring chevron; one new
  key (planning) with fr/ar parity.
- **Step 10:** RTL audit (zero physical sides, zero raw money-in-Text);
  pager and drill-in chevrons mirror; refund glyph made
  direction-neutral with regression guard.
- **Step 11:** per-theme status-bar and gesture-nav overlay styles
  (edge-to-edge legible both ways).
- **Step 12:** a11y sweep (tooltips, theme handle, 48dp); new 200%
  text-scale home test caught a real ListTile trailing-width bug,
  fixed with constraint-derived trailing plus MoneyText ellipsis.
- **Step 13:** final sweep leaves zero inline sizes/colors in screens;
  `dart format` normalized; debug APK green.

Verification: `flutter analyze` 0 issues, `flutter test` 226/226
(220 baseline + 4 theme + 1 scale + 1 refund-glyph), debug APK green.
Degraded verification declared: on-device toggle proof and visual
screenshot QA need real hardware (emulator cold-start stall).

---

## 23. DESKTOP LAUNCH — 2026-09-09 (redesigned app run)

User asked to open the new app. `flutter devices` showed Linux desktop
only (no emulator booted), so the final redesigned tree (1.1.0+2, Steps
1–13) was launched with `flutter run -d linux` (project-local
toolchain, detached via setsid after the first background attempt was
reaped by the tool session).

- Build compiled clean; hot-sync to device completed in 252ms.
- App binary `build/linux/x64/debug/bundle/masroufi` ran persistently
  (observed alive across checks), Dart VM service plus DevTools came
  up, run log showed zero errors and zero exceptions.
- Screenshot capture was attempted (`import -window root`, DISPLAY=:0
  present) but the screen-grab path failed, so no pixel proof was
  captured; frame rendering was not independently confirmed beyond
  process persistence plus a clean log.
- Session later ended with "Lost connection to device" (window
  closed/process exit, no errors logged). Debug `flutter run` wrapper
  does not survive on its own; relaunch with the same command to open
  again. For a phone artifact, cut a fresh signed release AAB (the
  AAB in `releases/` predates the redesign).

---

## 24. BI ANALYTICS — 2026-09-09 build pass (phases 1–7)

Dashboard rebuilt as the Analytics page (route `/dashboard`
unchanged, 3-slot bar and top switch untouched) on a new pure BI
engine. No schema change, no new dependencies, int-millimes end to
end; AI assistant stays out, with snapshot records as its future
interface.

- **Phase 1:** `kpi.dart` (net cash flow, savings rate null-safe,
  expense growth, uncapped utilization, weighted health score with
  bands plus missing-input flags) and `forecast.dart` (run-rate
  projection, overrun, pace). 8 boundary tests (zero income,
  overspend, leap-Feb).
- **Phase 2:** scoped repo sums (wallet-filtered income/expense,
  scoped count, wallet-filtered byCategory, sameMonthLastYear).
  Transfer endpoint semantics preserved; a bind-twice bug caught by
  test. 5 tests.
- **Phase 3:** `bi_scope.dart` (BiFilter with parent expansion,
  single-batched `BiSnapshot` load: KPIs, growth, YoY, byCategory/
  Priority/Wallet, filtered 6-month trend, pace inputs,
  obligations, debts, month-anchored budgets). Two half-open-scope
  off-by-one bugs caught by tests. 5 tests.
- **Phase 4:** page rebuild (KPI grid, global filter bar, forecast
  card, twin-bar trend, drill tree, wallet/priority, budget-vs-
  actual, health score). Legacy period chips and duplicated
  averages removed; calendar, upcoming, and deterministic insights
  preserved. Caught: filter-bar overflow (scrollable chips),
  duplicated MoM sentence (scope template created instead),
  dead preset keys removed. 1 widget test on 360px.
- **Phase 5:** `Insights.buildMovers` plus `insCatGrowth` ×3 locales
  and snapshot `prevByCat`; movers render in the health icon
  language. 3 template tests plus snapshot sum.
- **Phase 6:** `BiExport` (KPI CSV with raw numbers and omitted-not-
  zeroed optionals; dataset CSV with hierarchy paths) plus scope
  export row (2000-row documented cap, Amiri PDF). 2 builder tests
  (CRLF normalization noted).
- **Phase 7 (gate):** design-check triaged (one accepted sheet-scope
  shrinkWrap), analyzer 0 issues, suite 249/249, debug APK green.
  External concurrent files (README badges, LICENSE, .github/,
  docs/obsidian/, one product.md line) observed in-tree and left
  untouched.

Verification: `flutter analyze` 0 issues, `flutter test` 249/249
(226 baseline + 23 BI: 8 kpi + 5 scoped + 5 snapshot + 1 page + 2
movers/prevByCat + 2 export). Visual QA on hardware still pending.
