-- Keep source instants distinct from the existing civil-time ordering proxy.
-- Old clients/rows leave these unknown; never infer UTC from a wall clock.
ALTER TABLE external_activities ADD COLUMN start_date_utc_ms INTEGER;
ALTER TABLE external_activities ADD COLUMN source_timezone TEXT;
CREATE INDEX ix_sessions_completed_start
  ON sessions(user_id, started_at) WHERE status = 'completed';
CREATE INDEX ix_external_activity_match
  ON external_activities(user_id, source, kind, start_date_local_ms)
  WHERE deleted_at IS NULL;
