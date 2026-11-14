CREATE TABLE IF NOT EXISTS file_commands (
 id TEXT PRIMARY KEY, session_id TEXT NOT NULL, sender_id TEXT NOT NULL, receiver_id TEXT NOT NULL,
 action TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
 response TEXT, lease_until INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS file_command_incoming ON file_commands(session_id,receiver_id,state,created_at);
CREATE TABLE IF NOT EXISTS file_transfers (
 id TEXT PRIMARY KEY, session_id TEXT NOT NULL, sender_id TEXT NOT NULL, receiver_id TEXT NOT NULL,
 request_id TEXT NOT NULL, destination TEXT NOT NULL, overwrite_existing INTEGER NOT NULL DEFAULT 0,
 total_bytes INTEGER NOT NULL, checksum TEXT NOT NULL, chunk_count INTEGER NOT NULL,
 state TEXT NOT NULL DEFAULT 'uploading', result TEXT, lease_owner TEXT, lease_until INTEGER NOT NULL DEFAULT 0,
 created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
 UNIQUE(session_id,sender_id,request_id)
);
CREATE INDEX IF NOT EXISTS file_transfer_incoming ON file_transfers(session_id,receiver_id,state,created_at);
CREATE TABLE IF NOT EXISTS file_chunks (
 transfer_id TEXT NOT NULL REFERENCES file_transfers(id) ON DELETE CASCADE,
 part INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(transfer_id,part)
);
