<?php
declare(strict_types=1);
use MaurinDesk\Api;
require __DIR__.'/run.php';
// run.php has advanced the fake clock past the device token expiry. Renew first.
[$st,$r]=callApi('POST','/devices',$hb); $host=$r['data'];
[$st,$r]=callApi('POST','/devices',$cb); $client=$r['data'];
[$st,$r]=callApi('POST','/devices',$ob); $other=$r['data'];

function endpoint(array $device,array $body,string $ip='198.51.100.10',?string $idem=null): array {
    global $api;
    return $api->handle('POST','/devices/endpoint',[
        'authorization'=>'Bearer '.$device['device_token'],
        'idempotency-key'=>$idem??Api::uuid()],$body,$ip);
}
$port=['port'=>49152,'transport'=>'tcp'];
[$st,$r]=$api->handle('POST','/devices/endpoint',[],$port,'198.51.100.10');
check($st===401,'endpoint requires device authentication');
foreach ([0,1023,65536,'49152',49152.5,true] as $invalid) {
    [$st]=endpoint($host,['port'=>$invalid,'transport'=>'tcp']);
    check($st===400,'invalid listening port '.json_encode($invalid));
}
[$st]=endpoint($host,['port'=>49152,'transport'=>'udp']);
check($st===400,'unsupported transport rejected');
[$st]=endpoint($host,$port+['ip'=>'203.0.113.99']);
check($st===400,'client cannot supply another source IP');
[$st]=endpoint($host,$port,'not-an-ip');
check($st===400,'invalid server source address rejected');
$idem=Api::uuid();
[$st,$r]=endpoint($host,$port,'198.51.100.10',$idem);
check($st===200 && $r['data']['observed_ip']==='198.51.100.10' &&
    $r['data']['reachability']==='unverified','observed endpoint is not claimed reachable');
$oldExpiry=$r['data']['expires_at'];
$now+=1;
[$st,$r]=endpoint($host,$port,'198.51.100.10',$idem);
check($st===200 && $r['data']['expires_at']===$oldExpiry,'endpoint retry is idempotent');
[$st]=endpoint($host,['port'=>49153,'transport'=>'tcp'],'198.51.100.10',$idem);
check($st===409,'endpoint idempotency body conflict');
[$st,$r]=endpoint($client,['port'=>65535,'transport'=>'tcp'],'2001:db8::2');
check($st===200 && $r['data']['observed_ip']==='2001:db8::2','IPv6 observed source accepted');
$request=['target_key'=>$host['public_key'],'requested_permissions'=>['screen.view']];
[$st,$r]=callApi('POST','/sessions',$request,$client); $id=$r['data']['id'];
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$client);
check($st===403 && $r['error']['code']==='CONSENT_REQUIRED','pending request does not reveal endpoint');
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$other);
check($st===404,'third party cannot discover peer');
[$st]=callApi('POST','/sessions/'.$id.'/decision',$accept,$host);
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$client);
check($st===200 && $r['data']['observed_ip']==='198.51.100.10' &&
    $r['data']['port']===49152 && $r['data']['granted_permissions']===['screen.view'],
    'requester discovers authorized host endpoint');
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$host);
check($st===200 && $r['data']['observed_ip']==='2001:db8::2','host discovers requester endpoint');
[$st]=callApi('POST','/sessions/'.$id.'/close',['reason'=>'local_stop'],$client);
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$host);
check($st===410 && !isset($r['data']),'closed session stops endpoint discovery');

// Presence heartbeat must not renew an old listening endpoint.
$now+=45;
callApi('POST','/devices/heartbeat',[],$host);
callApi('POST','/devices/heartbeat',[],$client);
[$st,$r]=callApi('POST','/sessions',$request,$client); $id=$r['data']['id'];
callApi('POST','/sessions/'.$id.'/decision',$accept,$host);
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$client);
check($st===409 && $r['error']['code']==='PEER_UNAVAILABLE','heartbeat does not revive stale listener');
endpoint($host,['port'=>50000,'transport'=>'tcp'],'203.0.113.5');
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$client);
check($st===200 && $r['data']['observed_ip']==='203.0.113.5' && $r['data']['port']===50000,
    'endpoint refresh replaces old address and port');
$now+=30;
[$st,$r]=callApi('GET','/sessions/'.$id.'/peer',[],$client);
check($st===410,'negotiation expiry stops discovery even with fresh endpoint');

// Missing endpoint and rejection must not leak an address.
callApi('POST','/devices/heartbeat',[],$host);
[$st,$r]=callApi('POST','/sessions',$request,$client); $id=$r['data']['id'];
callApi('POST','/sessions/'.$id.'/decision',['decision'=>'reject'],$host);
[$st]=callApi('GET','/sessions/'.$id.'/peer',[],$client);
check($st===410,'rejected request cannot discover peer');
echo "$count total assertions passed\n";
