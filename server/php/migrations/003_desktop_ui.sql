CREATE TABLE IF NOT EXISTS device_preferences (
 device_id TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
 language TEXT NOT NULL DEFAULT 'pt-BR', theme TEXT NOT NULL DEFAULT 'system',
 view_mode TEXT NOT NULL DEFAULT 'cards', sort_by TEXT NOT NULL DEFAULT 'last_used',
 updated_at INTEGER NOT NULL
);
INSERT INTO device_preferences(device_id,updated_at)
 SELECT d.id,d.created_at FROM devices d
 WHERE NOT EXISTS(SELECT 1 FROM device_preferences p WHERE p.device_id=d.id);
CREATE TABLE IF NOT EXISTS device_contacts (
 id TEXT PRIMARY KEY, owner_device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
 remote_key TEXT NOT NULL CHECK(length(remote_key)=10), alias TEXT NOT NULL DEFAULT '',
 group_name TEXT NOT NULL DEFAULT '', is_favorite INTEGER NOT NULL DEFAULT 0 CHECK(is_favorite IN (0,1)),
 color TEXT NOT NULL DEFAULT '#3B82F6', sort_order INTEGER NOT NULL DEFAULT 0,
 created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
 UNIQUE(owner_device_id,remote_key)
);
CREATE INDEX IF NOT EXISTS contacts_owner_order ON device_contacts(owner_device_id,is_favorite,sort_order);
