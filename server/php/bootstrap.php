<?php
declare(strict_types=1);
require_once __DIR__.'/src/Api.php';
require_once __DIR__.'/src/Schema.php';
function maurindesk_load_env(): void {
    $file=getenv('MAURINDESK_ENV_FILE')?:__DIR__.'/.env';
    if (!is_file($file)) return;
    foreach (file($file,FILE_IGNORE_NEW_LINES) as $line) {
        $line=trim($line);
        if ($line==='' || str_starts_with($line,'#')) continue;
        if (!preg_match('/^([A-Z][A-Z0-9_]*)\s*=\s*(.*)$/D',$line,$m))
            throw new RuntimeException('Invalid configuration');
        $value=trim($m[2]);
        if (strlen($value)>=2 && (($value[0]==='"' && str_ends_with($value,'"')) ||
            ($value[0]==="'" && str_ends_with($value,"'")))) $value=substr($value,1,-1);
        if (getenv($m[1])===false) putenv($m[1].'='.$value);
    }
}
function maurindesk_db(): PDO {
    maurindesk_load_env();
    $driver=getenv('DB_DRIVER')?:(getenv('MAURINDESK_DB_PATH')?'sqlite':'mysql');
    if ($driver==='mysql') {
        $host=getenv('DB_HOST')?:'localhost'; $port=getenv('DB_PORT')?:'3306';
        $name=getenv('DB_NAME'); $user=getenv('DB_USER'); $password=getenv('DB_PASSWORD');
        if (!$name || !$user || $password===false ||
            !preg_match('/^[a-zA-Z0-9_.-]+$/D',$host) || !ctype_digit($port) ||
            (int)$port<1 || (int)$port>65535 || !preg_match('/^[a-zA-Z0-9_]+$/D',$name))
            throw new RuntimeException('Database configuration missing or invalid');
        $db=new PDO("mysql:host=$host;port=$port;dbname=$name;charset=utf8mb4",$user,$password,
            [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
    } elseif ($driver==='sqlite') {
        $path=getenv('MAURINDESK_DB_PATH');
        if (!$path || !is_dir(dirname($path))) throw new RuntimeException('Database directory missing');
        $parent=realpath(dirname($path)); $webRoot=realpath(__DIR__);
        if (str_starts_with(strtolower($parent.DIRECTORY_SEPARATOR),strtolower($webRoot.DIRECTORY_SEPARATOR)))
            throw new RuntimeException('SQLite database must be outside the server directory');
        $db=new PDO('sqlite:'.$path,null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
        @chmod($path,0600);
    } else throw new RuntimeException('Unsupported database driver');
    \MaurinDesk\Schema::migrate($db);
    return $db;
}
