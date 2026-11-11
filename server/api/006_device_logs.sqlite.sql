-- Migracao 0.5 SQLite: Tabela de logs e diagnosticos de falhas do cliente
CREATE TABLE IF NOT EXISTS device_logs (
    id TEXT PRIMARY KEY,
    device_id TEXT NULL,
    session_id TEXT NULL,
    level TEXT NOT NULL,
    category TEXT NOT NULL,
    message TEXT NOT NULL,
    log_content TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    app_version TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
