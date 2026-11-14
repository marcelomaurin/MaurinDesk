<?php
declare(strict_types=1);
require __DIR__.'/desktop_ui.php';
callApi('POST','/devices/heartbeat',[],$host);
callApi('POST','/devices/heartbeat',[],$client);
endpoint($host,['port'=>7071,'transport'=>'tcp','local_ip'=>'192.168.1.10'],'198.51.100.10');
endpoint($client,['port'=>7071,'transport'=>'tcp'],'2001:db8::2');
[$st,$r]=callApi('POST','/sessions',['target_key'=>$host['public_key'],
    'requested_permissions'=>['screen.view']],$client);
$relayId=$r['data']['id']; $route='/sessions/'.$relayId;
[$st,$r]=callApi('GET',$route,[],$client);
check($st===200 && !isset($r['data']['communication']),'pending session hides communication IPs');
callApi('GET','/sessions/incoming',[],$host);
callApi('GET','/sessions/incoming',[],$host);
callApi('POST',$route.'/decision',['decision'=>'accept','granted_permissions'=>['screen.view']],$host);
[$st,$r]=callApi('GET',$route,[],$client);
$comm=$r['data']['communication'];
check($st===200 && $comm['status']==='waiting_host_frame','accepted session distinguishes missing host images');
check($comm['host']['observed_ip']==='198.51.100.10' && $comm['requester']['observed_ip']==='2001:db8::2',
    'both source IPs available after consent');
check($comm['host']['local_ip']==='192.168.1.10' && $comm['host']['online'],'LAN and presence reported');
check(count(array_filter($comm['events'],fn($e)=>$e['event_type']==='session.delivered'))===1,
    'delivery logged once despite repeated polling');
[$st,$r]=callApi('GET',$route,[],$other);
check($st===404 && !isset($r['data']),'third party cannot read session diagnostic IPs');
[$st,$r]=callApi('GET',$route.'/relay_frame',[],$client);
check($st===200 && $r['data']['status']==='no_frame','empty relay responds explicitly');
$frame=['frame_id'=>7,'frame_data'=>base64_encode('test-jpeg-bytes')];
[$st]=callApi('POST',$route.'/relay_frame',$frame,$client);
check($st===403,'only host can upload screen');
[$st]=callApi('POST',$route.'/relay_frame',$frame,$host);
check($st===200,'host publishes relay frame');
[$st,$r]=callApi('GET',$route.'/relay_frame',[],$client);
check($st===200 && $r['data']['frame_id']===7 && $r['data']['frame_data']===$frame['frame_data'],
    'viewer can receive first image with non-one sequence');
callApi('GET',$route.'/relay_frame',[],$client);
[$st,$r]=callApi('GET',$route,[],$host);
$comm=$r['data']['communication'];
check($comm['status']==='frame_available' && $comm['frame_id']===7,'host sees server frame status too');
foreach (['relay.viewer_polling','relay.first_frame_uploaded','relay.first_frame_served'] as $event)
    check(count(array_filter($comm['events'],fn($e)=>$e['event_type']===$event))===1,'one milestone '.$event);
check(!str_contains(json_encode($comm),$host['device_token']) && !str_contains(json_encode($comm),$frame['frame_data']),
    'diagnostics contain neither credentials nor screen data');
[$st]=callApi('POST',$route.'/relay_input',['events'=>[['type'=>'key','key'=>65,'down'=>true]]],$client);
check($st===403,'view-only relay rejects input');
$now+=16;
[$st,$r]=callApi('GET',$route,[],$client);
check($r['data']['communication']['status']==='frame_stalled','stale uploads reported after fifteen seconds');
$now+=30;
[$st,$r]=callApi('GET',$route,[],$client);
check(!$r['data']['communication']['host']['online'] && !$r['data']['communication']['host']['endpoint_fresh'],
    'stale endpoint and host presence are explicit');
callApi('POST',$route.'/close',['reason'=>'test_complete'],$client);
[$st,$r]=callApi('GET',$route,[],$host);
check(!isset($r['data']['communication']),'closed session stops sharing IP diagnostics');
echo "$count total relay and API assertions passed\n";
