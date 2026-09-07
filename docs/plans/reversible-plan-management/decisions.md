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
`0041_oauth_grant_families.sql`, then deploy the reviewed compatible Worker.
Do not assume earlier storage migrations are already applied. These migrations
are required before this Worker reads the new columns/tables. TestFlight is a
separate release of the reviewed app after the service is available.

Keep a snapshot/lineage-aware rollback Worker or choose a forward fix. An older
Worker may tolerate additive columns but cannot preserve the new atomic
snapshot or refresh-lineage guarantees. Schema compatibility alone is not a
safe rollback proof. Do not delete snapshots or invalidate grants as a rollback
shortcut. Coach inactivity/absolute lifetimes, legacy transition and any
production invalidation remain an explicit owner decision.
