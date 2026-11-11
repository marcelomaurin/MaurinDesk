CREATE TABLE IF NOT EXISTS device_endpoints (
 device_id TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
 observed_ip TEXT NOT NULL,
 port INTEGER NOT NULL CHECK(port BETWEEN 1024 AND 65535),
 transport TEXT NOT NULL CHECK(transport = 'tcp'),
 updated_at INTEGER NOT NULL
);
