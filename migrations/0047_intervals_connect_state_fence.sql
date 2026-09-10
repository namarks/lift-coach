-- A disconnect/replacement cancels pending OAuth connect intents atomically.
-- Old unbound states remain compatible with the old Worker, but the new
-- callback rejects them and requires a fresh connect attempt.
ALTER TABLE intervals_oauth_states ADD COLUMN credential_generation INTEGER;
-- Already-consumed callbacks compare the generation captured at creation.
CREATE TRIGGER intervals_cancel_pending_connect
AFTER UPDATE OF intervals_credential_generation ON users
WHEN NEW.intervals_credential_generation != OLD.intervals_credential_generation
BEGIN
  DELETE FROM intervals_oauth_states WHERE user_id = NEW.id;
END;
