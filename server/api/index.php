<?php
declare(strict_types=1);
ini_set('display_errors','0');
require __DIR__.'/bootstrap.php';
use MaurinDesk\Api;
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
function send_error(int $status,string $code,string $message): never {
    http_response_code($status);
    echo json_encode(['error'=>['code'=>$code,'message'=>$message],'request_id'=>Api::uuid()]);
    exit;
}
// Never trust X-Forwarded-Proto from an arbitrary caller.
try { maurindesk_load_env(); }
catch (Throwable) { send_error(503,'CONFIGURATION_ERROR','Configuracao indisponivel.'); }
$local=getenv('APP_ENV')==='development' && in_array($_SERVER['REMOTE_ADDR']??'',['127.0.0.1','::1'],true);
if (!$local && ($_SERVER['HTTPS']??'')!=='on')
    send_error(400,'HTTPS_REQUIRED','HTTPS obrigatório.');
if ((int)($_SERVER['CONTENT_LENGTH']??0)>131072) send_error(413,'PAYLOAD_TOO_LARGE','Corpo excedente.');
$raw=file_get_contents('php://input',false,null,0,131073);
if ($raw===false || strlen($raw)>131072) send_error(413,'PAYLOAD_TOO_LARGE','Corpo excedente.');
$body=[];
if ($raw!=='') {
    if (strtolower(trim(explode(';',$_SERVER['CONTENT_TYPE']??'')[0]))!=='application/json')
        send_error(400,'VALIDATION_ERROR','Content-Type application/json obrigatório.');
    try {
        $decoded=json_decode($raw,false,32,JSON_THROW_ON_ERROR);
        if (!is_object($decoded)) send_error(400,'VALIDATION_ERROR','Objeto JSON obrigatório.');
        $body=json_decode($raw,true,32,JSON_THROW_ON_ERROR);
    } catch (JsonException) { send_error(400,'VALIDATION_ERROR','JSON inválido.'); }
}
$base=rtrim(getenv('API_BASE_PATH')?:'/maurindesk/api/v1','/');
$path=parse_url($_SERVER['REQUEST_URI']??'/',PHP_URL_PATH);
if (is_string($path) && $path===rtrim(dirname($base),'/').'/' && ($_SERVER['REQUEST_METHOD']??'GET')==='GET') {
    $path='/health';
} else {
    if (!is_string($path) || !str_starts_with($path,$base.'/')) send_error(404,'NOT_FOUND','Rota não encontrada.');
    $path=substr($path,strlen($base));
}
$headers=function_exists('getallheaders')?getallheaders():[];
if (isset($_SERVER['HTTP_AUTHORIZATION'])) $headers['authorization']=$_SERVER['HTTP_AUTHORIZATION'];
elseif (isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) $headers['authorization']=$_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
if (isset($_SERVER['HTTP_IDEMPOTENCY_KEY'])) $headers['idempotency-key']=$_SERVER['HTTP_IDEMPOTENCY_KEY'];
try {
    $api=new Api(maurindesk_db());
    [$status,$response]=$api->handle($_SERVER['REQUEST_METHOD']??'GET',$path,$headers,$body,$_SERVER['REMOTE_ADDR']??'unknown');
    http_response_code($status);
    if ($status===429) header('Retry-After: 60');
    echo json_encode($response,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
} catch (Throwable) { send_error(503,'SERVICE_UNAVAILABLE','Serviço indisponível.'); }
