# Cloud + Receipts Options (Track 4 — research only, no code commitment)

Status: options paper. No backend, no SDK, no schema change in this track.
Offline-first stays the default; anything cloud must preserve it.

## Requirements (non-negotiable)

- E2EE: server never sees plaintext money, notes, or payees. Keys stay on
  device; recovery via user-held recovery phrase only. No analytics/ads.
- Offline-first: reads/writes work without network; sync is background
  merge, never a gate. Conflicts resolve deterministically on device.
- Money safety: integer millimes end-to-end; no float conversion in
  transit; backup codec versioning reused for wire format.
- Tunisia constraints: low bandwidth, French/Arabic UX, no bank APIs
  assumed (see non-goals in UPGRADE_PLAN.md).

## Backend matrix

| Option | E2EE fit | Offline fit | Cost/ops | Verdict |
| --- | --- | --- | --- | --- |
| Self-hosted CouchDB/PouchDB-style | Good (client encrypts docs) | Excellent (built-in replication) | Server to run | Strong candidate for V1.2 pilot |
| Supabase/Postgres + pgcrypto envelope | Good (envelope per row) | Medium (need custom queue) | Managed, low ops | Candidate if managed preferred |
| Firebase Firestore | Weak (server-side rules ≠ E2EE; needs extra envelope) | Good (offline cache) | Vendor lock | Rejected for E2EE posture |
| iCloud/Google Drive file sync (backup file) | Good (encrypted blob) | Good (file-level) | Zero backend | Cheapest: versioned `.json` blob sync |
| Custom Rust/Go sync server | Best (protocol control) | Best (own merge) | High build cost | Long-term only |

Recommendation: start with encrypted-blob backup sync (Drive/iCloud file,
same v7/v8 codec + NaCl box), then graduate to row-level sync if needed.
No commitment in this track.

## Conflict-resolution sketch (stable UUIDs + updatedAt)

Repos already use stable UUID ids + `createdAt`/`updatedAt` on every table
(sync-ready per architecture docs). Merge rule per row:

1. Same `id` → higher `updatedAt` wins for scalar fields (last-writer-wins).
2. Ledger tables (`transactions`, `savings_contributions`, `debt_payments`):
   never update in place across devices — inserts only; deletes are
   tombstones (`{id, deletedAt}`) so a delete never resurrects.
3. Settings/KV (`language`, `hide_balances`, …): LWW per key.
4. Categories/wallets rename vs archive: archive flag merges OR-wise
   (archived wins); rename is LWW; hierarchy `parentId` moves are LWW with
   single-level validation re-run on merge (reject cycles/self-parent).
5. Budgets per (year, month, category): LWW per cell; copy-last-month is
   idempotent so replays are safe.
6. Templates/splits: same as ledger (insert-only + tombstones); split-sum
   invariant re-validated after merge, invalid splits quarantined (never
   auto-delete).

Clock skew: `updatedAt` is device-local; ties break by lexicographically
greater `id` (deterministic, no coordination). All math re-derives from
the merged ledger (balances are derived, never stored).

## Receipts

- Capture: camera/gallery → downscaled JPEG stored app-private (no cloud
  in this track). Optional link `receiptPath` per transaction would be a
  nullable column (future schema bump, not this track).
- OCR: explicitly out of scope (roadmap V2, on-device only if ever).
  No server OCR (would break E2EE).
- Ratings: capture UX ★★★★☆ (4/5 — useful, but storage + permissions
  cost); sync ★★★☆☆ (3/5 — blob sync is enough for most users).

## What is NOT in this track

No code, no SDK, no manifest permissions, no schema change, no network
calls. Next step if approved: encrypted-blob prototype behind a settings
flag, with migration tests reusing `backup_test.dart` fixtures.
