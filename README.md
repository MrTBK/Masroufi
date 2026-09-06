# Masroufi (مصروفي) — Tunisian Personal Finance, MVP v1.0

Offline-first, private, Arabic/ French/ English personal finance app for Tunisia.
Branding is centralized in `lib/core/config/brand.dart` so the name can change easily.

## Status

MVP in progress. See `MASROUFI_MASTER_TASKS.txt` (single source of truth).

## Money model (critical)

- TND with millimes. All balances computed in **integer millimes** (`int`), never `double`.
- `10.500 TND` = `10500` millimes internally. Formatting helper: `lib/core/money/money.dart`.
- Display e.g. `10.500 د.ت`.

## Tech

- Flutter 3.47 / Dart 3.13, Material 3, Riverpod, go_router, Drift + SQLite.
- Fully offline. No account, no backend for MVP.
- `applicationId: com.masroufi.app`

## Toolchain (this machine)

- Flutter: `~/flutter` (stable), JDK 17: `~/jdk17`, Android SDK: `~/Android/Sdk`
- `export PATH="$HOME/flutter/bin:$HOME/jdk17/bin:$PATH" JAVA_HOME="$HOME/jdk17" ANDROID_HOME="$HOME/Android/Sdk"`

## Commands

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter build apk --debug
flutter build appbundle --release
```

Signing: deferred for MVP (unsigned release AAB). Never commit keys (`android/key.properties`, `*.jks` are git-ignored).

## Docs

- `docs/architecture.md`, `docs/database.md`, `docs/localization.md`
- `docs/testing.md`, `docs/release.md`, `docs/product.md`
