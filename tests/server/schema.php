<?php
declare(strict_types=1);
require dirname(__DIR__,2).'/server/api/Schema.php';
use MaurinDesk\Schema;
$count=0;
function check(bool $condition,string $message): void {
    global $count;
    if (!$condition) throw new RuntimeException('FAIL: '.$message);
    ++$count; echo "OK $message\n";
}
$db=new PDO('sqlite::memory:',null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
Schema::migrate($db);
check($db->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn()===Schema::VERSION,'new database reaches current version '.Schema::VERSION);
check($db->query("SELECT versao FROM schema_migrations ORDER BY versao LIMIT 1")->fetchColumn()==='0.1','initial version 0.1 recorded before UI upgrade');
check((int)$db->query('SELECT COUNT(*) FROM schema_migrations')->fetchColumn()===6,'all ordered migrations recorded');
$db->exec("INSERT INTO params VALUES('EXEMPLO','preservar')");
Schema::migrate($db);
check($db->query("SELECT valor FROM params WHERE chave='EXEMPLO'")->fetchColumn()==='preservar','existing parameter preserved');
check((int)$db->query('SELECT COUNT(*) FROM schema_migrations')->fetchColumn()===6,'history is not duplicated');
foreach (['device_endpoints','device_preferences','device_contacts','session_relay_frames','session_relay_inputs','session_ports'] as $table) {
    $db->exec('DROP TABLE '.$table); Schema::migrate($db);
    check((int)$db->query('SELECT COUNT(*) FROM '.$table)->fetchColumn()===0,'missing '.$table.' recreated');
}
$db->exec('DROP TABLE params'); Schema::migrate($db);
check($db->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn()===Schema::VERSION,'missing params restored without history conflict');
$db->exec("UPDATE params SET valor='99.0' WHERE chave='VERSAO'");
try { Schema::migrate($db); check(false,'future version must fail'); }
catch (RuntimeException $e) { check($e->getMessage()==='Database version incompatible with this server','downgrade rejected'); }
check($db->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn()==='99.0','future version never overwritten');

// Start with exactly the schema shipped before the UI change.
$legacy=new PDO('sqlite::memory:',null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$legacy->exec(file_get_contents(dirname(__DIR__,2).'/server/api/001_initial.sqlite.sql'));
$legacy->exec(file_get_contents(dirname(__DIR__,2).'/server/api/002_peer_endpoints.sqlite.sql'));
$legacy->exec("CREATE TABLE params(chave TEXT PRIMARY KEY,valor TEXT NOT NULL);
 INSERT INTO params VALUES('VERSAO','0.1');
 CREATE TABLE schema_migrations(versao TEXT PRIMARY KEY,descricao TEXT NOT NULL,aplicada_em INTEGER NOT NULL);
 INSERT INTO schema_migrations VALUES('0.1','Base existente',1);
 INSERT INTO devices VALUES('old-device','0000000007','old-registration','hash','token-hash',9999999999,'Nome preservado','windows','0.2.0',1,1)");
$legacy->exec("CREATE TRIGGER fail_history BEFORE INSERT ON schema_migrations WHEN NEW.versao='0.2'
 BEGIN SELECT RAISE(ABORT,'test failure'); END");
try { Schema::migrate($legacy); check(false,'failed upgrade must throw'); }
catch (PDOException) { check(true,'UI migration failure reported'); }
check($legacy->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn()==='0.1','failed UI upgrade keeps version 0.1');
check((int)$legacy->query("SELECT COUNT(*) FROM schema_migrations WHERE versao='0.2'")->fetchColumn()===0,'failed upgrade has no success record');
check((int)$legacy->query("SELECT COUNT(*) FROM sqlite_master WHERE name='device_contacts'")->fetchColumn()===0,'failed SQLite upgrade rolls back new tables');
$legacy->exec('DROP TRIGGER fail_history'); Schema::migrate($legacy);
check($legacy->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn()===Schema::VERSION,'retry upgrades legacy database to '.Schema::VERSION);
check($legacy->query("SELECT public_key FROM devices WHERE id='old-device'")->fetchColumn()==='0000000007','upgrade preserves machine identity and leading zeroes');
check($legacy->query("SELECT display_name FROM devices WHERE id='old-device'")->fetchColumn()==='Nome preservado','upgrade preserves machine name');
require_once dirname(__DIR__,2).'/server/api/DesktopData.php';
$preferences=(new \MaurinDesk\DesktopData($legacy,time()))->preferences('old-device');
check($preferences['language']==='pt-BR','upgraded device gets default preferences on first access');
check($legacy->query("SELECT descricao FROM schema_migrations WHERE versao='0.1'")->fetchColumn()==='Base existente','old migration history preserved');
echo "$count schema assertions passed\n";
