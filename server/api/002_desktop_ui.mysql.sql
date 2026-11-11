CREATE TABLE IF NOT EXISTS device_preferences (
 device_id CHAR(36) PRIMARY KEY,
 language VARCHAR(10) NOT NULL DEFAULT 'pt-BR',theme VARCHAR(10) NOT NULL DEFAULT 'system',
 view_mode VARCHAR(10) NOT NULL DEFAULT 'cards',sort_by VARCHAR(12) NOT NULL DEFAULT 'last_used',
 updated_at BIGINT NOT NULL,
 FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
INSERT INTO device_preferences(device_id,updated_at)
 SELECT d.id,d.created_at FROM devices d
 WHERE NOT EXISTS(SELECT 1 FROM device_preferences p WHERE p.device_id=d.id);
CREATE TABLE IF NOT EXISTS device_contacts (
 id CHAR(36) PRIMARY KEY,owner_device_id CHAR(36) NOT NULL,
 remote_key CHAR(10) NOT NULL,alias VARCHAR(80) NOT NULL DEFAULT '',
 group_name VARCHAR(80) NOT NULL DEFAULT '',is_favorite TINYINT NOT NULL DEFAULT 0,
 color CHAR(7) NOT NULL DEFAULT '#3B82F6',sort_order INT NOT NULL DEFAULT 0,
 created_at BIGINT NOT NULL,updated_at BIGINT NOT NULL,
 UNIQUE KEY contact_per_owner(owner_device_id,remote_key),
 KEY contacts_owner_order(owner_device_id,is_favorite,sort_order),
 FOREIGN KEY(owner_device_id) REFERENCES devices(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
