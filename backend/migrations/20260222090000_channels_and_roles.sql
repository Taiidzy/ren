-- Channel/chat roles groundwork

-- Performance for permission checks by chat + role
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_role
  ON chat_participants(chat_id, role);

-- Keep chats.updated_at fresh when messages change
CREATE OR REPLACE FUNCTION set_chat_updated_at_from_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE chats
  SET updated_at = now()
  WHERE id = COALESCE(NEW.chat_id, OLD.chat_id);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_messages_touch_chat ON messages;
CREATE TRIGGER trg_messages_touch_chat
AFTER INSERT OR UPDATE OR DELETE ON messages
FOR EACH ROW
EXECUTE FUNCTION set_chat_updated_at_from_message();
