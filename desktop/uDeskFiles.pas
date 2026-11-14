unit uDeskFiles;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, fpjson;
type
  TFileServiceEvent = procedure(Sender: TObject; Data: TJSONObject) of object;
  TDeskFiles = class(TThread)
  private
    FURL,FToken,FSession,FCache,FOwner: string;
    FAllowLocal,FInControl: Boolean;
    FLock: TRTLCriticalSection;
    FActions: TJSONArray;
    FPendingCommands,FWaiting,FDelivered,FCommandJobs: TStringList;
    FAcks: TJSONArray;
    FNextControl: QWord;
    FEvent: TJSONObject;
    FOnEvent: TFileServiceEvent;
    procedure DeliverEvent;
    procedure Emit(Data: TJSONObject);
    procedure Progress(const Job,Direction,Source,Destination,State,Message: string; Percent: Integer);
    function Request(const Method,Route: string; Body: TJSONObject=nil): TJSONObject;
    procedure Enqueue(Action: TJSONObject);
    function TakeAction(Uploads: Boolean): TJSONObject;
    procedure PumpControl;
    procedure IncomingCommands;
    procedure PendingCommands;
    procedure PendingAcks;
    procedure WaitingTransfers;
    procedure Upload(Action: TJSONObject);
    procedure ReceiveTransfer;
    procedure SubmitCommand(Action: TJSONObject; Payload: TJSONObject);
  protected
    procedure Execute; override;
  public
    constructor Create(const URL,Token,Session: string; AllowLocal: Boolean; const CacheRoot: string='');
    destructor Destroy; override;
    function Browse(Local: Boolean; const Path,Filter: string; Offset: Integer=0): string;
    function Send(Paths: TStrings; const Destination: string; Overwrite: Boolean): string;
    function Receive(Paths: TStrings; const Destination: string; Overwrite: Boolean): string;
    procedure MakeDirectory(Local: Boolean; const Parent,Name: string);
    property OnEvent: TFileServiceEvent read FOnEvent write FOnEvent;
  end;
implementation
uses Windows, base64, sha1, airemoteidentity, airemotesignaling, LazFileUtils, FileUtil,
  uDeskHTTP,uDeskClipboardData,uDeskFileSystem;

function ValidFileId(const Id: string): Boolean;
var I: Integer;
begin
  Result:=Length(Id)=36; if not Result then Exit;
  for I:=1 to 36 do if I in [9,14,19,24] then begin if Id[I]<>'-' then Exit(False); end
    else if not (Id[I] in ['0'..'9','a'..'f']) then Exit(False);
end;
function PathArray(Paths: TStrings): TJSONArray;
var I: Integer;
begin Result:=TJSONArray.Create; for I:=0 to Paths.Count-1 do Result.Add(Paths[I]); end;

constructor TDeskFiles.Create(const URL,Token,Session: string; AllowLocal: Boolean; const CacheRoot: string);
begin
  inherited Create(True); FreeOnTerminate:=False;
  if not ValidFileId(Session) then raise Exception.Create('Sessao de arquivos invalida.');
  FURL:=URL; FToken:=Token; FSession:=Session; FAllowLocal:=AllowLocal; FOwner:=AIRemoteUUID;
  FCache:=IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('LOCALAPPDATA'))+'MaurinDesk\Files\'+Session+'\';
  if CacheRoot<>'' then FCache:=IncludeTrailingPathDelimiter(CacheRoot)+Session+'\';
  InitCriticalSection(FLock); FActions:=TJSONArray.Create; FAcks:=TJSONArray.Create;
  FPendingCommands:=TStringList.Create; FWaiting:=TStringList.Create; FDelivered:=TStringList.Create; FCommandJobs:=TStringList.Create;
end;
destructor TDeskFiles.Destroy;
var I: Integer;
begin
  Terminate; inherited Destroy;
  for I:=0 to FPendingCommands.Count-1 do FPendingCommands.Objects[I].Free;
  for I:=0 to FWaiting.Count-1 do FWaiting.Objects[I].Free;
  FPendingCommands.Free; FWaiting.Free; FDelivered.Free; FCommandJobs.Free; FAcks.Free; FActions.Free; DoneCriticalSection(FLock);
end;
procedure TDeskFiles.DeliverEvent;
begin if Assigned(FOnEvent) then FOnEvent(Self,FEvent); end;
procedure TDeskFiles.Emit(Data: TJSONObject);
begin FEvent:=Data; try if not Terminated then Synchronize(@DeliverEvent); finally FEvent:=nil; Data.Free; end; end;
procedure TDeskFiles.Progress(const Job,Direction,Source,Destination,State,Message: string; Percent: Integer);
begin Emit(TJSONObject.Create(['event','progress','job_id',Job,'direction',Direction,'source',Source,
  'destination',Destination,'state',State,'message',Message,'percent',Percent])); end;

function TDeskFiles.Request(const Method,Route: string; Body: TJSONObject): TJSONObject;
var Attempt: Integer; RetryKey: string;
begin
  RetryKey:=AIRemoteUUID;
  for Attempt:=1 to 3 do begin
    if Terminated then raise EAbort.Create('Transferência interrompida');
    try Result:=DeskAPIRequest(FURL,FToken,FAllowLocal,Method,'/sessions/'+FSession+'/files/'+Route,Body,RetryKey); Exit;
    except
      on E: EAIRemoteAPI do if (E.Status<500) or (Attempt=3) then raise;
      on E: Exception do if Attempt=3 then raise;
    end;
    Sleep(150);
  end;
  Result:=nil;
end;
procedure TDeskFiles.Enqueue(Action: TJSONObject);
begin
  EnterCriticalSection(FLock);
  try
    if FActions.Count>=32 then begin Action.Free; raise Exception.Create('Aguarde os itens da fila terminarem.'); end;
    FActions.Add(Action);
  finally LeaveCriticalSection(FLock); end;
end;
function TDeskFiles.TakeAction(Uploads: Boolean): TJSONObject;
var I: Integer;
begin
  Result:=nil; EnterCriticalSection(FLock);
  try for I:=0 to FActions.Count-1 do
    if (TJSONObject(FActions[I]).Get('op','')='upload')=Uploads then begin
      Result:=TJSONObject(FActions[I].Clone); FActions.Delete(I); Break;
    end;
  finally LeaveCriticalSection(FLock); end;
end;
function TDeskFiles.Browse(Local: Boolean; const Path,Filter: string; Offset: Integer): string;
begin
  Result:=AIRemoteUUID;
  Enqueue(TJSONObject.Create(['op','browse','local',Local,'ticket',Result,'path',Path,'filter',Filter,'offset',Offset]));
end;
function TDeskFiles.Send(Paths: TStrings; const Destination: string; Overwrite: Boolean): string;
var Action: TJSONObject;
begin
  if (Paths=nil) or (Paths.Count=0) or (Paths.Count>128) then raise Exception.Create('Selecione até 128 itens ou uma pasta.');
  Result:=AIRemoteUUID; Action:=TJSONObject.Create(['op','upload','job_id',Result,'destination',Destination,'overwrite',Overwrite]);
  Action.Add('paths',PathArray(Paths)); Enqueue(Action);
end;
function TDeskFiles.Receive(Paths: TStrings; const Destination: string; Overwrite: Boolean): string;
var Action: TJSONObject;
begin
  NormalizeDiskPath(Destination,True);
  if (Paths=nil) or (Paths.Count=0) or (Paths.Count>128) then raise Exception.Create('Selecione até 128 itens ou uma pasta.');
  Result:=AIRemoteUUID; Action:=TJSONObject.Create(['op','download','job_id',Result,'destination',Destination,'overwrite',Overwrite]);
  Action.Add('paths',PathArray(Paths)); Enqueue(Action);
end;
procedure TDeskFiles.MakeDirectory(Local: Boolean; const Parent,Name: string);
begin Enqueue(TJSONObject.Create(['op','mkdir','local',Local,'path',Parent,'name',Name])); end;

procedure TDeskFiles.SubmitCommand(Action: TJSONObject; Payload: TJSONObject);
var R: TJSONObject; Id: string;
begin
  try R:=Request('POST','commands',Payload); finally Payload.Free; end;
  try Id:=R.Get('id',''); if not ValidFileId(Id) then raise Exception.Create('Resposta remota inválida.');
    FPendingCommands.AddObject(Id,Action.Clone);
  finally R.Free; end;
end;

procedure TDeskFiles.PumpControl;
var Action,Payload,Data: TJSONObject; N: Integer; Local: Boolean; Op: string;
begin
  if FInControl or (GetTickCount64<FNextControl) or Terminated then Exit;
  FInControl:=True; FNextControl:=GetTickCount64+500;
  try
    for N:=1 to 4 do begin
      Action:=TakeAction(False); if Action=nil then Break;
      try
        Op:=Action.Get('op',''); Local:=Action.Get('local',False);
        try
          if Op='browse' then begin
            if Local then begin
              Data:=ReadDiskDirectory(Action.Get('path',''),Action.Get('filter',''),Action.Get('offset',0));
              Payload:=TJSONObject.Create(['event','listing','local',True,'ticket',Action.Get('ticket','')]);
              Payload.Add('data',Data); Emit(Payload);
            end else SubmitCommand(Action,TJSONObject.Create(['action','list','path',Action.Get('path',''),
              'filter',Action.Get('filter',''),'offset',Action.Get('offset',0)]));
          end else if Op='mkdir' then begin
            if Local then begin MakeDiskDirectory(Action.Get('path',''),Action.Get('name','')); Emit(TJSONObject.Create(['event','changed','local',True])); end
            else SubmitCommand(Action,TJSONObject.Create(['action','mkdir','path',Action.Get('path',''),'name',Action.Get('name','')]));
          end else if Op='download' then begin
            Payload:=TJSONObject.Create(['action','send','request_id',Action.Get('job_id',''),
              'destination',Action.Get('destination',''),'overwrite',Action.Get('overwrite',False)]);
            Payload.Add('paths',Action.Arrays['paths'].Clone); SubmitCommand(Action,Payload);
            Progress(Action.Get('job_id',''),'receive','Seleção remota',Action.Get('destination',''),'waiting','Aguardando o computador remoto preparar os arquivos...',0);
          end;
        except
          on E: EAbort do raise;
          on E: Exception do begin
            if Op='browse' then Emit(TJSONObject.Create(['event','listing_error','local',Local,'ticket',Action.Get('ticket',''),'message',E.Message]))
            else Progress(Action.Get('job_id',''),'receive','',Action.Get('destination',''),'error',E.Message,0);
          end;
        end;
      finally Action.Free; end;
    end;
    IncomingCommands; PendingCommands;
  finally FInControl:=False; end;
end;

procedure TDeskFiles.IncomingCommands;
var R,Command,Payload,Reply,B,A: TJSONObject; Items: TJSONArray; I: Integer;
begin
  R:=Request('GET','commands');
  try
    Items:=R.Arrays['items']; if Items=nil then Exit;
    for I:=0 to Items.Count-1 do begin
      if Terminated then Exit;
      Command:=TJSONObject(Items[I]); Payload:=Command.Objects['payload']; Reply:=nil;
      try
        try
          if Command.Get('action','')='list' then begin
            Reply:=TJSONObject.Create(['ok',True]);
            Reply.Add('data',ReadDiskDirectory(Payload.Get('path',''),Payload.Get('filter',''),Payload.Get('offset',0)));
          end else if Command.Get('action','')='mkdir' then begin
            MakeDiskDirectory(Payload.Get('path',''),Payload.Get('name','')); Reply:=TJSONObject.Create(['ok',True]);
          end else if Command.Get('action','')='send' then begin
            if FCommandJobs.IndexOf(Payload.Get('request_id',''))<0 then begin
            A:=TJSONObject.Create(['op','upload','job_id',Payload.Get('request_id',''),
              'destination',Payload.Get('destination',''),'overwrite',Payload.Get('overwrite',False)]);
            A.Add('paths',Payload.Arrays['paths'].Clone); Enqueue(A); FCommandJobs.Add(Payload.Get('request_id','')); end; Reply:=TJSONObject.Create(['ok',True,'queued',True]);
          end else if Command.Get('action','')='job_error' then begin
            Progress(Payload.Get('request_id',''),'receive','Selecao remota',Payload.Get('destination',''),'error',Payload.Get('message','Falha remota.'),0);
            Reply:=TJSONObject.Create(['ok',True]);
          end else raise Exception.Create('Comando remoto inválido.');
        except
          on E: EAbort do raise;
          on E: Exception do begin Reply.Free; Reply:=TJSONObject.Create(['ok',False,'error',E.Message]); end;
        end;
        B:=TJSONObject.Create; B.Add('response',Reply); Reply:=nil;
        try A:=Request('POST','commands/'+Command.Get('id',''),B); A.Free; finally B.Free; end;
      finally Reply.Free; end;
    end;
  finally R.Free; end;
end;

procedure TDeskFiles.PendingCommands;
var ErrorText: string; I: Integer; R,Response,Context,Event: TJSONObject; Op: string;
begin
  for I:=FPendingCommands.Count-1 downto 0 do begin
    R:=Request('GET','commands/'+FPendingCommands[I]);
    try
      if R.Get('state','')<>'completed' then Continue;
      Context:=TJSONObject(FPendingCommands.Objects[I]); Response:=R.Objects['response']; Op:=Context.Get('op','');
      try
        if (Response=nil) or not Response.Get('ok',False) then begin
          ErrorText:='Resposta remota invalida.'; if Response<>nil then ErrorText:=Response.Get('error','Falha remota.');
          if Op='browse' then Emit(TJSONObject.Create(['event','listing_error','local',False,'ticket',Context.Get('ticket',''),'message',ErrorText]))
          else Progress(Context.Get('job_id',''),'receive','Seleção remota',Context.Get('destination',''),'error',ErrorText,0);
        end else if (Op='browse') and (Response.Objects['data']<>nil) then begin
          Event:=TJSONObject.Create(['event','listing','local',False,'ticket',Context.Get('ticket','')]);
          Event.Add('data',Response.Objects['data'].Clone); Emit(Event);
        end else if Op='mkdir' then Emit(TJSONObject.Create(['event','changed','local',False]));
      finally Context.Free; FPendingCommands.Delete(I); end;
    finally R.Free; end;
  end;
end;

procedure TDeskFiles.Upload(Action: TJSONObject);
var Paths: TStringList; Source,Destination,Job,PackageName,Id,Raw: string; S: TFileStream;
    B,R,Context: TJSONObject; Count,Part,N,ProgressValue,I: Integer;
begin
  Job:=Action.Get('job_id',''); Destination:=Action.Get('destination',''); Source:=''; Id:='';
  Paths:=TStringList.Create; PackageName:=FCache+'send-'+Job+'.bin';
  try
    try
      for I:=0 to Action.Arrays['paths'].Count-1 do Paths.Add(NormalizeDiskPath(Action.Arrays['paths'].Strings[I],False));
      if Paths.Count=0 then raise Exception.Create('Nenhum arquivo selecionado.');
      Source:=Paths[0]; if Paths.Count>1 then Source:=Source+' (+'+IntToStr(Paths.Count-1)+')';
      Progress(Job,'send',Source,Destination,'preparing','Preparando arquivos e pastas...',0);
      if not ForceDirectoriesUTF8(FCache) then raise Exception.Create('Pasta de transferência indisponível.');
      BuildClipboardFiles(Paths,PackageName);
      if Terminated then Exit;
      S:=TFileStream.Create(PackageName,fmOpenRead or fmShareDenyWrite);
      try
        B:=TJSONObject.Create(['request_id',Job,'destination',Destination,'overwrite',Action.Get('overwrite',False),
          'total_bytes',S.Size,'checksum',LowerCase(SHA1Print(SHA1File(PackageName)))]);
        try R:=Request('POST','transfers',B); finally B.Free; end;
        try Id:=R.Get('id',''); Count:=R.Get('chunk_count',0); finally R.Free; end;
        if (not ValidFileId(Id)) or (Count<1) or (Count>1024) then raise Exception.Create('Resposta de transferência inválida.');
        Context:=TJSONObject.Create(['job_id',Job,'source',Source,'destination',Destination]); FWaiting.AddObject(Id,Context);
        for Part:=0 to Count-1 do begin
          if Terminated then Exit;
          PumpControl;
          N:=CLIP_CHUNK_BYTES; if S.Size-S.Position<N then N:=S.Size-S.Position;
          SetLength(Raw,N); if N>0 then S.ReadBuffer(Raw[1],N);
          B:=TJSONObject.Create(['data',EncodeStringBase64(Raw)]);
          try R:=Request('POST','transfers/'+Id+'/'+IntToStr(Part),B); R.Free; finally B.Free; end;
          ProgressValue:=(Part+1)*70 div Count;
          if (Part=0) or ((Part+1) mod 4=0) or (Part=Count-1) then
            Progress(Job,'send',Source,Destination,'uploading','Enviando...',ProgressValue);
        end;
        R:=Request('POST','transfers/'+Id); R.Free;
        Progress(Job,'send',Source,Destination,'waiting','Aguardando gravação no destino...',75);
      finally S.Free; end;
    except
      on E: EAbort do raise;
      on E: Exception do begin
        Progress(Job,'send',Source,Destination,'error',E.Message,0);
        I:=FWaiting.IndexOf(Id); if I>=0 then begin FWaiting.Objects[I].Free; FWaiting.Delete(I); end;
        if FCommandJobs.IndexOf(Job)>=0 then begin
          B:=TJSONObject.Create(['action','job_error','request_id',Job,'destination',Destination,'message',Copy(E.Message,1,1800)]);
          try try R:=Request('POST','commands',B); R.Free; except end; finally B.Free; end;
        end;
      end;
    end;
  finally Paths.Free; if FileExistsUTF8(PackageName) then DeleteFileUTF8(PackageName); end;
end;

procedure TDeskFiles.WaitingTransfers;
var I: Integer; R,C,Outcome: TJSONObject; State,Msg: string;
begin
  for I:=FWaiting.Count-1 downto 0 do begin
    R:=Request('GET','transfers/'+FWaiting[I]);
    try
      State:=R.Get('state',''); if (State<>'completed') and (State<>'error') then Continue;
      C:=TJSONObject(FWaiting.Objects[I]); Outcome:=R.Objects['result']; Msg:='Gravado na pasta de destino.';
      if (State='error') and (Outcome<>nil) then Msg:=Outcome.Get('message','Falha no destino.');
      Progress(C.Get('job_id',''),'send',C.Get('source',''),C.Get('destination',''),State,Msg,100);
      C.Free; FWaiting.Delete(I);
    finally R.Free; end;
  end;
end;

procedure TDeskFiles.PendingAcks;
var I: Integer; Item,B,R: TJSONObject;
begin
  for I:=FAcks.Count-1 downto 0 do begin
    Item:=TJSONObject(FAcks[I]); B:=TJSONObject(Item.Objects['body'].Clone);
    try
      try R:=Request('POST','transfers/'+Item.Get('id',''),B); R.Free; FAcks.Delete(I);
      except on E: EAIRemoteAPI do begin if E.Status=404 then FAcks.Delete(I) else raise; end; end;
    finally B.Free; end;
  end;
end;

procedure TDeskFiles.ReceiveTransfer;
var R,Item,B,Outcome,Ack: TJSONObject; Items: TJSONArray; Id,Job,Destination,PackageName,DirectoryPath,Raw,Checksum,State,Msg: string;
    Count,Part,N: Integer; Size: Int64; LastLease: QWord; S: TFileStream;
  procedure Claim;
  var C,Response: TJSONObject;
  begin C:=TJSONObject.Create(['owner',FOwner]); try Response:=Request('POST','transfers/'+Id+'/claim',C); Response.Free; finally C.Free; end; LastLease:=GetTickCount64; end;
begin
  R:=Request('GET','transfers');
  try
    Items:=R.Arrays['items']; if (Items=nil) or (Items.Count=0) then Exit;
    Item:=TJSONObject(Items[0]); Id:=Item.Get('id',''); Job:=Item.Get('request_id','');
    if (not ValidFileId(Id)) or (not ValidFileId(Job)) then raise Exception.Create('Transferência inválida.');
    if FDelivered.IndexOf(Id)>=0 then Exit;
    Destination:=Item.Get('destination',''); Count:=Item.Get('chunk_count',0); Size:=Item.Get('total_bytes',Int64(0)); Checksum:=Item.Get('checksum','');
    if (Count<1) or (Count>1024) or (Size<4) or (Size>CLIP_MAX_BYTES) then raise Exception.Create('Tamanho de transferência inválido.');
    try Claim; except on E: EAIRemoteAPI do begin if E.Status=409 then Exit else raise; end; end;
    DirectoryPath:=FCache+Id; PackageName:=IncludeTrailingPathDelimiter(DirectoryPath)+'payload.bin'; Outcome:=nil;
    try
      State:='completed'; Msg:='Arquivos gravados na pasta escolhida.';
      try
        NormalizeDiskPath(Destination,True);
        if not ForceDirectoriesUTF8(DirectoryPath) then raise Exception.Create('Pasta de recebimento indisponível.');
        S:=TFileStream.Create(PackageName,fmCreate);
        try
          for Part:=0 to Count-1 do begin
            if Terminated then Exit;
            PumpControl; if GetTickCount64-LastLease>25000 then Claim;
            B:=Request('GET','transfers/'+Id+'/'+IntToStr(Part));
            try Raw:=DecodeStringBase64(B.Get('data','')); finally B.Free; end;
            N:=Length(Raw); if (N>CLIP_CHUNK_BYTES) or (S.Size+N>Size) then raise Exception.Create('Parte de arquivo inválida.');
            if N>0 then S.WriteBuffer(Raw[1],N);
            if (Part=0) or ((Part+1) mod 4=0) or (Part=Count-1) then Progress(Job,'receive','Seleção remota',Destination,'receiving','Recebendo...',5+(Part+1)*85 div Count);
          end;
          if S.Size<>Size then raise Exception.Create('Transferência incompleta.');
        finally S.Free; end;
        if LowerCase(SHA1Print(SHA1File(PackageName)))<>Checksum then raise Exception.Create('Integridade dos arquivos inválida.');
        Claim; Progress(Job,'receive','Seleção remota',Destination,'saving','Gravando na pasta escolhida...',95);
        Outcome:=PlaceFilePackage(PackageName,IncludeTrailingPathDelimiter(DirectoryPath)+'unpacked',Destination,Item.Get('overwrite',False));
      except
        on E: EAbort do raise;
        on E: Exception do begin State:='error'; Msg:=E.Message; Outcome:=TJSONObject.Create(['message',Msg,'destination',Destination]); end;
      end;
      FDelivered.Add(Id);
      Ack:=TJSONObject.Create(['id',Id]); B:=TJSONObject.Create(['owner',FOwner,'state',State]); B.Add('result',Outcome); Outcome:=nil;
      Ack.Add('body',B); FAcks.Add(Ack);
      Progress(Job,'receive','Seleção remota',Destination,State,Msg,100);
    finally
      Outcome.Free;
      // Only the UUID-named private receive cache is removed, never the selected destination.
      try if DirectoryExistsUTF8(DirectoryPath) then begin NormalizeDiskPath(DirectoryPath,True); FileUtil.DeleteDirectory(DirectoryPath,False); end; except end;
    end;
  finally R.Free; end;
end;

procedure TDeskFiles.Execute;
var Action: TJSONObject; I: Integer;
begin
  while not Terminated do begin
    try
      PumpControl; PendingAcks; WaitingTransfers; ReceiveTransfer;
      Action:=TakeAction(True);
      if Action<>nil then try Upload(Action); finally Action.Free; end;
    except
      on E: EAbort do Break;
      on E: EAIRemoteAPI do begin
        Emit(TJSONObject.Create(['event','service_error','message',E.Message]));
        if (E.Status=401) or (E.Status=403) then Break;
        for I:=1 to 20 do begin if Terminated then Break; Sleep(100); end;
      end;
      on E: Exception do begin
        Emit(TJSONObject.Create(['event','service_error','message',E.Message]));
        for I:=1 to 20 do begin if Terminated then Break; Sleep(100); end;
      end;
    end;
    for I:=1 to 5 do begin if Terminated then Break; Sleep(100); end;
  end;
end;
end.
