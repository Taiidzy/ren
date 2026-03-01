-- Signal protocol bundle fields for native E2EE bootstrap
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS signed_pre_key_id INTEGER,
  ADD COLUMN IF NOT EXISTS signed_pre_key TEXT,
  ADD COLUMN IF NOT EXISTS signed_pre_key_signature TEXT,
  ADD COLUMN IF NOT EXISTS kyber_pre_key_id INTEGER,
  ADD COLUMN IF NOT EXISTS kyber_pre_key TEXT,
  ADD COLUMN IF NOT EXISTS kyber_pre_key_signature TEXT,
  ADD COLUMN IF NOT EXISTS one_time_pre_keys JSONB,
  ADD COLUMN IF NOT EXISTS one_time_pre_keys_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN users.signed_pre_key_id IS 'Signal signed pre-key id';
COMMENT ON COLUMN users.signed_pre_key IS 'Signal signed pre-key public key (base64)';
COMMENT ON COLUMN users.signed_pre_key_signature IS 'Signal signed pre-key signature (base64)';
COMMENT ON COLUMN users.kyber_pre_key_id IS 'Signal kyber pre-key id';
COMMENT ON COLUMN users.kyber_pre_key IS 'Signal kyber pre-key public key (base64)';
COMMENT ON COLUMN users.kyber_pre_key_signature IS 'Signal kyber pre-key signature (base64)';
COMMENT ON COLUMN users.one_time_pre_keys IS 'Signal one-time pre-keys pool JSON';
COMMENT ON COLUMN users.one_time_pre_keys_updated_at IS 'Timestamp when one-time pre-keys were last refreshed';
