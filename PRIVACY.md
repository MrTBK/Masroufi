# Masroufi Privacy Policy (v1.3: BI + automatic ads + opt-in AI)

Masroufi is an offline-first personal finance app. Your ledger stays
on your device. Core finance (wallets, transactions, budgets, reports,
backup) works in airplane mode with no account.

- **No account.** Core features work without registration.
- **Local ledger.** Transactions, wallets, budgets, and settings are
  stored in an on-device SQLite database. Balances are derived, never
  uploaded.
- **Backups/exports you create** (JSON backup, CSV) are files you choose
  to share or keep. The app only writes them to your device and opens
  the system share sheet at your request.
- **Ads (automatic, Google AdMob).** Banners and occasional
  post-success interstitials load when you are online; no tap needed.
  The Settings switch tunes personalization only, and Google shows
  its consent form where the law requires it. Google may collect
  your Advertising ID, approximate app interactions, and performance
  diagnostics to show ads. Finance never depends on ads; banners
  collapse offline. See https://policies.google.com/privacy.
   PRO remove-ads disables all ad requests.
- **Static promos (donate page).** The advertise-here card and any
  future paid placements ship inside the app: no SDK, no tracking,
  no data leaves the device. Tapping copy only fills your clipboard.
- **Cloud AI explanations (opt-in).** Off by default. When you enable
  it and tap "Explain", the app sends a redacted summary (period
  totals, top categories by name, forecast: int millimes) to our
  proxy, which forwards it to an LLM and returns plain-language text.
  Notes and payees NEVER leave the device unless you explicitly enable
  "include notes" (default off). No auto-sending, 15s timeout, no
  prompt logging. AI explains on-device numbers only; planning aid,
  not professional financial advice.
- **Permissions:** `INTERNET` + `ACCESS_NETWORK_STATE` are used ONLY
  for ads / AI-explain. `AD_ID` is used by AdMob (personalized only
  with consent). `USE_BIOMETRIC` for app lock, `POST_NOTIFICATIONS`
  for the optional digest. File access uses the system picker only.
  Camera, contacts, location, microphone are never requested.
- **Children:** general finance tool, no age-gated content, no accounts.

Contact for privacy questions: provided at release time.
