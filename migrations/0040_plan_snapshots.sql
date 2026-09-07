CREATE TABLE plan_snapshots (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id),
  plan_id    TEXT NOT NULL REFERENCES plans(id),
  version    INTEGER NOT NULL,
  document   TEXT NOT NULL,
  actor      TEXT NOT NULL,
  operation  TEXT NOT NULL,
  reason     TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE(plan_id, version)
);

CREATE INDEX ix_plan_snapshots_user_plan_version
  ON plan_snapshots(user_id, plan_id, version DESC);
