-- Migracao 0.5: Tabela de logs e diagnosticos de falhas do cliente + expansao de local_ip
ALTER TABLE device_endpoints MODIFY COLUMN local_ip VARCHAR(100) NULL;

CREATE TABLE IF NOT EXISTS device_logs (
    id VARCHAR(36) PRIMARY KEY,
    device_id VARCHAR(36) NULL,
    session_id VARCHAR(36) NULL,
    level VARCHAR(10) NOT NULL,
    category VARCHAR(50) NOT NULL,
    message VARCHAR(255) NOT NULL,
    log_content MEDIUMTEXT NOT NULL,
    ip_address VARCHAR(45) NOT NULL,
    app_version VARCHAR(20) NOT NULL,
    created_at BIGINT NOT NULL,
    KEY idx_logs_device(device_id),
    KEY idx_logs_session(session_id),
    KEY idx_logs_created(created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
