ALTER TABLE users
  ADD COLUMN IF NOT EXISTS signal_state_backup TEXT,
  ADD COLUMN IF NOT EXISTS signal_state_backup_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN users.signal_state_backup IS 'Encrypted Signal state backup blob (opaque to server)';
COMMENT ON COLUMN users.signal_state_backup_updated_at IS 'Timestamp when encrypted Signal backup was last updated';
