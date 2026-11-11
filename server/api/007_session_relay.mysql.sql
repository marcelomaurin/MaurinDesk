-- MaurinDesk v0.6: Negociacao dinamica de portas e servidor como ponte (relay)
CREATE TABLE IF NOT EXISTS session_ports (
    session_id VARCHAR(36) NOT NULL PRIMARY KEY,
    current_port INT NOT NULL DEFAULT 7071,
    port_status VARCHAR(20) NOT NULL DEFAULT 'probing',
    use_relay TINYINT(1) NOT NULL DEFAULT 0,
    tried_ports VARCHAR(255) NOT NULL DEFAULT '[]',
    updated_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS session_relay_frames (
    session_id VARCHAR(36) NOT NULL PRIMARY KEY,
    frame_id BIGINT NOT NULL DEFAULT 0,
    frame_data MEDIUMTEXT NOT NULL,
    updated_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS session_relay_inputs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id VARCHAR(36) NOT NULL,
    event_data TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    INDEX idx_session (session_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
