# Release checklist (prepare only: do NOT publish without authorization)

- [x] applicationId `com.masroufi.app`, version 1.4.2+10
- [x] Original icon + splash, brand green #0E7C5B
- [x] Debug APK builds; release AAB builds with local keystore
      (`.tooling/keystore/masroufi-release.jks`, git-ignored; `android/key.properties`
      git-ignored). Keys NEVER committed.
- [x] Permissions audit: INTERNET + ACCESS_NETWORK_STATE + AD_ID for automatic ads / opt-in AI; core finance verified offline in airplane mode (verify in manifest)
- [x] Listings EN/FR/AR written (title ≤30, short ≤80, PRO + dark-gated theme claims)
- [x] Privacy policy finalized (store/privacy-policy.md, v1.3 automatic-ads posture)
- [ ] AdMob: App ID `ca-app-pub-...` set via ADS_APP_ID, 4 units (2 banners, interstitial, rewarded) created; test IDs in debug, real IDs via --dart-define
- [ ] PRO_SECRET + PRO_PIN exported at release build; UMP consent tested (EU flow), PRO purchase + restore tested, manual MASR- code tested per device
- [ ] AI proxy deployed (AI_PROXY_URL), quota 20/mo free / unlimited PRO, no prompt logging verified
- [ ] Screenshots: capture per required sizes when a Play Console account exists
      (phone 16:9/9:16 min 2, 7-inch tablet, feature graphic 1024x500).
      Queries from QA: Arabic dark dashboard verified on emulator.
- [ ] Create Play Console app record, upload SIGNED AAB to internal testing
- [ ] Content rating questionnaire, target audience, data safety form
       (declare: Device IDs (Ad ID by Google SDK), App interactions for automatic ads, AI summaries (opt-in, totals only): matches policy)
- [ ] Screenshots must show banner slot + consent + PRO page (ar/fr/en)
- [ ] Rollout only after explicit authorization
