unit uDeskHTTP;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpjson;
function DeskAPIRequest(const BaseURL, Token: string; AllowLocal: Boolean;
  const Method, Route: string; Body: TJSONObject = nil; const RetryKey: string = ''): TJSONObject;
function DeskRequestSession(const URL, Token, Key: string; AllowLocal, Control: Boolean): TJSONObject;
function DeskAcceptControl(const URL, Token, Id: string; AllowLocal: Boolean; Requested: TJSONArray): TJSONObject;
function DeskGetJSON(const URL: string): TJSONObject;
function DeskHeartbeat(const URL, Token, Version: string; AllowLocal: Boolean): TJSONObject;
procedure DeskDownloadFile(const URL, Target: string; MaxBytes: Int64);
implementation
uses Windows, jsonparser, airemoteidentity, airemotesignaling;
{$IFDEF WINDOWS}
type HINTERNET=Pointer;
function WinHttpOpen(Agent:PWideChar; AccessType:DWORD; ProxyName,ProxyBypass:PWideChar; Flags:DWORD):HINTERNET;
  stdcall; external 'winhttp.dll';
function WinHttpConnect(Session:HINTERNET; Server:PWideChar; Port:Word; Reserved:DWORD):HINTERNET;
  stdcall; external 'winhttp.dll';
function WinHttpOpenRequest(Connect:HINTERNET; Verb,ObjectName,Version,Referrer:PWideChar;
  AcceptTypes:Pointer; Flags:DWORD):HINTERNET; stdcall; external 'winhttp.dll';
function WinHttpSetTimeouts(Session:HINTERNET; Resolve,Connect,Send,Receive:Integer):BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpSetOption(Handle:HINTERNET; Option:DWORD; Buffer:Pointer; BufferLength:DWORD):BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpSendRequest(Request:HINTERNET; Headers:PWideChar; HeadersLength:DWORD; Optional:Pointer;
  OptionalLength,TotalLength:DWORD; Context:PtrUInt):BOOL; stdcall; external 'winhttp.dll';
function WinHttpReceiveResponse(Request:HINTERNET; Reserved:Pointer):BOOL; stdcall; external 'winhttp.dll';
function WinHttpQueryHeaders(Request:HINTERNET; InfoLevel:DWORD; Name:PWideChar;
  Buffer:Pointer; var BufferLength:DWORD; Index:Pointer):BOOL; stdcall; external 'winhttp.dll';
function WinHttpReadData(Request:HINTERNET; Buffer:Pointer; BytesToRead:DWORD; var BytesRead:DWORD):BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpCloseHandle(Handle:HINTERNET):BOOL; stdcall; external 'winhttp.dll';

function HTTP(const URL,Method,Token,Body,Idempotency:string; AllowLocal:Boolean; out Status:Integer;
  Output: TStream = nil; MaxBytes: Int64 = 1048576):string;
var Rest,Host,Resource,Authority:string; Port:Word; P,I,N:Integer; Secure:Boolean;
    Session,Connection,Req:HINTERNET; WAgent,WHost,WMethod,WResource,WHeaders:UnicodeString;
    Flags,Policy,Size,Code,ReadCount:DWORD; Buffer:array[0..8191] of Byte; Data:Pointer;
    Total: Int64;
begin
  Secure:=Copy(URL,1,8)='https://';
  if Secure then Rest:=Copy(URL,9,MaxInt)
  else if Copy(URL,1,7)='http://' then Rest:=Copy(URL,8,MaxInt)
  else raise Exception.Create('HTTPS URL required');
  P:=Pos('/',Rest);
  if P=0 then raise Exception.Create('API path required');
  Authority:=Copy(Rest,1,P-1); Resource:=Copy(Rest,P,MaxInt);
  Host:=Authority; if Secure then Port:=443 else Port:=80;
  P:=Pos(':',Authority);
  if P>0 then begin
    Host:=Copy(Authority,1,P-1);
    N:=StrToIntDef(Copy(Authority,P+1,MaxInt),0);
    if (N<1) or (N>65535) then raise Exception.Create('Invalid port');
    Port:=N;
  end;
  if Host='' then raise Exception.Create('Invalid host');
  for I:=1 to Length(Host) do if not (Host[I] in ['a'..'z','A'..'Z','0'..'9','-','.']) then
    raise Exception.Create('Invalid host');
  if not Secure and not (AllowLocal and ((Host='127.0.0.1') or (Host='localhost'))) then
    raise Exception.Create('HTTPS URL required');
  if (Pos(#13,URL)>0) or (Pos(#10,URL)>0) or (Pos('#',URL)>0) or (Pos('?',URL)>0) then
    raise Exception.Create('Invalid API URL');
  WAgent:='AIRemoteSignaling/0.2.0'; WHost:=UTF8Decode(Host);
  WMethod:=UTF8Decode(Method); WResource:=UTF8Decode(Resource);
  Session:=WinHttpOpen(PWideChar(WAgent),0,nil,nil,0);
  if Session=nil then raise Exception.Create('WinHTTP unavailable');
  try
    if not WinHttpSetTimeouts(Session,5000,5000,8000,8000) then raise Exception.Create('Cannot set network timeouts');
    Connection:=WinHttpConnect(Session,PWideChar(WHost),Port,0);
    if Connection=nil then raise Exception.Create('Connection failed');
    try
      Flags:=0; if Secure then Flags:=$00800000;
      Req:=WinHttpOpenRequest(Connection,PWideChar(WMethod),PWideChar(WResource),nil,nil,nil,Flags);
      if Req=nil then raise Exception.Create('Request creation failed');
      try
        Policy:=0; // WINHTTP_OPTION_REDIRECT_POLICY_NEVER. Certificate verification stays enabled.
        if not WinHttpSetOption(Req,88,@Policy,SizeOf(Policy)) then raise Exception.Create('Cannot disable redirects');
        WHeaders:='Accept: application/json'+#13#10+'Content-Type: application/json'+#13#10;
        if Token<>'' then WHeaders:=WHeaders+UTF8Decode('Authorization: Bearer '+Token)+#13#10;
        if Idempotency<>'' then WHeaders:=WHeaders+UTF8Decode('Idempotency-Key: '+Idempotency)+#13#10;
        Data:=nil; if Body<>'' then Data:=PChar(Body);
        if not WinHttpSendRequest(Req,PWideChar(WHeaders),Length(WHeaders),Data,Length(Body),Length(Body),0) then
          raise Exception.Create('HTTPS request failed; verify network and certificate');
        if not WinHttpReceiveResponse(Req,nil) then raise Exception.Create('No API response');
        Size:=SizeOf(Code);
        if not WinHttpQueryHeaders(Req,19 or $20000000,nil,@Code,Size,nil) then raise Exception.Create('Invalid HTTP response');
        Status:=Code; Result:=''; Total:=0;
        repeat
          if not WinHttpReadData(Req,@Buffer[0],SizeOf(Buffer),ReadCount) then raise Exception.Create('Response interrupted');
          Inc(Total,ReadCount);
          if Total>MaxBytes then raise Exception.Create('Resposta excede o tamanho permitido');
          if Output<>nil then begin if ReadCount>0 then Output.WriteBuffer(Buffer[0],ReadCount); end
          else begin
            I:=Length(Result); SetLength(Result,I+ReadCount);
            if ReadCount>0 then Move(Buffer[0],Result[I+1],ReadCount);
          end;
        until ReadCount=0;
      finally WinHttpCloseHandle(Req); end;
    finally WinHttpCloseHandle(Connection); end;
  finally WinHttpCloseHandle(Session); end;
end;
{$ENDIF}

function DeskGetJSON(const URL: string): TJSONObject;
var Raw: string; Status: Integer; J: TJSONData;
begin
  Raw := HTTP(URL,'GET','','','',False,Status);
  if Status<>200 then raise Exception.Create('Consulta de versao: HTTP '+IntToStr(Status));
  if Copy(Raw,1,3)=#$EF#$BB#$BF then Delete(Raw,1,3);
  J := GetJSON(Raw);
  if not (J is TJSONObject) then begin J.Free; raise Exception.Create('JSON de atualizacao invalido'); end;
  Result := TJSONObject(J);
end;

function DeskHeartbeat(const URL, Token, Version: string; AllowLocal: Boolean): TJSONObject;
var B: TJSONObject;
begin
  B:=TJSONObject.Create(['app_version',Version]);
  try Result:=DeskAPIRequest(URL,Token,AllowLocal,'POST','/devices/heartbeat',B); finally B.Free; end;
end;

procedure DeskDownloadFile(const URL, Target: string; MaxBytes: Int64);
var Stream: TFileStream; Status: Integer;
begin
  Stream := TFileStream.Create(Target,fmCreate);
  try HTTP(URL,'GET','','','',False,Status,Stream,MaxBytes);
    if Status<>200 then raise Exception.Create('Download: HTTP '+IntToStr(Status));
  finally Stream.Free; end;
end;

function DeskAPIRequest(const BaseURL, Token: string; AllowLocal: Boolean;
  const Method, Route: string; Body: TJSONObject; const RetryKey: string): TJSONObject;
var Raw, Payload, Key: string; Status, I: Integer; J, D: TJSONData;
begin
  if Length(Token) <> 64 then raise Exception.Create('Credencial invalida');
  for I := 1 to Length(Token) do
    if not (Token[I] in ['a'..'f','0'..'9']) then raise Exception.Create('Credencial invalida');
  Payload := ''; if Body <> nil then Payload := Body.AsJSON;
  Key := RetryKey;
  if (Method <> 'GET') and (Key = '') then Key := AIRemoteUUID;
  Raw := HTTP(ExcludeTrailingPathDelimiter(BaseURL) + Route, Method, Token, Payload, Key, AllowLocal, Status);
  J := GetJSON(Raw);
  try
    if not (J is TJSONObject) then raise Exception.Create('Resposta JSON invalida');
    if (Status < 200) or (Status >= 300) then begin
      D := TJSONObject(J).Find('error');
      if D is TJSONObject then
        raise EAIRemoteAPI.CreateAPI(Status,TJSONObject(D).Get('code','API_ERROR'),TJSONObject(D).Get('message','Falha na API'));
      raise EAIRemoteAPI.CreateAPI(Status,'API_ERROR','HTTP ' + IntToStr(Status));
    end;
    D := TJSONObject(J).Find('data');
    if not (D is TJSONObject) then raise Exception.Create('Dados JSON invalidos');
    Result := TJSONObject(D.Clone);
  finally J.Free; end;
end;
function DeskRequestSession(const URL, Token, Key: string; AllowLocal, Control: Boolean): TJSONObject;
var B: TJSONObject; P: TJSONArray;
begin
  if not AIRemoteValidKey(Key) then raise Exception.Create('Chave deve conter 10 digitos');
  B := TJSONObject.Create(['target_key',Key]);
  P := TJSONArray.Create(['screen.view']); B.Add('requested_permissions',P);
  if Control then begin P.Add('input.mouse'); P.Add('input.keyboard'); P.Add('clipboard.sync'); end;
  try Result := DeskAPIRequest(URL,Token,AllowLocal,'POST','/sessions',B); finally B.Free; end;
end;
function DeskAcceptControl(const URL, Token, Id: string; AllowLocal: Boolean; Requested: TJSONArray): TJSONObject;
var B: TJSONObject; P: TJSONArray; I: Integer;
begin
  B := TJSONObject.Create(['decision','accept']);
  P := TJSONArray.Create(['screen.view','input.mouse','input.keyboard']); B.Add('granted_permissions',P);
  if Requested <> nil then for I := 0 to Requested.Count - 1 do
    if Requested.Strings[I] = 'clipboard.sync' then P.Add('clipboard.sync');
  try Result := DeskAPIRequest(URL,Token,AllowLocal,'POST','/sessions/' + Id + '/decision',B); finally B.Free; end;
end;
end.
