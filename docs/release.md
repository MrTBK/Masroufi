# Release

- `applicationId: com.masroufi.app`, app name from `brand.dart` ("Masroufi").
- `minSdk/targetSdk/compileSdk` follow Flutter stable (`flutter.*Version`).
- Permissions: none extra for MVP (offline; storage via system picker only).
  No `INTERNET` needed for core flows.
- Signing: local keystore via `android/key.properties` (git-ignored, never
  committed); without it, release builds fall back to debug signing.
- Builds: `flutter build apk --debug` (QA), `flutter build appbundle --release`.
  Prod AdMob IDs, `PRO_SECRET`, and `PRO_PIN` arrive ONLY via env +
  `--dart-define` (see `tool/release_apk.sh`); without them the build
  falls back to Google test ads and disables manual PRO codes.
- GitHub sideload APK: `flutter build apk --release` is broken in this repo
  (generated registrant references the dev-only `integration_test` plugin),
  so derive it instead: `./tool/release_apk.sh <version>` builds the signed
  AAB and converts it to a release-signed universal APK via bundletool.
  CI (`.github/workflows/release.yml`) does the same with debug signing.
- Store metadata/screenshots/privacy policy: prepared at release time, not
  auto-published.
