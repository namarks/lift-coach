-- Keep the schema-adaptive release-A/B Worker serving during this rollback.
-- This reverses identifiers only; it never deletes or reconstructs history.
ALTER TABLE workouts RENAME TO day_templates;
ALTER TABLE template_exercises RENAME COLUMN workout_id TO day_template_id;
ALTER TABLE sessions RENAME COLUMN workout_id TO day_template_id;
DROP INDEX ix_te_workout;
CREATE INDEX ix_te_day ON template_exercises(day_template_id, order_index);
-- The release runbook owns migration-ledger reconciliation and verification.
