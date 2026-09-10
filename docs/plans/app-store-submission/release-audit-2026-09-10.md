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

The storage audit found personal training blobs in `StateSnapshotStore`,
set/activity/correction/terminal outboxes and runner recovery preferences.
The candidate now routes these blobs, HealthKit anchors, Intervals metadata and
other app-owned encoded local state through `LocalPersistence` and
`ProtectedTrainingStore`. It preserves the released account keys and codecs,
migrates inactive accounts, writes protected/excluded staging files before
atomic replacement, and uses deletion markers to prevent stale preference
resurrection. A legacy-account binding prevents a failed migration from later
transferring old work to a different Apple account.

Failed new set/activity/finish/discard/correction saves stop before sending.
Unreadable durable queues remain preserved, while replaceable corrupt browse
caches can reload. Failed deletion cleanup keeps the receipt and credential so
the same deletion can resume after unlocking or freeing storage, including after
relaunch. A foreground retry handles ordinary protected-data unavailability;
unresolved errors expose a local recovery banner. Final exact-head review/CI
and physical-device proof remain required.

Navigation recovery also preserves unreadable envelopes and invalid encoded
intents. Ordinary removal cannot erase a failed read. Link requests and sheet
dismissals update visible state only after persistence succeeds; onboarding
does not advance after a failed destination save. Storage recovery reloads
AuthModel's saved links and resumes account binding. A failed bind cannot pass
an unbound link to another account. Sign-out requires successful navigation
cleanup; acknowledged account deletion has a separate path that can erase
unreadable bytes while retaining its receipt until cleanup succeeds.

Deletion completion checks the deleted account's cleanup results, so a later
account's failed navigation save cannot retain the deleted account's identifiers.
The legacy ownership marker is removed only after legacy cleanup succeeds.
Stale-workout fallback requests require a durable queue rewrite and a fresh
account/storage check before sending. The final follow-up ran 478 unit tests
with zero failures and one explicit simulator protection skip, plus the ordinary
workout-completion UI journey. All 268 source-manifest entries matched.

The prior remote smoke run connected Intervals but showed empty History. Its
failure report led to a reproducible model-lifecycle defect: constructing an
unused `MainTabView` eagerly created feature models and invalidated an existing
snapshot request. Models now belong to one lazily installed `StateObject`
container. The regression failed before this change; 72 focused unit tests and
12 connection/onboarding/workout UI journeys passed afterward. The final
268-entry source manifest matched. Fresh remote CI and independent review remain
required; the local result does not retroactively clear the earlier CI run.

Disposable metadata recovery includes corrupt plan-change dismissal markers and
Intervals connection mirrors, including legacy mirrors. A failed cleanup retries
after storage becomes writable. Corrupt queues, navigation, runner checkpoints
and Health anchors remain intact. Eager migration also covers the dismissal
marker's app namespace. This follow-up passed 83 focused unit tests and all five
affected UI journeys; the 268-entry iOS source manifest matched.

A failed runner checkpoint save now rejects the change immediately, restoring
the last durable selection, skips, feedback and inputs with an error. Retrying
storage and remounting the feature no longer silently reverses a visible change.
The regression reproduced failures for skips, navigation and edited inputs;
after the fix all 328 affected unit tests and the ordinary workout-completion
UI journey passed. A timed-set start also stops before creating its notification
or Live Activity if its checkpoint cannot be saved. Fresh independent review
and required CI must pass this revision before merging.

Unsigned Release-configuration verification at 17:21:39 UTC built for generic
iOS with version 1.0, minimum iOS 17.0, iPhone-only device family and the widget
extension. The bundled privacy manifest declares UserDefaults reason `CA92.1`;
the synthetic fixture environment switch was absent from the Release executable.
The build used project placeholder 29, which is not reserved or selected for
upload. Its source manifest matched all 268 iOS inputs. Temporary build products
were removed. This was a build check, not an archive, upload, or device test.

Before candidate upload, use a physical iPhone to verify file protection on the
same source, upgrade migration without erasing the install, offline workout
recovery, lock/unlock and foreground retry, and account deletion. Backup exclusion
cannot recover unsynced device-only writes from iCloud. Do not downgrade to a
build that reads only the old preferences while pending work remains; any
rollback candidate must preserve the new protected-storage reader.

Cloudflare service metadata downloaded read-only through Wrangler 4.92.0 at
17:07:31 UTC confirms persisted invocation logs, 100% sampling and URL query
redaction disabled. Tracing is disabled; no export destinations or tail consumers
were returned. This command does not expose Logpush, so that remains unverified.
No request logs were opened, and temporary downloaded source/configuration was
deleted. Intervals callback URLs carry temporary `code` and `state` parameters;
the configuration therefore permits sensitive URL values in retained logs.

The backend diagnostics fix removes raw unexpected error text from application
logs and HTTP/MCP responses. [PR #173](https://github.com/namarks/tres-fort/pull/173)
passed exact-head independent review and all required CI at
`528aa8c7f79d5624c89f9ac4e31a98f1b76afb74`, then merged as
`0f82e0ad045c21a5f0bda0215b9d1b8b07c020f8` with identical tree
`530be6e14b42dd6a50b127031e99e3282bd8f6a9`. TypeScript and all 972 backend
tests passed locally before an 85-test validation-code follow-up; final-head
CI passed all backend shards. It is not deployed and does not sanitize provider-added request
metadata. See the [owner logging-policy proposal](diagnostics-policy-proposal.md).
Cloudflare documents up to seven days for Workers Logs; any historical export
copies require separate verification. Final App Privacy classifications remain
pending. No retention or production setting has been changed.

## Public URLs

Read-only HTTP clients, including a normal-network retry, returned 403 for
`https://tresfort.app/` and `https://tresfort.app/privacy`. A subsequent browser
check on 2026-09-10 successfully rendered both public pages without sign-in.
The marketing page shows the coming-soon state, sample workout screenshots,
privacy navigation and `mailto:nick@tresfort.app` support. The privacy page is
dated September 10, 2026 and visibly covers account/training data, on-device
speech, optional providers, group sharing, export/deletion and support.
Browser reachability and visible links are verified; mailbox delivery was not
tested and the HTTP-client 403 behavior remains distinct.

## Owner-provided App Store Connect readback

The owner's 2026-09-10 phone screenshot of Très Fort's Pricing and Availability
page shows **Add Pricing** and **Set Up Availability**: neither setting was
configured in that view. The owner subsequently confirmed saving the app as
free and available in the United States only. Treat those settings as
owner-confirmed; the existing API key still cannot read them. Signing in on the
phone does not authenticate the agent's browser. The owner deferred checking
App Store agreements; agreement readiness remains pending.
