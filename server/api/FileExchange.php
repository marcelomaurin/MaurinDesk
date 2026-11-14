<?php
declare(strict_types=1);
namespace MaurinDesk;
use PDO;

/** Only exchanges session-authorized messages/bytes. PHP never opens client filesystem paths. */
final class FileExchange {
    public function __construct(private PDO $db,private int $now) {}
    private function run(string $sql,array $args=[]): \PDOStatement {
        $q=$this->db->prepare($sql); $q->execute($args); return $q;
    }
    private function fail(int $status,string $message): never { throw new ApiError($status,'FILE_EXCHANGE_ERROR',$message); }
    private function path(mixed $path,bool $special=false): string {
        if (!is_string($path) || strlen($path)>2048 || preg_match('/[\x00-\x1f]/',$path)) $this->fail(400,'Caminho invalido.');
        if ($special && in_array($path,['','@home'],true)) return $path;
        if (!preg_match('#^[a-zA-Z]:[\\\\/]#D',$path)) $this->fail(400,'Selecione uma pasta local do computador.');
        return $path;
    }
    private function uuid(mixed $id): string {
        if (!is_string($id) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/D',$id))
            $this->fail(400,'Identificador invalido.');
        return $id;
    }
    private function authorize(array $s): void {
        if (!in_array($s['state'],['accepted','connecting','active'],true) || (int)$s['expires_at']<=$this->now ||
            !in_array('files.transfer',json_decode($s['granted'],true)?:[],true))
            $this->fail(403,'Acesso a arquivos nao autorizado nesta sessao.');
    }
    public function handle(string $method,array $s,string $actor,string $channel,?string $id,?string $part,array $body): array {
        $this->authorize($s);
        $peer=$s['host_id']===$actor?$s['requester_id']:$s['host_id'];
        if ($channel==='commands') {
            if ($id===null && $method==='POST') {
                $version=(string)$this->run('SELECT app_version FROM devices WHERE id=?',[$peer])->fetchColumn();
                if (version_compare($version,'0.6.7','<')) $this->fail(409,'Atualize os dois computadores para a versao 0.6.7 ou posterior.');
                $action=$body['action']??'';
                if (!in_array($action,['list','send','mkdir','job_error'],true)) $this->fail(400,'Acao de arquivos invalida.');
                if (strlen(json_encode($body,JSON_THROW_ON_ERROR))>131072) $this->fail(400,'Solicitacao muito grande.');
                if ($action==='list') {
                    $this->path($body['path']??null,true);
                    if (!is_int($body['offset']??0) || ($body['offset']??0)<0 || ($body['offset']??0)>1000000 ||
                        !is_string($body['filter']??'') || strlen($body['filter']??'')>128) $this->fail(400,'Filtro ou pagina invalida.');
                } elseif ($action==='mkdir') {
                    $this->path($body['path']??null);
                    $name=$body['name']??'';
                    if (!is_string($name) || $name==='' || strlen($name)>255 || preg_match('#[\\\\/:\x00-\x1f]#',$name)) $this->fail(400,'Nome de pasta invalido.');
                } elseif ($action==='job_error') {
                    $this->uuid($body['request_id']??null); $this->path($body['destination']??null);
                    if (!is_string($body['message']??null) || strlen($body['message'])>2048) $this->fail(400,'Erro de arquivo invalido.');
                } else {
                    $paths=$body['paths']??null;
                    if (!is_array($paths) || !array_is_list($paths) || count($paths)<1 || count($paths)>128) $this->fail(400,'Selecione ate 128 itens ou uma pasta.');
                    foreach ($paths as $path) $this->path($path);
                    $this->path($body['destination']??null); $this->uuid($body['request_id']??null);
                    if (!is_bool($body['overwrite']??false)) $this->fail(400,'Opcao de substituicao invalida.');
                }
                $pending=(int)$this->run("SELECT COUNT(*) FROM file_commands WHERE session_id=? AND sender_id=? AND state IN ('pending','running')",[$s['id'],$actor])->fetchColumn();
                if ($pending>=16) $this->fail(429,'Aguarde as solicitacoes de arquivos pendentes.');
                $id=Api::uuid();
                $this->run("INSERT INTO file_commands(id,session_id,sender_id,receiver_id,action,payload,state,created_at) VALUES(?,?,?,?,?,?,'pending',?)",
                    [$id,$s['id'],$actor,$peer,$action,json_encode($body,JSON_THROW_ON_ERROR),$this->now]);
                return ['id'=>$id,'state'=>'pending'];
            }
            if ($id===null && $method==='GET') {
                $rows=$this->run("SELECT id,action,payload FROM file_commands WHERE session_id=? AND receiver_id=?
                    AND (state='pending' OR (state='running' AND lease_until<=?)) ORDER BY created_at,id LIMIT 4",[$s['id'],$actor,$this->now])->fetchAll(PDO::FETCH_ASSOC);
                $items=[];
                foreach ($rows as $row) {
                    $this->run("UPDATE file_commands SET state='running',lease_until=? WHERE id=?",[$this->now+60,$row['id']]);
                    $items[]=['id'=>$row['id'],'action'=>$row['action'],'payload'=>json_decode($row['payload'],true)];
                }
                return ['items'=>$items];
            }
            $row=$this->run('SELECT * FROM file_commands WHERE id=? AND session_id=?',[$id,$s['id']])->fetch(PDO::FETCH_ASSOC);
            if (!$row) $this->fail(404,'Solicitacao de arquivos nao encontrada.');
            if ($method==='GET' && $actor===$row['sender_id'])
                return ['id'=>$id,'state'=>$row['state'],'response'=>$row['response']!==null?json_decode($row['response'],true):null];
            if ($method==='POST' && $actor===$row['receiver_id']) {
                $result=$body['response']??null;
                if (!is_array($result) || strlen(json_encode($result,JSON_THROW_ON_ERROR))>524288) $this->fail(400,'Resposta de arquivos invalida.');
                if ($row['state']==='completed') return ['id'=>$id,'state'=>'completed'];
                $this->run("UPDATE file_commands SET state='completed',response=? WHERE id=?",[json_encode($result,JSON_THROW_ON_ERROR),$id]);
                return ['id'=>$id,'state'=>'completed'];
            }
            $this->fail(403,'Operacao de arquivos nao permitida.');
        }
        if ($channel!=='transfers') $this->fail(404,'Rota de arquivos nao encontrada.');
        if ($id===null && $method==='POST') {
            $requestId=$this->uuid($body['request_id']??null); $destination=$this->path($body['destination']??null);
            $size=$body['total_bytes']??null; $checksum=$body['checksum']??null; $overwrite=$body['overwrite']??false;
            if (!is_int($size) || $size<4 || $size>ClipboardData::MAX_BYTES || !is_bool($overwrite) ||
                !is_string($checksum) || !preg_match('/^[a-f0-9]{40}$/D',$checksum)) $this->fail(400,'Pacote de arquivos invalido.');
            $existing=$this->run('SELECT * FROM file_transfers WHERE session_id=? AND sender_id=? AND request_id=?',[$s['id'],$actor,$requestId])->fetch(PDO::FETCH_ASSOC);
            if ($existing) {
                if ($existing['checksum']!==$checksum || (int)$existing['total_bytes']!==$size || $existing['destination']!==$destination || (bool)$existing['overwrite_existing']!==$overwrite)
                    $this->fail(409,'Transferencia repetida com dados diferentes.');
                return ['id'=>$existing['id'],'chunk_count'=>(int)$existing['chunk_count'],'state'=>$existing['state']];
            }
            $used=(int)$this->run("SELECT COALESCE(SUM(total_bytes),0) FROM file_transfers WHERE sender_id=? AND state IN ('uploading','ready','receiving')",[$actor])->fetchColumn();
            if ($used+$size>ClipboardData::MAX_BYTES) $this->fail(429,'Aguarde a transferencia anterior terminar.');
            $id=Api::uuid(); $count=(int)ceil($size/ClipboardData::CHUNK_BYTES);
            $this->run("INSERT INTO file_transfers(id,session_id,sender_id,receiver_id,request_id,destination,overwrite_existing,total_bytes,checksum,chunk_count,state,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?,?,?,?,'uploading',?,?)",[$id,$s['id'],$actor,$peer,$requestId,$destination,(int)$overwrite,$size,$checksum,$count,$this->now,$this->now]);
            return ['id'=>$id,'chunk_count'=>$count,'state'=>'uploading'];
        }
        if ($id===null && $method==='GET') {
            $rows=$this->run("SELECT id,request_id,destination,overwrite_existing,total_bytes,checksum,chunk_count FROM file_transfers
                WHERE session_id=? AND receiver_id=? AND (state='ready' OR (state='receiving' AND lease_until<=?)) ORDER BY created_at,id LIMIT 1",[$s['id'],$actor,$this->now])->fetchAll(PDO::FETCH_ASSOC);
            foreach ($rows as &$row) { $row['total_bytes']=(int)$row['total_bytes']; $row['chunk_count']=(int)$row['chunk_count']; $row['overwrite']=(bool)$row['overwrite_existing']; unset($row['overwrite_existing']); }
            return ['items'=>$rows];
        }
        $t=$this->run('SELECT * FROM file_transfers WHERE id=? AND session_id=?',[$id,$s['id']])->fetch(PDO::FETCH_ASSOC);
        if (!$t) $this->fail(404,'Transferencia nao encontrada.');
        if ($part===null && $method==='GET') return ['id'=>$id,'request_id'=>$t['request_id'],'state'=>$t['state'],
            'destination'=>$t['destination'],'result'=>$t['result']!==null?json_decode($t['result'],true):null];
        if ($part==='claim' && $method==='POST' && $actor===$t['receiver_id']) {
            $owner=$this->uuid($body['owner']??null);
            if (!in_array($t['state'],['ready','receiving'],true) ||
                ($t['state']==='receiving' && (int)$t['lease_until']>$this->now && $t['lease_owner']!==$owner)) $this->fail(409,'Transferencia ja esta sendo recebida.');
            $this->run("UPDATE file_transfers SET state='receiving',lease_owner=?,lease_until=?,updated_at=? WHERE id=?",[$owner,$this->now+60,$this->now,$id]);
            return ['id'=>$id,'state'=>'receiving'];
        }
        if ($part===null && $method==='POST' && isset($body['state'])) {
            $state=$body['state']; $result=$body['result']??[];
            if (!in_array($state,['completed','error'],true) || !is_array($result) || strlen(json_encode($result,JSON_THROW_ON_ERROR))>16384)
                $this->fail(400,'Resultado de transferencia invalido.');
            if ($actor===$t['receiver_id'] && $t['lease_owner']===($body['owner']??null) && $t['state']===$state) return ['id'=>$id,'state'=>$state];
            if ($actor!==$t['receiver_id'] || $t['lease_owner']!==($body['owner']??null) || $t['state']!=='receiving') $this->fail(403,'Somente quem recebe confirma a gravacao.');
            $this->run('UPDATE file_transfers SET state=?,result=?,updated_at=? WHERE id=?',[$state,json_encode($result,JSON_THROW_ON_ERROR),$this->now,$id]);
            $this->run('DELETE FROM file_chunks WHERE transfer_id=?',[$id]);
            return ['id'=>$id,'state'=>$state];
        }
        if ($part!==null) {
            if (!ctype_digit($part) || (int)$part>=(int)$t['chunk_count']) $this->fail(400,'Parte invalida.');
            $index=(int)$part;
            if ($method==='GET' && $actor===$t['receiver_id'] && in_array($t['state'],['ready','receiving'],true)) {
                $data=$this->run('SELECT data FROM file_chunks WHERE transfer_id=? AND part=?',[$id,$index])->fetchColumn();
                if ($data===false) $this->fail(404,'Parte nao encontrada.'); return ['data'=>$data];
            }
            if ($method!=='POST' || $actor!==$t['sender_id'] || $t['state']!=='uploading') $this->fail(403,'Envio de parte nao permitido.');
            $data=$body['data']??null; if (!is_string($data) || strlen($data)>349528) $this->fail(400,'Parte excedente.');
            $raw=base64_decode($data,true); $expected=$index===(int)$t['chunk_count']-1?(int)$t['total_bytes']-$index*ClipboardData::CHUNK_BYTES:ClipboardData::CHUNK_BYTES;
            if ($raw===false || strlen($raw)!==$expected) $this->fail(400,'Parte incompleta.');
            $old=$this->run('SELECT data FROM file_chunks WHERE transfer_id=? AND part=?',[$id,$index])->fetchColumn();
            if ($old!==false && $old!==$data) $this->fail(409,'Parte alterada.');
            if ($old===false) $this->run('INSERT INTO file_chunks(transfer_id,part,data) VALUES(?,?,?)',[$id,$index,$data]);
            $this->run('UPDATE file_transfers SET updated_at=? WHERE id=?',[$this->now,$id]); return ['state'=>'stored'];
        }
        if ($method==='POST' && $actor===$t['sender_id']) {
            if ($t['state']!=='uploading') return ['id'=>$id,'state'=>$t['state']];
            $hash=hash_init('sha1'); $size=0;
            for ($i=0;$i<(int)$t['chunk_count'];$i++) {
                $data=$this->run('SELECT data FROM file_chunks WHERE transfer_id=? AND part=?',[$id,$i])->fetchColumn();
                if ($data===false) $this->fail(409,'Pacote incompleto.');
                $raw=base64_decode($data,true); $size+=strlen($raw); hash_update($hash,$raw);
            }
            if ($size!==(int)$t['total_bytes'] || !hash_equals($t['checksum'],hash_final($hash))) $this->fail(409,'Integridade do pacote invalida.');
            $this->run("UPDATE file_transfers SET state='ready',updated_at=? WHERE id=?",[$this->now,$id]); return ['id'=>$id,'state'=>'ready'];
        }
        $this->fail(403,'Operacao de transferencia nao permitida.');
    }
}
