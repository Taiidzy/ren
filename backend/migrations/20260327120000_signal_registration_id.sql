ALTER TABLE users
  ADD COLUMN IF NOT EXISTS registration_id INT;

COMMENT ON COLUMN users.registration_id IS 'Signal registration id for E2EE';
