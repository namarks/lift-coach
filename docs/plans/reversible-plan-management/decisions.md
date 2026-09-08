# Reversible plan contract

## 2026-09-07: full documents over the existing plan model

Snapshot schema version 1 stores the plan name and metadata plus ordered days
and exercise prescriptions. It preserves IDs and nullable stored values needed
for restoration. Metadata and progression retain their existing JSON-string
storage representation. Catalog names and other enrichment, user identity,
timestamps and the sync version are excluded from the document; ownership,
version, actor, operation, reason and epoch-ms creation time live on the snapshot
row. SQL serialization occurs inside the mutation transaction. The TypeScript
serializer follows the same writable-field contract and canonical day/slot order.

The first write to an existing plan captures its actual previous version as a
baseline, then its resulting version. A newly created plan has only versions
that were actually committed. History is scoped to the caller's current active
plan. A restore requires both the reviewed plan identity and version, commits a
new version, and records attribution in the same transaction. A replay with the
old expected version conflicts. Restore rejects active workouts, including a
workout that starts after the preliminary read but before the transaction claim.
Historical sets keep their logged values; removed template references are
detached and already-detached references stay detached.

Comparison matches retained IDs first and unambiguous workout labels/names
after a full-plan rebuild. Repeated slots match by exercise, warm-up role and
occurrence. Added/removed workouts include prescriptions. The app pins the
comparison and restore to the reviewed target version, displays actor/reason/
time, and requires a new comparison after conflict. An acknowledged restore
remains acknowledged if the subsequent state refresh fails.

Account export schema version 2 includes snapshot history. Account deletion
removes it with the training data. No pruning or new retention policy is
introduced; storage growth must be assessed from representative documents
before choosing one.

A local synthetic stress fixture with 50 days and 1,000 exercise slots produced
a 315,741-byte document. This measures serialized document bytes, excluding
SQLite row/index overhead, and is not a production usage estimate. Full-document
storage grows with both plan size and accepted mutation count; at that fixture
size, 1,000 versions would contain about 301 MiB of document payload alone.

## Repository verification

The integrated source at `99eee864cff0f6ba8b9e1becd9d83c5cea374a7c` passed
all 723 Workers/D1 tests in 52 files, the five uploader-script checks and the
storage query-plan guard. TypeScript and the shared plan compiler passed. A
Worker dry-run built a 658.34 KiB bundle (155.84 KiB gzip); it did not deploy.
The app built for the iPhone 17 Pro simulator on iOS 26.3 and all 280 iOS unit
tests passed at `5569aa0`; the iOS source is unchanged through the integrated
source above. Build artifacts were removed after verification.

Sol workers implemented the three member slices under Astra orchestration.
Independent reviews crossed authorship boundaries and verified fixes for
refresh replay/revocation races, snapshot/response version mismatches, duplicate
history rows, malformed write inputs and exhausted slot-retry conflicts.
Regression tests cover atomic bootstrap and attribution rollback, deletion
fences, legacy recovery/restore rejection, active-workout restore races and
post-commit acknowledgement. The delivery pull request must retain the final
reviewed head and required CI evidence. These checks establish repository
behavior, not deployed production behavior.

## Release and rollback boundary

Repository delivery does not apply migrations, deploy the Worker, upload
TestFlight, change production prescriptions, or activate a coach lifetime policy.
Those actions need the owner authority recorded in the canonical member plans.

An authorized release must inspect the deployed source and migration ledger,
apply every pending migration in order through `0040_plan_snapshots.sql` and
`0041_oauth_grant_families.sql` and `0042_oauth_grant_lifecycle.sql`, then deploy
the reviewed compatible Worker.
Do not assume earlier storage migrations are already applied. These migrations
are required before this Worker reads the new columns/tables. TestFlight is a
separate release of the reviewed app after the service is available.

Keep a snapshot/lineage-aware rollback Worker or choose a forward fix. An older
Worker may tolerate additive columns but cannot preserve the new atomic
snapshot or refresh-lineage guarantees. Schema compatibility alone is not a
safe rollback proof. Do not delete snapshots or invalidate grants as a rollback
shortcut. Nick approved coach inactivity/absolute lifetimes and the existing-
connection transition; production deployment and one-time clock activation
remain owner release actions. After activation, recovery must also enforce the
approved deadlines. Follow the [shared service release procedure](../completed/coach-access-integrity/release.md).

## 2026-09-07: service released; app and restore canary pending

Nick approved the exact reviewed service source `2e67f93` and migrations through
`0042`. They were applied and deployed, with independent source/schema
verification recorded in the [shared release evidence](../completed/coach-access-integrity/decisions.md).
Health and discovery succeeded; authenticated history remains unexercised because
an existing client was unavailable. No production plan edit or restore occurred.
TestFlight and a concrete edit/restore canary remain separate owner decisions.

The existing Claude Desktop connection subsequently read the current plan and
history successfully before and after coach-policy activation at
2026-09-08 00:06:37 UTC. The returned history was empty, consistent with no
post-upgrade plan mutation; this confirms authenticated reads, not production
snapshot creation or restore behavior. No plan-write canary or TestFlight upload
was performed.

## 2026-09-07: TestFlight authorized; execution availability blocked

Nick requested the TestFlight release and subsequently said to continue. The
initial release candidate was integrated `ceca28273132c8f414291d46f126c2a424711f66`, tree
`7ea802e0745fa34ba586e09930a87aa965c9c3a9`, with iOS subtree
`672ce7d43cc3e30ac7755d288f979fdb3eb0d7a0`. Its iOS source and uploader are
unchanged from independently reviewed PR #139 and the approved service source.
Integrated CI run `34173076884` passed. Fresh Xcode 26.3 iPhone 17 Pro/iOS 26.3
simulator verification passed all 280 iOS tests; the uploader harness passed
all five checks. Those results apply to the pre-fix candidate; the subsequent
acknowledgement correction below changes the iOS source and requires fresh
verification before release. The build-number file is unchanged.

A live App Store Connect query through the standard Fastlane API-key action
confirmed marketing version `0.1.0` had latest upload `31`; `32` was selected
for the release. The existing credential was used through the normal client;
its contents were not inspected or copied. The isolated locked Fastlane bundle
and standard query lane are prepared for the later processing check. Browser
sign-in was unavailable, but the API query succeeded. A host-level read-only
device inventory found a paired iPhone 15 Pro; no device installation or launch
was performed.

Automatic approval review rejected `BUILD_NUMBER=32 npm run ios:testflight`
before process creation because the Codex account had reached its usage limit.
No archive, export, upload, production mutation, or external beta/App Store
submission occurred. This is an execution-availability blocker, not evidence of
a signing or application defect; signing/export remain untested this run. Do
not bypass the rejected execution through another path. The TestFlight approval
persists when execution availability is restored; recheck live build numbering
before resuming. Require affirmative upload success, Apple `VALID`, and the
existing internal testing-group assignment before claiming release completion.

TestFlight alone does not complete either trust plan. A proposed production
canary changes only an approved existing slot's cue temporarily, verifies
invalid-prescription rejection and cross-client history, then restores the
baseline as a new version and checks stale-version rejection. The concrete
slot/value and production requests remain unapproved; no legacy repair is
authorized. The canary must preserve concurrent changes and stop on uncertain
acknowledgment or account/workout state.


## 2026-09-07: preserve acknowledged target edits after refresh failure

A local adversarial review found that `updateSlot` returned failure after a
successful PATCH when the following state read failed. The still-open target
form could resend its stale fields without an expected version, adding duplicate
history or overwriting an intervening coach change. This behavior predates the
trust implementation; Nick approved its correction before TestFlight.

The PATCH acknowledgement now remains successful when only refresh fails, so
the target form closes. The parent workout editor retains the sync error, offers
a Refresh action that only reads current state, and disables editing stale
values until that refresh succeeds. The lockout is specific to an acknowledged
target edit awaiting fresh state; unrelated errors and rejected PATCH requests
do not activate it. Genuine PATCH failures remain failures, and existing
account/session guards are preserved. Regression coverage requires
one accepted PATCH, a failed refresh, then a successful read of a newer coach
version without a second PATCH. This is an iOS-only correction; the deployed
Worker and production training data are unchanged.

Verification of the corrected candidate passed all four focused target-save
regressions and all 202 `SetOutboxTests`, including compilation of the updated
app UI. Diff hygiene and the plan compiler passed (12 plans, 40 edges, four
initiatives). These are repository checks; signing/export, TestFlight processing,
and the production canary remain separate evidence. The repair must pass fresh
independent exact-head review and required CI before merge and release.


## 2026-09-07: target-save repair merged and TestFlight delivery accepted

PR #143 merged the independently reviewed target-save correction as
`0d3965676c2d709a307cfbcfc16c215054068b4b`. The final reviewed head was
`fd5bfdf5bd87d070ae89f7725a80b91db2a6cb45`; its tree
`c0b26c00ef53e5f19bd4c2fb6607f3f6dd626cdd` exactly matches the fetched merge.
Required PR CI `34175122206` passed, no unresolved review threads remained, and
integration CI `34175427643` subsequently passed. The clean merged source was
used for release, with iOS subtree
`e931b368ff0618c653f425a75a8a8f5f992d98a0`.

The approved release resumed through the normal execution approval path after
a fresh App Store Connect read confirmed build 31 remained the latest upload.
Xcode archive/export succeeded with explicit `BUILD_NUMBER=32`. Archive and IPA
metadata both identify `com.nmarkspdx.tresfort`, marketing version `0.1.0`, build
`32`; app and widget signing metadata identify team `8BA2RY6RCA`. The IPA is
7,063,486 bytes with SHA-256
`165f552ff3cc1bf457231b5a4aef8ca68de232324f6bbae968ee7fa186b3d259`. The artifact
identity and source were independently checked before documenting release.

At 2026-09-07 18:08:07 PDT (2026-09-08 01:08:07 UTC), altool returned
`UPLOAD SUCCEEDED with no errors`, delivery UUID
`93c6d7ee-dfb8-484d-bd33-69c8ab665b58`, and the wrapper exited zero. Upload
acceptance is distinct from terminal processing and internal tester availability.
Local exported-app `codesign --verify --deep --strict` returned
`CSSMERR_TP_NOT_TRUSTED`, so local certificate-chain verification is not claimed.
No signing configuration or signature was changed to bypass that result.
Apple-side processing evidence is required separately.

At 2026-09-07 18:10:44 PDT (2026-09-08 01:10:44 UTC), an independent App Store
Connect read verified build `0.1.0 (32)`, build ID
`93c6d7ee-dfb8-484d-bd33-69c8ab665b58`, `processingState=VALID`, and
`internalBuildState=IN_BETA_TESTING`, assigned to the existing internal Testers
group. Apple records uploadedDate `2026-09-07T18:08:42-07:00`. No group-assignment
change or second upload was needed. This completes internal TestFlight delivery,
not a physical-device install or production canary. No external Beta App Review
or App Store submission occurred.

The prior execution-availability block is resolved for this release. The
production validation/edit/restore canary remains a separate owner decision, and
no training plan or legacy prescription was changed. Release artifacts and
verification scratch paths may be removed after this evidence is retained; the
IPA hash, source identity, delivery ID, and Apple terminal result are the durable
release record.
