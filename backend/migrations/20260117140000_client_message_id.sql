-- Add client_message_id to support idempotency/deduplication for realtime sends

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS client_message_id TEXT;

CREATE INDEX IF NOT EXISTS idx_messages_client_message_id
ON messages(chat_id, sender_id, client_message_id);
