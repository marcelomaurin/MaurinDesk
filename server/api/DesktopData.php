<?php
declare(strict_types=1);
namespace MaurinDesk;
use PDO;

/** Metadata for desktop cards. Never stores remote-screen thumbnails or peer IPs. */
final class DesktopData {
    public function __construct(private PDO $db,private int $now) { }
    private function run(string $sql,array $args=[]): \PDOStatement {
        $q=$this->db->prepare($sql); $q->execute($args); return $q;
    }
    private function invalid(): never {
        throw new ApiError(400,'VALIDATION_ERROR','Dados da interface invalidos.');
    }
    private function fields(array $body,array $allowed): void {
        if (array_diff(array_keys($body),$allowed)) $this->invalid();
    }
    private function label(mixed $value): string {
        if (!is_string($value) || strlen($value)>80 || preg_match('/[\x00-\x1f]/',$value)) $this->invalid();
        return trim($value);
    }
    public function preferences(string $owner): array {
        $p=$this->run('SELECT language,theme,view_mode,sort_by,updated_at FROM device_preferences WHERE device_id=?',[$owner])->fetch(PDO::FETCH_ASSOC);
        if (!$p) {
            $this->run('INSERT INTO device_preferences(device_id,updated_at) VALUES(?,?)',[$owner,$this->now]);
            return $this->preferences($owner);
        }
        $p['updated_at']=gmdate('Y-m-d\TH:i:s\Z',(int)$p['updated_at']);
        return $p;
    }
    public function updatePreferences(string $owner,array $body): array {
        $this->fields($body,['language','theme','view_mode','sort_by']);
        $p=$this->preferences($owner);
        foreach ($body as $key=>$value) $p[$key]=$value;
        if (!is_string($p['language']) || !preg_match('/^[a-z]{2,3}(?:-[A-Z]{2})?$/D',$p['language']) ||
            !in_array($p['theme'],['system','light','dark'],true) ||
            !in_array($p['view_mode'],['cards','list'],true) ||
            !in_array($p['sort_by'],['last_used','name'],true)) $this->invalid();
        $this->run('UPDATE device_preferences SET language=?,theme=?,view_mode=?,sort_by=?,updated_at=? WHERE device_id=?',
            [$p['language'],$p['theme'],$p['view_mode'],$p['sort_by'],$this->now,$owner]);
        return $this->preferences($owner);
    }
    public function rename(array $device,array $body): array {
        $this->fields($body,['display_name']);
        $name=$this->label($body['display_name']??null);
        if ($name==='') $this->invalid();
        $this->run('UPDATE devices SET display_name=? WHERE id=?',[$name,$device['id']]);
        return ['device_id'=>$device['id'],'public_key'=>$device['public_key'],'display_name'=>$name];
    }
    private function contactView(array $c): array {
        $availability='unknown';
        if (!empty($c['known_peer'])) $availability=(int)($c['last_seen']??0)>$this->now-45 &&
            (int)($c['token_expires']??0)>$this->now ? 'online' : 'offline';
        return ['id'=>$c['id'],'remote_key'=>$c['remote_key'],'alias'=>$c['alias'],
            'group_name'=>$c['group_name'],'is_favorite'=>(bool)$c['is_favorite'],
            'color'=>$c['color'],'sort_order'=>(int)$c['sort_order'],'availability'=>$availability,
            'created_at'=>gmdate('Y-m-d\TH:i:s\Z',(int)$c['created_at']),
            'updated_at'=>gmdate('Y-m-d\TH:i:s\Z',(int)$c['updated_at'])];
    }
    private function contact(string $owner,string $id): array {
        $c=$this->run('SELECT * FROM device_contacts WHERE owner_device_id=? AND id=?',[$owner,$id])->fetch(PDO::FETCH_ASSOC);
        if (!$c) throw new ApiError(404,'NOT_FOUND','Contato nao encontrado.');
        return $c;
    }
    public function contacts(string $owner): array {
        $rows=$this->run("SELECT c.*,d.last_seen,d.token_expires,
            CASE WHEN EXISTS(SELECT 1 FROM sessions s WHERE s.granted<>'[]' AND
                ((s.requester_id=c.owner_device_id AND s.host_id=d.id) OR
                 (s.host_id=c.owner_device_id AND s.requester_id=d.id))) THEN 1 ELSE 0 END AS known_peer
            FROM device_contacts c LEFT JOIN devices d ON d.public_key=c.remote_key
            WHERE c.owner_device_id=? ORDER BY c.is_favorite DESC,c.sort_order,c.alias,c.id LIMIT 500",[$owner])->fetchAll(PDO::FETCH_ASSOC);
        return ['items'=>array_map(fn($c)=>$this->contactView($c),$rows)];
    }
    public function saveContact(array $device,array $body,?string $id=null): array {
        $this->fields($body,$id===null
            ? ['remote_key','alias','group_name','is_favorite','color','sort_order']
            : ['alias','group_name','is_favorite','color','sort_order']);
        $owner=$device['id'];
        if ($id!==null) $c=$this->contact($owner,$id);
        else {
            $key=$body['remote_key']??null;
            if (!is_string($key) || !preg_match('/^[0-9]{10}$/D',$key) || $key===$device['public_key']) $this->invalid();
            $c=$this->run('SELECT * FROM device_contacts WHERE owner_device_id=? AND remote_key=?',[$owner,$key])->fetch(PDO::FETCH_ASSOC);
            if (!$c) {
                if ((int)$this->run('SELECT COUNT(*) FROM device_contacts WHERE owner_device_id=?',[$owner])->fetchColumn()>=500)
                    throw new ApiError(409,'CONTACT_LIMIT','Limite de 500 contatos atingido.');
                $c=['id'=>Api::uuid(),'remote_key'=>$key,'alias'=>'','group_name'=>'','is_favorite'=>false,
                    'color'=>'#3B82F6','sort_order'=>0,'created_at'=>$this->now];
            }
        }
        $favorite=array_key_exists('is_favorite',$body)?$body['is_favorite']:(bool)$c['is_favorite'];
        $color=array_key_exists('color',$body)?$body['color']:$c['color'];
        $order=array_key_exists('sort_order',$body)?$body['sort_order']:(int)$c['sort_order'];
        if (!is_bool($favorite) || !is_string($color) || !preg_match('/^#[0-9a-fA-F]{6}$/D',$color) ||
            !is_int($order) || $order<0 || $order>1000000) $this->invalid();
        $alias=$this->label(array_key_exists('alias',$body)?$body['alias']:$c['alias']);
        $group=$this->label(array_key_exists('group_name',$body)?$body['group_name']:$c['group_name']);
        $exists=$this->run('SELECT id FROM device_contacts WHERE id=? AND owner_device_id=?',[$c['id'],$owner])->fetchColumn();
        if ($exists) $this->run('UPDATE device_contacts SET alias=?,group_name=?,is_favorite=?,color=?,sort_order=?,updated_at=? WHERE id=? AND owner_device_id=?',
            [$alias,$group,(int)$favorite,strtoupper($color),$order,$this->now,$c['id'],$owner]);
        else $this->run('INSERT INTO device_contacts(id,owner_device_id,remote_key,alias,group_name,is_favorite,color,sort_order,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
            [$c['id'],$owner,$c['remote_key'],$alias,$group,(int)$favorite,strtoupper($color),$order,$c['created_at'],$this->now]);
        return $this->contactView($this->contact($owner,$c['id']));
    }
    public function deleteContact(string $owner,string $id): array {
        $this->contact($owner,$id);
        $this->run('DELETE FROM device_contacts WHERE owner_device_id=? AND id=?',[$owner,$id]);
        return ['deleted'=>true,'id'=>$id];
    }
    public function recent(string $owner): array {
        $rows=$this->run('SELECT s.*,r.public_key AS requester_key,r.display_name AS requester_name,
            h.public_key AS host_key,h.display_name AS host_name FROM sessions s
            JOIN devices r ON r.id=s.requester_id JOIN devices h ON h.id=s.host_id
            WHERE s.requester_id=? OR s.host_id=? ORDER BY s.created_at DESC,s.id DESC LIMIT 50',[$owner,$owner])->fetchAll(PDO::FETCH_ASSOC);
        $items=[];
        foreach ($rows as $s) {
            $requester=$s['requester_id']===$owner;
            $key=$requester?$s['host_key']:$s['requester_key'];
            $contact=$this->run('SELECT alias FROM device_contacts WHERE owner_device_id=? AND remote_key=?',[$owner,$key])->fetchColumn();
            $items[]=['session_id'=>$s['id'],'remote_key'=>$key,
                'display_name'=>$contact!==false && $contact!==''?$contact:($requester?$s['host_name']:$s['requester_name']),
                'direction'=>$requester?'outgoing':'incoming','state'=>$s['state'],
                'was_authorized'=>json_decode($s['granted'],true)!==[],
                'created_at'=>gmdate('Y-m-d\TH:i:s\Z',(int)$s['created_at']),
                'ended_at'=>$s['ended_at']===null?null:gmdate('Y-m-d\TH:i:s\Z',(int)$s['ended_at'])];
        }
        return ['items'=>$items];
    }
    public function dashboard(array $device): array {
        $contacts=$this->contacts($device['id'])['items'];
        $recent=$this->recent($device['id'])['items'];
        $cards=[];
        foreach ($recent as $session) {
            $key=$session['remote_key'];
            if (!isset($cards[$key])) $cards[$key]=$session;
        }
        return ['device'=>['device_id'=>$device['id'],'public_key'=>$device['public_key'],
            'display_name'=>$device['display_name'],'platform'=>$device['platform']],
            'preferences'=>$this->preferences($device['id']),'contacts'=>$contacts,
            'favorites'=>array_values(array_filter($contacts,fn($c)=>$c['is_favorite'])),
            'recent_devices'=>array_values($cards),'recent_sessions'=>$recent];
    }
}
