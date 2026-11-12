-- Migracao 0.4: Suporte a IP local (LAN) para conexao P2P direta sem NAT
ALTER TABLE device_endpoints ADD COLUMN local_ip VARCHAR(45) NULL;
