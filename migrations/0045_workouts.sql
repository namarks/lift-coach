-- Release B only: deploy the schema-adaptive release-A Worker BEFORE applying.
-- See docs/plans/workouts-and-multi-session/rollout.md. SQLite updates foreign
-- keys and trigger references; IDs, session attempts and logged values survive.
ALTER TABLE day_templates RENAME TO workouts;
ALTER TABLE template_exercises RENAME COLUMN day_template_id TO workout_id;
ALTER TABLE sessions RENAME COLUMN day_template_id TO workout_id;
DROP INDEX ix_te_day;
CREATE INDEX ix_te_workout ON template_exercises(workout_id, order_index);
