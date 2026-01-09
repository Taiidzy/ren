-- Add migration script here

CREATE TABLE IF NOT EXISTS chat_favorites (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, chat_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_favorites_user_created ON chat_favorites(user_id, created_at DESC);
