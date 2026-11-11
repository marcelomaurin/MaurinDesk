PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS devices (
 id TEXT PRIMARY KEY, public_key TEXT NOT NULL UNIQUE CHECK(length(public_key)=10),
 registration_id TEXT NOT NULL UNIQUE, registration_hash TEXT NOT NULL,
 token_hash TEXT NOT NULL UNIQUE, token_expires INTEGER NOT NULL,
 display_name TEXT NOT NULL, platform TEXT NOT NULL, app_version TEXT NOT NULL,
 last_seen INTEGER NOT NULL, created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
 id TEXT PRIMARY KEY, requester_id TEXT NOT NULL REFERENCES devices(id),
 host_id TEXT NOT NULL REFERENCES devices(id), state TEXT NOT NULL,
 requested TEXT NOT NULL, granted TEXT NOT NULL DEFAULT '[]',
 created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 ended_at INTEGER, reason TEXT, CHECK(requester_id <> host_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS one_session_per_host ON sessions(host_id)
 WHERE state IN ('accepted','connecting','active');
CREATE INDEX IF NOT EXISTS incoming_sessions ON sessions(host_id,state,created_at);
CREATE TABLE IF NOT EXISTS idempotency (
 device_id TEXT NOT NULL REFERENCES devices(id), route TEXT NOT NULL,
 key TEXT NOT NULL, body_hash TEXT NOT NULL, response TEXT NOT NULL,
 status INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 PRIMARY KEY(device_id,route,key)
);
CREATE TABLE IF NOT EXISTS rate_limits (
 bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_events (
 id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, actor_id TEXT,
 event_type TEXT NOT NULL, occurred_at INTEGER NOT NULL
);
