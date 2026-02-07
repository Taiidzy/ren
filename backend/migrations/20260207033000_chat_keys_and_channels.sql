-- Add migration script here

-- Chats: key versioning and channel metadata
ALTER TABLE chats
  ADD COLUMN IF NOT EXISTS key_version INTEGER NOT NULL DEFAULT 0;

ALTER TABLE chats
  ADD COLUMN IF NOT EXISTS channel_owner_id INTEGER REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE chats
  ADD COLUMN IF NOT EXISTS channel_is_public BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE chats
  ADD COLUMN IF NOT EXISTS channel_username TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_chats_channel_username
  ON chats(channel_username)
  WHERE kind = 'channel' AND channel_username IS NOT NULL;

-- Messages: store key_version used for encryption (group/channel)
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS key_version INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_messages_chat_key_version
  ON messages(chat_id, key_version);

-- Encrypted delivery of per-chat symmetric keys (group rotation / channel static key)
CREATE TABLE IF NOT EXISTS chat_keys (
  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  key_version INTEGER NOT NULL,
  envelopes JSONB NOT NULL, -- {"user_id": {"key": "...", "ephem_pub_key": "...", "iv": "..."}}
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (chat_id, key_version)
);

CREATE INDEX IF NOT EXISTS idx_chat_keys_chat_created
  ON chat_keys(chat_id, created_at DESC);

-- Channel posts: store messages that are posted 'as channel' (sender_id = channel_owner/admin)
-- We keep using the existing messages table for delivery; enforcement is done at application layer.
