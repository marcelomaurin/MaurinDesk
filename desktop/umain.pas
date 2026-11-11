unit umain;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  fpjson, jsonparser, IniFiles, md5, airemoteidentity, airemotesignaling;
type
  TMainForm=class;
  TOperation=(opRegister,opPoll,opConnect,opAcceptView,opAcceptControl,opReject,opClose);
  TAPIWorker=class(TThread)
  private
    FOwner:TMainForm;
    procedure Deliver;
  protected
    procedure Execute; override;
  public
    Operation:TOperation;
    URL,Token,IdentityFile,RemoteKey,SessionId,Failure:string;
    AllowLocal,Control:Boolean;
    Data:TJSONObject;
    constructor Create(AOwner:TMainForm);
    destructor Destroy; override;
  end;
  TMainForm=class(TForm)
  private
    FURL,FToken,FSessionId,FProfile,FIdentityFile:string;
    FBusy,FClosing,FAllowLocal:Boolean;
    FWorker:TAPIWorker;
    FTimer:TTimer;
    FKeyLabel,FStatus:TLabel;
    FTarget,FName:TEdit;
    FIncoming,FFavorites:TListBox;
    FIds:TStringList;
    FConnect,FRegister,FView,FControlButton,FReject,FStop,FSave:TButton;
    procedure Start(Operation:TOperation; const Id:string='');
    procedure Finished(W:TAPIWorker);
    procedure RegisterClick(Sender:TObject);
    procedure ConnectClick(Sender:TObject);
    procedure Tick(Sender:TObject);
    procedure ViewClick(Sender:TObject);
    procedure ControlClick(Sender:TObject);
    procedure RejectClick(Sender:TObject);
    procedure StopClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    procedure FavoriteClick(Sender:TObject);
    procedure DeleteFavorite(Sender:TObject);
    procedure LoadFavorites;
    procedure SaveFavorites;
    function SelectedId:string;
    procedure Closing(Sender:TObject; var CanClose:Boolean);
  public
    constructor Create(AOwner:TComponent); override;
    destructor Destroy; override;
  end;
var MainForm:TMainForm;
implementation
constructor TAPIWorker.Create(AOwner:TMainForm);
begin inherited Create(True); FreeOnTerminate:=False; FOwner:=AOwner; end;
destructor TAPIWorker.Destroy;
begin Data.Free; inherited Destroy; end;
procedure TAPIWorker.Deliver;
begin FOwner.Finished(Self); end;
procedure TAPIWorker.Execute;
var C:TAIRemoteSignalingClient; J,Identity,R:TJSONObject; V:TJSONData; S:string;
begin
  C:=TAIRemoteSignalingClient.Create;
  try
    try
      C.BaseURL:=URL; C.DeviceToken:=Token; C.AllowLocalHTTP:=AllowLocal;
      case Operation of
        opRegister: begin
          if FileExists(IdentityFile) then begin
            V:=GetJSON(AIRemoteLoadSecret(IdentityFile));
            if not(V is TJSONObject) then begin V.Free; raise Exception.Create('Identidade inválida'); end;
            Identity:=TJSONObject(V);
          end else begin
            Identity:=TJSONObject.Create(['registration_id',AIRemoteUUID,
              'registration_secret',AIRemoteRandomHex(32),'api_url',URL]);
            AIRemoteSaveSecret(IdentityFile,Identity.AsJSON);
          end;
          try
            if Identity.Get('api_url','')<>URL then raise Exception.Create('Identidade pertence a outro servidor');
            R:=nil;
            C.DeviceToken:=Identity.Get('device_token','');
            if (C.DeviceToken<>'') and (Identity.Get('public_key','')<>'') then begin
              try
                J:=C.Heartbeat; J.Free;
                R:=TJSONObject.Create(['device_token',C.DeviceToken,
                  'device_id',Identity.Get('device_id',''),'public_key',Identity.Get('public_key','')]);
              except
                on E:EAIRemoteAPI do if E.Status<>401 then raise;
              end;
            end;
            if R=nil then begin
              C.DeviceToken:='';
              R:=C.RegisterDevice(Identity.Get('registration_id',''),Identity.Get('registration_secret',''),
                GetEnvironmentVariable('COMPUTERNAME'),'windows','0.2.0');
            end;
            try
              Identity.Delete('device_token'); Identity.Add('device_token',R.Get('device_token',''));
              Identity.Delete('device_id'); Identity.Add('device_id',R.Get('device_id',''));
              Identity.Delete('public_key'); Identity.Add('public_key',R.Get('public_key',''));
              AIRemoteSaveSecret(IdentityFile,Identity.AsJSON);
              Data:=TJSONObject(R.Clone);
            finally R.Free; end;
          finally Identity.Free; end;
        end;
        opPoll: begin
          J:=C.Heartbeat; J.Free; Data:=C.Incoming;
          if SessionId<>'' then begin J:=C.GetSession(SessionId); Data.Add('current_session',J); end;
        end;
        opConnect: Data:=C.RequestSession(RemoteKey,Control);
        opAcceptView: Data:=C.Decide(SessionId,True,False);
        opAcceptControl: Data:=C.Decide(SessionId,True,True);
        opReject: Data:=C.Decide(SessionId,False,False);
        opClose: Data:=C.CloseSession(SessionId,'local_stop');
      end;
    except
      on E:EAIRemoteAPI do begin S:=E.Code; Failure:=S+': '+E.Message; end;
      on E:Exception do Failure:=E.Message;
    end;
  finally C.Free; end;
  Synchronize(@Deliver);
end;
function AddLabel(Owner:TComponent; Parent:TWinControl; const Text:string; X,Y,W:Integer):TLabel;
begin Result:=TLabel.Create(Owner); Result.Parent:=Parent; Result.SetBounds(X,Y,W,28); Result.Caption:=Text; end;
function AddButton(Owner:TComponent; Parent:TWinControl; const Text:string; X,Y,W:Integer; Handler:TNotifyEvent):TButton;
begin Result:=TButton.Create(Owner); Result.Parent:=Parent; Result.SetBounds(X,Y,W,32); Result.Caption:=Text; Result.OnClick:=Handler; end;
constructor TMainForm.Create(AOwner:TComponent);
var I:Integer; Prefix:string;
begin
  inherited CreateNew(AOwner);
  Caption:='MaurinDesk 0.2.0 — conexão assistida'; SetBounds(160,100,780,650);
  Position:=poScreenCenter; OnCloseQuery:=@Closing;
  FURL:='https://maurinsoft.com.br/maurindesk/api/v1';
  Prefix:='--dev-local-api=';
  for I:=1 to ParamCount do if Copy(ParamStr(I),1,Length(Prefix))=Prefix then begin
    FURL:=Copy(ParamStr(I),Length(Prefix)+1,MaxInt); FAllowLocal:=True;
  end;
  FProfile:=IncludeTrailingPathDelimiter(GetAppConfigDir(False))+MD5Print(MD5String(FURL))+DirectorySeparator;
  ForceDirectories(FProfile); FIdentityFile:=FProfile+'identity.dat';
  FIds:=TStringList.Create;
  AddLabel(Self,Self,'Servidor: '+FURL,20,15,730);
  FKeyLabel:=AddLabel(Self,Self,'Sua chave: registre esta máquina',20,48,500);
  FRegister:=AddButton(Self,Self,'Registrar / recuperar chave',20,80,240,@RegisterClick);
  AddLabel(Self,Self,'Chave remota (10 dígitos)',20,126,240);
  FTarget:=TEdit.Create(Self); FTarget.Parent:=Self; FTarget.SetBounds(20,154,220,30); FTarget.MaxLength:=10;
  FConnect:=AddButton(Self,Self,'Solicitar acesso',255,153,180,@ConnectClick);
  AddLabel(Self,Self,'Pedidos recebidos — autorize apenas quem você conhece',20,205,700);
  FIncoming:=TListBox.Create(Self); FIncoming.Parent:=Self; FIncoming.SetBounds(20,235,720,105);
  FView:=AddButton(Self,Self,'Só visualizar',20,350,155,@ViewClick);
  FControlButton:=AddButton(Self,Self,'Permitir controle',185,350,165,@ControlClick);
  FReject:=AddButton(Self,Self,'Recusar',360,350,120,@RejectClick);
  FStop:=AddButton(Self,Self,'Encerrar sessão',490,350,170,@StopClick);
  AddLabel(Self,Self,'Favoritos: chave + apelido (sem autorização permanente)',20,400,700);
  FName:=TEdit.Create(Self); FName.Parent:=Self; FName.SetBounds(20,430,220,28); FName.TextHint:='Apelido do computador';
  FSave:=AddButton(Self,Self,'Salvar chave',255,429,150,@SaveClick);
  AddButton(Self,Self,'Excluir favorito',420,429,160,@DeleteFavorite);
  FFavorites:=TListBox.Create(Self); FFavorites.Parent:=Self; FFavorites.SetBounds(20,470,720,75);
  FFavorites.OnDblClick:=@FavoriteClick;
  FStatus:=AddLabel(Self,Self,'Inicial: registro e autorização. Tela remota ainda em implementação.',20,565,730);
  FStatus.WordWrap:=True; FStatus.Height:=55;
  LoadFavorites;
  FTimer:=TTimer.Create(Self); FTimer.Interval:=15000; FTimer.OnTimer:=@Tick;
  FTimer.Enabled:=True;
end;
procedure TMainForm.Start(Operation:TOperation; const Id:string);
begin
  if FBusy or FClosing then Exit;
  if (Operation<>opRegister) and (FToken='') then begin FStatus.Caption:='Registre esta máquina primeiro.'; Exit; end;
  if FWorker<>nil then begin FWorker.WaitFor; FreeAndNil(FWorker); end;
  FBusy:=True;
  FWorker:=TAPIWorker.Create(Self); FWorker.Operation:=Operation;
  FWorker.URL:=FURL; FWorker.Token:=FToken; FWorker.IdentityFile:=FIdentityFile;
  FWorker.RemoteKey:=FTarget.Text; FWorker.SessionId:=Id;
  FWorker.AllowLocal:=FAllowLocal; FWorker.Control:=True;
  if Operation=opPoll then FWorker.SessionId:=FSessionId;
  FStatus.Caption:='Comunicando com o servidor...';
  FWorker.Start;
end;
procedure TMainForm.Finished(W:TAPIWorker);
var A:TJSONArray; I:Integer; J:TJSONObject; State:string;
begin
  FBusy:=False; if FClosing then Exit;
  if W.Failure<>'' then begin FStatus.Caption:=W.Failure; Exit; end;
  if W.Data=nil then Exit;
  case W.Operation of
    opRegister: begin
      FToken:=W.Data.Get('device_token','');
      FKeyLabel.Caption:='Sua chave: '+W.Data.Get('public_key','');
      FStatus.Caption:='Máquina registrada. Você já pode solicitar ou autorizar pedidos.';
    end;
    opPoll: begin
      FIncoming.Clear; FIds.Clear;
      A:=W.Data.Arrays['items'];
      for I:=0 to A.Count-1 do begin
        J:=TJSONObject(A[I]); FIds.Add(J.Get('id',''));
        FIncoming.Items.Add(J.Get('requester_key','')+' — '+J.Get('requester_name',''));
      end;
      FStatus.Caption:='Online. '+IntToStr(A.Count)+' pedido(s) pendente(s).';
      J:=TJSONObject(W.Data.Find('current_session'));
      if J<>nil then begin
        State:=J.Get('state',''); FStatus.Caption:='Sessão: '+State+'. Compartilhamento de tela ainda indisponível.';
        if (State='closed') or (State='expired') or (State='rejected') or (State='cancelled') then FSessionId:='';
      end;
    end;
    opConnect,opAcceptView,opAcceptControl: begin
      FSessionId:=W.Data.Get('id','');
      FStatus.Caption:='Sessão: '+W.Data.Get('state','')+'. Apenas autorização; tela e controle ainda indisponíveis.';
    end;
    opReject: FStatus.Caption:='Pedido recusado.';
    opClose: begin FSessionId:=''; FStatus.Caption:='Sessão encerrada.'; end;
  end;
end;
procedure TMainForm.RegisterClick(Sender:TObject);
begin Start(opRegister); end;
procedure TMainForm.ConnectClick(Sender:TObject);
begin
  if not AIRemoteValidKey(FTarget.Text) then begin FStatus.Caption:='Digite exatamente 10 dígitos.'; Exit; end;
  Start(opConnect);
end;
procedure TMainForm.Tick(Sender:TObject);
begin if FToken<>'' then Start(opPoll); end;
function TMainForm.SelectedId:string;
begin Result:=''; if (FIncoming.ItemIndex>=0) and (FIncoming.ItemIndex<FIds.Count) then Result:=FIds[FIncoming.ItemIndex]; end;
procedure TMainForm.ViewClick(Sender:TObject);
var Id:string;
begin
  Id:=SelectedId;
  if (Id<>'') and (MessageDlg('Autorizar somente visualização para o pedido selecionado? A transmissão ainda não está implementada.',
    mtConfirmation,[mbYes,mbNo],0)=mrYes) then Start(opAcceptView,Id);
end;
procedure TMainForm.ControlClick(Sender:TObject);
var Id:string;
begin
  Id:=SelectedId;
  if (Id<>'') and (MessageDlg('Autorizar visualização, mouse e teclado para o pedido selecionado? O controle ainda não está implementado.',
    mtConfirmation,[mbYes,mbNo],0)=mrYes) then Start(opAcceptControl,Id);
end;
procedure TMainForm.RejectClick(Sender:TObject);
var Id:string;
begin Id:=SelectedId; if Id<>'' then Start(opReject,Id); end;
procedure TMainForm.StopClick(Sender:TObject);
begin if FSessionId<>'' then Start(opClose,FSessionId); end;
procedure TMainForm.LoadFavorites;
var Ini:TIniFile; Keys:TStringList; I:Integer;
begin
  Ini:=TIniFile.Create(FProfile+'favorites.ini'); Keys:=TStringList.Create;
  try
    Ini.ReadSection('favorites',Keys);
    for I:=0 to Keys.Count-1 do if AIRemoteValidKey(Keys[I]) then
      FFavorites.Items.Add(Keys[I]+'='+Ini.ReadString('favorites',Keys[I],Keys[I]));
  finally Keys.Free; Ini.Free; end;
end;
procedure TMainForm.SaveFavorites;
var Ini:TIniFile; I,P:Integer; S:string;
begin
  Ini:=TIniFile.Create(FProfile+'favorites.ini');
  try
    Ini.EraseSection('favorites');
    for I:=0 to FFavorites.Items.Count-1 do begin
      S:=FFavorites.Items[I]; P:=Pos('=',S);
      if P>0 then Ini.WriteString('favorites',Copy(S,1,P-1),Copy(S,P+1,MaxInt));
    end;
    Ini.UpdateFile;
  finally Ini.Free; end;
end;
procedure TMainForm.SaveClick(Sender:TObject);
var I:Integer; Key,AliasName:string;
begin
  Key:=FTarget.Text; AliasName:=Trim(FName.Text);
  if not AIRemoteValidKey(Key) then begin FStatus.Caption:='Informe uma chave de 10 dígitos.'; Exit; end;
  if (Length(AliasName)>80) or (Pos(#13,AliasName)>0) or (Pos(#10,AliasName)>0) then Exit;
  if AliasName='' then AliasName:=Key;
  for I:=FFavorites.Items.Count-1 downto 0 do if Copy(FFavorites.Items[I],1,11)=Key+'=' then FFavorites.Items.Delete(I);
  FFavorites.Items.Add(Key+'='+AliasName); SaveFavorites;
end;
procedure TMainForm.FavoriteClick(Sender:TObject);
begin
  if FFavorites.ItemIndex>=0 then FTarget.Text:=Copy(FFavorites.Items[FFavorites.ItemIndex],1,10);
end;
procedure TMainForm.DeleteFavorite(Sender:TObject);
begin if FFavorites.ItemIndex>=0 then begin FFavorites.Items.Delete(FFavorites.ItemIndex); SaveFavorites; end; end;
procedure TMainForm.Closing(Sender:TObject; var CanClose:Boolean);
begin
  CanClose:=not FBusy;
  if FBusy then FStatus.Caption:='Aguarde a operação atual para fechar.';
  if CanClose and (FSessionId<>'') then begin Start(opClose,FSessionId); CanClose:=False; end;
end;
destructor TMainForm.Destroy;
begin
  FClosing:=True; FTimer.Enabled:=False;
  if FWorker<>nil then begin FWorker.WaitFor; FWorker.Free; end;
  FIds.Free; inherited Destroy;
end;
end.
