-- P0-4: Double Ratchet Protocol Support
-- Добавляет поддержку protocol_version для сообщений

-- Добавляем колонку protocol_version в messages
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS protocol_version INTEGER DEFAULT 1;

-- Добавляем колонку sender_identity_key для Double Ratchet
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS sender_identity_key TEXT;

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_messages_protocol_version ON messages(protocol_version) WHERE protocol_version = 2;
CREATE INDEX IF NOT EXISTS idx_messages_sender_identity ON messages(sender_identity_key) WHERE sender_identity_key IS NOT NULL;

-- Comment
COMMENT ON COLUMN messages.protocol_version IS 'Версия протокола шифрования: 1=legacy, 2=Double Ratchet';
COMMENT ON COLUMN messages.sender_identity_key IS 'Identity public key отправителя для Double Ratchet (protocol_version=2)';

-- Обновляем существующие сообщения (устанавливаем protocol_version=1 по умолчанию)
UPDATE messages SET protocol_version = 1 WHERE protocol_version IS NULL;
