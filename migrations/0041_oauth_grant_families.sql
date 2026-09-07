-- OAuth refresh-token family lineage and caller-scoped revocation.
-- Lifetime columns intentionally remain NULL: activating inactivity or absolute
-- expiry is a separate owner policy and production-transition decision.

ALTER TABLE oauth_tokens ADD COLUMN grant_id TEXT;

UPDATE oauth_tokens
   SET grant_id = lower(hex(randomblob(16)))
 WHERE grant_id IS NULL;

CREATE TABLE oauth_grants (
  id                    TEXT PRIMARY KEY,
  user_id               TEXT,
  client_id             TEXT NOT NULL,
  scope                 TEXT,
  created_at            INTEGER NOT NULL,
  last_refreshed_at     INTEGER,
  revoked_at            INTEGER,
  inactivity_expires_at INTEGER,
  absolute_expires_at   INTEGER,
  legacy                INTEGER NOT NULL DEFAULT 0 CHECK (legacy IN (0, 1))
);

INSERT INTO oauth_grants
  (id, user_id, client_id, scope, created_at, last_refreshed_at, legacy)
SELECT grant_id, user_id, client_id, scope, created_at, created_at, 1
  FROM oauth_tokens;

CREATE TABLE oauth_refresh_history (
  token_sha256 TEXT PRIMARY KEY,
  grant_id     TEXT NOT NULL REFERENCES oauth_grants(id) ON DELETE CASCADE,
  client_id    TEXT NOT NULL,
  consumed_at  INTEGER NOT NULL
);

CREATE UNIQUE INDEX ix_oauth_tokens_grant
  ON oauth_tokens(grant_id) WHERE grant_id IS NOT NULL;
CREATE INDEX ix_oauth_grants_user
  ON oauth_grants(user_id, revoked_at, created_at);
CREATE INDEX ix_oauth_refresh_history_grant
  ON oauth_refresh_history(grant_id);
