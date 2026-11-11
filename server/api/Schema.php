<?php
declare(strict_types=1);
namespace MaurinDesk;
use PDO;
use RuntimeException;
use Throwable;

/** Ordered migrations. VERSAO changes only after successful schema changes. */
final class Schema {
    public const VERSION='0.2';
    public static function migrate(PDO $db): void {
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
                    'files'=>$mysql ? ['001_initial.mysql.sql'] : ['001_initial.sqlite.sql','002_peer_endpoints.sqlite.sql']],
                '0.2'=>['descricao'=>'Preferencias do desktop, contatos, favoritos e cartoes da interface',
                    'repairable'=>true,
                    'files'=>$mysql ? ['002_desktop_ui.mysql.sql'] : ['003_desktop_ui.sqlite.sql']],
            ];
            foreach ($migrations as $version=>$migration) {
                // Baseline CREATE IF NOT EXISTS also restores missing tables.
                if ($current!==false && !version_compare($version,(string)$current,'>') &&
                    !($migration['repairable']??($version==='0.1'))) continue;
                foreach ($migration['files'] as $relative) {
                    $sql=file_get_contents(__DIR__.'/'.$relative);
                    if ($sql===false) throw new RuntimeException('Missing migration');
                    $db->exec($sql);
                }
                if ($current!==false && !version_compare($version,(string)$current,'>')) continue;
                // MySQL DDL commits implicitly: record history and version afterwards.
                if ($mysql) $db->beginTransaction();
                $insert=$mysql ? 'INSERT IGNORE' : 'INSERT OR IGNORE';
                $q=$db->prepare($insert.' INTO schema_migrations(versao,descricao,aplicada_em) VALUES(?,?,?)');
                $q->execute([$version,$migration['descricao'],time()]);
                $q=$db->prepare($current===false
                    ? "INSERT INTO params(chave,valor) VALUES('VERSAO',?)"
                    : "UPDATE params SET valor=? WHERE chave='VERSAO'");
                $q->execute([$version]);
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
