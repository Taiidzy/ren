DROP INDEX IF EXISTS idx_auth_sessions_sdk_fingerprint;

ALTER TABLE auth_sessions
DROP COLUMN IF EXISTS sdk_fingerprint;
