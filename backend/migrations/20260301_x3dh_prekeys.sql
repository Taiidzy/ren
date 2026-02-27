-- P0-4: X3DH PreKeys storage
-- One-Time PreKeys для X3DH key exchange

-- One-Time PreKeys
CREATE TABLE IF NOT EXISTS prekeys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prekey_id INTEGER NOT NULL,
    prekey_public TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    used_at TIMESTAMPTZ,
    UNIQUE(user_id, prekey_id)
);

-- Signed PreKeys
CREATE TABLE IF NOT EXISTS signed_prekeys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prekey_public TEXT NOT NULL,
    signature TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_current BOOLEAN DEFAULT TRUE
);

-- Indexes для производительности
CREATE INDEX IF NOT EXISTS idx_prekeys_user_unused ON prekeys(user_id) WHERE used_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_signed_prekeys_current ON signed_prekeys(user_id, is_current);

-- Comment
COMMENT ON TABLE prekeys IS 'One-Time PreKeys для X3DH key exchange';
COMMENT ON TABLE signed_prekeys IS 'Signed PreKeys для X3DH key exchange';
