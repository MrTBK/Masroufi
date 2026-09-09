# Release checklist (prepare only — do NOT publish without authorization)

- [x] applicationId `com.masroufi.app`, version 1.0.0+1
- [x] Original icon + splash, brand green #0E7C5B
- [x] Debug APK builds; release AAB builds with local keystore
      (`.tooling/keystore/masroufi-release.jks`, git-ignored; `android/key.properties`
      git-ignored). Keys NEVER committed.
- [x] Permissions audit: no INTERNET for core features (verify in manifest)
- [x] Listings EN/FR/AR written (title ≤30, short ≤80)
- [x] Privacy policy finalized (store/privacy-policy.md)
- [ ] Screenshots: capture per required sizes when a Play Console account exists
      (phone 16:9/9:16 min 2, 7-inch tablet, feature graphic 1024x500).
      Queries from QA: Arabic dark dashboard verified on emulator.
- [ ] Create Play Console app record, upload SIGNED AAB to internal testing
- [ ] Content rating questionnaire, target audience, data safety form
      (declare: no data collected, no data shared — matches policy)
- [ ] Rollout only after explicit authorization
