# Workout rename rollout

This runbook implements P0's three stages. Repository approval authorizes code,
local verification, review and merge. It does **not** authorize production D1
changes, Worker deployment, or TestFlight distribution. Record their separately
approved source SHA, Worker deployment/version ID, migration result and app build
in `plan.md` when each stage actually runs.

## Local rehearsal

```sh
npm ci
npm run typecheck
npm test
npm run test:workout-rollout
npm run ios:verify -- --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2 --device com.apple.CoreSimulator.SimDeviceType.iPhone-17
```

`test:workout-rollout` creates a temporary config/database with synthetic local
credentials, applies migrations through 0044, starts a local Worker, creates a
workout through the released route, applies 0045 with that Worker still running,
edits through the new route, runs the down-migration, and edits through the old
route. The identity survives and each successful edit advances the plan version
once. It shuts down its Worker and removes its temporary database on exit.
`test/workout_schema.test.ts` additionally covers foreign keys, retained set and
session-alias references, the attempt trigger, atomic-batch rollback, cache
expiry, and non-retryable failures. `test/workout_wire.test.ts` exercises both
client vocabularies against both schemas; snapshot tests restore immutable v1
history without rewriting its bytes.

## A — deploy the adaptive Worker before renaming storage

After release authorization, work from the exact reviewed and verified source.
Inspect current deployment and pending migrations first:

```sh
npx wrangler deployments list
npx wrangler d1 migrations list tres-fort-db --remote
npx wrangler d1 execute tres-fort-db --remote --command 'PRAGMA table_info(sessions)'
```

The existing database must already contain migrations through 0044. If earlier
migrations are pending, stop and resolve their separate release requirements;
this runbook is not permission to apply them. Save the current deployment ID.
Run the preflight and then deploy **without applying 0045**:

```sh
npm run release:preflight
npm run deploy
npx wrangler deployments list
```

Prove the approved source is serving all traffic; no older non-adaptive version
may retain a traffic allocation. Using the owner's existing authenticated
clients, confirm active-plan/state reads, legacy `/api/days` authoring and new
`/api/workouts` authoring on an owner-approved disposable workout, plus both MCP
names. Do not print bearer tokens, copy credentials or use real history as test
data. Save value-free results. A deployment acknowledgement alone is insufficient
proof of the serving version or client behavior.

The first iOS build in this branch reads either vocabulary but deliberately
sends `/api/days` and `day_template_id`. Its Workouts UI can be distributed after
separate TestFlight authorization while the legacy wire contract remains live.

## B — rename the database under the adaptive Worker

Only after A is verified, the production migration is separately authorized,
and the pending migration list contains **only 0045**, record a D1 Time Travel
bookmark using `npx wrangler d1 time-travel info tres-fort-db --json` in a private
release receipt. Then apply the rename directly:

```sh
npx wrangler d1 migrations apply tres-fort-db --remote
npx wrangler d1 execute tres-fort-db --remote --command 'PRAGMA table_info(sessions); PRAGMA foreign_key_check; SELECT name FROM sqlite_master WHERE name IN ("workouts","day_templates","ix_te_workout","ix_te_day")'
```

Expect `workout_id`, the `workouts` table and `ix_te_workout`, no old table/index,
and no foreign-key violations. Verify reads, new/legacy authoring, schedule
membership, a one-date assignment, and set/finish/discard attempt behavior through
approved client checks. Existing workout/slot/session IDs and all logged values
must remain intact. No schedule or plan version changes come from the migration.
The same adaptive Worker remains the supported rollback target.

After the dual-key Worker is proven live, prepare a **later** app build changing
`APIClient.workoutWireFormat`'s default from `.legacy` to `.canonical`, with the
request and UI suites rerun. That reviewed change and its TestFlight distribution
need their own recorded evidence. Never switch an app's outgoing shape merely
because its decoder accepts new fields.

## C — remove compatibility only after the observed client cycle

Keep old routes, request/response keys and `add_day`/`update_day` for at least one
TestFlight compatibility cycle after the canonical-writing build becomes the
minimum supported build. Record that build, minimum-client decision, cycle
start/end and evidence of supported-client use in `plan.md`. Elapsed time alone
is not proof that clients have upgraded.

Then prepare a reviewed cleanup change removing `workoutSchema.ts`, the temporary
release guard, deprecated wire aliases and old MCP registrations. Restore the
normal release commands only once the migrated schema and supported clients are
proven. Keep immutable v1 snapshot readers and old cache/outbox decoders as long
as their persisted data can be encountered. Never rewrite historical audit tool
names. This repository delivery leaves P0(b) and P0(c) open.

## Rollback

Before B, retain the adaptive Worker when rolling back application behavior:
it writes snapshot schema v2, which a pre-A Worker cannot restore. After B,
rolling back to a pre-A Worker also breaks all old physical SQL references.
Choose an approved adaptive source; do not select an arbitrary previous version.

If the schema rename itself must be reverted, obtain explicit production rollback
authority and keep the adaptive Worker serving while running:

```sh
npx wrangler d1 execute tres-fort-db --remote --file docs/plans/workouts-and-multi-session/rollback/0045_workouts.sql
npx wrangler d1 execute tres-fort-db --remote --command 'PRAGMA table_info(sessions); PRAGMA foreign_key_check'
```

The down-migration restores identifiers and the index, leaving identities,
versions, snapshots and history unchanged. Verify both client vocabularies again.
It deliberately does not edit `d1_migrations`; 0045 remains recorded as applied.
For a later reattempt, verify the legacy physical schema and apply the reviewed
forward SQL explicitly with `wrangler d1 execute ... --file
migrations/0045_workouts.sql` under separate authority, or add a reviewed recovery
migration. Do not blindly delete the migration ledger row or rerun the entire
migration history. A Time Travel restore can discard intervening writes and is
an independent destructive decision, not the routine rename rollback.

## Compatibility boundaries

- Service types, SQL and new snapshots use `workouts` / `workout_id`.
- The SQL adapter rewrites identifiers only, caches schema metadata for 60 seconds,
  and retries only a failed statement or failed atomic batch once after a proven
  schema change. It never retries network uncertainty or a whole service write.
- REST/MCP add deprecated aliases at the serialization boundary. Export schema v2
  also retains its historical `training.day_templates` collection. Opaque user
  text, metadata, audit arguments and snapshot documents are unchanged.
- Plan and session caches continue encoding the old vocabulary; durable set and
  terminal intents retain their original `dayTemplateID` key and attempt tokens.
- `template_exercises`, `template_exercise_id`, legacy error codes, `day_label`,
  and historical comparison kind/summary fields remain compatible. A civil
  calendar day and a reusable workout remain separate concepts.
- The schedule is still a weekday-to-workout-ID map. Unschedule clears only that
  workout's recurring entries; dated sessions and the workout remain. Delete
  uses the existing atomic deletion/history rules. Date assignment uses the
  existing attempt-CAS path and rejects past, active/completed and hard-blackout
  dates in the app. There is still one strength session per civil date.

The ordinary `npm run release` and `npm run db:migrate:remote` fail locally during
this window and point here. Their replacement is this explicit, authorized
sequence; neither command performs a remote operation while guarded.
