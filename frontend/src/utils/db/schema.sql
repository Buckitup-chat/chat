-- CREATE TABLE IF NOT EXISTS contacts_synced (
--   pub_key TEXT PRIMARY KEY,
--   name TEXT,                  
--   synced BOOLEAN DEFAULT TRUE
-- );

-- CREATE TABLE IF NOT EXISTS contacts_local (
--   pub_key TEXT,  
--   name TEXT,          
--   synced BOOLEAN DEFAULT FALSE,        
--   operation TEXT CHECK(operation IN ('insert', 'delete'))
-- );

-- UPDATE contacts_local
-- SET pub_key = '\x' || substring(pub_key FROM 3)
-- WHERE pub_key LIKE '0x%';

-- CREATE OR REPLACE VIEW contacts AS
-- SELECT 
--   COALESCE(l.pub_key, s.pub_key) AS pub_key,
--   COALESCE(l.name, s.name) AS name,
--   COALESCE(l.synced, s.synced) AS synced
-- FROM contacts_synced s
-- FULL OUTER JOIN contacts_local l ON s.pub_key = l.pub_key
-- WHERE l.operation != 'delete' OR l.operation IS NULL;

-- CREATE OR REPLACE FUNCTION delete_local_if_synced()
-- RETURNS TRIGGER AS $$
-- BEGIN
--   DELETE FROM contacts_local WHERE pub_key = NEW.pub_key;
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;


-- CREATE OR REPLACE TRIGGER trg_sync_delete_local
-- AFTER INSERT OR UPDATE ON contacts_synced
-- FOR EACH ROW
-- EXECUTE FUNCTION delete_local_if_synced();


CREATE TABLE IF NOT EXISTS users_synced (
  pub_key TEXT PRIMARY KEY,
  name    TEXT NOT NULL,
  -- можна додати created_at, avatar_url тощо, якщо є
  synced  BOOLEAN DEFAULT TRUE
);

-- Локальні зміни (offline-first, optimistic)
CREATE TABLE IF NOT EXISTS users_local (
  pub_key    TEXT PRIMARY KEY,
  name       TEXT,
  operation  TEXT CHECK (operation IN ('insert', 'update', 'delete')),
  synced     BOOLEAN DEFAULT FALSE
);

-- View, який бачить клієнт (комбінує synced + local з пріоритетом локальним)
CREATE OR REPLACE VIEW users AS
SELECT 
  COALESCE(l.pub_key, s.pub_key)           AS pub_key,
  COALESCE(l.name,    s.name)              AS name,
  COALESCE(l.synced,  s.synced, FALSE)     AS synced
FROM users_synced s
FULL OUTER JOIN users_local l ON s.pub_key = l.pub_key
WHERE l.operation IS NULL OR l.operation != 'delete';

-- Тригер: після успішної синхронізації видаляємо локальний запис
CREATE OR REPLACE FUNCTION cleanup_local_after_sync()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM users_local WHERE pub_key = NEW.pub_key;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_cleanup_local_users
AFTER INSERT OR UPDATE ON users_synced
FOR EACH ROW EXECUTE FUNCTION cleanup_local_after_sync();