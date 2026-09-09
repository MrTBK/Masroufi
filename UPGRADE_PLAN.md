# Masroufi Upgrade Plan — Ship + Features + Safety Net

Status: **IN PROGRESS.** Execute top-to-bottom. After every track:
`flutter analyze` + `flutter test` + emulator matrix green before
continuing. Log each completed track in
`MASROUFI_IMPLEMENTATION_LOG.md` (§21+). Rules: no rewrites, no fake
data, no AI in financial logic, schema changes only with proper Drift
migrations + backup-codec bumps + migration tests.

## Track 1 — Ship readiness (do first)

- [ ] Git hygiene: split dirty paths into logical commits (v6 styling
      → v7 templates → redesign → upgrade); stage only intended files,
      never secrets; end with clean `git status`.
- [ ] Version `1.1.0+2` in `pubspec.yaml` + new `CHANGELOG.md`
      (Keep-a-Changelog; en + short ar/fr summary of everything
      since MVP).
- [ ] Signed release AAB: `android/key.properties` (git-ignored) +
      local keystore + `flutter build appbundle --release`; verify
      install, cold start, backup/restore round-trip on the artifact.
- [ ] Play assets: 6-combo screenshots, feature graphic, listing copy
      en/fr/ar, privacy link, rating questionnaire.
- [ ] Gate: analyze + unit tests + emulator matrix + signed AAB launches.

## Track 2 — PDF monthly export

- [ ] Deps: `pdf` + `printing` (no schema, no permissions).
- [ ] `MonthlyStatementBuilder` (pure, tested): brand header,
      localized month, income/expense/net, top categories, budget vs
      actual, txn count — from existing `AnalyticsRepo` data.
- [ ] Bundle SIL-licensed Arabic font under `assets/`; verify shaping
      + attached minus signs in output.
- [ ] Reports page → Export PDF → share sheet; l10n keys ×3.
- [ ] Tests: builder totals vs fixtures, Arabic bytes present,
      button flow.

## Track 3 — Safety + small follow-ups

- [ ] CSV-import undo (session restore point; document backup-first).
- [ ] Savings↔wallet link decision → implement optional-link
      (default unlinked) or document as designed.
- [ ] Calendar month pager (`calMonthProvider` + chevrons).
- [ ] Template rename + reorder (`rename()` exists; add `move()` + UI).
- [ ] Exact-alarm + boot receiver only on demand.

## Track 4 — Cloud + receipts (research doc only)

- [ ] Write `docs/cloud_receipts_options.md`: backend matrix, E2EE
      requirement, conflict-resolution sketch on stable UUIDs +
      `updatedAt`, ratings. No code commitment.

## Track 5 — Money safety net (no schema)

- [ ] Weekly auto-backup (filename-rotated, keep last 4,
      `auto_backup_at` KV) on app start when stale.
- [ ] Backup-health nag (14+ days, dismissible).
- [ ] Duplicate-expense warning (same wallet+category+amount within
      30 min, warn-only).
- [ ] Data-health tools in Settings → Data (dangling-ref scan from
      no-FK design + safe repair, never delete).
- [ ] Tests for each.

## Track 6 — Budget intelligence (no schema)

- [ ] Projection alerts reusing `partialMonth` run-rate (+ planner rule).
- [ ] Rollover: global opt-in toggle, display-level only.
- [ ] Copy-last-month budgets (idempotent batch upsert).
- [ ] Tests incl. month boundaries.

## Track 7 — Wealth views (no schema)

- [ ] Net-worth trend mini-chart (documented formula, never relabeled).
- [ ] Savings-goal widget variant (same provider + manifest entry).
- [ ] Year-in-review shareable card (`RepaintBoundary`, offline).
- [ ] Tests on data builders, not pixels.

## Track 8 — Everyday power (schema v8)

- [ ] Split transactions: `txn_splits` child table, parent row
      untouched, v8 migration + codec v8 + tests.
- [ ] Multi-currency: manual offline rates in KV + nullable per-txn
      original amount/currency (v8 columns), display-only conversion,
      stale-rate badge.
- [ ] Per-action biometric gate for hidden balances (reuse lock stack).
- [ ] Tests: split-sum invariants, currency math, gate paths.

## Explicit non-goals

AI explanations, family budgets, bank integrations, OCR, Glance —
stay on roadmap, not in this file. No rewrites, no fake data, no new
dashboard sections beyond what exists.
