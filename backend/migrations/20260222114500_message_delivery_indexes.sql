CREATE INDEX IF NOT EXISTS idx_messages_chat_id_desc_not_deleted
  ON messages(chat_id, id DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_messages_chat_sender_id_desc_not_deleted
  ON messages(chat_id, sender_id, id DESC)
  WHERE deleted_at IS NULL;
