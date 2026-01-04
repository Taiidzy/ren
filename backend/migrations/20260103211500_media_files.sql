-- Add migration script here
CREATE TABLE IF NOT EXISTS media_files (
  id SERIAL PRIMARY KEY,
  owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chat_id INTEGER REFERENCES chats(id) ON DELETE SET NULL,
  message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
  path TEXT NOT NULL,
  filename TEXT NOT NULL,
  mimetype TEXT NOT NULL,
  size BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_media_files_owner ON media_files(owner_id);
CREATE INDEX IF NOT EXISTS idx_media_files_chat ON media_files(chat_id);
CREATE INDEX IF NOT EXISTS idx_media_files_message ON media_files(message_id);
