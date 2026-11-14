<?php
declare(strict_types=1);
require __DIR__.'/relay.php';
use MaurinDesk\ClipboardData;
callApi('POST','/devices/heartbeat',[],$host); callApi('POST','/devices/heartbeat',[],$client);
[$st,$r]=callApi('POST','/sessions',['target_key'=>$host['public_key'],
    'requested_permissions'=>['screen.view','clipboard.sync']],$client);
$cid=$r['data']['id']; $clip='/sessions/'.$cid.'/clipboard';
[$st]=callApi('GET',$clip,[],$client); check($st===403,'clipboard requires consent');
callApi('POST','/sessions/'.$cid.'/decision',['decision'=>'accept','granted_permissions'=>['screen.view','clipboard.sync']],$host);
callApi('POST','/devices/heartbeat',['app_version'=>'0.6.6'],$host);
check($db->query("SELECT app_version FROM devices WHERE id='".$host['device_id']."'")->fetchColumn()==='0.6.6','heartbeat refreshes installed app version');
[$st,$r]=callApi('GET',$clip,[],$host); check($st===200 && $r['data']['status']==='empty','new clipboard empty');
[$st]=callApi('GET',$clip,[],$other); check($st===404,'third party cannot read clipboard');
foreach ([['kind'=>'image','total_bytes'=>1,'checksum'=>sha1('x')],
    ['kind'=>'text','total_bytes'=>1048577,'checksum'=>sha1('x')],
    ['kind'=>'files','total_bytes'=>ClipboardData::MAX_BYTES+1,'checksum'=>sha1('x')]] as $invalid) {
    [$st]=callApi('POST',$clip,$invalid,$client); check($st===400,'clipboard rejects unsupported kind or oversize');
}
function clipboardSend(string $route,array $sender,string $raw,string $kind='text'): string {
    [$st,$r]=callApi('POST',$route,['kind'=>$kind,'total_bytes'=>strlen($raw),'checksum'=>sha1($raw)],$sender);
    check($st===200,'clipboard begin '.$kind); $id=$r['data']['id'];
    for ($i=0;$i<$r['data']['chunk_count'];$i++) {
        [$st]=callApi('POST',$route.'/'.$id.'/'.$i,['data'=>base64_encode(substr($raw,$i*ClipboardData::CHUNK_BYTES,ClipboardData::CHUNK_BYTES))],$sender);
        check($st===200,'clipboard stores chunk '.$i);
    }
    [$st]=callApi('POST',$route.'/'.$id,[],$sender); check($st===200,'clipboard completes '.$kind); return $id;
}
$raw="Olá, arquivo e texto — 漢字 😀\r\nsegunda linha";
$id=clipboardSend($clip,$client,$raw);
[$st,$r]=callApi('GET',$clip,[],$host); check($st===200 && $r['data']['id']===$id,'host receives controller clipboard');
[$st,$r]=callApi('GET',$clip.'/'.$id.'/0',[],$host);
check($st===200 && base64_decode($r['data']['data'])===$raw,'Unicode text preserved exactly');
[$st,$r]=callApi('GET',$clip.'/'.$id,[],$client); check($st===200 && $r['data']['status']==='ready','upload is not yet a receipt');
[$st]=callApi('POST',$clip.'/'.$id,['received'=>true],$client); check($st===403,'sender cannot confirm its own delivery');
[$st,$r]=callApi('POST',$clip.'/'.$id,['received'=>true],$host); check($st===200 && $r['data']['status']==='received','receiver confirms local clipboard readiness');
[$st,$r]=callApi('GET',$clip.'/'.$id,[],$client); check($r['data']['status']==='received','sender observes actual receipt');
[$st]=callApi('POST',$clip.'/'.$id.'/0',['data'=>base64_encode('changed')],$host);
check($st===403,'receiver cannot change sender content');
$back=clipboardSend($clip,$host,'Resposta do host');
[$st,$r]=callApi('GET',$clip,[],$client); check($r['data']['id']===$back,'host clipboard travels back to controller');
$binary=random_bytes(ClipboardData::CHUNK_BYTES+57); $files=clipboardSend($clip,$client,$binary,'files');
[$st,$r]=callApi('GET',$clip.'/'.$files.'/1',[],$host);
check($st===200 && base64_decode($r['data']['data'])===substr($binary,ClipboardData::CHUNK_BYTES),'binary second chunk preserved');
[$st]=callApi('GET',$clip.'/'.$id.'/0',[],$host); check($st===404,'superseded clipboard is deleted');
[$st,$r]=callApi('POST',$clip,['kind'=>'text','total_bytes'=>3,'checksum'=>sha1('abc')],$client); $bad=$r['data']['id'];
[$st]=callApi('POST',$clip.'/'.$bad,[],$client); check($st===409,'incomplete clipboard cannot be published');
[$st]=callApi('GET',$clip.'/'.$bad.'/0',[],$host); check($st===403,'unfinished upload cannot be downloaded');
[$st]=callApi('POST',$clip.'/'.$bad.'/0',['data'=>base64_encode('xy')],$client); check($st===400,'wrong chunk size rejected');
[$st]=callApi('POST',$clip.'/'.$bad.'/0',['data'=>base64_encode('xyz')],$client); check($st===200,'same-size chunk accepted provisionally');
[$st]=callApi('POST',$clip.'/'.$bad.'/0',['data'=>base64_encode('abc')],$client); check($st===409,'changing an existing chunk rejected');
[$st]=callApi('POST',$clip.'/'.$bad,[],$client); check($st===409,'wrong final checksum rejected');
callApi('POST','/sessions/'.$cid.'/close',['reason'=>'done'],$host);
[$st,$r]=callApi('GET','/sessions/'.$cid,[],$client);
check($r['data']['closed_by']['role']==='host' && $r['data']['reason']==='done','closure reports actor and reason to peer');
check((int)$db->query('SELECT COUNT(*) FROM clipboard_transfers')->fetchColumn()===0,'clipboard content removed on close');
check((int)$db->query('SELECT COUNT(*) FROM clipboard_chunks')->fetchColumn()===0,'clipboard chunks cascade on close');
[$st]=callApi('GET',$clip,[],$client); check($st===403,'closed session cannot access clipboard');
echo "$count total clipboard and API assertions passed\n";
