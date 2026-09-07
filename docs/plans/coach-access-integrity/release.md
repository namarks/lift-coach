# Training Data Trust service release

This is the reviewable procedure for the owner release gate in the
[coach plan](plan.md) and the other Training Data Trust member plans. It does
not authorize execution. Policy approval covers 90 elapsed days without
successful renewal, a 365-day absolute maximum, and activation grace for existing
authorized connections. TestFlight and a production workout-edit/restore canary
are separate decisions.

## Source and observed starting point

Use a clean isolated checkout of the exact reviewed source approved for this
release. Record its full commit and tree, terminal-green CI and independent
review evidence. A later main commit is not automatically approved.

The read-only preflight on 2026-09-07 around 22:11 UTC found production source
`696c1d34c98d956a3e1fddf78fcfd5eba168e874`, Worker version
`571457ad-322b-4622-a22c-69963b330632`, at 100% in deployment
`5ec35cd3-690f-473b-9a4f-272d2155e273`. The migration ledger was complete through
`0039`, and the Intervals source fence was already active. Existing legacy
owner-bound coach tokens make the `0041` backfill a real transition. Every
preflight SQL result reported `changed_db=false` and `rows_written=0`.
These are historical observations; refresh them immediately before execution.

## Execution after explicit approval

1. Recheck the clean source/tree, reviewed head and required checks. Inspect
   deployment metadata and the complete migration ledger using the installed
   Wrangler version. Stop on an unexpected source, schema or policy state.

   ```sh
   node_modules/.bin/wrangler deployments list --json
   node_modules/.bin/wrangler versions view APPROVED_ACTIVE_VERSION_ID --json
   node_modules/.bin/wrangler d1 execute DB --remote --json --command "SELECT id, name, applied_at FROM d1_migrations ORDER BY id"
   ```

2. From the approved checkout, apply the pending migrations in order:
   `0040_plan_snapshots.sql`, `0041_oauth_grant_families.sql`, then
   `0042_oauth_grant_lifecycle.sql`. Inspect the pending list before applying;
   an additional migration requires review of the changed release scope.

   ```sh
   node_modules/.bin/wrangler d1 migrations list DB --remote
   node_modules/.bin/wrangler d1 migrations apply DB --remote
   ```

   Recheck the ledger, foreign-key integrity and value-free grant counts.
   Confirm the singleton lifecycle row has both activation fields NULL, legacy
   token rows have grant families, and the existing Intervals source fence is
   unchanged. Migrations alone do not start the coach clocks. If a migration
   fails, inspect its acknowledgement and ledger before deciding what remains;
   do not deploy code against an incomplete schema.

3. Deploy the exact reviewed Worker with a source/tree annotation. Replace the
   placeholders with the approved full values; do not use a moving branch name.

   ```sh
   node_modules/.bin/wrangler deploy --message "source APPROVED_COMMIT tree APPROVED_TREE"
   ```

   Verify that the new version is the active 100% deployment and its annotation
   matches. Check `/health` and OAuth discovery, then use an existing authorized
   client through its normal UI for a read-only plan/history request. The
   lifecycle row must still be disabled. Health/discovery alone do not prove
   authenticated data access. If no connected client is available, record the
   smoke as unexercised and stop for owner direction before activation.
   Do not obtain, print, copy or rotate owner credentials to run a smoke test.

4. Once schema, source and read-only smoke checks pass, execute the separately
   approved activation. Generate and retain one nonsecret operation UUID,
   substitute it for `ACTIVATION_UUID`, and use this single conditional UPDATE:

   ```sh
   node_modules/.bin/wrangler d1 execute DB --remote --json --command "UPDATE oauth_grant_lifecycle_policy SET activated_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000, activation_nonce = 'ACTIVATION_UUID' WHERE id = 1 AND activated_at IS NULL RETURNING activated_at, activation_nonce"
   ```

   Migration `0042` initializes existing live grant deadlines in a trigger in
   that same transaction. A failed grant update rolls the activation back.
   A repeat UPDATE cannot restart clocks. If the response is lost or no row is
   returned, read the singleton and compare its nonce with the retained UUID:

   ```sh
   node_modules/.bin/wrangler d1 execute DB --remote --json --command "SELECT activated_at, activation_nonce FROM oauth_grant_lifecycle_policy WHERE id = 1"
   ```

   An already committed matching activation is success. An unexpected nonce or
   state needs investigation; never clear the row or advance the timestamp to
   retry. The TypeScript administrative helper additionally binds retries to
   the original timestamp and nonce. No ordinary REST or MCP route activates
   this policy.

5. Verify the activation timestamp is retained, live grants have both deadlines,
   and no revoked grant was revived. Existing grants receive activation +90/+365
   days; a successful refresh may subsequently advance only inactivity, capped
   by the absolute deadline. Recheck read-only access through the existing
   authorized client. Record source/version, migration ledger, activation and
   smoke outcomes without token or workout contents. Do not simulate future
   expiry by editing production timestamps. Expiry, renewal and rollback-failure
   behavior are exercised in local D1 tests; a natural client renewal supplies
   the later production observation.

## Failure and recovery

Keep the migrations and activation record. Use a reviewed forward fix, or a
previously verified Worker that preserves the active Intervals fence, atomic
snapshots, refresh lineage and coach deadline enforcement. Neither the observed
`696c1d34` Worker nor the first Training Data Trust source `ae295d0a` satisfies all
of those requirements after lifecycle activation. A schema-compatible older
binary is not a sufficient rollback.

Before activation, a failing new Worker leaves the approved clocks unstarted;
diagnose before activating. After activation, do not disable expiry, move its
epoch, revive grants, delete snapshots, restore old tokens or roll back the
database as a recovery shortcut. A corrective deployment that changes the
approved source must pass review and the applicable release authority gate.
Existing app and static-bearer lifecycles remain available under their own
contracts; reconnecting an expired coach grant does not delete training data.
