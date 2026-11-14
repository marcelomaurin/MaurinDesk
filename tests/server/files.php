<?php
declare(strict_types=1);
require __DIR__.'/clipboard.php';
use MaurinDesk\Api;
use MaurinDesk\ClipboardData;
foreach ([$host,$client] as $d) callApi('POST','/devices/heartbeat',['app_version'=>'0.6.7'],$d);
[$st,$r]=callApi('POST','/sessions',['target_key'=>$host['public_key'],'requested_permissions'=>['screen.view','files.transfer']],$client);
check($st===201,'file session requested'); $sid=$r['data']['id']; $route='/sessions/'.$sid.'/files/';
[$st]=callApi('GET',$route.'commands',[],$client); check($st===403,'files require host consent');
callApi('POST','/sessions/'.$sid.'/decision',['decision'=>'accept','granted_permissions'=>['screen.view','files.transfer']],$host);
[$st]=callApi('GET',$route.'commands',[],$other); check($st===404,'third party cannot browse files');
[$st,$r]=callApi('POST',$route.'commands',['action'=>'list','path'=>'C:\\Users','offset'=>0],$client);
check($st===200,'Windows path accepted'); $cmd=$r['data']['id'];
[$st,$r]=callApi('GET',$route.'commands',[],$host); check($st===200 && count($r['data']['items'])===1 && $r['data']['items'][0]['id']===$cmd,'list routed to peer');
[$st,$r]=callApi('GET',$route.'commands',[],$host); check(count($r['data']['items'])===0,'command lease prevents duplicate work');
[$st]=callApi('POST',$route.'commands/'.$cmd,['response'=>['ok'=>true]],$client); check($st===403,'sender cannot forge listing');
$listing=['path'=>'C:\\Users','entries'=>[['name'=>'ação.txt','kind'=>'file','size'=>12]],'offset'=>0,'has_more'=>false];
[$st]=callApi('POST',$route.'commands/'.$cmd,['response'=>['ok'=>true,'data'=>$listing]],$host); check($st===200,'peer replies listing');
[$st,$r]=callApi('GET',$route.'commands/'.$cmd,[],$client); check($r['data']['response']['data']===$listing,'listing and Unicode preserved');
foreach (['../outside','\\\\server\\share','C:relative'] as $path) { [$st]=callApi('POST',$route.'commands',['action'=>'list','path'=>$path],$client); check($st===400,'invalid absolute path rejected'); }
[$st]=callApi('POST',$route.'commands',['action'=>'mkdir','path'=>'C:\\Users','name'=>'../outside'],$client); check($st===400,'mkdir traversal rejected');
callApi('POST','/devices/heartbeat',['app_version'=>'0.6.6'],$host);
[$st]=callApi('POST',$route.'commands',['action'=>'list','path'=>'@home'],$client); check($st===409,'old peer gets explicit upgrade error');
callApi('POST','/devices/heartbeat',['app_version'=>'0.6.7'],$host);
// Only the side that started the connection with the key commands the other computer's files.
foreach ([['action'=>'list','path'=>'C:\\Users','offset'=>0],['action'=>'mkdir','path'=>'C:\\Users','name'=>'x'],
 ['action'=>'send','paths'=>['C:\\Users\\a.txt'],'destination'=>'D:\\Destino final','request_id'=>Api::uuid(),'overwrite'=>false]] as $forbidden) {
 [$st]=callApi('POST',$route.'commands',$forbidden,$host); check($st===403,'host cannot command requester files: '.$forbidden['action']); }
[$st,$r]=callApi('GET',$route.'commands',[],$client); check($st===200 && count($r['data']['items'])===0,'no host command reaches the requester');
$raw=random_bytes(64); [$st]=callApi('POST',$route.'transfers',['request_id'=>Api::uuid(),'destination'=>'D:\\Destino final','overwrite'=>false,'total_bytes'=>64,'checksum'=>sha1($raw)],$host);
check($st===403,'host cannot push unsolicited files to requester');
foreach ([[$client,$host],[$host,$client]] as [$sender,$receiver]) {
 $raw=random_bytes(ClipboardData::CHUNK_BYTES+35); $job=Api::uuid();
 $body=['request_id'=>$job,'destination'=>'D:\\Destino final','overwrite'=>false,'total_bytes'=>strlen($raw),'checksum'=>sha1($raw)];
 if ($sender===$host) {
  $wrong=$body; $wrong['destination']='D:\\Outra';
  [$st]=callApi('POST',$route.'commands',['action'=>'send','paths'=>['C:\\Users\\a.txt'],'destination'=>$body['destination'],'request_id'=>$job,'overwrite'=>false],$client); check($st===200,'requester asks host for files');
  [$st]=callApi('POST',$route.'transfers',$wrong,$host); check($st===403,'host cannot change the requested destination');
 }
 [$st,$r]=callApi('POST',$route.'transfers',$body,$sender); check($st===200,'begin explicit destination transfer'); $id=$r['data']['id'];
 [$st,$r]=callApi('POST',$route.'transfers',$body,$sender); check($r['data']['id']===$id,'same job reuses transfer');
 $changed=$body; $changed['destination']='D:\\Other'; [$st]=callApi('POST',$route.'transfers',$changed,$sender); check($st===409,'same job cannot change destination');
 [$st]=callApi('POST',$route.'transfers/'.$id,[],$sender); check($st===409,'incomplete file cannot publish');
 for ($part=0;$part<2;$part++) { [$st]=callApi('POST',$route.'transfers/'.$id.'/'.$part,['data'=>base64_encode(substr($raw,$part*ClipboardData::CHUNK_BYTES,ClipboardData::CHUNK_BYTES))],$sender); check($st===200,'file chunk accepted'); }
 [$st]=callApi('POST',$route.'transfers/'.$id,[],$sender); check($st===200,'complete verified file published');
 [$st,$r]=callApi('GET',$route.'transfers',[],$receiver); check($r['data']['items'][0]['destination']===$body['destination'] && $r['data']['items'][0]['overwrite']===false,'receiver sees selected final destination');
 $owner=Api::uuid(); [$st]=callApi('POST',$route.'transfers/'.$id.'/claim',['owner'=>$owner],$receiver); check($st===200,'receiver claims transfer');
 [$st]=callApi('POST',$route.'transfers/'.$id.'/claim',['owner'=>Api::uuid()],$receiver); check($st===409,'second instance cannot duplicate transfer');
 $download=''; for ($part=0;$part<2;$part++) { [$st,$r]=callApi('GET',$route.'transfers/'.$id.'/'.$part,[],$receiver); $download.=base64_decode($r['data']['data']); }
 check($download===$raw,'binary content exact in both directions');
 $ack=['owner'=>$owner,'state'=>'completed','result'=>['destination'=>$body['destination'],'count'=>2]];
 [$st]=callApi('POST',$route.'transfers/'.$id,$ack,$sender); check($st===403,'sender cannot confirm disk write');
 [$st]=callApi('POST',$route.'transfers/'.$id,$ack,$receiver); check($st===200,'actual receiver confirms final write');
 [$st]=callApi('POST',$route.'transfers/'.$id,$ack,$receiver); check($st===200,'receipt retry idempotent');
 [$st,$r]=callApi('GET',$route.'transfers/'.$id,[],$sender); check($r['data']['state']==='completed','sender observes final receipt');
 check((int)$db->query("SELECT COUNT(*) FROM file_chunks WHERE transfer_id='".$id."'")->fetchColumn()===0,'received chunks removed');
}
callApi('POST','/sessions/'.$sid.'/close',['reason'=>'done'],$host);
check((int)$db->query('SELECT COUNT(*) FROM file_transfers')->fetchColumn()===0,'close cleans file metadata');
check((int)$db->query('SELECT COUNT(*) FROM file_commands')->fetchColumn()===0,'close cleans pending commands');
[$st]=callApi('GET',$route.'commands',[],$client); check($st===403,'closed file session denied');
// A view-only decision never grants filesystem access.
[$st,$r]=callApi('POST','/sessions',['target_key'=>$host['public_key'],'requested_permissions'=>['screen.view','files.transfer']],$client); $view=$r['data']['id'];
callApi('POST','/sessions/'.$view.'/decision',['decision'=>'accept','granted_permissions'=>['screen.view']],$host);
[$st]=callApi('GET','/sessions/'.$view.'/files/commands',[],$client); check($st===403,'read-only view cannot access file manager');
// Diagnostics are accepted only from registered devices holding a valid credential.
[$st]=callApi('POST','/diagnostics/logs',['message'=>'x','log_content'=>'y']); check($st===401,'anonymous diagnostics rejected');
[$st,$r]=callApi('POST','/diagnostics/logs',['message'=>'x','log_content'=>str_repeat('a',300000),'session_id'=>$sid],$client); check($st===201,'registered device stores diagnostics');
$row=$db->query("SELECT device_id,session_id,LENGTH(log_content) AS n FROM device_logs WHERE id='".$r['data']['id']."'")->fetch(PDO::FETCH_ASSOC);
check($row['device_id']===$client['device_id'] && $row['session_id']===$sid && (int)$row['n']===262144,'diagnostics bound to device, own session and size limit');
[$st,$r]=callApi('POST','/diagnostics/logs',['message'=>'x','session_id'=>$sid],$other); $row=$db->query("SELECT session_id FROM device_logs WHERE id='".$r['data']['id']."'")->fetch(PDO::FETCH_ASSOC);
check($st===201 && $row['session_id']===null,'diagnostics cannot be attached to another session');
echo "$count total file exchange and API assertions passed\n";
