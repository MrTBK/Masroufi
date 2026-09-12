# Masroufi (مصروفي): Tunisian Personal Finance

[![Latest release](https://img.shields.io/github/v/release/MrTBK/Masroufi)](https://github.com/MrTBK/Masroufi/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-155E75.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter)](https://flutter.dev)

<p align="center">
  <a href="https://github.com/MrTBK/Masroufi/releases/latest/download/masroufi-v1.3.3.apk">
    <img src="https://img.shields.io/badge/⬇_Download-APK_(Android)-155E75?style=for-the-badge&logo=android" alt="Download Masroufi APK" />
  </a>
</p>
<p align="center">
  <a href="https://github.com/MrTBK/Masroufi/releases">All releases & changelog</a>
  ·
  <a href="#build-from-source">Build from source</a>
</p>

Offline-first, private personal finance app for Tunisia in **العربية (RTL)**,
**Français** and **English**. No account, no cloud, no tracking: your money
stays on your device.

> **مصروفي**: تطبيق تونسي بسيط وخاص لإدارة المصاريف بالدينار، يشتغل كامل دون أنترنت.
>
> **Masroufi** : application tunisienne simple et privée pour gérer son argent
> en dinar, 100&nbsp;% hors-ligne.

## Features

- **Today-first home**: spending hero, month in/out, budget bar, upcoming payments, recent transactions, top categories
- **Wallets**: Cash, Bank, Card, Savings + your own; archive, per-wallet balance hiding
- **Expenses / Income / Transfers**: atomic transfers, edit, delete with undo, duplicate, templates
- **Tunisian categories**: Café, Taxi, Louage, STEG, SONEDE, Internet… + custom categories, hierarchy, icon picker
- **Mizania (budgets)**: overall monthly budget + per-category budgets, daily guidance, over-budget warnings
- **Recurring transactions**: daily / weekly / monthly / yearly, auto-generated on launch
- **Debts**: owe / owed-to-me, partial payments, auto-settle
- **Savings goals**: separate ledger with contributions & withdrawals
- **Analytics**: trends, averages, month comparison, insights, calendar, net-worth view
- **Reports**: monthly statement PDF export, CSV export
- **Backup**: versioned local JSON backup + restore (old backups restore cleanly)
- **App lock (PRO)**: PIN + biometrics; global + per-action hidden-balance gates
- **Dark theme (PRO)**: light-first petrol identity, derived dark mode
- **Reminders**: local notifications digest; home-screen widget
- **Support the dev**: D17 + Ba9chich tips, PRO 9.9 DT (Settings)

## Privacy

- No account. Ledger stays on-device; core finance works in airplane mode, see [PRIVACY.md](PRIVACY.md).
- Ads (AdMob) load automatically when online; the Settings switch tunes personalization only. Cloud AI stays opt-in. PRO (9.9 DT) removes ads and unlocks dark theme + app lock.
- Backups/exports are files **you** create and share; the app only writes them to your device.

## Money model (for contributors)

- TND with millimes. All balances are computed in **integer millimes** (`int`), never `double`.
- `10.500 TND` = `10500` millimes internally. Helpers: `lib/core/money/money.dart`, `lib/core/money/calc.dart`.
- Display e.g. `10.500 د.ت`. Amounts always render through `MoneyText` (RTL-safe).

## Tech

- Flutter 3.47 / Dart 3.13, Material 3, Riverpod, go_router, Drift + SQLite.
- Fully offline. `applicationId: com.masroufi.app` (see `lib/core/config/brand.dart`).
- Version: see `pubspec.yaml` + [CHANGELOG.md](CHANGELOG.md).

## Install

1. Tap **Download APK** above (or pick a file from [Releases](https://github.com/MrTBK/Masroufi/releases)).
2. On Android, allow "Install unknown apps" for your browser when asked.
3. Open the APK to install, then launch **Masroufi**.

## Build from source

This repo ships a project-local toolchain under `.tooling/` (never committed except `env.sh`):

```sh
source .tooling/env.sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter build apk --release        # installable APK
flutter build appbundle --release  # Play Store bundle
```

Signing: if `android/key.properties` + your keystore exist, release builds are signed with them; otherwise they fall back to debug signing so any checkout still builds. **Never commit keys** (`android/key.properties`, `*.jks` are git-ignored).

## Project structure

```text
lib/
  app/            # MaterialApp, Riverpod providers
  core/           # brand, l10n (ar/fr/en), money, theme, routing,
                  # analytics, budgets, security (app lock), notify,
                  # backup, export (PDF), fx, safety, wealth, widgets
  data/           # Drift/SQLite database + repositories
  features/       # onboarding, dashboard, transactions, wallets,
                  # categories, budgets, reports, recurring, debts,
                  # savings, backup, settings
test/             # unit + widget tests (275 green)
integration_test/ # on-device QA matrix
docs/             # architecture, database, product, release, testing…
store/            # Play Store listings (en/fr/ar), privacy policy
```

## Docs

- [`docs/product.md`](docs/product.md): scope & upgrade decisions
- [`docs/architecture.md`](docs/architecture.md): UI → Riverpod → Repository → Drift
- [`docs/database.md`](docs/database.md): schema & migrations
- [`docs/localization.md`](docs/localization.md): ar/fr/en conventions
- [`docs/testing.md`](docs/testing.md): test inventory
- [`docs/release.md`](docs/release.md): signing & store notes
- [`docs/cloud_receipts_options.md`](docs/cloud_receipts_options.md): cloud/sync research
- [`store/`](store/): Play listings & release checklist
- [`CHANGELOG.md`](CHANGELOG.md): release history

## Roadmap

- **Next:** signed Play release + internal testing, manual multi-currency display, savings-to-wallet optional link.
- **Later:** cloud backup/sync (E2EE), receipt capture, family budgets, bank integrations where officially supported.

## Contributing

Issues and pull requests are welcome. Please:

1. Keep money math in integer millimes (never `double` for financial logic).
2. Add/extend tests for behavior changes (`flutter test` must stay green).
3. Keep `flutter analyze` clean; run `dart format .`.
4. Schema changes need a Drift migration + backup-codec bump + migration test.
5. No new permissions or network calls for core features without discussion.

## License

[MIT](LICENSE), © 2026 MrTBK.

> Financial figures and estimates shown in the app are planning aids, not professional financial advice.
