# Release audit — 2026-09-10

Dated evidence, not live completion status. See [plan.md](plan.md). Re-read
production and App Store Connect before any release action. No personal
training records, secret values, or account exports were queried for this audit.

## Repository foundations

[PR #171](https://github.com/namarks/tres-fort/pull/171) merged at
2026-09-10 15:13:52 UTC as `95f90307deaf4993a2cadc4546480933d785a048`.
Codex's independent review completed at the exact head
`3629ab656ba6b99d8a852d8fdf8473e71480431b`, with a positive review reaction and
zero review threads. [CI run 34491716466](https://github.com/namarks/tres-fort/actions/runs/34491716466)
passed every backend, plan and iOS check. Reviewed and merged trees both equal
`122d8e9c537ad7e3fb15d2512b419432d2ae9a4c`.

## Production readback

- Latest deployment: `7217b618-148d-4c8c-9200-1ee5ba15a4fe`, created
  2026-09-09 17:57:39 UTC, serving version
  `c5a298d1-a72a-4fa8-a24f-bd2cf0e27a6b` at 100%.
- Version annotation identifies source
  `ff512825779f90b630a4a5dfd11a68e6a113825a`, tree
  `0f3621b3132ff27e659d7554a72bc96010973f8b`, tag `workout-rename-a`.
  This is provider metadata; it does not replace a final exact-source deployment
  and device verification for the App Store candidate.
- Binding names confirm Apple signing configuration, `OWNER_APPLE_SUB` and
  the expected database/integration bindings are present. `DEV_AUTH_SECRET`
  is absent. Secret values were not displayed or recorded.
- The annotated source's `/auth/apple` path permits new ordinary accounts with
  zero memberships. `OWNER_APPLE_SUB` anchors the owner bootstrap; it does not
  restrict ordinary sign-in to the owner. Fresh-user behavior still needs
  final physical-device verification.
- A SELECT-only query of `d1_migrations` returned 45 applied migrations,
  through `0045_workouts.sql`. The query reported `changed_db=false`, zero
  rows written. `0046_activity_source_time.sql` and
  `0047_intervals_connect_state_fence.sql` are present in source but not in
  that ledger. Neither migration nor deployment was run.
- Wrangler 4.92.0's `d1 migrations list` internally runs
  `CREATE TABLE IF NOT EXISTS`; it was not used against production. The audit
  used an explicit SELECT to preserve its read-only boundary.

## Privacy and account paths

The source audit traced `DELETE /api/me` through the transactional account
cleanup and its idempotency receipt. Recent authentication is required for a
new deletion. Apple token revocation precedes final cleanup; provider failure
produces an explicit manual Apple-revocation handoff. Shared groups transfer
to a remaining member. Account-owned training, snapshots, credentials and
authorizations are removed; minimal receipts/owner suppression remain as the
policy discloses. The iOS client clears the originating account's namespace
only after acknowledgement or typed authenticated absence, preserving another
account that became current during the request. Existing behavioral coverage
passed in the P0 full backend and iOS unit runs.

`GET /api/me/export` uses the authenticated principal, one D1 batch snapshot,
credential/invite-capability exclusion and `Cache-Control: no-store`. Its iOS
handoff rejects a result after the account changes. Export data is held in
memory until the user chooses a destination through the document exporter.

Speech code requires on-device recognition and does not fall back to server
recognition. Its audio buffers are not written to an app audio file. A real
device/language-model and permission-denial test remains necessary.

The current storage audit found personal training blobs in `StateSnapshotStore`,
set/activity/correction/terminal outboxes and runner recovery preferences.
HealthKit anchors and Intervals connection metadata also need to be included
in the migration/account-cleanup analysis. The new storage utility is only a
prototype until these call sites preserve failure handling and recovery.

Cloudflare observability is enabled in repository configuration. Most explicit
service logs are aggregate or error-type-only; the global unhandled-error
handler still logs the raw error. Provider request-log fields and retention
remain unverified. App Privacy diagnostic classifications are not finalized.

## Public URLs

Read-only HTTPS requests to `https://tresfort.app/` and
`https://tresfort.app/privacy` returned HTTP 403 from this environment.
This does not distinguish public-site restrictions from the execution
environment's network behavior. Successful public access to the marketing,
support and privacy pages remains unverified.
