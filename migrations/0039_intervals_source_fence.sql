-- P4.6: source-bound cutover fence for mixed-version intervals.icu rollouts.
--
-- The legacy Worker knows only users.intervals_athlete_id.  Activation moves
-- that identity into a shadow column and clears the legacy column, so an old
-- invocation can no longer discover a connected user or satisfy an identity
-- predicate.  Generation advancement fences provider responses that were
-- already in flight.  After activation, every protected users-row update must
-- also advance intervals_protocol_write_seq exactly once; old credential
-- writers therefore abort even when they address a user directly by id.
--
-- This is an identity-discovery and D1-mutation fence, not secret erasure.
-- Credential columns remain readable to a legacy invocation, and one that
-- captured an identity before activation can finish its provider call.  The
-- generation move and triggers guarantee that its resulting D1 mutations do
-- not commit after activation.
-- A provider-side OAuth exchange/refresh may therefore complete while its D1
-- store is rejected; rollout preflight must check only whether refresh-token
-- state is present (never read/log its value) and accept reconnect/repair if
-- needed.  Authorized terminal account deletion is also an intentional
-- carve-out: DELETE FROM users still wins and cascades account-owned state.
-- Rolling the Worker back to P4 after activation is safe but intentionally
-- degraded: the legacy code observes no athlete identities and cannot sync.
--
-- Installing this migration is inert.  Activation is the single statement:
--
--   UPDATE intervals_source_fence
--      SET enabled = 1,
--          activated_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000,
--          activated_user_count = (SELECT COUNT(*) FROM users),
--          activated_connected_count = (
--            SELECT COUNT(*) FROM users
--             WHERE intervals_athlete_id IS NOT NULL
--               AND (intervals_api_key IS NOT NULL
--                    OR intervals_oauth_access_token IS NOT NULL)
--          )
--    WHERE singleton = 1 AND enabled = 0;
--
-- The AFTER trigger performs and validates the complete cutover in the same
-- SQLite statement.  Any malformed row, duplicate athlete, or counter
-- exhaustion aborts and rolls back both the user changes and the fence flip.

ALTER TABLE users ADD COLUMN intervals_cutover_athlete_id TEXT;
ALTER TABLE users ADD COLUMN intervals_protocol_write_seq INTEGER NOT NULL DEFAULT 0
  CHECK (intervals_protocol_write_seq BETWEEN 0 AND 9007199254740991);

CREATE TABLE intervals_source_fence (
  singleton    INTEGER PRIMARY KEY CHECK (singleton = 1),
  enabled      INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
  activated_at INTEGER,
  activated_user_count INTEGER,
  activated_connected_count INTEGER,
  CHECK (
    (
      enabled = 0
      AND activated_at IS NULL
      AND activated_user_count IS NULL
      AND activated_connected_count IS NULL
    )
    OR
    (
      enabled = 1
      AND typeof(activated_at) = 'integer'
      AND activated_at >= 0
      AND typeof(activated_user_count) = 'integer'
      AND activated_user_count >= 0
      AND typeof(activated_connected_count) = 'integer'
      AND activated_connected_count >= 0
      AND activated_connected_count <= activated_user_count
    )
  )
);

INSERT INTO intervals_source_fence
  (singleton, enabled, activated_at, activated_user_count, activated_connected_count)
VALUES (1, 0, NULL, NULL, NULL);

-- The same expression is used by every dual-mode athlete lookup.  This index
-- stays useful before and after activation without indexing either sync
-- attempt counter or the monotonically-changing protocol sequence.
CREATE INDEX ix_users_intervals_effective_athlete
  ON users(COALESCE(intervals_cutover_athlete_id, intervals_athlete_id))
  WHERE COALESCE(intervals_cutover_athlete_id, intervals_athlete_id) IS NOT NULL;

CREATE TRIGGER intervals_source_fence_update_shape
BEFORE UPDATE ON intervals_source_fence
WHEN NOT (
  OLD.singleton = 1
  AND NEW.singleton = 1
  AND (
    (
      OLD.enabled = NEW.enabled
      AND OLD.activated_at IS NEW.activated_at
      AND OLD.activated_user_count IS NEW.activated_user_count
      AND OLD.activated_connected_count IS NEW.activated_connected_count
    )
    OR
    (
      OLD.enabled = 0
      AND OLD.activated_at IS NULL
      AND NEW.enabled = 1
      AND typeof(NEW.activated_at) = 'integer'
      AND NEW.activated_at >= 0
      AND NEW.activated_user_count = (SELECT COUNT(*) FROM users)
      AND NEW.activated_connected_count = (
        SELECT COUNT(*) FROM users
         WHERE intervals_athlete_id IS NOT NULL
           AND (intervals_api_key IS NOT NULL
                OR intervals_oauth_access_token IS NOT NULL)
      )
    )
  )
)
BEGIN
  SELECT RAISE(ABORT, 'intervals_source_fence_is_monotonic');
END;

CREATE TRIGGER intervals_source_fence_cannot_be_deleted
BEFORE DELETE ON intervals_source_fence
BEGIN
  SELECT RAISE(ABORT, 'intervals_source_fence_cannot_be_deleted');
END;

CREATE TRIGGER intervals_source_fence_cannot_be_inserted
BEFORE INSERT ON intervals_source_fence
BEGIN
  SELECT RAISE(ABORT, 'intervals_source_fence_cannot_be_inserted');
END;

-- Before activation, the shadow identity and protocol sequence are reserved
-- for the new Worker.  Ordinary P4 updates remain byte-for-byte compatible:
-- they do not mention either column, so their NEW values equal OLD values.
CREATE TRIGGER intervals_source_fence_users_update_inactive
BEFORE UPDATE OF
  intervals_athlete_id,
  intervals_cutover_athlete_id,
  intervals_api_key,
  intervals_oauth_access_token,
  intervals_oauth_refresh_token,
  intervals_oauth_expires_at,
  intervals_auth_error_at,
  intervals_credential_generation,
  intervals_events_synced_at,
  intervals_activities_synced_at,
  intervals_events_sync_attempt,
  intervals_activities_sync_attempt,
  intervals_protocol_write_seq
ON users
WHEN (SELECT enabled FROM intervals_source_fence WHERE singleton = 1) = 0
  AND (
    NEW.intervals_cutover_athlete_id IS NOT NULL
    OR NEW.intervals_protocol_write_seq <> OLD.intervals_protocol_write_seq
    OR typeof(NEW.intervals_credential_generation) <> 'integer'
    OR NEW.intervals_credential_generation < 0
    OR NEW.intervals_credential_generation > 9007199254740991
  )
BEGIN
  SELECT RAISE(ABORT, 'intervals_source_fence_not_active');
END;

-- Schema damage must never silently turn enforcement off.  The row-level
-- monotonic/delete guards make a missing singleton unreachable through normal
-- SQL, but protected writes still fail closed if the invariant is violated.
CREATE TRIGGER intervals_source_fence_users_update_missing
BEFORE UPDATE OF
  intervals_athlete_id,
  intervals_cutover_athlete_id,
  intervals_api_key,
  intervals_oauth_access_token,
  intervals_oauth_refresh_token,
  intervals_oauth_expires_at,
  intervals_auth_error_at,
  intervals_credential_generation,
  intervals_events_synced_at,
  intervals_activities_synced_at,
  intervals_events_sync_attempt,
  intervals_activities_sync_attempt,
  intervals_protocol_write_seq
ON users
WHEN COALESCE(
       (SELECT enabled FROM intervals_source_fence WHERE singleton = 1),
       -1
     ) NOT IN (0, 1)
BEGIN
  SELECT RAISE(ABORT, 'intervals_source_fence_missing');
END;

-- Once enabled, any statement that lists a protected Intervals field must use
-- the shadow identity and consume exactly one protocol sequence number.  This
-- is deliberately an UPDATE-OF trigger: an old direct credential write fails
-- even if it happens to assign values equal to the current row.
CREATE TRIGGER intervals_source_fence_users_update_active
BEFORE UPDATE OF
  intervals_athlete_id,
  intervals_cutover_athlete_id,
  intervals_api_key,
  intervals_oauth_access_token,
  intervals_oauth_refresh_token,
  intervals_oauth_expires_at,
  intervals_auth_error_at,
  intervals_credential_generation,
  intervals_events_synced_at,
  intervals_activities_synced_at,
  intervals_events_sync_attempt,
  intervals_activities_sync_attempt,
  intervals_protocol_write_seq
ON users
WHEN (SELECT enabled FROM intervals_source_fence WHERE singleton = 1) = 1
BEGIN
  SELECT CASE
    WHEN NEW.intervals_athlete_id IS NOT NULL
      THEN RAISE(ABORT, 'intervals_source_fence_legacy_identity_forbidden')
    WHEN typeof(NEW.intervals_protocol_write_seq) <> 'integer'
      OR OLD.intervals_protocol_write_seq >= 9007199254740991
      OR NEW.intervals_protocol_write_seq <> OLD.intervals_protocol_write_seq + 1
      THEN RAISE(ABORT, 'intervals_source_fence_sequence_required')
    WHEN typeof(NEW.intervals_credential_generation) <> 'integer'
      OR NEW.intervals_credential_generation < 0
      OR NEW.intervals_credential_generation > 9007199254740991
      THEN RAISE(ABORT, 'intervals_source_fence_generation_out_of_range')
    WHEN typeof(NEW.intervals_events_sync_attempt) <> 'integer'
      OR typeof(NEW.intervals_activities_sync_attempt) <> 'integer'
      OR NEW.intervals_events_sync_attempt < 0
      OR NEW.intervals_activities_sync_attempt < 0
      OR NEW.intervals_events_sync_attempt > 9007199254740991
      OR NEW.intervals_activities_sync_attempt > 9007199254740991
      OR (
        NEW.intervals_oauth_refresh_token IS NOT NULL
        AND (
          typeof(NEW.intervals_oauth_refresh_token) <> 'text'
          OR length(NEW.intervals_oauth_refresh_token) = 0
        )
      )
      OR (
        NEW.intervals_oauth_expires_at IS NOT NULL
        AND (
          typeof(NEW.intervals_oauth_expires_at) <> 'integer'
          OR NEW.intervals_oauth_expires_at < 0
        )
      )
      OR (
        NEW.intervals_auth_error_at IS NOT NULL
        AND (
          typeof(NEW.intervals_auth_error_at) <> 'integer'
          OR NEW.intervals_auth_error_at < 0
        )
      )
      OR (
        NEW.intervals_events_synced_at IS NOT NULL
        AND (
          typeof(NEW.intervals_events_synced_at) <> 'integer'
          OR NEW.intervals_events_synced_at < 0
        )
      )
      OR (
        NEW.intervals_activities_synced_at IS NOT NULL
        AND (
          typeof(NEW.intervals_activities_synced_at) <> 'integer'
          OR NEW.intervals_activities_synced_at < 0
        )
      )
      THEN RAISE(ABORT, 'intervals_source_fence_invalid_user_shape')
    WHEN NEW.intervals_cutover_athlete_id IS NULL
      AND (
        NEW.intervals_api_key IS NOT NULL
        OR NEW.intervals_oauth_access_token IS NOT NULL
        OR NEW.intervals_oauth_refresh_token IS NOT NULL
        OR NEW.intervals_oauth_expires_at IS NOT NULL
        OR NEW.intervals_events_synced_at IS NOT NULL
        OR NEW.intervals_activities_synced_at IS NOT NULL
        OR NEW.intervals_events_sync_attempt <> 0
        OR NEW.intervals_activities_sync_attempt <> 0
      )
      THEN RAISE(ABORT, 'intervals_source_fence_invalid_user_shape')
    WHEN NEW.intervals_cutover_athlete_id IS NOT NULL
      AND (
        typeof(NEW.intervals_cutover_athlete_id) <> 'text'
        OR length(NEW.intervals_cutover_athlete_id) = 0
        OR (NEW.intervals_api_key IS NULL) = (NEW.intervals_oauth_access_token IS NULL)
        OR (
          NEW.intervals_api_key IS NOT NULL
          AND (
            typeof(NEW.intervals_api_key) <> 'text'
            OR length(NEW.intervals_api_key) = 0
            OR NEW.intervals_oauth_refresh_token IS NOT NULL
            OR NEW.intervals_oauth_expires_at IS NOT NULL
          )
        )
        OR (
          NEW.intervals_oauth_access_token IS NOT NULL
          AND (
            typeof(NEW.intervals_oauth_access_token) <> 'text'
            OR length(NEW.intervals_oauth_access_token) = 0
          )
        )
        OR NEW.intervals_auth_error_at IS NOT NULL
      )
      THEN RAISE(ABORT, 'intervals_source_fence_invalid_user_shape')
    WHEN NEW.intervals_cutover_athlete_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM users other
         WHERE other.id <> NEW.id
           AND COALESCE(
                 other.intervals_cutover_athlete_id,
                 other.intervals_athlete_id
               ) = NEW.intervals_cutover_athlete_id
      )
      THEN RAISE(ABORT, 'intervals_source_fence_duplicate_athlete')
  END;
END;

-- New user rows created after activation must begin disconnected.  Existing
-- account-creation statements omit all of these columns and retain their
-- defaults, while credential attachment remains an explicitly fenced UPDATE.
CREATE TRIGGER intervals_source_fence_users_insert_active
BEFORE INSERT ON users
WHEN (SELECT enabled FROM intervals_source_fence WHERE singleton = 1) = 1
  AND (
    NEW.intervals_athlete_id IS NOT NULL
    OR NEW.intervals_cutover_athlete_id IS NOT NULL
    OR NEW.intervals_api_key IS NOT NULL
    OR NEW.intervals_oauth_access_token IS NOT NULL
    OR NEW.intervals_oauth_refresh_token IS NOT NULL
    OR NEW.intervals_oauth_expires_at IS NOT NULL
    OR NEW.intervals_auth_error_at IS NOT NULL
    OR NEW.intervals_credential_generation <> 0
    OR NEW.intervals_events_synced_at IS NOT NULL
    OR NEW.intervals_activities_synced_at IS NOT NULL
    OR NEW.intervals_events_sync_attempt <> 0
    OR NEW.intervals_activities_sync_attempt <> 0
    OR NEW.intervals_protocol_write_seq <> 0
  )
BEGIN
  SELECT RAISE(ABORT, 'intervals_source_fence_connected_insert_forbidden');
END;

CREATE TRIGGER intervals_source_fence_users_insert_missing
BEFORE INSERT ON users
WHEN COALESCE(
       (SELECT enabled FROM intervals_source_fence WHERE singleton = 1),
       -1
     ) NOT IN (0, 1)
BEGIN
  SELECT RAISE(ABORT, 'intervals_source_fence_missing');
END;

CREATE TRIGGER intervals_source_fence_activate
AFTER UPDATE OF enabled ON intervals_source_fence
WHEN OLD.enabled = 0 AND NEW.enabled = 1
BEGIN
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM users
     WHERE intervals_cutover_athlete_id IS NOT NULL
        OR intervals_protocol_write_seq <> 0
        OR typeof(intervals_credential_generation) <> 'integer'
        OR intervals_credential_generation < 0
        OR intervals_credential_generation > 9007199254740989
        OR typeof(intervals_events_sync_attempt) <> 'integer'
        OR typeof(intervals_activities_sync_attempt) <> 'integer'
        OR intervals_events_sync_attempt < 0
        OR intervals_activities_sync_attempt < 0
        OR intervals_events_sync_attempt > 9007199254740991
        OR intervals_activities_sync_attempt > 9007199254740991
        OR (
          intervals_oauth_refresh_token IS NOT NULL
          AND (
            typeof(intervals_oauth_refresh_token) <> 'text'
            OR length(intervals_oauth_refresh_token) = 0
          )
        )
        OR (
          intervals_oauth_expires_at IS NOT NULL
          AND (
            typeof(intervals_oauth_expires_at) <> 'integer'
            OR intervals_oauth_expires_at < 0
          )
        )
        OR (
          intervals_auth_error_at IS NOT NULL
          AND (
            typeof(intervals_auth_error_at) <> 'integer'
            OR intervals_auth_error_at < 0
          )
        )
        OR (
          intervals_events_synced_at IS NOT NULL
          AND (
            typeof(intervals_events_synced_at) <> 'integer'
            OR intervals_events_synced_at < 0
          )
        )
        OR (
          intervals_activities_synced_at IS NOT NULL
          AND (
            typeof(intervals_activities_synced_at) <> 'integer'
            OR intervals_activities_synced_at < 0
          )
        )
        OR (
          intervals_athlete_id IS NULL
          AND (
            intervals_api_key IS NOT NULL
            OR intervals_oauth_access_token IS NOT NULL
            OR intervals_oauth_refresh_token IS NOT NULL
            OR intervals_oauth_expires_at IS NOT NULL
            OR intervals_events_synced_at IS NOT NULL
            OR intervals_activities_synced_at IS NOT NULL
            OR intervals_events_sync_attempt <> 0
            OR intervals_activities_sync_attempt <> 0
          )
        )
        OR (
          intervals_athlete_id IS NOT NULL
          AND (
            typeof(intervals_athlete_id) <> 'text'
            OR length(intervals_athlete_id) = 0
            OR (intervals_api_key IS NULL) = (intervals_oauth_access_token IS NULL)
            OR (
              intervals_api_key IS NOT NULL
              AND (
                typeof(intervals_api_key) <> 'text'
                OR length(intervals_api_key) = 0
                OR intervals_oauth_refresh_token IS NOT NULL
                OR intervals_oauth_expires_at IS NOT NULL
              )
            )
            OR (
              intervals_oauth_access_token IS NOT NULL
              AND (
                typeof(intervals_oauth_access_token) <> 'text'
                OR length(intervals_oauth_access_token) = 0
              )
            )
            OR intervals_auth_error_at IS NOT NULL
          )
        )
  ) THEN RAISE(ABORT, 'intervals_source_fence_activation_preflight_failed') END;

  SELECT CASE WHEN EXISTS (
    SELECT intervals_athlete_id
      FROM users
     WHERE intervals_athlete_id IS NOT NULL
     GROUP BY intervals_athlete_id
    HAVING COUNT(*) > 1
  ) THEN RAISE(ABORT, 'intervals_source_fence_duplicate_athlete') END;

  UPDATE users
     SET intervals_cutover_athlete_id = intervals_athlete_id,
         intervals_athlete_id = NULL,
         intervals_credential_generation = intervals_credential_generation + 1,
         intervals_events_synced_at = NULL,
         intervals_activities_synced_at = NULL,
         intervals_events_sync_attempt = 0,
         intervals_activities_sync_attempt = 0,
         intervals_protocol_write_seq = intervals_protocol_write_seq + 1;

  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM users
     WHERE intervals_athlete_id IS NOT NULL
        OR intervals_protocol_write_seq <> 1
        OR intervals_events_synced_at IS NOT NULL
        OR intervals_activities_synced_at IS NOT NULL
        OR intervals_events_sync_attempt <> 0
        OR intervals_activities_sync_attempt <> 0
        OR (
          intervals_cutover_athlete_id IS NULL
          AND (
            intervals_api_key IS NOT NULL
            OR intervals_oauth_access_token IS NOT NULL
            OR intervals_oauth_refresh_token IS NOT NULL
            OR intervals_oauth_expires_at IS NOT NULL
          )
        )
  ) THEN RAISE(ABORT, 'intervals_source_fence_activation_postflight_failed') END;

  SELECT CASE
    WHEN (SELECT COUNT(*) FROM users) <> NEW.activated_user_count
      OR (
        SELECT COUNT(*) FROM users
         WHERE intervals_cutover_athlete_id IS NOT NULL
           AND (intervals_api_key IS NOT NULL
                OR intervals_oauth_access_token IS NOT NULL)
      ) <> NEW.activated_connected_count
      THEN RAISE(ABORT, 'intervals_source_fence_activation_count_mismatch')
  END;
END;
