-- Add migration script here

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS reply_to_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS forwarded_from_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS forwarded_from_chat_id INTEGER REFERENCES chats(id) ON DELETE SET NULL;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS forwarded_from_sender_id INTEGER REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS deleted_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_message_id);
CREATE INDEX IF NOT EXISTS idx_messages_forwarded_from ON messages(forwarded_from_message_id);
CREATE INDEX IF NOT EXISTS idx_messages_deleted_at ON messages(chat_id, deleted_at);
