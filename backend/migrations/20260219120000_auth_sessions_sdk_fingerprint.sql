ALTER TABLE auth_sessions
ADD COLUMN IF NOT EXISTS sdk_fingerprint TEXT;

CREATE INDEX IF NOT EXISTS idx_auth_sessions_sdk_fingerprint
ON auth_sessions(sdk_fingerprint);

