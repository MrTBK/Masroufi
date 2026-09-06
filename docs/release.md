# Release

- `applicationId: com.masroufi.app`, app name from `brand.dart` ("Masroufi").
- `minSdk/targetSdk/compileSdk` follow Flutter stable (`flutter.*Version`).
- Permissions: none extra for MVP (offline; storage via system picker only).
  No `INTERNET` needed for core flows.
- Signing: deferred — release builds use debug signing until a real keystore is
  provided. `android/key.properties` + `*.jks` are git-ignored and never committed.
- Builds: `flutter build apk --debug` (QA), `flutter build appbundle --release`.
- Store metadata/screenshots/privacy policy: prepared at release time, not
  auto-published.
