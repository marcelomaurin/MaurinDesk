CREATE TABLE IF NOT EXISTS devices (
 id CHAR(36) PRIMARY KEY, public_key CHAR(10) NOT NULL UNIQUE,
 registration_id CHAR(36) NOT NULL UNIQUE, registration_hash CHAR(64) NOT NULL,
 token_hash CHAR(64) NOT NULL UNIQUE, token_expires BIGINT NOT NULL,
 display_name VARCHAR(80) NOT NULL, platform VARCHAR(40) NOT NULL,
 app_version VARCHAR(40) NOT NULL, last_seen BIGINT NOT NULL, created_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS sessions (
 id CHAR(36) PRIMARY KEY, requester_id CHAR(36) NOT NULL,host_id CHAR(36) NOT NULL,
 state VARCHAR(20) NOT NULL,requested TEXT NOT NULL,granted TEXT NOT NULL,
 created_at BIGINT NOT NULL,expires_at BIGINT NOT NULL,ended_at BIGINT NULL,reason VARCHAR(80) NULL,
 active_host CHAR(36) GENERATED ALWAYS AS
    (CASE WHEN state IN ('accepted','connecting','active') THEN RTRIM(host_id) ELSE NULL END) STORED,
 UNIQUE KEY one_session_per_host(active_host),
 KEY incoming_sessions(host_id,state,created_at),
 KEY idx_sessions_requester(requester_id),
 KEY idx_sessions_host(host_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS idempotency (
 device_id CHAR(36) NOT NULL,route VARCHAR(200) NOT NULL,`key` CHAR(36) NOT NULL,
 body_hash CHAR(64) NOT NULL,response MEDIUMTEXT NOT NULL,status INT NOT NULL,expires_at BIGINT NOT NULL,
 PRIMARY KEY(device_id,route,`key`),
 KEY idx_idempotency_device(device_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS rate_limits (
 bucket VARCHAR(160) PRIMARY KEY,count INT NOT NULL,expires_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS audit_events (
 id BIGINT AUTO_INCREMENT PRIMARY KEY,session_id CHAR(36) NULL,actor_id CHAR(36) NULL,
 event_type VARCHAR(80) NOT NULL,occurred_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS device_endpoints (
 device_id CHAR(36) PRIMARY KEY,observed_ip VARCHAR(45) NOT NULL,
 port INT NOT NULL,transport VARCHAR(10) NOT NULL,updated_at BIGINT NOT NULL,
 KEY idx_endpoints_device(device_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS api_mutex (id INT PRIMARY KEY) ENGINE=InnoDB;
INSERT IGNORE INTO api_mutex(id) VALUES(1);
