-- P0-2: Add identity key support for public key authentication
-- Adds Ed25519 identity public key and key versioning

-- Add identity public key column (Ed25519, Base64-encoded 32 bytes)
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS identity_pubk TEXT;

-- Add key version for rotation support
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS key_version INTEGER DEFAULT 1;

-- Add timestamp when key was last signed
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS key_signed_at TIMESTAMPTZ;

-- Add index for efficient key lookups
CREATE INDEX IF NOT EXISTS idx_users_identity_pubk 
  ON users(identity_pubk) 
  WHERE identity_pubk IS NOT NULL;

-- Add comment documenting the purpose
COMMENT ON COLUMN users.identity_pubk IS 'Ed25519 identity public key for signing X25519 keys (P0-2)';
COMMENT ON COLUMN users.key_version IS 'Public key version for rotation support (P0-2)';
COMMENT ON COLUMN users.key_signed_at IS 'Timestamp when current key was signed (P0-2)';
