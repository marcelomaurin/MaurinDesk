-- MaurinDesk v0.6: Negociacao dinamica de portas e servidor como ponte (relay)
CREATE TABLE IF NOT EXISTS session_ports (
    session_id TEXT PRIMARY KEY,
    current_port INTEGER NOT NULL DEFAULT 7071,
    port_status TEXT NOT NULL DEFAULT 'probing',
    use_relay INTEGER NOT NULL DEFAULT 0,
    tried_ports TEXT NOT NULL DEFAULT '[]',
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS session_relay_frames (
    session_id TEXT PRIMARY KEY,
    frame_id INTEGER NOT NULL DEFAULT 0,
    frame_data TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS session_relay_inputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    event_data TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_session_relay_inputs ON session_relay_inputs(session_id, created_at);
