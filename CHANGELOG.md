# Changelog — Masroufi (مصروفي)

All notable changes. Format: Keep a Changelog. Money stays integer
millimes; database upgrades are staged with data-preserving migrations.

## [1.1.0+2] — 2026-09-09

### Added
- Today-first Transactions home (spending hero, comparison strip,
  timeline, filter sheet, detail sheets, undo, templates)
- Analytics dashboard (donut, top categories, averages, in/out,
  insights, health facts, calendar, upcoming, month comparison)
- Wallet cards with visibility control, wallet statistics
- Mizania with category budgets, daily guidance, 80% warnings
- Category hierarchy, centralized icon registry, icon picker
- Recurring transactions, debts with partial payments, savings goals
- Transaction templates, CSV import with validation report
- App lock (PIN + biometrics), local notifications, home widget
- RTL-correct money rendering everywhere, full ar/fr/en coverage

### Changed
- 3-slot navigation (Wallets | + | Mizania), onboarding in 2 steps
- Database v1 → v7, backup codec v1 → v7 (old backups restore cleanly)

### Résumé (fr)
- Accueil Aujourd'hui (héros dépenses, comparaisons, timeline, filtres,
  fiches détail, annuler, modèles), tableau analytique, portefeuilles
  masquables, Mizania avec budgets par catégorie, hiérarchie, récurrences,
  dettes, objectifs, verrouillage, notifications, widget, import CSV.

### ملخص (ar)
- رئيسية اليوم أولا (البطل، المقارنات، الخط الزمني، الفلاتر، التفاصيل،
  التراجع، القوالب)، لوحة تحليلات، محافظ قابلة للإخفاء، ميزانية بأقسام،
  تسلسل هرمي، متكررات، ديون، أهداف ادخار، قفل، إشعارات، ودجت، استيراد CSV.

## [1.0.0+1] — MVP baseline

- Offline-first wallets, transactions, categories, budgets, reports
- JSON backup, CSV export, onboarding, settings, ar/fr/en + RTL
- See `MASROUFI_IMPLEMENTATION_LOG.md` §§1–15 for full history.
