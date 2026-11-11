<?php
declare(strict_types=1);
require_once __DIR__.'/src/Api.php';
function maurindesk_db(): PDO {
    $path=getenv('MAURINDESK_DB_PATH');
    if (!$path || !is_file($path)) throw new RuntimeException('Database not initialized');
    return new PDO('sqlite:'.$path);
}
