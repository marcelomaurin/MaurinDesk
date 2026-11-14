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
foreach ([[$client,$host],[$host,$client]] as [$sender,$receiver]) {
 $raw=random_bytes(ClipboardData::CHUNK_BYTES+35); $job=Api::uuid();
 $body=['request_id'=>$job,'destination'=>'D:\\Destino final','overwrite'=>false,'total_bytes'=>strlen($raw),'checksum'=>sha1($raw)];
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
echo "$count total file exchange and API assertions passed\n";
