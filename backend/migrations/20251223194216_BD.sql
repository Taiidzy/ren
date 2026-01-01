-- Add migration script here
-- Add migration script here
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  login TEXT NOT NULL UNIQUE,
  username TEXT NOT NULL UNIQUE,
  avatar TEXT,
  password TEXT NOT NULL,
  pkebymk TEXT,
  pkebyrk TEXT,
  salt TEXT,
  pubk TEXT
);

-- Чаты
CREATE TABLE IF NOT EXISTS chats (
  id SERIAL PRIMARY KEY,
  kind TEXT NOT NULL, -- 'private' | 'group' | other
  title TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_archived BOOLEAN DEFAULT FALSE,
  user_a INTEGER,
  user_b INTEGER
);

-- Участники чатов (ссылаются на users.id, который INTEGER)
CREATE TABLE IF NOT EXISTS chat_participants (
  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  role TEXT DEFAULT 'member', -- 'member','admin', ...
  last_read_message_id INTEGER,
  is_muted BOOLEAN DEFAULT FALSE,
  PRIMARY KEY (chat_id, user_id)
);

-- Сообщения
CREATE TABLE IF NOT EXISTS messages (
  id SERIAL PRIMARY KEY,
  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  message TEXT, -- зашифрованное сообщение (вместо body)
  message_type TEXT DEFAULT 'text', -- 'text' | 'file' | 'image' и т.д.
  edited_at TIMESTAMPTZ,
  is_read BOOLEAN DEFAULT FALSE,
  envelopes JSONB, -- конверты для каждого участника
  metadata JSONB -- метаданные файлов
);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_chat_participant_user ON chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON messages(chat_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_private_pair ON chats(user_a, user_b) WHERE kind = 'private';
CREATE INDEX IF NOT EXISTS idx_messages_is_read ON messages(chat_id, is_read) WHERE is_read = FALSE;

-- Комментарии
COMMENT ON COLUMN users.avatar IS 'Путь к файлу аватара (например, avatars/user_123.jpg) или NULL';
COMMENT ON COLUMN messages.message IS 'Зашифрованное сообщение (E2EE)';
COMMENT ON COLUMN messages.message_type IS 'Тип сообщения: text, file, image и т.д.';
COMMENT ON COLUMN messages.envelopes IS 'JSON объект с конвертами для каждого участника: {"userId": {"key": "...", "ephempubk": "...", "iv": "..."}}';
COMMENT ON COLUMN messages.metadata IS 'JSON массив с метаданными файлов: [{"file_id": 1, "filename": "...", "mimetype": "...", ...}]';
