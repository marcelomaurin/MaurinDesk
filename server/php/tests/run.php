<?php
declare(strict_types=1);
require dirname(__DIR__).'/src/Api.php';
require dirname(__DIR__).'/src/Schema.php';
use MaurinDesk\Api;
$dsn=getenv('MAURINDESK_TEST_MYSQL_DSN');
$db=$dsn ? new PDO($dsn,getenv('MAURINDESK_TEST_MYSQL_USER'),getenv('MAURINDESK_TEST_MYSQL_PASSWORD'),
    [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]) : new PDO('sqlite::memory:');
\MaurinDesk\Schema::migrate($db);
$now=1800000000;
$api=new Api($db,function() use (&$now): int { return $now; });
$count=0;
function check(bool $ok,string $name): void {
    global $count;
    if (!$ok) throw new RuntimeException('FAIL: '.$name);
    $count++; echo "OK $name\n";
}
function callApi(string $method,string $path,array $body=[],?array $device=null,?string $key=null): array {
    global $api;
    $h=$device?['authorization'=>'Bearer '.$device['device_token'],'idempotency-key'=>$key??Api::uuid()]:[];
    return $api->handle($method,$path,$h,$body,$device['device_id']??($body['registration_id']??'health'));
}
function registerDevice(string $name): array {
    $b=['registration_id'=>Api::uuid(),'registration_secret'=>bin2hex(random_bytes(32)),
        'display_name'=>$name,'platform'=>'test','app_version'=>'0.2.0'];
    [$status,$r]=callApi('POST','/devices',$b);
    check($status===201,'register '.$name);
    return [$r['data'],$b];
}
[$host,$hb]=registerDevice('host'); [$client,$cb]=registerDevice('client'); [$other,$ob]=registerDevice('other');
check(preg_match('/^[0-9]{10}$/D',$host['public_key'])===1,'ten digits string');
check($host['public_key']!==$client['public_key'],'unique keys');
[$st,$r]=callApi('POST','/devices',$hb);
check($st===201 && $r['data']['public_key']===$host['public_key'],'recovery preserves key');
[$st]=callApi('POST','/devices/heartbeat',[],$host);
check($st===401,'recovery revokes old token');
$host=$r['data'];
$bad=$hb; $bad['registration_secret']=bin2hex(random_bytes(32));
[$st]=callApi('POST','/devices',$bad);
check($st===409,'wrong recovery secret');
[$st]=callApi('GET','/sessions/incoming');
check($st===401,'authentication required');
$body=['target_key'=>$host['public_key'],'requested_permissions'=>['screen.view','input.mouse']];
$idem=Api::uuid();
[$st,$r]=callApi('POST','/sessions',$body,$client,$idem);
check($st===201 && $r['data']['state']==='pending','request stays pending');
$id=$r['data']['id'];
[$st,$r]=callApi('POST','/sessions',$body,$client,$idem);
check($st===201 && $r['data']['id']===$id,'idempotent request');
$changed=$body; $changed['requested_permissions']=['screen.view'];
[$st]=callApi('POST','/sessions',$changed,$client,$idem);
check($st===409,'idempotency body conflict');
[$st,$r]=callApi('GET','/sessions/incoming',[],$host);
check($st===200 && count($r['data']['items'])===1,'host receives request');
[$st]=callApi('GET','/sessions/'.$id,[],$other);
check($st===404,'third party cannot inspect');
$accept=['decision'=>'accept','granted_permissions'=>['screen.view']];
[$st]=callApi('POST','/sessions/'.$id.'/decision',$accept,$client);
check($st===403,'requester cannot consent');
$wide=['decision'=>'accept','granted_permissions'=>['screen.view','input.keyboard']];
[$st]=callApi('POST','/sessions/'.$id.'/decision',$wide,$host);
check($st===400,'cannot grant unrequested permission');
$decisionKey=Api::uuid();
[$st,$r]=callApi('POST','/sessions/'.$id.'/decision',$accept,$host,$decisionKey);
check($st===200 && $r['data']['granted_permissions']===['screen.view'],'host grants view only');
[$st,$r]=callApi('POST','/sessions',$body,$other);
$id2=$r['data']['id'];
[$st]=callApi('POST','/sessions/'.$id2.'/decision',$accept,$host);
check($st===409,'single active host session');
[$st]=callApi('POST','/sessions/'.$id.'/close',['reason'=>'local_stop'],$host);
check($st===200,'local stop');
[$st,$r]=callApi('GET','/sessions/'.$id,[],$client);
check($st===200 && $r['data']['state']==='closed','both see terminal state');
[$st]=callApi('POST','/sessions/'.$id.'/decision',$accept,$host);
check($st===409,'cannot reopen session');
$now+=61;
[$st,$r]=callApi('GET','/sessions/'.$id2,[],$other);
check($st===200 && $r['data']['state']==='expired','expiry without cron');
[$st]=callApi('POST','/sessions',$body,$client);
check($st===404,'stale host is unavailable');
[$st]=callApi('POST','/devices/heartbeat',[],$host);
check($st===200,'heartbeat restores presence');
[$st,$r]=callApi('POST','/sessions',$body,$client);
$id3=$r['data']['id'];
[$st]=callApi('POST','/sessions/'.$id3.'/cancel',[],$host);
check($st===403,'host cannot cancel as requester');
[$st]=callApi('POST','/sessions/'.$id3.'/cancel',[],$client);
check($st===200,'requester cancellation');
[$st]=callApi('POST','/sessions/'.$id3.'/credentials',[],$client);
check($st===404,'unimplemented media credentials fail closed');
$hash=$db->query('SELECT token_hash FROM devices LIMIT 1')->fetchColumn();
check(!in_array($hash,[$host['device_token'],$client['device_token']],true),'tokens hashed');
$now+=2592001;
[$st]=callApi('GET','/sessions/incoming',[],$host);
check($st===401,'expired device token');
echo "$count assertions passed\n";
