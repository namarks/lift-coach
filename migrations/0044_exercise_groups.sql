-- Group attributes belong to the versioned slot document. Ordinary slot rest
-- remains intact so ungrouping restores the original prescription.
ALTER TABLE template_exercises ADD COLUMN group_id TEXT;
ALTER TABLE template_exercises ADD COLUMN group_rest_seconds INTEGER;
ALTER TABLE template_exercises ADD COLUMN group_transition_seconds INTEGER;
