-- Migracao 0.4 SQLite: Coluna local_ip para device_endpoints
ALTER TABLE device_endpoints ADD COLUMN local_ip TEXT;
