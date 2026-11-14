CREATE TABLE IF NOT EXISTS clipboard_transfers (
 id CHAR(36) NOT NULL PRIMARY KEY, session_id CHAR(36) NOT NULL, sender_id CHAR(36) NOT NULL,
 kind VARCHAR(10) NOT NULL, total_bytes BIGINT NOT NULL, checksum CHAR(40) NOT NULL,
 chunk_count INT NOT NULL, ready TINYINT NOT NULL DEFAULT 0,
 created_at BIGINT NOT NULL, updated_at BIGINT NOT NULL,
 KEY clipboard_session_sender(session_id,sender_id,ready,updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
CREATE TABLE IF NOT EXISTS clipboard_chunks (
 transfer_id CHAR(36) NOT NULL, part INT NOT NULL, data MEDIUMTEXT NOT NULL,
 PRIMARY KEY(transfer_id,part),
 CONSTRAINT clipboard_chunk_transfer FOREIGN KEY(transfer_id) REFERENCES clipboard_transfers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
