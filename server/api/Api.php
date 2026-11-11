<?php
declare(strict_types=1);
namespace MaurinDesk;

use PDO;
use RuntimeException;
use Throwable;
require_once __DIR__.'/DesktopData.php';

final class ApiError extends RuntimeException {
    public int $status;
    public string $errorCode;
    public function __construct(int $status, string $errorCode, string $message) {
        $this->status = $status;
        $this->errorCode = $errorCode;
        parent::__construct($message);
    }
}

if (!function_exists('array_is_list')) {
    function array_is_list(array $a): bool {
        if ($a === []) return true;
        return array_keys($a) === range(0, count($a) - 1);
    }
}

/** Device identity, presence, explicit consent and P2P endpoint discovery.
 * Media, input and authentication of the desktop channel are separate concerns.
 */
final class Api {
    private int $now;
    private bool $mysql;
    public function __construct(private PDO $db, private $clock = null) {
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $this->mysql=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';
        if (!$this->mysql) {
            $db->exec('PRAGMA foreign_keys=ON');
            $db->exec('PRAGMA busy_timeout=5000');
        }
    }
    public static function uuid(): string {
        $b = random_bytes(16);
        $b[6] = chr((ord($b[6]) & 15) | 64);
        $b[8] = chr((ord($b[8]) & 63) | 128);
        $h = bin2hex($b);
        return substr($h,0,8).'-'.substr($h,8,4).'-'.substr($h,12,4).'-'.substr($h,16,4).'-'.substr($h,20);
    }
    private function run(string $sql, array $args = []): \PDOStatement {
        $q=$this->db->prepare($sql); $q->execute($args); return $q;
    }
    private function beginWrite(): void {
        if ($this->mysql) {
            $this->db->beginTransaction();
            // Serialize state changes, including host reservation and rate limits.
            $this->db->query('SELECT id FROM api_mutex WHERE id=1 FOR UPDATE')->fetch();
        } else $this->db->exec('BEGIN IMMEDIATE');
    }
    private function fail(int $status, string $code, string $message) {
        throw new ApiError($status,$code,$message);
    }
    private function text(array $b,string $key,int $max=128): string {
        $s=$b[$key]??null;
        if (!is_string($s) || trim($s)==='' || strlen($s)>$max || preg_match('/[\x00-\x1f]/',$s))
            $this->fail(400,'VALIDATION_ERROR','Campo inválido: '.$key);
        return $s;
    }
    private function permissions(mixed $value): array {
        $allowed=['screen.view','input.mouse','input.keyboard'];
        if (!is_array($value) || !array_is_list($value) || count($value)>3 ||
            !in_array('screen.view',$value,true) || count(array_unique($value,SORT_REGULAR))!==count($value))
            $this->fail(400,'VALIDATION_ERROR','Permissões inválidas.');
        foreach($value as $p) if (!is_string($p) || !in_array($p,$allowed,true))
            $this->fail(400,'VALIDATION_ERROR','Permissões inválidas.');
        sort($value); return $value;
    }
    private function audit(string $event,?string $actor=null,?string $session=null): void {
        $this->run('INSERT INTO audit_events(session_id,actor_id,event_type,occurred_at) VALUES(?,?,?,?)',
            [$session,$actor,$event,$this->now]);
    }
    private function limit(string $bucket,int $max,int $seconds): void {
        $this->beginWrite();
        try {
            $r=$this->run('SELECT * FROM rate_limits WHERE bucket=?',[$bucket])->fetch();
            if (!$r || (int)$r['expires_at']<=$this->now) {
                $upsert=$this->mysql
                    ? 'ON DUPLICATE KEY UPDATE count=1,expires_at=VALUES(expires_at)'
                    : 'ON CONFLICT(bucket) DO UPDATE SET count=1,expires_at=excluded.expires_at';
                $this->run('INSERT INTO rate_limits(bucket,count,expires_at) VALUES(?,1,?) '.$upsert,
                    [$bucket,$this->now+$seconds]);
            } elseif ((int)$r['count'] >= $max) {
                $this->db->exec('COMMIT');
                $this->fail(429,'RATE_LIMITED','Limite de solicitações atingido.');
            } else $this->run('UPDATE rate_limits SET count=count+1 WHERE bucket=?',[$bucket]);
            $this->db->exec('COMMIT');
        } catch(Throwable $e) {
            // A 429 has already committed its read-only decision.
            if (!($e instanceof ApiError && $e->status===429)) $this->db->exec('ROLLBACK');
            throw $e;
        }
    }
    private function expire(): void {
        // Enforced during every request, independent of cron.
        $this->run("UPDATE sessions SET state='expired', ended_at=?, reason='timeout'
                    WHERE state IN ('pending','accepted','connecting','active') AND expires_at<=?",
                    [$this->now,$this->now]);
        $this->run('DELETE FROM idempotency WHERE expires_at<=?',[$this->now]);
        $this->run('DELETE FROM rate_limits WHERE expires_at<=?',[$this->now]);
    }
    private function authenticate(array $headers): array {
        $auth=$headers['authorization']??'';
        if (!preg_match('/^Bearer ([a-f0-9]{64})$/D',$auth,$m))
            $this->fail(401,'UNAUTHORIZED','Credencial ausente ou inválida.');
        $d=$this->run('SELECT * FROM devices WHERE token_hash=? AND token_expires>?',
            [hash('sha256',$m[1]),$this->now])->fetch();
        if (!$d) $this->fail(401,'UNAUTHORIZED','Credencial ausente ou inválida.');
        return $d;
    }
    private function view(array $s): array {
        $r=$this->run('SELECT public_key,display_name FROM devices WHERE id=?',[$s['requester_id']])->fetch();
        return ['id'=>$s['id'],'state'=>$s['state'],'requester_id'=>$s['requester_id'],
            'host_id'=>$s['host_id'],'requester_key'=>$r['public_key'],'requester_name'=>$r['display_name'],
            'requested_permissions'=>json_decode($s['requested'],true),
            'granted_permissions'=>json_decode($s['granted'],true),
            'expires_at'=>gmdate('Y-m-d\TH:i:s\Z',(int)$s['expires_at']),
            'reason'=>$s['reason']];
    }
    private function session(string $id,string $device): array {
        $s=$this->run('SELECT * FROM sessions WHERE id=? AND (host_id=? OR requester_id=?)',[$id,$device,$device])->fetch();
        if (!$s) $this->fail(404,'NOT_FOUND','Sessão não encontrada.');
        return $s;
    }
    private function publishEndpoint(array $device,array $body,string $ip): array {
        $port=$body['port']??null;
        if (!is_int($port) || $port<1024 || $port>65535 || ($body['transport']??null)!=='tcp')
            $this->fail(400,'VALIDATION_ERROR','Informe porta TCP inteira entre 1024 e 65535.');
        if (array_diff(array_keys($body),['port','transport']))
            $this->fail(400,'VALIDATION_ERROR','Somente port e transport sao aceitos; o IP e observado pelo servidor.');
        if (filter_var($ip,FILTER_VALIDATE_IP)===false)
            $this->fail(400,'INVALID_SOURCE_ADDRESS','Endereco de origem indisponivel.');
        $upsert=$this->mysql
            ? 'ON DUPLICATE KEY UPDATE observed_ip=VALUES(observed_ip),port=VALUES(port),
                transport=VALUES(transport),updated_at=VALUES(updated_at)'
            : 'ON CONFLICT(device_id) DO UPDATE SET observed_ip=excluded.observed_ip,
                port=excluded.port,transport=excluded.transport,updated_at=excluded.updated_at';
        $this->run('INSERT INTO device_endpoints(device_id,observed_ip,port,transport,updated_at)
            VALUES(?,?,?,?,?) '.$upsert,
            [$device['id'],$ip,$port,'tcp',$this->now]);
        $this->run('UPDATE devices SET last_seen=? WHERE id=?',[$this->now,$device['id']]);
        return ['observed_ip'=>$ip,'port'=>$port,'transport'=>'tcp',
            'expires_at'=>gmdate('Y-m-d\TH:i:s\Z',$this->now+45),
            'next_endpoint_update_seconds'=>15,'reachability'=>'unverified'];
    }
    private function peerEndpoint(array $session,string $device): array {
        if (in_array($session['state'],['expired','closed','cancelled','rejected'],true))
            $this->fail(410,'SESSION_ENDED','Sessao encerrada ou expirada.');
        if (!in_array($session['state'],['accepted','connecting','active'],true))
            $this->fail(403,'CONSENT_REQUIRED','O host ainda nao autorizou a conexao.');
        $peer=$session['host_id']===$device ? $session['requester_id'] : $session['host_id'];
        $endpoint=$this->run('SELECT e.*,d.public_key FROM device_endpoints e
            JOIN devices d ON d.id=e.device_id WHERE e.device_id=? AND e.updated_at>?
            AND d.last_seen>? AND d.token_expires>?',
            [$peer,$this->now-45,$this->now-45,$this->now])->fetch();
        if (!$endpoint) $this->fail(409,'PEER_UNAVAILABLE','O outro computador nao anunciou uma porta recente.');
        return ['session_id'=>$session['id'],'peer_device_id'=>$peer,'peer_key'=>$endpoint['public_key'],
            'observed_ip'=>$endpoint['observed_ip'],'port'=>(int)$endpoint['port'],
            'transport'=>$endpoint['transport'],'reachability'=>'unverified',
            'endpoint_expires_at'=>gmdate('Y-m-d\TH:i:s\Z',(int)$endpoint['updated_at']+45),
            'session_expires_at'=>gmdate('Y-m-d\TH:i:s\Z',(int)$session['expires_at']),
            'granted_permissions'=>json_decode($session['granted'],true)];
    }
    private function register(array $b): array {
        $rid=$this->text($b,'registration_id',36);
        $secret=$this->text($b,'registration_secret',64);
        if (!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/D',$rid) || !preg_match('/^[a-f0-9]{64}$/D',$secret))
            $this->fail(400,'VALIDATION_ERROR','Identidade de registro inválida.');
        $name=$this->text($b,'display_name',80);
        $platform=$this->text($b,'platform',40);
        $version=$this->text($b,'app_version',40);
        $d=$this->run('SELECT * FROM devices WHERE registration_id=?',[$rid])->fetch();
        $hash=hash('sha256',$secret); $token=bin2hex(random_bytes(32)); $exp=$this->now+2592000;
        if ($d) {
            if (!hash_equals($d['registration_hash'],$hash))
                $this->fail(409,'REGISTRATION_CONFLICT','Registro indisponível.');
            $id=$d['id']; $key=$d['public_key'];
            $this->run('UPDATE devices SET token_hash=?,token_expires=?,last_seen=?,platform=?,app_version=? WHERE id=?',
                [hash('sha256',$token),$exp,$this->now,$platform,$version,$id]);
        } else {
            $id=self::uuid();
            do {
                $key='';
                for($i=0;$i<10;$i++) $key.=(string)random_int(0,9);
            } while($this->run('SELECT id FROM devices WHERE public_key=?',[$key])->fetch());
            $this->run('INSERT INTO devices(id,public_key,registration_id,registration_hash,token_hash,token_expires,display_name,platform,app_version,last_seen,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                [$id,$key,$rid,$hash,hash('sha256',$token),$exp,$name,$platform,$version,$this->now,$this->now]);
        }
        (new DesktopData($this->db,$this->now))->preferences($id);
        $this->audit('device.registered',$id);
        return ['device_id'=>$id,'public_key'=>$key,'device_token'=>$token,
            'expires_at'=>gmdate('Y-m-d\TH:i:s\Z',$exp)];
    }
    /** Returns [HTTP status, JSON-compatible body]. Headers use lowercase names. */
    public function handle(string $method,string $path,array $headers=[],array $body=[],string $ip='local'): array {
        $this->now=$this->clock ? ($this->clock)() : time();
        $headers=array_change_key_case($headers,CASE_LOWER);
        $requestId=self::uuid(); $transaction=false;
        try {
            if ($method==='GET' && $path==='/health') {
                $this->db->query('SELECT id FROM devices LIMIT 1');
                $this->db->query('SELECT device_id FROM device_endpoints LIMIT 1');
                $version=$this->db->query("SELECT valor FROM params WHERE chave='VERSAO'")->fetchColumn();
                return [200,['data'=>['status'=>'ok','version'=>$version,'stage'=>'p2p-discovery'],'request_id'=>$requestId]];
            }
            $device=null;
            if ($method==='POST' && $path==='/devices') $this->limit('register:'.hash('sha256',$ip),5,3600);
            else $device=$this->authenticate($headers);
            if ($method==='POST' && $path==='/sessions') {
                $this->limit('request:'.$device['id'],10,60);
                if (isset($body['target_key']) && is_string($body['target_key']))
                    $this->limit('target:'.$body['target_key'],5,60);
            }
            $this->beginWrite(); $transaction=true;
            // Recheck inside the write transaction, so concurrent expiry cannot be bypassed.
            $this->expire();
            if ($device) $device=$this->authenticate($headers);
            $status=200; $data=null; $idem=null; $bodyHash=hash('sha256',json_encode($body,JSON_THROW_ON_ERROR));
            if ($device && $method!=='GET') {
                $idem=$headers['idempotency-key']??'';
                if (!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/Di',$idem))
                    $this->fail(400,'VALIDATION_ERROR','Idempotency-Key UUID obrigatório.');
                $cached=$this->run('SELECT * FROM idempotency WHERE device_id=? AND route=? AND `key`=?',
                    [$device['id'],$method.' '.$path,$idem])->fetch();
                if ($cached) {
                    if (!hash_equals($cached['body_hash'],$bodyHash))
                        $this->fail(409,'IDEMPOTENCY_CONFLICT','Chave reutilizada com outro corpo.');
                    $this->db->exec('COMMIT'); $transaction=false;
                    return [(int)$cached['status'],['data'=>json_decode($cached['response'],true),'request_id'=>$requestId]];
                }
            }
            if ($method==='POST' && $path==='/devices') {
                $data=$this->register($body); $status=201;
            } elseif ($method==='POST' && $path==='/devices/endpoint') {
                $data=$this->publishEndpoint($device,$body,$ip);
            } elseif ($method==='POST' && $path==='/devices/heartbeat') {
                $this->run('UPDATE devices SET last_seen=? WHERE id=?',[$this->now,$device['id']]);
                $data=['server_time'=>gmdate('Y-m-d\TH:i:s\Z',$this->now),'next_heartbeat_seconds'=>15];
            } elseif ($method==='GET' && $path==='/desktop') {
                $data=(new DesktopData($this->db,$this->now))->dashboard($device);
            } elseif ($method==='PATCH' && $path==='/devices/me') {
                $data=(new DesktopData($this->db,$this->now))->rename($device,$body);
            } elseif ($method==='PATCH' && $path==='/desktop/preferences') {
                $data=(new DesktopData($this->db,$this->now))->updatePreferences($device['id'],$body);
            } elseif ($method==='GET' && $path==='/contacts') {
                $data=(new DesktopData($this->db,$this->now))->contacts($device['id']);
            } elseif ($method==='POST' && $path==='/contacts') {
                $data=(new DesktopData($this->db,$this->now))->saveContact($device,$body);
            } elseif (preg_match('#^/contacts/([a-f0-9-]{36})$#D',$path,$contact)) {
                $ui=new DesktopData($this->db,$this->now);
                if ($method==='PATCH') $data=$ui->saveContact($device,$body,$contact[1]);
                elseif ($method==='DELETE') $data=$ui->deleteContact($device['id'],$contact[1]);
                else $this->fail(404,'NOT_FOUND','Rota nao encontrada.');
            } elseif ($method==='GET' && $path==='/sessions/recent') {
                $data=(new DesktopData($this->db,$this->now))->recent($device['id']);
            } elseif ($method==='POST' && $path==='/sessions') {
                $key=$this->text($body,'target_key',10);
                if (!preg_match('/^[0-9]{10}$/D',$key)) $this->fail(400,'VALIDATION_ERROR','Chave deve ter 10 dígitos.');
                $perms=$this->permissions($body['requested_permissions']??null);
                $host=$this->run('SELECT id FROM devices WHERE public_key=? AND last_seen>? AND token_expires>?',
                    [$key,$this->now-45,$this->now])->fetch();
                if (!$host) $this->fail(404,'TARGET_UNAVAILABLE','Destino indisponível.');
                if ($host['id']===$device['id']) $this->fail(400,'VALIDATION_ERROR','Não conecte à própria máquina.');
                $id=self::uuid();
                $this->run("INSERT INTO sessions(id,requester_id,host_id,state,requested,granted,created_at,expires_at) VALUES(?,?,?,'pending',?,'[]',?,?)",
                    [$id,$device['id'],$host['id'],json_encode($perms),$this->now,$this->now+60]);
                $this->audit('session.requested',$device['id'],$id);
                $data=$this->view($this->session($id,$device['id'])); $status=201;
            } elseif ($method==='GET' && $path==='/sessions/incoming') {
                $rows=$this->run("SELECT * FROM sessions WHERE host_id=? AND state='pending' ORDER BY created_at,id LIMIT 100",
                    [$device['id']])->fetchAll();
                $data=['items'=>array_map(fn($s)=>$this->view($s),$rows),'server_time'=>gmdate('c',$this->now)];
            } elseif (preg_match('#^/sessions/([a-f0-9-]{36})(?:/(decision|cancel|close|peer))?$#D',$path,$m)) {
                $s=$this->session($m[1],$device['id']); $action=$m[2]??'';
                if ($method==='GET' && $action==='') $data=$this->view($s);
                elseif ($method==='GET' && $action==='peer') $data=$this->peerEndpoint($s,$device['id']);
                elseif ($method==='POST' && $action==='close') {
                    if (in_array($s['state'],['pending','accepted','connecting','active'],true)) {
                        $reason=$this->text($body,'reason',80);
                        $this->run("UPDATE sessions SET state='closed',ended_at=?,reason=? WHERE id=?",[$this->now,$reason,$s['id']]);
                        $this->audit('session.closed',$device['id'],$s['id']);
                    }
                    $data=$this->view($this->session($s['id'],$device['id']));
                } elseif ($method==='POST' && in_array($action,['decision','cancel'],true)) {
                    if ($action==='decision' && $s['host_id']!==$device['id'])
                        $this->fail(403,'FORBIDDEN','Somente o host pode decidir.');
                    if ($action==='cancel' && $s['requester_id']!==$device['id'])
                        $this->fail(403,'FORBIDDEN','Somente o solicitante pode cancelar.');
                    if ($s['state']==='expired') $this->fail(410,'SESSION_EXPIRED','Pedido expirado.');
                    if ($s['state']!=='pending') $this->fail(409,'INVALID_STATE','Pedido já decidido.');
                    $state='cancelled'; $granted=[];
                    if ($action==='decision') {
                        $decision=$this->text($body,'decision',6);
                        if (!in_array($decision,['accept','reject'],true)) $this->fail(400,'VALIDATION_ERROR','Decisão inválida.');
                        $state=$decision==='accept'?'accepted':'rejected';
                        if ($state==='accepted') {
                            $granted=$this->permissions($body['granted_permissions']??null);
                            if (array_diff($granted,json_decode($s['requested'],true)))
                                $this->fail(400,'VALIDATION_ERROR','Permissão não solicitada.');
                            if ($this->run("SELECT id FROM sessions WHERE host_id=? AND state IN ('accepted','connecting','active')",
                                [$device['id']])->fetch()) $this->fail(409,'HOST_BUSY','Host ocupado.');
                        }
                    }
                    $expires=$state==='accepted'?$this->now+30:(int)$s['expires_at'];
                    $this->run('UPDATE sessions SET state=?,granted=?,expires_at=?,ended_at=? WHERE id=?',
                        [$state,json_encode($granted),$expires,$state==='accepted'?null:$this->now,$s['id']]);
                    $this->audit('session.'.$state,$device['id'],$s['id']);
                    $data=$this->view($this->session($s['id'],$device['id']));
                } else $this->fail(404,'NOT_FOUND','Rota não encontrada.');
            } else $this->fail(404,'NOT_FOUND','Rota não implementada.');
            if ($idem!==null) $this->run('INSERT INTO idempotency(device_id,route,`key`,body_hash,response,status,expires_at) VALUES(?,?,?,?,?,?,?)',
                [$device['id'],$method.' '.$path,$idem,$bodyHash,json_encode($data,JSON_THROW_ON_ERROR),$status,$this->now+86400]);
            $this->db->exec('COMMIT'); $transaction=false;
            return [$status,['data'=>$data,'request_id'=>$requestId]];
        } catch(Throwable $e) {
            if ($transaction) $this->db->exec('ROLLBACK');
            if ($e instanceof ApiError)
                return [$e->status,['error'=>['code'=>$e->errorCode,'message'=>$e->getMessage()],'request_id'=>$requestId]];
            // Do not log exception text: database values may contain credentials.
            error_log('MaurinDesk request '.$requestId.' failed: '.get_class($e));
            return [503,['error'=>['code'=>'SERVICE_UNAVAILABLE','message'=>'Serviço indisponível.'],'request_id'=>$requestId]];
        }
    }
}
