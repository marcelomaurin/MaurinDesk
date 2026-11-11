program signaling_probe;
{$mode objfpc}{$H+}
uses SysUtils, fpjson, airemotesignaling, airemoteidentity;
procedure Check(B:Boolean; const Msg:string);
begin if not B then raise Exception.Create(Msg); WriteLn('OK ',Msg); end;
function RegisterClient(C:TAIRemoteSignalingClient; const LabelText:string):string;
var J:TJSONObject;
begin
  J:=C.RegisterDevice(AIRemoteUUID,AIRemoteRandomHex(32),LabelText,'windows-test','0.2.0');
  try C.DeviceToken:=J.Get('device_token',''); Result:=J.Get('public_key','');
  finally J.Free; end;
end;
var Host,Viewer:TAIRemoteSignalingClient; J:TJSONObject; Key,Id:string;
begin
  Host:=TAIRemoteSignalingClient.Create; Viewer:=TAIRemoteSignalingClient.Create;
  try
    Host.BaseURL:='http://127.0.0.1:18765/v1'; Host.AllowLocalHTTP:=True;
    Viewer.BaseURL:=Host.BaseURL; Viewer.AllowLocalHTTP:=True;
    Key:=RegisterClient(Host,'integration-host'); RegisterClient(Viewer,'integration-viewer');
    Check(AIRemoteValidKey(Key),'HTTP registration');
    J:=Viewer.RequestSession(Key,True);
    try Id:=J.Get('id',''); Check(J.Get('state','')='pending','HTTP pending request'); finally J.Free; end;
    J:=Host.Incoming;
    try Check(J.Arrays['items'].Count=1,'HTTP incoming host request'); finally J.Free; end;
    try J:=Viewer.Decide(Id,True,True); J.Free; raise Exception.Create('self-approval accepted');
    except on E:EAIRemoteAPI do Check(E.Status=403,'HTTP requester consent rejected'); end;
    J:=Host.Decide(Id,True,False);
    try Check(J.Get('state','')='accepted','HTTP host consent'); finally J.Free; end;
    J:=Viewer.GetSession(Id);
    try Check(J.Arrays['granted_permissions'].Count=1,'HTTP permissions restricted'); finally J.Free; end;
    J:=Host.CloseSession(Id,'integration_test'); J.Free;
    J:=Viewer.GetSession(Id);
    try Check(J.Get('state','')='closed','HTTP closed session'); finally J.Free; end;
    WriteLn('Native Windows client to PHP API integration passed');
  finally Viewer.Free; Host.Free; end;
end.
