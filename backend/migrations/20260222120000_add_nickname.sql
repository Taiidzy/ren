-- Add nickname column to users table
ALTER TABLE users 
ADD COLUMN nickname TEXT;

-- Set existing users' nickname to their username
UPDATE users SET nickname = username WHERE nickname IS NULL;

-- Add check constraint for nickname length (max 32 chars)
ALTER TABLE users ADD CONSTRAINT chk_nickname_length CHECK (LENGTH(nickname) <= 32);

-- Add comment
COMMENT ON COLUMN users.nickname IS 'Отображаемое имя пользователя (не уникальное, макс. 32 символа)';
