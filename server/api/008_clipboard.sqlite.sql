CREATE TABLE IF NOT EXISTS clipboard_transfers (
 id TEXT PRIMARY KEY, session_id TEXT NOT NULL, sender_id TEXT NOT NULL,
 kind TEXT NOT NULL, total_bytes INTEGER NOT NULL, checksum TEXT NOT NULL,
 chunk_count INTEGER NOT NULL, ready INTEGER NOT NULL DEFAULT 0,
 created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS clipboard_session_sender ON clipboard_transfers(session_id,sender_id,ready,updated_at);
CREATE TABLE IF NOT EXISTS clipboard_chunks (
 transfer_id TEXT NOT NULL REFERENCES clipboard_transfers(id) ON DELETE CASCADE,
 part INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(transfer_id,part)
);
