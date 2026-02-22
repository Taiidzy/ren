ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS is_delivered BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_messages_is_delivered
  ON messages(chat_id, is_delivered)
  WHERE is_delivered = FALSE;
