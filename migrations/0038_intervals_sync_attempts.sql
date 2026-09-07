-- P4.5: latest-started-wins ordering for same-generation intervals syncs.
--
-- Each reconciled cache owns an independent monotonic attempt counter. A sync
-- atomically claims its cache's next value before provider I/O, then fences all
-- post-fetch writes on that claimed value. The counters are deliberately
-- unindexed and bounded to JavaScript's largest safe integer. Credential
-- identity changes reset both counters while advancing the separate generation
-- fence; counters never wrap within a generation.

ALTER TABLE users ADD COLUMN intervals_events_sync_attempt INTEGER NOT NULL DEFAULT 0
  CHECK (intervals_events_sync_attempt BETWEEN 0 AND 9007199254740991);
ALTER TABLE users ADD COLUMN intervals_activities_sync_attempt INTEGER NOT NULL DEFAULT 0
  CHECK (intervals_activities_sync_attempt BETWEEN 0 AND 9007199254740991);
