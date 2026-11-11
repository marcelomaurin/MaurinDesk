<?php
declare(strict_types=1);
require __DIR__.'/p2p.php';
use MaurinDesk\Api;
[$st]=callApi('GET','/desktop');
check($st===401,'desktop requires authentication');
[$st,$r]=callApi('GET','/desktop',[],$client);
check($st===200 && $r['data']['device']['public_key']===$client['public_key'] &&
    $r['data']['preferences']['view_mode']==='cards','desktop returns own identity and card preferences');
check($r['data']['contacts']===[] && $r['data']['favorites']===[],'new address book is empty');
check(count($r['data']['recent_devices'])===count(array_unique(array_column($r['data']['recent_devices'],'remote_key'))),
    'recent devices have one card per remote key');
check(!str_contains(json_encode($r),$client['device_token']) && !str_contains(json_encode($r),$host['device_token']),
    'dashboard never returns credentials');
[$st,$r]=callApi('PATCH','/desktop/preferences',['theme'=>'dark','view_mode'=>'list','language'=>'en','sort_by'=>'name'],$client);
check($st===200 && $r['data']['theme']==='dark' && $r['data']['language']==='en','preferences persist');
[$st,$r]=callApi('GET','/desktop',[],$host);
check($r['data']['preferences']['theme']==='system','preferences isolated between devices');
[$st]=callApi('PATCH','/desktop/preferences',['theme'=>'unknown'],$client);
check($st===400,'unknown theme rejected');
[$st]=callApi('PATCH','/desktop/preferences',['device_id'=>$host['device_id']],$client);
check($st===400,'preference owner cannot be supplied');
[$st,$r]=callApi('PATCH','/devices/me',['display_name'=>'Notebook Marcelo'],$client);
check($st===200 && $r['data']['display_name']==='Notebook Marcelo','device can be renamed');
[$st,$r]=callApi('POST','/devices',$cb); $client=$r['data'];
[$st,$r]=callApi('GET','/desktop',[],$client);
check($r['data']['device']['display_name']==='Notebook Marcelo','registration recovery preserves chosen name');

$contact=['remote_key'=>$host['public_key'],'alias'=>'Computador trabalho','group_name'=>'Saude',
    'is_favorite'=>true,'color'=>'#aa44cc','sort_order'=>10];
$idem=Api::uuid();
[$st,$r]=callApi('POST','/contacts',$contact,$client,$idem); $cid=$r['data']['id'];
check($st===200 && $r['data']['color']==='#AA44CC' && $r['data']['is_favorite']===true,'card metadata and favorite saved');
[$st,$r]=callApi('POST','/contacts',$contact,$client,$idem);
check($st===200 && $r['data']['id']===$cid,'contact retry returns same card');
[$st,$r]=callApi('POST','/contacts',['remote_key'=>$host['public_key'],'alias'=>'Trabalho'],$client);
check($st===200 && $r['data']['id']===$cid && $r['data']['is_favorite']===true,'same key updates card without duplication');
[$st,$r]=callApi('GET','/contacts',[],$client);
check(count($r['data']['items'])===1,'contact key unique per owner');
[$st,$r]=callApi('GET','/contacts',[],$other);
check($r['data']['items']===[],'other device cannot list owner contacts');
[$st]=callApi('PATCH','/contacts/'.$cid,['alias'=>'intruso'],$other);
check($st===404,'other device cannot edit card');
[$st]=callApi('DELETE','/contacts/'.$cid,[],$other);
check($st===404,'other device cannot delete card');
[$st]=callApi('PATCH','/contacts/'.$cid,['owner_device_id'=>$other['device_id']],$client);
check($st===400,'contact ownership cannot be changed');
[$st]=callApi('POST','/contacts',['remote_key'=>$client['public_key']],$client);
check($st===400,'own key cannot be saved as remote contact');
[$st]=callApi('PATCH','/contacts/'.$cid,['color'=>'url(secret)'],$client);
check($st===400,'invalid card color rejected');
[$st]=callApi('PATCH','/contacts/'.$cid,['is_favorite'=>'true'],$client);
check($st===400,'favorite must be boolean');
[$st]=callApi('PATCH','/contacts/'.$cid,['sort_order'=>-1],$client);
check($st===400,'negative sort order rejected');
[$st]=callApi('POST','/contacts',['remote_key'=>'0123456789','alias'=>'Sem conexao'],$client);
check($st===200,'offline or unknown key can be saved without revealing a device');
[$st,$r]=callApi('GET','/desktop',[],$client);
check(count($r['data']['favorites'])===1 && count($r['data']['contacts'])===2,'dashboard separates favorites and contacts');
foreach ($r['data']['contacts'] as $card) {
    if ($card['remote_key']==='0123456789') check($card['availability']==='unknown','unknown contact does not reveal device presence');
}
callApi('POST','/devices/heartbeat',[],$host);
[$st,$r]=callApi('GET','/desktop',[],$client);
check($r['data']['favorites'][0]['availability']==='online','authorized known peer shows fresh presence');
$now+=45;
[$st,$r]=callApi('GET','/desktop',[],$client);
check($r['data']['favorites'][0]['availability']==='offline','stale heartbeat does not remain online in cards');
check(!str_contains(json_encode($r),'observed_ip') && !str_contains(json_encode($r),'registration_secret'),
    'cards do not disclose peer endpoints or secrets');
[$st,$r]=callApi('GET','/sessions/recent',[],$client);
$recent=$r['data']['items']; $sawAlias=false;
foreach ($recent as $entry) {
    $q=$db->prepare('SELECT requester_id,host_id FROM sessions WHERE id=?'); $q->execute([$entry['session_id']]);
    $s=$q->fetch(PDO::FETCH_ASSOC);
    check(in_array($client['device_id'],[$s['requester_id'],$s['host_id']],true),'recent session belongs to caller');
    if ($entry['remote_key']===$host['public_key'] && $entry['display_name']==='Trabalho') $sawAlias=true;
    check(!array_key_exists('connected',$entry),'history does not fabricate transport success');
}
check($sawAlias,'recent session card uses owner alias');
[$st]=callApi('PATCH','/contacts/'.$cid,['is_favorite'=>false],$client);
[$st,$r]=callApi('GET','/desktop',[],$client);
check(count($r['data']['favorites'])===0 && count($r['data']['contacts'])===2,'unfavorite keeps address book entry');
[$st]=callApi('DELETE','/contacts/'.$cid,[],$client);
check($st===200,'owner can delete contact');
[$st,$r]=callApi('GET','/sessions/recent',[],$client);
check(count($r['data']['items'])===count($recent),'deleting contact keeps session history');
echo "$count total API assertions passed\n";
