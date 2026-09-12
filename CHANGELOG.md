# Masroufi (مصروفي): App Overview & Changelog

> Read this file first. It describes what the app is, what it does,
> how it is built, and what changed in each release, so a new
> developer can understand the whole project without digging through
> git history.

## 1. What this app is

Masroufi is an **offline-first, private personal finance app for
Tunisia**, in **Arabic (RTL-first), French, and English**. No account:
all money lives in an on-device SQLite database. Ads load automatically
when online (personalization switch in Settings); cloud AI stays opt-in.
Core finance works in airplane mode.
The current version is **1.3.2+6**
(`pubspec.yaml`), DB schema **v8**, backup codec **v8**.

In one line: **personal finance management + embedded business
intelligence + opt-in AI explanations + automatic ads with PRO remove**.

## 2. What the app does (feature tour)

- **Transactions (home screen).** Today-first timeline: today's
  spending hero, available money, compact period context, then
  today's and previous transactions grouped by date. Every row shows
  category icon, category/subcategory, wallet, time, and a
  sign-attached amount. Expense / income / atomic transfer (a
  transfer is one row with two wallet legs and is never counted as
  spending). Fast creation flow (Amount → Category → Wallet),
  templates, recents, edit, swipe-delete with 10s undo, duplicate,
  copy, CSV import with validation report and session undo.
- **Wallets.** Bank-card-style cards (Cash, Bank, Card, Savings +
  custom) with per-wallet color/design identity. Balances are
  **derived** (`initial + income − expense + net transfers`), never
  stored. Archive, per-wallet and global balance hiding (mask-only,
  math untouched), per-wallet statistics, per-action biometric gate
  when revealing hidden balances.
- **Mizania (budgets).** Overall monthly budget + per-category
  budgets, remaining-as-hero, daily safe-to-spend guidance, 80%
  approaching state, over-budget state, projection alerts, rollover
  toggle (display-only), copy-last-month budgets.
- **Categories.** 20 Tunisian expense defaults (Café, Taxi, Louage,
  STEG, SONEDE…) + 7 income defaults, single-level
  parent → child hierarchy with rollup totals, expense/income kinds,
  importance priorities, archive (never breaks history), reorder,
  and a centralized icon registry (the DB stores stable icon keys,
  never `IconData`).
- **Recurring transactions.** Daily/weekly/monthly/yearly rules with
  month-end clamping, pause/skip, auto-generation on startup
  (never blocks launch, never duplicates).
- **Debts.** Owe / owed-to-me with partial payments linked to real
  wallet transactions (balances update exactly once), overpayment
  blocked, auto-settle, due dates.
- **Savings goals.** Separate contributions ledger (contribute /
  withdraw) that never moves wallet money; archive and progress.
- **Analytics (Dashboard page).** KPI cards (income, expenses, net
  cash flow, savings rate, daily/monthly averages), global filter
  bar (day/week/month/year + wallet + category + type) driving one
  recomputed snapshot, forecast card (projected spend, overrun,
  pace), expense/income trend, income-vs-expenses, drill-down
  category tree to transactions, wallet/priority breakdowns,
  budget-vs-actual, transparent financial-health score (all inputs
  shown), automatic factual insights, calendar, upcoming payments.
- **Reports & export.** Monthly statement PDF (bundled Amiri font
  for Arabic shaping) via share sheet, KPI-summary CSV, analytical
  dataset CSV, transaction CSV export.
- **Backup & safety.** Versioned JSON backup/restore (v1–v7 backups
  restore cleanly into v8), weekly filename-rotated auto-backup
  (keeps last 4), 14-day backup-health nag, duplicate-expense
  warning, data-health scan + safe repair (dangling refs from the
  no-FK design; repairs null, never deletes).
- **Security & platform.** PIN (salted stretched hash, no keystore
  plugin) + OS biometrics, app lock with relock timeouts, local
  notification digest (inexact, best-effort), home-screen widget +
  savings variant, multi-currency display (manual offline rates,
  original amount per transaction, stale-rate badge) with TND-only
  ledger.
- **Onboarding & settings.** 2-step onboarding (language, first
  wallet), settings hub (General / Money / Analysis / Planning /
  Data / Notifications / Security / About), per-action and global
  privacy controls.

## 3. Architecture

```text
UI (features/*, core/widgets) → Riverpod providers (lib/app)
→ repositories (lib/data/repositories/*) → Drift/SQLite (lib/data/database/*)
+ pure helpers: core/money, core/analytics (Periods, AnalyticsStats,
  Insights, Kpi, ForecastV2, BiSnapshot engine), core/fx, core/safety,
  core/security, core/notify, core/export, core/wealth
```

- No separate domain/services layer; business logic lives in repos
  + pure helpers. No business logic in widgets.
- All IDs are stable UUIDs with `createdAt`/`updatedAt` (sync-ready).
- Cross-table references are plain text, no foreign keys: archiving
  or deleting never breaks history (dangling refs are possible and
  covered by data-health tools).
- Navigation: `go_router` `StatefulShellRoute`, 3-slot bar
  (Wallets | + | Mizania); Transactions `/` is default, Dashboard
  `/dashboard` shares home via top switch; `/settings/*` hub keeps
  legacy `/more/*` redirects.

## 4. Money model (critical, never change casually)

- TND with millimes. Everything is **integer millimes** (`int`):
  `10.500 TND` = `10500`. Never `double` in financial logic.
- Helpers: `lib/core/money/money.dart` (`parse`/`format`/`inline`),
  `lib/core/money/calc.dart` (integer-only math).
- Display: `12.500 TND` / `12.500 د.ت`. Every amount renders through
  `MoneyText` (standalone, LTR island, sign attached) or
  `Money.inline` (inside sentences): this is what fixes the Arabic
  minus-sign bug centrally. Never interpolate `Money.format` into
  RTL text.

## 5. Database, migrations, backup

- Drift + `drift_flutter`, 13 tables: wallets, categories,
  transactions, budgets, settings, recurring rules, category
  budgets, savings goals + contributions, debts + payments,
  transaction templates, split lines (`txn_splits`: parent row
  untouched, splits must sum to it).
- `schemaVersion = 8`, staged `onUpgrade` chain v1→v8 with backfills
  (kinds, priorities, hierarchy parents, card styling). Downgrades
  are not supported.
- Backup codec v8 accepts v1–v7 and normalizes (missing tables →
  empty, new columns → defaults). See `docs/database.md`.

## 6. Localization, RTL, design system

- Hand-rolled `lib/core/l10n/strings.dart`, full en/fr/ar parity
  (tests enforce it), RTL first-class, `intl` for dates/numbers.
- Theme foundation in `lib/core/theme/app_theme.dart`: light-first
  petrol identity, derived (not inverted) dark mode, IBM Plex Sans
  bundled + Amiri for Arabic brand/PDF moments, spacing/radius/
  motion tokens, full component themes. Rules: everything flows
  from `ThemeData` (no inline colors/sizes in screens), tabular
  figures for amounts, one accent, 48dp targets, reduced-motion
  respect. Standing decisions live in root `DESIGN.md` plus
  `docs/brand-guidelines.md`.

## 7. Quality gates (for contributors)

- `flutter analyze` must be clean; `flutter test` must stay green
  (36 files, 275 tests: unit, widget incl. 360×640 small-screen
  and 200% text-scale proofs, migration v1→v8, codec upgrades).
- Rules: integer millimes only; schema changes need migration +
  codec bump + migration test; transfers stay transfers; no new
  permissions/network for core features; ar/fr parity for new
  strings; no fake data, no AI in financial logic (the BI snapshot
  records are the future AI interface, not AI output).
- Toolchain: project-local under `.tooling/` (`source
  .tooling/env.sh`), `flutter build apk --debug` /
  `flutter build appbundle --release`. Signing deferred to local
  keystore (`android/key.properties` + `*.jks` git-ignored, never
  committed).

## 8. Release history

### [1.3.2+6], 2026-09-12

Fixed: reinstalls reset PRO. Android Auto Backup used to clone the
install id + PRO flag to the new install; a backup-excluded probe
file now detects restores, rotates to a fresh id, and drops PRO so
the buyer buys again with a new ref. Device-to-device transfer
excluded too (clones would share codes).

### [1.3.1+5], 2026-09-12

Fixed: release carries the seller PIN, so manual `MASR-NNNNNN` codes
verify on phones (1.3.0 release builds shipped without it). No app
changes besides the version bump.

### [1.3.0+4], 2026-09-12

Added: PRO pay flow (D17 56597139 + Ba9chich, 9.9 DT, WhatsApp proof,
per-device `MASR-NNNNNN` calculator codes + legacy HMAC path, seller
mint tool, release `--dart-define` wiring); donation page + settings
tile; PRO-gated dark theme + app lock (gated UI, runtime enforcement);
automatic ads for all online users (consent switch now tunes
personalization); PRO/donate nudge sheet on home (5th launch, 14-day
cooldown); dashboard split into part files; reports folded onto the BI
snapshot; labeled error retry; explicit back buttons on
Wallets/Mizania. Full en/fr/ar + RTL throughout.

Changed: removed dead summary services + forecast V1 (unified on
ForecastV2); manual codes reject empty device ids. No schema change
(DB v8, codec v8).

### Résumé (fr)

- Paiement PRO D17 + Ba9chich (9,9 DT, codes par appareil), page dons,
  thème sombre + verrouillage PRO, pubs auto, rappel PRO/dons,
  tableau découpé, rapports unifiés. Base v8 inchangée.

### ملخص (ar)

- دفع PRO عبر D17 وبقشيش (9.9 دنانير، أكواد لكل جهاز)، صفحة تبرع،
  السمة الداكنة والقفل PRO، إعلانات تلقائية، تذكير PRO/تبرع. قاعدة v8.

### [1.2.0+3], 2026-09-10

Added: BI depth (YoY any-range, seasonal average/band, 3-month anchor,
per-wallet net flows, wallet/anomaly CSV exports); recurring-aware
forecast with confidence band; anomaly flags; what-if cut simulator;
last-6/12-month + YTD periods. Opt-in AdMob (banners, post-export
interstitial capped 1/10min, rewarded unlocks) with UMP consent and
PRO remove-ads (Play Billing + manual MASR codes for Tunisia).
Opt-in cloud AI explanations (redacted summaries, notes never leave
the device, offline fallback) + on-device smart-categorize.
Privacy & Ads settings hub, full ar/fr/en + RTL throughout.

Changed: `INTERNET`/`ACCESS_NETWORK_STATE`/`AD_ID` permissions for
ads/AI opt-in only (core finance still offline); privacy policy
rewritten for opt-in posture. No schema change (DB v8, codec v8).

### Résumé (fr)

- BI approfondie (YoY, saisonnalité, prévision récurrente, anomalies,
  simulateur), pubs AdMob opt-in + PRO, IA explicative opt-in,
  ar/fr/en + RTL. Base v8 inchangée.

### ملخص (ar)

- تحليلات أعمق (مقارنة سنوية، توقع واعٍ بالمتكررات، شذوذ، محاكاة)،
  إعلانات opt-in مع PRO، شرح ذكي opt-in، عربي/فرنسي/إنجليزي. قاعدة v8.

### [1.1.0+2], 2026-09-09

Added: Today-first Transactions home; Analytics dashboard (KPIs,
filters, forecast, trends, drill-down, health score, insights);
wallet cards + statistics + hidden-balance gates; Mizania
(category budgets, guidance, rollover, copy-last-month);
category hierarchy + icon registry; recurring, debts, savings;
templates; CSV import with undo; app lock (PIN + biometrics);
notifications; home + savings widgets; split transactions;
multi-currency display; PDF/CSV exports; auto-backup, backup nag,
duplicate warning, data-health tools. Design: light-first petrol
theme, Plex Sans, dark mode, full ar/fr/en + RTL.

Changed: 3-slot navigation, 2-step onboarding, database v1 → v8,
backup codec v1 → v8 (old backups restore cleanly).

### Résumé (fr)

- Accueil Aujourd'hui, tableau analytique (KPI, filtres, prévision,
  drill-down, score santé), portefeuilles masquables, Mizania avec
  budgets par catégorie, hiérarchie, récurrences, dettes, objectifs,
  verrouillage, notifications, widgets, import CSV avec annulation,
  export PDF/CSV, sauvegarde auto. Base v8, ar/fr/en + RTL.

### ملخص (ar)

- رئيسية اليوم أولا، لوحة تحليلات (مؤشرات، فلاتر، توقع، تعمق،
  نقاط الصحة)، محافظ قابلة للإخفاء، ميزانية بأقسام، تسلسل هرمي،
  متكررات، ديون، أهداف ادخار، قفل، إشعارات، ودجت، استيراد CSV مع
  تراجع، تصدير PDF/CSV، نسخ تلقائي. قاعدة v8، عربي/فرنسي/إنجليزي.

### [1.0.0+1]: MVP baseline

- Offline-first wallets, transactions, categories, budgets, reports.
- JSON backup, CSV export, onboarding, settings, ar/fr/en + RTL.

## 9. Roadmap (post-1.2, direction, no commitments)

- On-device visual QA matrix on real hardware; signed release AAB
  + Play Console internal testing.
- Cloud backup/sync with end-to-end encryption (see
  `docs/cloud_receipts_options.md`), receipt capture, family
  budgets, bank integrations where officially supported.
- Explicit non-goals for now: AI financial advice (BI snapshots
  are the designed interface for it later), OCR, Glance widgets.
