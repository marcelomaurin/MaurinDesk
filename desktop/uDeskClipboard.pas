unit uDeskClipboard;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Windows, fpjson, uDeskRelay;
type
  TDeskClipboardThread = class(TThread)
  private
    FURL, FToken, FSessionId, FRoot, FLastRemote: string;
    FAllowLocal: Boolean;
    FSequence: DWORD;
    FWindow: HWND;
    FOnLog: TRelayLogEvent;
    FLogMessage: string;
    FQueueLock: TRTLCriticalSection;
    FPendingFiles: TStringList;
    FReceivedDirectory, FLastSentId, FPendingReceipt: string;
    FReceiptsSupported, FAwaitFileReceipt: Boolean;
    procedure PollSentReceipt;
    procedure SendReceipt;
    function GetReceivedDirectory: string;
    function Request(const Method, Route: string; Body: TJSONObject = nil): TJSONObject;
    procedure Log(const Msg: string);
    procedure DeliverLog;
    procedure SendClipboard;
    procedure ReceiveClipboard;
  protected
    procedure Execute; override;
  public
    constructor Create(const URL, Token, SessionId: string; AllowLocal: Boolean);
    destructor Destroy; override;
    procedure QueueFiles(Paths: TStrings);
    property ReceivedDirectory: string read GetReceivedDirectory;
    property OnLog: TRelayLogEvent read FOnLog write FOnLog;
  end;
implementation
uses base64, sha1, airemoteidentity, airemotesignaling, LazFileUtils,
  uDeskHTTP, uDeskClipboardData;

constructor TDeskClipboardThread.Create(const URL, Token, SessionId: string; AllowLocal: Boolean);
begin
  inherited Create(True); FreeOnTerminate := False;
  FURL := URL; FToken := Token; FSessionId := SessionId; FAllowLocal := AllowLocal;
  FSequence := GetClipboardSequenceNumber;
  InitCriticalSection(FQueueLock); FPendingFiles:=TStringList.Create;
  FRoot := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('LOCALAPPDATA')) +
    'MaurinDesk' + PathDelim + 'Clipboard' + PathDelim + FSessionId + PathDelim;
end;

destructor TDeskClipboardThread.Destroy;
begin
  Terminate; inherited Destroy;
  FPendingFiles.Free; DoneCriticalSection(FQueueLock);
end;
procedure TDeskClipboardThread.QueueFiles(Paths: TStrings);
begin
  if (Paths=nil) or (Paths.Count=0) or (Paths.Count>10000) then raise Exception.Create('Selecione arquivos ou uma pasta');
  EnterCriticalSection(FQueueLock);
  try FPendingFiles.Assign(Paths); finally LeaveCriticalSection(FQueueLock); end;
end;
function TDeskClipboardThread.GetReceivedDirectory: string;
begin
  EnterCriticalSection(FQueueLock);
  try Result:=FReceivedDirectory; finally LeaveCriticalSection(FQueueLock); end;
end;

function TDeskClipboardThread.Request(const Method, Route: string; Body: TJSONObject): TJSONObject;
var Attempt: Integer; RetryKey: string;
begin
  RetryKey := AIRemoteUUID;
  for Attempt := 1 to 3 do begin
    if Terminated then raise EAbort.Create('Transferencia interrompida');
    try
      Result := DeskAPIRequest(FURL, FToken, FAllowLocal, Method,
        '/sessions/' + FSessionId + '/clipboard' + Route, Body, RetryKey);
      Exit;
    except
      on E: EAIRemoteAPI do begin
        if (E.Status < 500) or (Attempt = 3) then raise;
      end;
      on E: Exception do if Attempt = 3 then raise;
    end;
    Sleep(200);
  end;
  Result := nil;
end;

procedure TDeskClipboardThread.Log(const Msg: string);
begin FLogMessage := Msg; Synchronize(@DeliverLog); end;
procedure TDeskClipboardThread.DeliverLog;
begin if Assigned(FOnLog) then FOnLog(Self, FLogMessage); end;

procedure TDeskClipboardThread.SendClipboard;
var Paths: TStringList; Text, Kind, PackagePath, Raw, Id: string; Sequence: DWORD;
    Stream: TFileStream; B, R: TJSONObject; Part, Count, ReadBytes: Integer; Forced, PeerReceipts: Boolean;
begin
  if FAwaitFileReceipt then Exit;
  Paths := TStringList.Create; PackagePath := FRoot + 'sending.bin';
  try
    EnterCriticalSection(FQueueLock);
    try Paths.Assign(FPendingFiles); FPendingFiles.Clear; finally LeaveCriticalSection(FQueueLock); end;
    Forced:=Paths.Count>0; Text:=''; Sequence:=GetClipboardSequenceNumber;
    if not Forced then begin
    if Sequence=FSequence then Exit;
    if GetClipboardOwner=FWindow then begin FSequence:=Sequence; Exit; end;
    if not ReadWindowsClipboard(FWindow, Sequence, Text, Paths) then begin
      // Unsupported format: do not send private or existing clipboard formats.
      if not IsClipboardFormatAvailable(CF_HDROP) and not IsClipboardFormatAvailable(CF_UNICODETEXT) then
        FSequence := GetClipboardSequenceNumber;
      Exit;
    end;
    end;
    if not ForceDirectoriesUTF8(FRoot) then raise Exception.Create('Nao foi possivel preparar a copia');
    if Paths.Count > 0 then begin Kind := 'files'; BuildClipboardFiles(Paths, PackagePath); end
    else begin
      Kind := 'text'; Stream := TFileStream.Create(PackagePath, fmCreate);
      try if Text <> '' then Stream.WriteBuffer(Text[1], Length(Text)); finally Stream.Free; end;
    end;
    // A newer local copy supersedes this snapshot.
    if not Forced and (GetClipboardSequenceNumber <> Sequence) then Exit;
    Stream := TFileStream.Create(PackagePath, fmOpenRead or fmShareDenyWrite);
    try
      B := TJSONObject.Create(['kind', Kind, 'total_bytes', Stream.Size,
        'checksum', LowerCase(SHA1Print(SHA1File(PackagePath)))]);
      try R := Request('POST', '', B); finally B.Free; end;
      try Id := R.Get('id', ''); Count := R.Get('chunk_count', 0);
        FReceiptsSupported:=R.Get('protocol_version',0)>=2;
        PeerReceipts:=R.Get('peer_receipts',False);
      finally R.Free; end;
      if (Length(Id) <> 36) or (Count < 1) or (Count > 1024) then raise Exception.Create('Transferencia invalida');
      Log('[CLIPBOARD] Enviando ' + Kind + ' (' + IntToStr(Stream.Size) + ' bytes)...');
      for Part := 0 to Count - 1 do begin
        if Terminated or (not Forced and (GetClipboardSequenceNumber <> Sequence)) then Exit;
        ReadBytes := CLIP_CHUNK_BYTES;
        if Stream.Size - Stream.Position < ReadBytes then ReadBytes := Stream.Size - Stream.Position;
        SetLength(Raw, ReadBytes); if ReadBytes > 0 then Stream.ReadBuffer(Raw[1], ReadBytes);
        B := TJSONObject.Create(['data', EncodeStringBase64(Raw)]);
        try R := Request('POST', '/' + Id + '/' + IntToStr(Part), B); finally B.Free; end;
        R.Free;
        if (Count > 10) and ((Part + 1) mod 10 = 0) then
          Log('[CLIPBOARD] Envio: ' + IntToStr((Part + 1) * 100 div Count) + '%');
      end;
      R := Request('POST', '/' + Id); R.Free;
      if not Forced then FSequence := Sequence;
      FLastSentId:=''; FAwaitFileReceipt:=(Kind='files') and FReceiptsSupported and PeerReceipts;
      if FReceiptsSupported and PeerReceipts then begin
        FLastSentId:=Id; Log('[CLIPBOARD] Enviado ao servidor. Aguardando recebimento na outra maquina.');
      end else Log('[CLIPBOARD] Enviado ao servidor. A outra versao nao confirma o recebimento; confira no destino.');
    finally Stream.Free; end;
  finally Paths.Free; if FileExistsUTF8(PackagePath) then DeleteFileUTF8(PackagePath); end;
end;

procedure TDeskClipboardThread.ReceiveClipboard;
var R: TJSONObject; Id, Kind, Hash, PackagePath, Raw, Text: string;
    Size: Int64; Count, Part, Attempt: Integer; Sequence, AppliedSequence: DWORD;
    Stream: TFileStream; Paths: TStringList; Applied: Boolean;
begin
  R := Request('GET', '');
  try
    if R.Get('status', '') <> 'ready' then Exit;
    FReceiptsSupported:=R.Get('protocol_version',0)>=2;
    Id := R.Get('id', ''); if Id = FLastRemote then Exit;
    Kind := R.Get('kind', ''); Size := R.Get('total_bytes', Int64(-1));
    Count := R.Get('chunk_count', 0); Hash := R.Get('checksum', '');
  finally R.Free; end;
  if (Length(Id) <> 36) or (Size < 0) or (Size > CLIP_MAX_BYTES) or (Count < 1) or (Count > 1024) or
    not ((Kind = 'text') or (Kind = 'files')) or ((Kind = 'text') and (Size > CLIP_MAX_TEXT)) then
    raise Exception.Create('Transferencia recebida invalida');
  for Part := 1 to Length(Id) do
    if not (Id[Part] in ['a'..'f', '0'..'9', '-']) then raise Exception.Create('Identificador invalido');
  Sequence := GetClipboardSequenceNumber;
  if not ForceDirectoriesUTF8(FRoot) then raise Exception.Create('Nao foi possivel preparar o recebimento');
  PackagePath := FRoot + 'receiving.bin'; Paths := TStringList.Create;
  try
    Stream := TFileStream.Create(PackagePath, fmCreate);
    try
      for Part := 0 to Count - 1 do begin
        if Terminated then Exit;
        try R := Request('GET', '/' + Id + '/' + IntToStr(Part));
        except on E: EAIRemoteAPI do begin
          if (E.Status=404) and (E.Code='CLIPBOARD_ERROR') then Exit;
          raise;
        end; end;
        try Raw := DecodeStringBase64(R.Get('data', '')); finally R.Free; end;
        if (Length(Raw) > CLIP_CHUNK_BYTES) or (Stream.Size + Length(Raw) > Size) then
          raise Exception.Create('Parte recebida excede o tamanho anunciado');
        if Raw <> '' then Stream.WriteBuffer(Raw[1], Length(Raw));
        if (Count > 10) and ((Part + 1) mod 10 = 0) then
          Log('[CLIPBOARD] Recebimento: ' + IntToStr((Part + 1) * 100 div Count) + '%');
      end;
      if Stream.Size <> Size then raise Exception.Create('Transferencia incompleta');
    finally Stream.Free; end;
    if LowerCase(SHA1Print(SHA1File(PackagePath))) <> Hash then raise Exception.Create('Integridade da copia invalida');
    if GetClipboardSequenceNumber <> Sequence then begin
      FLastRemote := Id; Log('[CLIPBOARD] Copia local mais recente preservada.'); Exit;
    end;
    Text := '';
    if Kind = 'files' then begin
      Log('[CLIPBOARD] Preparando arquivos e pastas recebidos...');
      ExtractClipboardFiles(PackagePath, FRoot + Id, Paths);
      EnterCriticalSection(FQueueLock);
      try FReceivedDirectory:=FRoot+Id; finally LeaveCriticalSection(FQueueLock); end;
    end
    else begin
      Stream := TFileStream.Create(PackagePath, fmOpenRead or fmShareDenyWrite);
      try SetLength(Text, Stream.Size); if Text <> '' then Stream.ReadBuffer(Text[1], Length(Text)); finally Stream.Free; end;
    end;
    Applied := False;
    for Attempt := 1 to 20 do begin
      if Terminated then Exit;
      if GetClipboardSequenceNumber <> Sequence then Break;
      Applied := WriteWindowsClipboard(FWindow, Sequence, Text, Paths, AppliedSequence);
      if Applied then Break;
      Sleep(100);
    end;
    if Applied then begin
      FSequence := AppliedSequence; // Do not echo the received copy or lose a later local copy.
      FLastRemote := Id;
      Log('[CLIPBOARD] ' + Kind + ' recebido. Pronto para colar com Ctrl+V.');
      if FReceiptsSupported then FPendingReceipt:=Id;
    end else if GetClipboardSequenceNumber <> Sequence then FLastRemote := Id;
  finally Paths.Free; if FileExistsUTF8(PackagePath) then DeleteFileUTF8(PackagePath); end;
end;

procedure TDeskClipboardThread.SendReceipt;
var B,R: TJSONObject;
begin
  if FPendingReceipt='' then Exit;
  B:=TJSONObject.Create(['received',True]);
  try
    try R:=Request('POST','/'+FPendingReceipt,B); R.Free; FPendingReceipt:='';
    except on E: EAIRemoteAPI do begin if E.Status=404 then FPendingReceipt:='' else raise; end; end;
  finally B.Free; end;
end;
procedure TDeskClipboardThread.PollSentReceipt;
var R: TJSONObject;
begin
  if (FLastSentId='') or not FReceiptsSupported then Exit;
  try
    R:=Request('GET','/'+FLastSentId);
    try
      if R.Get('status','')='received' then begin
        FLastSentId:=''; FAwaitFileReceipt:=False;
        Log('[CLIPBOARD] Recebimento confirmado pela outra maquina. Pronto para colar com Ctrl+V.');
      end;
    finally R.Free; end;
  except on E: EAIRemoteAPI do begin
    if E.Status=404 then begin FLastSentId:=''; FAwaitFileReceipt:=False; end else raise;
  end; end;
end;

procedure TDeskClipboardThread.Execute;
var I: Integer;
begin
  FWindow := CreateWindowExW(0, 'STATIC', 'MaurinDesk Clipboard', 0, 0, 0, 0, 0, 0, 0, HInstance, nil);
  if FWindow = 0 then begin Log('[CLIPBOARD ERRO] Nao foi possivel inicializar a area de transferencia'); Exit; end;
  try
    Log('[CLIPBOARD] Sincronizacao de texto e arquivos ativa nos dois sentidos.');
    while not Terminated do begin
      try
        SendReceipt;
        PollSentReceipt;
        SendClipboard;
        if not Terminated then ReceiveClipboard;
      except
        on E: EAbort do Break;
        on E: EAIRemoteAPI do begin
          Log('[CLIPBOARD ERRO] ' + E.Code + ': ' + E.Message);
          if (E.Status = 401) or (E.Status = 403) or (E.Status = 404) then Break;
          for I := 1 to 30 do begin if Terminated then Break; Sleep(100); end;
        end;
        on E: Exception do begin
          Log('[CLIPBOARD ERRO] ' + E.Message);
          for I := 1 to 30 do begin if Terminated then Break; Sleep(100); end;
        end;
      end;
      for I := 1 to 5 do begin if Terminated then Break; Sleep(100); end;
    end;
  finally DestroyWindow(FWindow); end;
end;
end.
