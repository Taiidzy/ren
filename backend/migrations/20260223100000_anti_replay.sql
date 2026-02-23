-- P1-6: Anti-replay / Idempotency for messages
-- Adds client_message_id for deduplication of client-sent messages

-- Add client_message_id column for idempotency
ALTER TABLE messages 
  ADD COLUMN IF NOT EXISTS client_message_id UUID;

-- Create unique index for deduplication: (chat_id, sender_id, client_message_id)
-- This prevents duplicate messages from being created on replay attacks
CREATE UNIQUE INDEX IF NOT EXISTS uniq_client_msg 
  ON messages(chat_id, sender_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

-- Add index for efficient lookup during idempotency checks
CREATE INDEX IF NOT EXISTS idx_messages_client_id 
  ON messages(client_message_id)
  WHERE client_message_id IS NOT NULL;

-- Add comment documenting the purpose
COMMENT ON COLUMN messages.client_message_id IS 'Client-provided UUID for idempotency (P1-6 anti-replay)';
