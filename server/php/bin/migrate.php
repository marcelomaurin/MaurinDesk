<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') exit(1);
require dirname(__DIR__).'/bootstrap.php';
try {
    $db=maurindesk_db();
    echo 'Banco pronto. VERSAO='.$db->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn()."\n";
} catch (Throwable) {
    fwrite(STDERR,"Falha ao preparar banco. Confira configuracao, permissoes e versao do servidor.\n");
    exit(1);
}
