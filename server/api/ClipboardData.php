<?php
declare(strict_types=1);
namespace MaurinDesk;
use PDO;

/** Session-scoped, bidirectional clipboard. Data is never exposed to third parties. */
final class ClipboardData {
    public const CHUNK_BYTES=262144;
    public const MAX_BYTES=268435456;
    public function __construct(private PDO $db, private int $now) {}
    private function run(string $sql,array $args=[]): \PDOStatement {
        $q=$this->db->prepare($sql); $q->execute($args); return $q;
    }
    private function fail(int $status,string $message): never {
        throw new ApiError($status,'CLIPBOARD_ERROR',$message);
    }
    public function handle(string $method,array $session,string $actor,array $body,?string $id,?int $part): array {
        if (!in_array($session['state'],['accepted','connecting','active'],true) || (int)$session['expires_at']<=$this->now ||
            !in_array('clipboard.sync',json_decode($session['granted'],true)?:[],true))
            $this->fail(403,'Area de transferencia nao autorizada para esta sessao.');
        if ($id===null && $method==='GET') {
            $row=$this->run('SELECT id,kind,total_bytes,checksum,chunk_count FROM clipboard_transfers
                WHERE session_id=? AND sender_id<>? AND ready=1 ORDER BY updated_at DESC,id DESC LIMIT 1',
                [$session['id'],$actor])->fetch(PDO::FETCH_ASSOC);
            if (!$row) return ['status'=>'empty'];
            return ['status'=>'ready','id'=>$row['id'],'kind'=>$row['kind'],'total_bytes'=>(int)$row['total_bytes'],
                'checksum'=>$row['checksum'],'chunk_count'=>(int)$row['chunk_count']];
        }
        if ($id===null && $method==='POST') {
            $kind=$body['kind']??null; $size=$body['total_bytes']??null; $hash=$body['checksum']??'';
            if (!in_array($kind,['text','files'],true) || !is_int($size) || $size<0 || $size>self::MAX_BYTES ||
                ($kind==='text' && $size>1048576) || !is_string($hash) || !preg_match('/^[a-f0-9]{40}$/D',$hash))
                $this->fail(400,'Conteudo ou tamanho da area de transferencia invalido.');
            // Keep the previous completed item until the replacement is complete; at most one upload per sender.
            $this->run('DELETE FROM clipboard_transfers WHERE session_id=? AND sender_id=? AND ready=0',[$session['id'],$actor]);
            $id=Api::uuid(); $count=max(1,(int)ceil($size/self::CHUNK_BYTES));
            $this->run('INSERT INTO clipboard_transfers(id,session_id,sender_id,kind,total_bytes,checksum,chunk_count,ready,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?,0,?,?)',[$id,$session['id'],$actor,$kind,$size,$hash,$count,$this->now,$this->now]);
            return ['id'=>$id,'chunk_count'=>$count,'chunk_bytes'=>self::CHUNK_BYTES];
        }
        $t=$id===null?false:$this->run('SELECT * FROM clipboard_transfers WHERE id=? AND session_id=?',[$id,$session['id']])->fetch(PDO::FETCH_ASSOC);
        if (!$t) $this->fail(404,'Transferencia nao encontrada.');
        if ($part!==null && ($part<0 || $part>=(int)$t['chunk_count'])) $this->fail(400,'Parte invalida.');
        if ($method==='GET' && $part!==null) {
            if ($t['sender_id']===$actor || !(int)$t['ready']) $this->fail(403,'Transferencia ainda nao disponivel.');
            $row=$this->run('SELECT data FROM clipboard_chunks WHERE transfer_id=? AND part=?',[$id,$part])->fetch(PDO::FETCH_ASSOC);
            if (!$row) $this->fail(404,'Parte nao encontrada.');
            return ['data'=>$row['data'],'part'=>$part];
        }
        if ($method!=='POST' || $t['sender_id']!==$actor) $this->fail(403,'Apenas o remetente pode enviar esta transferencia.');
        if ($part!==null) {
            if ((int)$t['ready']) $this->fail(409,'Transferencia ja concluida.');
            $data=$body['data']??null;
            if (!is_string($data) || strlen($data)>349528) $this->fail(400,'Parte excede o limite.');
            $raw=base64_decode($data,true);
            $expected=$part===(int)$t['chunk_count']-1?(int)$t['total_bytes']-$part*self::CHUNK_BYTES:self::CHUNK_BYTES;
            if ($raw===false || strlen($raw)!==$expected) $this->fail(400,'Tamanho da parte invalido.');
            $previous=$this->run('SELECT data FROM clipboard_chunks WHERE transfer_id=? AND part=?',[$id,$part])->fetchColumn();
            if ($previous!==false && $previous!==$data) $this->fail(409,'Parte reenviada com conteudo diferente.');
            if ($previous===false) $this->run('INSERT INTO clipboard_chunks(transfer_id,part,data) VALUES(?,?,?)',[$id,$part,$data]);
            $this->run('UPDATE clipboard_transfers SET updated_at=? WHERE id=?',[$this->now,$id]);
            return ['status'=>'stored','part'=>$part];
        }
        if (!(int)$t['ready']) {
            $count=(int)$this->run('SELECT COUNT(*) FROM clipboard_chunks WHERE transfer_id=?',[$id])->fetchColumn();
            if ($count!==(int)$t['chunk_count']) $this->fail(409,'Partes incompletas.');
            $hash=hash_init('sha1'); $size=0;
            // Fetch one chunk at a time: PDO MySQL's default buffering must not load a 256 MiB upload in PHP memory.
            for ($index=0;$index<$count;$index++) {
                $data=$this->run('SELECT data FROM clipboard_chunks WHERE transfer_id=? AND part=?',[$id,$index])->fetchColumn();
                if ($data===false) $this->fail(409,'Partes incompletas.');
                $raw=base64_decode($data,true); $size+=strlen($raw); hash_update($hash,$raw);
            }
            if ($count!==(int)$t['chunk_count'] || $size!==(int)$t['total_bytes'] || !hash_equals($t['checksum'],hash_final($hash)))
                $this->fail(409,'Transferencia incompleta ou verificacao de integridade falhou.');
            $this->run('UPDATE clipboard_transfers SET ready=1,updated_at=? WHERE id=?',[$this->now,$id]);
            $this->run('DELETE FROM clipboard_transfers WHERE session_id=? AND sender_id=? AND id<>?',[$session['id'],$actor,$id]);
        }
        return ['status'=>'ready','id'=>$id];
    }
}
