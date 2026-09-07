-- P4: per-cache intervals.icu freshness for the webhook-primary cron backstop.
--
-- These timestamps describe the last SUCCESSFUL provider reconcile for each
-- cache. They are deliberately independent: an activity webhook must not make
-- the planned-events cache look fresh (or vice versa). Failed/disabled fetches
-- never advance them. The hourly cron uses them only as a polling skip hint;
-- the reconciled cache rows remain the source of truth for client deltas.
--
-- NULL means the cache has not completed a successful reconcile for the
-- current credential identity and must be polled by the backstop. Credential
-- connect/disconnect paths reset both columns when that identity changes.

ALTER TABLE users ADD COLUMN intervals_credential_generation INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN intervals_events_synced_at INTEGER;
ALTER TABLE users ADD COLUMN intervals_activities_synced_at INTEGER;
