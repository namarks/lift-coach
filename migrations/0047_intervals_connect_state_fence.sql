-- A disconnect/replacement cancels pending OAuth connect intents atomically.
-- Already-consumed callbacks compare the generation captured at consumption.
CREATE TRIGGER intervals_cancel_pending_connect
AFTER UPDATE OF intervals_credential_generation ON users
WHEN NEW.intervals_credential_generation != OLD.intervals_credential_generation
BEGIN
  DELETE FROM intervals_oauth_states WHERE user_id = NEW.id;
END;
