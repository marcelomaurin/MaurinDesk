CREATE TABLE IF NOT EXISTS file_commands (
 id CHAR(36) NOT NULL PRIMARY KEY, session_id CHAR(36) NOT NULL, sender_id CHAR(36) NOT NULL, receiver_id CHAR(36) NOT NULL,
 action VARCHAR(20) NOT NULL, payload MEDIUMTEXT NOT NULL, state VARCHAR(20) NOT NULL DEFAULT 'pending',
 response MEDIUMTEXT, lease_until BIGINT NOT NULL DEFAULT 0, created_at BIGINT NOT NULL,
 KEY file_command_incoming(session_id,receiver_id,state,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
CREATE TABLE IF NOT EXISTS file_transfers (
 id CHAR(36) NOT NULL PRIMARY KEY, session_id CHAR(36) NOT NULL, sender_id CHAR(36) NOT NULL, receiver_id CHAR(36) NOT NULL,
 request_id CHAR(36) NOT NULL, destination VARCHAR(2048) NOT NULL, overwrite_existing TINYINT NOT NULL DEFAULT 0,
 total_bytes BIGINT NOT NULL, checksum CHAR(40) NOT NULL, chunk_count INT NOT NULL,
 state VARCHAR(20) NOT NULL DEFAULT 'uploading', result MEDIUMTEXT, lease_owner CHAR(36), lease_until BIGINT NOT NULL DEFAULT 0,
 created_at BIGINT NOT NULL, updated_at BIGINT NOT NULL,
 UNIQUE KEY file_transfer_request(session_id,sender_id,request_id),
 KEY file_transfer_incoming(session_id,receiver_id,state,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
CREATE TABLE IF NOT EXISTS file_chunks (
 transfer_id CHAR(36) NOT NULL, part INT NOT NULL, data MEDIUMTEXT NOT NULL,
 PRIMARY KEY(transfer_id,part),
 CONSTRAINT file_chunk_transfer FOREIGN KEY(transfer_id) REFERENCES file_transfers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
