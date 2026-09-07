CREATE TABLE oauth_grant_lifecycle_policy (
  id               INTEGER PRIMARY KEY CHECK (id = 1),
  activated_at     INTEGER CHECK (
    activated_at IS NULL OR (typeof(activated_at) = 'integer' AND activated_at > 0)
  ),
  activation_nonce TEXT CHECK (
    activation_nonce IS NULL OR length(activation_nonce) > 0
  ),
  CHECK (
    (activated_at IS NULL AND activation_nonce IS NULL)
    OR (activated_at IS NOT NULL AND activation_nonce IS NOT NULL)
  )
);

-- Shipping the schema does not activate the policy. Activation is a separate,
-- explicitly authorized administrative operation through the db.ts helper.
INSERT INTO oauth_grant_lifecycle_policy (id, activated_at, activation_nonce)
VALUES (1, NULL, NULL);

-- A single conditional UPDATE is the complete activation operation. SQLite
-- runs this trigger in the same transaction, so policy activation cannot
-- commit without initializing every existing live grant.
CREATE TRIGGER oauth_grant_lifecycle_activation_preflight
BEFORE UPDATE OF activated_at ON oauth_grant_lifecycle_policy
WHEN OLD.activated_at IS NULL AND NEW.activated_at IS NOT NULL
 AND EXISTS (
       SELECT 1 FROM oauth_grants
        WHERE revoked_at IS NULL
          AND (inactivity_expires_at IS NOT NULL OR absolute_expires_at IS NOT NULL)
     )
BEGIN
  SELECT RAISE(ABORT, 'oauth_grant_lifecycle_policy found unexpected deadlines');
END;

CREATE TRIGGER oauth_grant_lifecycle_activate
AFTER UPDATE OF activated_at ON oauth_grant_lifecycle_policy
WHEN OLD.activated_at IS NULL AND NEW.activated_at IS NOT NULL
BEGIN
  UPDATE oauth_grants
     SET inactivity_expires_at = NEW.activated_at + 7776000000,
         absolute_expires_at = NEW.activated_at + 31536000000
   WHERE revoked_at IS NULL
     AND inactivity_expires_at IS NULL
     AND absolute_expires_at IS NULL;
END;

CREATE TRIGGER oauth_grant_lifecycle_no_delete
BEFORE DELETE ON oauth_grant_lifecycle_policy
BEGIN
  SELECT RAISE(ABORT, 'oauth_grant_lifecycle_policy cannot be deleted');
END;

CREATE TRIGGER oauth_grant_lifecycle_monotonic
BEFORE UPDATE ON oauth_grant_lifecycle_policy
WHEN NEW.id <> 1
  OR (OLD.activated_at IS NOT NULL AND
      (NEW.activated_at IS NOT OLD.activated_at
       OR NEW.activation_nonce IS NOT OLD.activation_nonce))
BEGIN
  SELECT RAISE(ABORT, 'oauth_grant_lifecycle_policy is monotonic');
END;
