<?php
declare(strict_types=1);
namespace MaurinDesk;
use PDO;
use RuntimeException;
use Throwable;

/** Ordered migrations. VERSAO changes only after successful schema changes. */
final class Schema {
    public const VERSION='0.6';
    public static function migrate(PDO $db): void {
        // Fast path: se o banco já estiver na versão mais recente, não precisa travar nem verificar migrações a cada request
        try {
            $curVer = $db->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn();
            if ($curVer === self::VERSION) {
                // A version marker alone does not prove the relay tables survived a partial restore.
                // Validate the structure without reading rows or rerunning DDL on every frame.
                $db->query('SELECT e.local_ip,f.frame_id,f.frame_data,i.event_data,p.current_port
                    FROM devices d,device_endpoints e,device_preferences pref,device_contacts c,
                    sessions s,session_relay_frames f,session_relay_inputs i,session_ports p,
                    audit_events a,device_logs l,schema_migrations m,api_mutex mutex,idempotency idem,rate_limits r
                    WHERE 1=0');
                return;
            }
        } catch (Throwable) {
            // Tabela params ainda não existe, prossegue com o fluxo completo de migração
        }

        $mysql=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';
        $lock=false; $lockName='maurindesk_schema';
        try {
            if ($mysql) {
                $database=(string)$db->query('SELECT DATABASE()')->fetchColumn();
                $lockName='maurindesk_'.substr(hash('sha256',$database),0,32);
                $q=$db->prepare('SELECT GET_LOCK(?,10)'); $q->execute([$lockName]);
                if ((int)$q->fetchColumn()!==1) throw new RuntimeException('Schema busy');
                $lock=true;
                $db->exec('CREATE TABLE IF NOT EXISTS params (
                    chave VARCHAR(100) NOT NULL PRIMARY KEY, valor VARCHAR(255) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin');
                $db->exec('CREATE TABLE IF NOT EXISTS schema_migrations (
                    versao VARCHAR(30) NOT NULL PRIMARY KEY, descricao VARCHAR(255) NOT NULL,
                    aplicada_em BIGINT NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin');
            } else {
                $db->exec('PRAGMA foreign_keys=ON'); $db->exec('PRAGMA busy_timeout=5000');
                $db->exec('BEGIN IMMEDIATE');
                $db->exec('CREATE TABLE IF NOT EXISTS params (chave TEXT PRIMARY KEY,valor TEXT NOT NULL)');
                $db->exec('CREATE TABLE IF NOT EXISTS schema_migrations (
                    versao TEXT PRIMARY KEY,descricao TEXT NOT NULL,aplicada_em INTEGER NOT NULL)');
            }
            $current=$db->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn();
            if ($current!==false && (!preg_match('/^\d+\.\d+(?:\.\d+)?$/D',(string)$current) ||
                version_compare((string)$current,self::VERSION,'>')))
                throw new RuntimeException('Database version incompatible with this server');
            // Append future versions here, in order. Keep previous migrations immutable.
            $migrations=[
                '0.1'=>['descricao'=>'Identidade, consentimento e descoberta de endpoints P2P',
                    'repairable'=>true,
                    'files'=>$mysql ? ['001_initial.mysql.sql'] : ['001_initial.sqlite.sql','002_peer_endpoints.sqlite.sql']],
                '0.2'=>['descricao'=>'Preferencias do desktop, contatos, favoritos e cartoes da interface',
                    'repairable'=>true,
                    'files'=>$mysql ? ['002_desktop_ui.mysql.sql'] : ['003_desktop_ui.sqlite.sql']],
                '0.3'=>['descricao'=>'Verificacao e reparo completo de tabelas e colunas do MaurinDesk',
                    'repairable'=>true,
                    'files'=>$mysql ? ['003_schema_repair.mysql.sql'] : ['004_schema_repair.sqlite.sql']],
                '0.4'=>['descricao'=>'Suporte a IP local (LAN) para conexao P2P direta',
                    'repairable'=>true,
                    'files'=>$mysql ? ['004_endpoints_lan.mysql.sql'] : ['005_endpoints_lan.sqlite.sql']],
                '0.5'=>['descricao'=>'Tabela de logs e diagnosticos de falhas do cliente',
                    'repairable'=>true,
                    'files'=>$mysql ? ['006_device_logs.mysql.sql'] : ['006_device_logs.sqlite.sql']],
                '0.6'=>['descricao'=>'Negociacao dinamica de portas P2P e servidor como ponte (relay)',
                    'repairable'=>true,
                    'files'=>$mysql ? ['007_session_relay.mysql.sql'] : ['007_session_relay.sqlite.sql']],
            ];
            foreach ($migrations as $version=>$migration) {
                // Baseline CREATE IF NOT EXISTS also restores missing tables.
                if ($current!==false && !version_compare($version,(string)$current,'>') &&
                    !($migration['repairable']??($version==='0.1'))) continue;
                foreach ($migration['files'] as $relative) {
                    $sql=file_get_contents(__DIR__.'/'.$relative);
                    if ($sql===false) throw new RuntimeException('Missing migration');
                    if ($mysql) $db->exec('SET FOREIGN_KEY_CHECKS=0');
                    $cleanSql = preg_replace('/^\s*--.*$/m', '', $sql);
                    $cleanSql = preg_replace('/\/\*.*?\*\//s', '', $cleanSql);
                    $statements = preg_split('/;\s*(?:\r?\n|$)/', $cleanSql);
                    foreach ($statements as $statement) {
                        $s = trim($statement);
                        if ($s === '') continue;
                        try {
                            $db->exec($s);
                        } catch (Throwable $e) {
                            $msg = strtolower($e->getMessage());
                            if (str_contains($msg, 'duplicate') || str_contains($msg, 'already exists') || str_contains($msg, '1060')) {
                                continue;
                            }
                            throw $e;
                        }
                    }
                    if ($mysql) $db->exec('SET FOREIGN_KEY_CHECKS=1');
                }
                if ($current!==false && !version_compare($version,(string)$current,'>')) continue;
                // MySQL DDL commits implicitly: record history and version afterwards.
                if ($mysql) $db->beginTransaction();
                $insert=$mysql ? 'INSERT IGNORE' : 'INSERT OR IGNORE';
                $q=$db->prepare($insert.' INTO schema_migrations(versao,descricao,aplicada_em) VALUES(?,?,?)');
                $q->execute([$version,$migration['descricao'],time()]);
                if ($mysql) {
                    $q=$db->prepare("INSERT INTO params(chave,valor) VALUES('VERSAO',?) ON DUPLICATE KEY UPDATE valor=VALUES(valor)");
                    $q->execute([$version]);
                } else {
                    $q=$db->prepare("INSERT OR REPLACE INTO params(chave,valor) VALUES('VERSAO',?)");
                    $q->execute([$version]);
                }
                if ($mysql) $db->commit();
                $current=$version;
            }
            if (!$mysql) $db->exec('COMMIT');
        } catch (Throwable $e) {
            if ($mysql && $db->inTransaction()) $db->rollBack();
            elseif (!$mysql) { try { $db->exec('ROLLBACK'); } catch (Throwable) { } }
            throw $e;
        } finally {
            if ($lock) { $q=$db->prepare('SELECT RELEASE_LOCK(?)'); $q->execute([$lockName]); }
        }
    }
}
