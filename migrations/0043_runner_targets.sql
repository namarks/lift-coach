-- Original workout intent, captured with the first accepted set in an attempt.
-- Never backfill old sessions from today's mutable plan.
ALTER TABLE sessions ADD COLUMN runner_targets TEXT;
