<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') exit(1);
$path=getenv('MAURINDESK_DB_PATH');
if (!$path) { fwrite(STDERR,"Defina MAURINDESK_DB_PATH fora do diretório público.\n"); exit(1); }
if (!is_dir(dirname($path))) { fwrite(STDERR,"Diretório do banco não existe.\n"); exit(1); }
$db=new PDO('sqlite:'.$path);
$db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
$db->exec(file_get_contents(dirname(__DIR__).'/migrations/001_initial.sql'));
@chmod($path,0600);
echo "Schema 001 pronto.\n";
