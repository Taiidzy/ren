-- Persist explicit key signature for public key authentication.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS key_signature TEXT;

COMMENT ON COLUMN users.key_signature IS 'Signature over current public key material (base64)';
