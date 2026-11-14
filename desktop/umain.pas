unit umain;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, DateUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, LMessages,
  Graphics, Menus, Clipbrd, IniFiles, md5, LCLIntf,
  fpjson, jsonparser, airemoteidentity, airemotesignaling,
  uDeskProtocol, uScreenCapture, uDeskStream, uRemoteViewer, uDeskRelay, uDeskI18n, uDeskFirewall,
  uDeskHTTP, uDeskClipboard, uDeskUI, setmain, uDeskSettings, uDeskUpdate;

type
  TMainForm = class;
  TOperation = (opRegister, opPoll, opConnect, opAcceptView, opAcceptControl, opReject, opClose, opHealth, opSendLog);

  { TAPIWorker }
  TAPIWorker = class(TThread)
  private
    FOwner: TMainForm;
    procedure Deliver;
  protected
    procedure Execute; override;
  public
    Operation: TOperation;
    URL, Token, IdentityFile, RemoteKey, SessionId, Failure: string;
    LogCategory, LogMessage, LogContent: string;
    StreamPort: Integer;
    CloseReason: string;
    AllowLocal, Control: Boolean;
    Data: TJSONObject;
    constructor Create(AOwner: TMainForm);
    destructor Destroy; override;
  end;

  { TMainForm }
  TMainForm = class(TForm)
  private
    FURL, FToken, FSessionId, FProfile, FIdentityFile, FConfigFile: string;
    FRawPublicKey: string;
    FStreamPort: Integer;
    FBusy, FClosing, FAllowLocal: Boolean;
    FWorker: TAPIWorker;
    FTimer: TTimer;
    FStreamServer: TDeskStreamServer;
    FStreamClient: TDeskStreamClient;
    FRelayClient: TDeskRelayClient;
    FRelayHost: TDeskRelayHost;
    FClipboardThread: TDeskClipboardThread;
    FRemoteViewer: TfRemoteViewer;
    FIsController: Boolean;
    FSessionCanControl: Boolean;
    FHasPendingOp: Boolean;
    FPendingOp: TOperation;
    FPendingId: string;
    FHeading, FIntro: TLabel;
    FLocalDeskCard: TPanel;
    FNavConnect, FNavFavorites, FNavHistory: TDeskButton;
    FNavigation, FGridColumns: Integer;
    FLogExpanded: Boolean;
    FRecordedSession: string;
    FTrayIcon: TTrayIcon;
    FTrayMenu: TPopupMenu;
    FExitRequested: Boolean;
    FSetMain: TSetMain;
    FUpdater: TDeskUpdateThread;
    FUpdateTimer: TTimer;
    FPendingUpdate, FPendingUpdateHash: string;
    FSessionTargetKey: string;
    FSessionWasAccepted: Boolean;
    FStoppingSession: Boolean;
    FStoppingStreams: Boolean;
    FNamePromptKey: string;
    FLastIncomingId: string;
    FTrayAvailable: Boolean;
    FRequestedCloseReason: string;
    FTransferMenu: TPopupMenu;
    FBtnTransfer: TDeskButton;
    procedure BuildModernLayout;
    procedure LayoutModern(Sender: TObject);
    procedure NavigationClick(Sender: TObject);
    procedure ToggleLog(Sender: TObject);
    procedure TargetKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RememberRemote;
    procedure NameRemote;
    procedure PromptRemoteName(Data: PtrInt);
    procedure ProcessPendingOperation(Data: PtrInt);
    procedure InitializeTrayIcon;
    procedure FileTransferMenuClick(Sender: TObject);
    procedure ChooseFiles(Sender: TObject);
    procedure ChooseFolder(Sender: TObject);
    procedure QueueSelectedFiles(Sender: TObject; Paths: TStrings);
    procedure OpenReceivedFiles(Sender: TObject);
    procedure RestoreFromTray(Sender: TObject);
    procedure ExitFromTray(Sender: TObject);
    procedure WindowStateChanged(Sender: TObject);
    procedure CheckUpdates(Sender: TObject);
    procedure UpdateReady(Sender: TObject);

  private
    // Header Controls
    FTopBar: TPanel;
    FLogoBox: TPaintBox;
    FTabPanel: TPanel;
    FTabLabel: TLabel;
    FTopSearchPanel: TPanel;
    FTopSearchEdit: TEdit;
    FTopConnectBtn: TPanel;
    FBtnLang: TDeskButton;
    FBtnSettings: TDeskButton;

    // Sidebar Controls
    FSidebar: TPanel;
    FDeskTitle: TLabel;
    FDeskSubtitle: TLabel;
    FKeyBox: TPanel;
    FKeyIconBox: TPaintBox;
    FKeyTextLabel: TLabel;
    FBtnRegister: TDeskButton;
    FSidebarStatus: TLabel;
    FBannerPanel: TPanel;
    FBannerTitleLabel: TLabel;
    FBannerBuildLabel: TLabel;
    FBannerTagLabel: TLabel;
    FBannerWebLabel: TLabel;

    // Main Content Controls
    FContentArea: TPanel;
    FTopCardsPanel: TPanel;
    FRemoteDeskCard: TPanel;
    FRemoteAccentBar: TPanel;
    FRemoteTitle: TLabel;
    FRemoteSubtitle: TLabel;
    FTarget: TEdit;
    FBtnConnect: TDeskButton;
    FBtnSaveFav: TDeskButton;

    FDiscoveryCard: TPanel;
    FDiscTitle: TLabel;
    FDiscSubtitle: TLabel;
    FDiscServerLabel: TLabel;

    FRecentHeaderPanel: TPanel;
    FRecentTitle: TLabel;
    FRecentHint: TLabel;
    FCardsScrollBox: TScrollBox;

    // Connection Consent & Session Panels
    FIncomingPanel: TPanel;
    FIncomingText: TLabel;
    FBtnAcceptControl: TDeskButton;
    FBtnAcceptView: TDeskButton;
    FBtnReject: TDeskButton;
    FIncomingIds: TStringList;

    FActiveSessionPanel: TPanel;
    FActiveSessionText: TLabel;
    FBtnStop: TDeskButton;

    // Log Console Panel (Bottom)
    FLogPanel: TPanel;
    FLogHeader: TPanel;
    FLogTitleLabel: TLabel;
    FBtnTestConn: TDeskButton;
    FBtnSendLog: TDeskButton;
    FBtnCopyLog: TDeskButton;
    FBtnClearLog: TDeskButton;
    FLogMemo: TMemo;

    // Status Bar
    FStatusBar: TPanel;
    FStatusDot: TLabel;
    FServerStatusLabel: TLabel;
    FStatusMsgLabel: TLabel;

    FCardPopupMenu: TPopupMenu;
    FPopupTargetKey: string;

    procedure Start(Operation: TOperation; const Id: string = '');
    procedure Finished(W: TAPIWorker);
    procedure RegisterClick(Sender: TObject);
    procedure ConnectClick(Sender: TObject);
    procedure TopConnectClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure AcceptControlClick(Sender: TObject);
    procedure AcceptViewClick(Sender: TObject);
    procedure RejectClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure SaveFavClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure BtnLangClick(Sender: TObject);
    procedure SendLogClick(Sender: TObject);
    procedure SendFailureLogToServer(const Category, Message: string);
    procedure ApplyLanguage;
    procedure KeyBoxClick(Sender: TObject);
    procedure TestConnClick(Sender: TObject);
    procedure ClearLogClick(Sender: TObject);
    procedure CopyLogClick(Sender: TObject);
    procedure DrawLogo(Sender: TObject);
    procedure DrawKeyIcon(Sender: TObject);
    procedure DrawCardThumbnail(Sender: TObject);
    procedure CardClick(Sender: TObject);
    procedure CardDblClick(Sender: TObject);
    procedure PopupConnectClick(Sender: TObject);
    procedure PopupDeleteClick(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure ViewerClosed(Sender: TObject);
    procedure StopStreaming;
    procedure StartRelayStreaming;
    procedure StartClipboard(Session: TJSONObject);
    procedure HandleStreamLog(Sender: TObject; const Msg: string);
    procedure HandleFallbackToRelay(Sender: TObject);
    procedure HandlePortSuccess(Sender: TObject; APort: Integer);

    procedure LogMsg(const Msg: string);
    procedure LoadConfig;
    procedure SaveConfig;
    procedure LoadFavorites;
    procedure RebuildFavoriteCards;
    procedure UpdateServerLabels;
    function FormatDeskKey(const Key: string): string;
  protected
    procedure WndProc(var TheMessage: TLMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property TrayAvailable: Boolean read FTrayAvailable;
  end;

var
  MainForm: TMainForm;

implementation

function DeskOption(const Value: string): Boolean;
var I: Integer;
begin Result := False; for I:=1 to ParamCount do if ParamStr(I)=Value then Exit(True); end;

function FormatDeskKeyHelper(const Key: string): string;
begin
  if Length(Key) = 10 then
    Result := Copy(Key, 1, 3) + ' ' + Copy(Key, 4, 3) + ' ' + Copy(Key, 7, 4)
  else
    Result := Key;
end;

{ TAPIWorker }

constructor TAPIWorker.Create(AOwner: TMainForm);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

destructor TAPIWorker.Destroy;
begin
  Data.Free;
  inherited Destroy;
end;

procedure TAPIWorker.Deliver;
begin
  FOwner.Finished(Self);
end;

procedure TAPIWorker.Execute;
var
  C: TAIRemoteSignalingClient;
  J, Identity, R: TJSONObject;
  V: TJSONData;
  S: string;
begin
  C := TAIRemoteSignalingClient.Create;
  try
    try
      C.BaseURL := URL;
      C.DeviceToken := Token;
      C.AllowLocalHTTP := AllowLocal;
      case Operation of
        opRegister: begin
          if FileExists(IdentityFile) then begin
            V := GetJSON(AIRemoteLoadSecret(IdentityFile));
            if not (V is TJSONObject) then begin
              V.Free;
              raise Exception.Create('Identidade local inválida.');
            end;
            Identity := TJSONObject(V);
          end else begin
            Identity := TJSONObject.Create([
              'registration_id', AIRemoteUUID,
              'registration_secret', AIRemoteRandomHex(32),
              'api_url', URL
            ]);
            AIRemoteSaveSecret(IdentityFile, Identity.AsJSON);
          end;
          try
            if Identity.Get('api_url', '') <> URL then
              raise Exception.Create('Identidade local pertence a outro servidor.');
            R := nil;
            C.DeviceToken := Identity.Get('device_token', '');
            if (C.DeviceToken <> '') and (Identity.Get('public_key', '') <> '') then begin
              try
                J := DeskHeartbeat(URL,C.DeviceToken,DESK_VERSION,AllowLocal);
                J.Free;
                R := TJSONObject.Create([
                  'device_token', C.DeviceToken,
                  'device_id', Identity.Get('device_id', ''),
                  'public_key', Identity.Get('public_key', '')
                ]);
              except
                on E: EAIRemoteAPI do if E.Status <> 401 then raise;
              end;
            end;
            if R = nil then begin
              C.DeviceToken := '';
              R := C.RegisterDevice(
                Identity.Get('registration_id', ''),
                Identity.Get('registration_secret', ''),
                GetEnvironmentVariable('COMPUTERNAME'),
                'windows',
                '0.6.6'
              );
            end;
            try
              Identity.Delete('device_token');
              Identity.Add('device_token', R.Get('device_token', ''));
              Identity.Delete('device_id');
              Identity.Add('device_id', R.Get('device_id', ''));
              Identity.Delete('public_key');
              Identity.Add('public_key', R.Get('public_key', ''));
              AIRemoteSaveSecret(IdentityFile, Identity.AsJSON);
              Data := TJSONObject(R.Clone);
              try
                J := C.AnnounceEndpoint(StreamPort, 'tcp', GetLocalIPAddress);
                J.Free;
              except
              end;
            finally
              R.Free;
            end;
          finally
            Identity.Free;
          end;
        end;

        opPoll: begin
          J := DeskHeartbeat(URL,C.DeviceToken,DESK_VERSION,AllowLocal);
          J.Free;
          try
            J := C.AnnounceEndpoint(StreamPort, 'tcp', GetLocalIPAddress);
            J.Free;
          except
          end;
          Data := C.Incoming;
          if SessionId <> '' then begin
            J := C.GetSession(SessionId);
            Data.Add('current_session', J);
            if J.Get('state', '') = 'accepted' then begin
              try
                R := C.GetPeerEndpoint(SessionId);
                Data.Add('peer_endpoint', R);
              except
                on E: Exception do
                  Data.Add('peer_endpoint_error', E.Message);
              end;
            end;
          end;
        end;

        opConnect: Data := DeskRequestSession(URL, Token, RemoteKey, AllowLocal, Control);
        opAcceptView: begin
          Data := C.Decide(SessionId, True, False);
          try
            J := C.AnnounceEndpoint(StreamPort, 'tcp', GetLocalIPAddress);
            J.Free;
          except
          end;
        end;
        opAcceptControl: begin
          J := C.GetSession(SessionId);
          try Data := DeskAcceptControl(URL, Token, SessionId, AllowLocal, J.Arrays['requested_permissions']);
          finally J.Free; end;
          try
            J := C.AnnounceEndpoint(StreamPort, 'tcp', GetLocalIPAddress);
            J.Free;
          except
          end;
        end;
        opReject: Data := C.Decide(SessionId, False, False);
        opClose: Data := C.CloseSession(SessionId, CloseReason);
        opHealth: Data := C.Health;
        opSendLog: Data := C.SendDiagnosticLog(LogCategory, LogMessage, LogContent, SessionId);
      end;
    except
      on E: EAIRemoteAPI do begin
        S := E.Code;
        Failure := S + ': ' + E.Message;
      end;
      on E: Exception do Failure := E.Message;
    end;
  finally
    C.Free;
  end;
  Synchronize(@Deliver);
end;

{ TMainForm }

procedure TMainForm.BuildModernLayout;
  function Panel(Parent: TWinControl; Card: Boolean = False): TPanel;
  begin
    if Card then Result := TDeskCard.Create(Self) else Result := TPanel.Create(Self);
    Result.Parent := Parent; Result.BevelOuter := bvNone;
    Result.Color := clWhite; Result.ParentFont := True;
  end;
  function LabelAt(Parent: TWinControl; const Text: string; X,Y,W,H,Size: Integer; Bold: Boolean = False): TLabel;
  begin
    Result := TLabel.Create(Self); Result.Parent := Parent; Result.AutoSize := False;
    Result.SetBounds(X,Y,W,H); Result.Caption := Text; Result.Font.Name := 'Segoe UI'; Result.Font.Size := Size;
    Result.Font.Color := RGBToColor(37,44,57); Result.Transparent := True;
    if Bold then Result.Font.Style := [fsBold];
  end;
  function ButtonAt(Parent: TWinControl; const Text: string; Handler: TNotifyEvent): TDeskButton;
  begin Result := TDeskButton.Create(Self); Result.Parent := Parent; Result.Caption := Text; Result.OnClick := Handler; end;
var Item: TMenuItem;
begin
  DoubleBuffered := True;
  FTopBar := Panel(Self); FTopBar.Align := alTop; FTopBar.Height := 64;
  FLogoBox := TPaintBox.Create(Self); FLogoBox.Parent := FTopBar; FLogoBox.SetBounds(20,14,36,36); FLogoBox.OnPaint := @DrawLogo;
  FTabLabel := LabelAt(FTopBar,'MaurinDesk',66,16,220,36,18,True);
  FServerStatusLabel := LabelAt(FTopBar,'Aguardando conexão ao servidor',600,23,280,24,10);
  FServerStatusLabel.Font.Color := RGBToColor(107,117,133);
  FBtnLang := ButtonAt(FTopBar,'PT',@BtnLangClick);
  FBtnSettings := ButtonAt(FTopBar,'Configurações',@SettingsClick);
  FTopSearchEdit := TEdit.Create(Self); FTopSearchEdit.Parent := FTopBar; FTopSearchEdit.Visible := False;
  FStatusBar := Panel(Self); FStatusBar.Align := alBottom; FStatusBar.Height := 30;
  FStatusDot := LabelAt(FStatusBar,'●',16,8,16,16,9); FStatusDot.Font.Color := RGBToColor(34,170,85);
  FStatusMsgLabel := LabelAt(FStatusBar,'Pronto para conectar.',36,8,950,18,9);
  FSidebar := Panel(Self); FSidebar.Align := alLeft; FSidebar.Width := 196;
  FNavConnect := ButtonAt(FSidebar,'Conexões',@NavigationClick); FNavConnect.Tag := 0;
  FNavFavorites := ButtonAt(FSidebar,'Favoritos',@NavigationClick); FNavFavorites.Tag := 1;
  FNavHistory := ButtonAt(FSidebar,'Histórico',@NavigationClick); FNavHistory.Tag := 2;
  FNavConnect.SetBounds(16,28,164,46); FNavFavorites.SetBounds(16,84,164,46); FNavHistory.SetBounds(16,140,164,46);
  FNavConnect.Selected := True;
  FBannerPanel := Panel(FSidebar); FBannerPanel.Align := alBottom; FBannerPanel.Height := 100;
  FBannerTitleLabel := LabelAt(FBannerPanel,'MaurinDesk',20,12,160,22,11,True);
  FBannerBuildLabel := LabelAt(FBannerPanel,'v0.6.6',20,36,160,20,9);
  FBannerWebLabel := LabelAt(FBannerPanel,'maurinsoft.com.br',20,61,160,20,9);
  FBannerWebLabel.Font.Color := RGBToColor(126,135,151);
  FContentArea := Panel(Self); FContentArea.Align := alClient; FContentArea.Color := RGBToColor(248,249,252);
  FHeading := LabelAt(FContentArea,'Conecte-se com facilidade',28,22,850,42,23,True);
  FIntro := LabelAt(FContentArea,'Acesse outro computador ou compartilhe o seu com segurança.',28,68,850,24,10);
  FIntro.Font.Color := RGBToColor(107,117,133);
  FTopCardsPanel := Panel(FContentArea); FTopCardsPanel.Color := FContentArea.Color;
  FLocalDeskCard := Panel(FTopCardsPanel,True);
  FDeskTitle := LabelAt(FLocalDeskCard,'Este computador',20,18,300,30,15,True);
  FSidebarStatus := LabelAt(FLocalDeskCard,'● Preparando conexão...',20,54,320,22,10);
  FSidebarStatus.Font.Color := RGBToColor(29,157,83);
  FKeyBox := Panel(FLocalDeskCard); FKeyBox.Color := RGBToColor(255,243,244); FKeyBox.Cursor := crHandPoint; FKeyBox.OnClick := @KeyBoxClick;
  FKeyTextLabel := LabelAt(FKeyBox,'--- --- ----',16,12,320,42,23,True); FKeyTextLabel.OnClick := @KeyBoxClick; FKeyTextLabel.Cursor := crHandPoint;
  FDeskSubtitle := LabelAt(FLocalDeskCard,'Compartilhe esta chave com quem vai acessar seu computador.',20,151,320,40,9);
  FDeskSubtitle.WordWrap := True; FDeskSubtitle.Font.Color := RGBToColor(107,117,133);
  FBtnRegister := ButtonAt(FLocalDeskCard,'Copiar chave',@KeyBoxClick);
  FRemoteDeskCard := Panel(FTopCardsPanel,True);
  FRemoteTitle := LabelAt(FRemoteDeskCard,'Acessar outro computador',24,18,500,30,15,True);
  FRemoteSubtitle := LabelAt(FRemoteDeskCard,'Chave do computador remoto',24,65,500,24,10);
  FTarget := TEdit.Create(Self); FTarget.Parent := FRemoteDeskCard; FTarget.Font.Size := 18;
  FTarget.TextHint := '000 000 0000'; FTarget.MaxLength := 64; FTarget.OnKeyDown := @TargetKeyDown;
  FBtnConnect := ButtonAt(FRemoteDeskCard,'Conectar  →',@ConnectClick); FBtnConnect.Primary := True;
  FBtnSaveFav := ButtonAt(FRemoteDeskCard,'☆  Salvar nos favoritos',@SaveFavClick);
  FRecentHeaderPanel := Panel(FContentArea); FRecentHeaderPanel.Color := FContentArea.Color;
  FRecentTitle := LabelAt(FRecentHeaderPanel,'Conexões recentes',0,9,360,30,15,True);
  FRecentHint := LabelAt(FRecentHeaderPanel,'Duplo clique para conectar',440,14,300,22,9);
  FRecentHint.Font.Color := RGBToColor(130,140,155);
  FCardsScrollBox := TScrollBox.Create(Self); FCardsScrollBox.Parent := FContentArea;
  FCardsScrollBox.BorderStyle := bsNone; FCardsScrollBox.Color := FContentArea.Color;
  FCardsScrollBox.HorzScrollBar.Visible := False;
  FDiscoveryCard := Panel(FContentArea,True);
  FDiscTitle := LabelAt(FDiscoveryCard,'Área de transferência',20,12,500,24,11,True);
  FDiscSubtitle := LabelAt(FDiscoveryCard,'Texto e arquivos durante a sessão autorizada.',20,36,800,22,9);
  FDiscSubtitle.Font.Color := RGBToColor(107,117,133);
  FTransferMenu:=TPopupMenu.Create(Self);
  Item:=TMenuItem.Create(FTransferMenu); Item.Caption:='Enviar arquivos...'; Item.OnClick:=@ChooseFiles; FTransferMenu.Items.Add(Item);
  Item:=TMenuItem.Create(FTransferMenu); Item.Caption:='Enviar pasta...'; Item.OnClick:=@ChooseFolder; FTransferMenu.Items.Add(Item);
  Item:=TMenuItem.Create(FTransferMenu); Item.Caption:='Abrir arquivos recebidos'; Item.OnClick:=@OpenReceivedFiles; FTransferMenu.Items.Add(Item);
  FBtnTransfer:=ButtonAt(FDiscoveryCard,'Arquivos e pastas',@FileTransferMenuClick);
  FDiscServerLabel := LabelAt(FDiscoveryCard,'',0,0,0,0,8); FDiscServerLabel.Visible := False;
  FLogPanel := Panel(FContentArea,True);
  FLogHeader := Panel(FLogPanel); FLogHeader.Color := clWhite; FLogHeader.Cursor := crHandPoint; FLogHeader.OnClick := @ToggleLog;
  FLogTitleLabel := LabelAt(FLogHeader,'⌄  Diagnóstico da conexão',16,12,500,24,10,True);
  FLogTitleLabel.OnClick := @ToggleLog; FLogTitleLabel.Cursor := crHandPoint;
  FBtnTestConn := ButtonAt(FLogPanel,'Testar conexão',@TestConnClick);
  FBtnSendLog := ButtonAt(FLogPanel,'Enviar diagnóstico',@SendLogClick);
  FBtnCopyLog := ButtonAt(FLogPanel,'Copiar',@CopyLogClick);
  FBtnClearLog := ButtonAt(FLogPanel,'Limpar',@ClearLogClick);
  FLogMemo := TMemo.Create(Self); FLogMemo.Parent := FLogPanel; FLogMemo.ReadOnly := True;
  FLogMemo.ScrollBars := ssAutoBoth; FLogMemo.WordWrap := False; FLogMemo.BorderStyle := bsNone;
  FLogMemo.Font.Name := 'Consolas'; FLogMemo.Font.Size := 9; FLogMemo.Color := RGBToColor(247,249,252);
  FLogMemo.Font.Color := RGBToColor(65,76,94);
  FActiveSessionPanel := Panel(FContentArea,True); FActiveSessionPanel.Color := RGBToColor(238,252,244); FActiveSessionPanel.Visible := False;
  FActiveSessionText := LabelAt(FActiveSessionPanel,'Sessão ativa',16,16,700,24,10,True);
  FBtnStop := ButtonAt(FActiveSessionPanel,'Encerrar sessão',@StopClick);
  FIncomingPanel := Panel(FContentArea,True); FIncomingPanel.Color := RGBToColor(255,248,231); FIncomingPanel.Visible := False;
  FIncomingText := LabelAt(FIncomingPanel,'Solicitação de conexão',16,10,780,42,9,True); FIncomingText.WordWrap := True;
  FBtnAcceptControl := ButtonAt(FIncomingPanel,'Controle + área de transferência',@AcceptControlClick);
  FBtnAcceptControl.Primary := True; FBtnAcceptControl.Font.Size := 9;
  FBtnAcceptView := ButtonAt(FIncomingPanel,'Só visualizar',@AcceptViewClick);
  FBtnReject := ButtonAt(FIncomingPanel,'Recusar',@RejectClick);
  FTrayMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(FTrayMenu); Item.Caption := 'Abrir MaurinDesk'; Item.OnClick := @RestoreFromTray; FTrayMenu.Items.Add(Item);
  Item := TMenuItem.Create(FTrayMenu); Item.Caption := 'Configurações'; Item.OnClick := @SettingsClick; FTrayMenu.Items.Add(Item);
  Item := TMenuItem.Create(FTrayMenu); Item.Caption := 'Sair do MaurinDesk'; Item.OnClick := @ExitFromTray; FTrayMenu.Items.Add(Item);
  FTrayIcon := TTrayIcon.Create(Self); FTrayIcon.Hint := 'MaurinDesk — clique para abrir';
  FTrayIcon.PopupMenu := FTrayMenu;
  FTrayIcon.OnClick:=@RestoreFromTray; FTrayIcon.OnDblClick := @RestoreFromTray;
  InitializeTrayIcon;
  OnResize := @LayoutModern; OnWindowStateChange := @WindowStateChanged;
  LayoutModern(Self);
end;

procedure TMainForm.LayoutModern(Sender: TObject);
var W, RowW, LocalW, BottomY, LogHeight, Columns, RecentTop: Integer;
begin
  if FContentArea = nil then Exit;
  W := FContentArea.ClientWidth; RowW := W - 56; LocalW := RowW * 42 div 100;
  FServerStatusLabel.SetBounds(ClientWidth-540,23,280,24);
  FBtnLang.SetBounds(ClientWidth-246,14,56,36); FBtnSettings.SetBounds(ClientWidth-178,14,154,36);
  FStatusMsgLabel.Width := ClientWidth-60;
  FHeading.Width := RowW; FIntro.Width := RowW;
  FTopCardsPanel.SetBounds(28,105,RowW,252);
  FLocalDeskCard.SetBounds(0,0,LocalW-8,252);
  FRemoteDeskCard.SetBounds(LocalW+8,0,RowW-LocalW-8,252);
  FDeskTitle.Width := FLocalDeskCard.Width-40; FSidebarStatus.Width := FLocalDeskCard.Width-40;
  FKeyBox.SetBounds(20,83,FLocalDeskCard.Width-40,60); FKeyTextLabel.Width := FKeyBox.Width-32;
  if LocalW < 350 then FKeyTextLabel.Font.Size := 20 else FKeyTextLabel.Font.Size := 23;
  FDeskSubtitle.Width := FLocalDeskCard.Width-40; FBtnRegister.SetBounds(20,202,FLocalDeskCard.Width-40,34);
  FRemoteTitle.Width := FRemoteDeskCard.Width-48; FRemoteSubtitle.Width := FRemoteDeskCard.Width-48;
  FTarget.SetBounds(24,94,FRemoteDeskCard.Width-48,42);
  FBtnConnect.SetBounds(24,151,FRemoteDeskCard.Width-48,44); FBtnSaveFav.SetBounds(24,205,FRemoteDeskCard.Width-48,32);
  RecentTop:=373; if FNavigation<>0 then RecentTop:=105;
  FRecentHeaderPanel.SetBounds(28,RecentTop,RowW,44); FRecentTitle.Width := RowW div 2;
  FRecentHint.SetBounds(RowW-230,16,230,22);
  if FLogExpanded then LogHeight := 228 else LogHeight := 44;
  BottomY := FContentArea.ClientHeight-18;
  FLogPanel.SetBounds(28,BottomY-LogHeight,RowW,LogHeight); FLogHeader.SetBounds(8,2,RowW-16,40);
  FLogTitleLabel.Width := RowW-48;
  FBtnTestConn.Visible := FLogExpanded; FBtnSendLog.Visible := FLogExpanded;
  FBtnCopyLog.Visible := FLogExpanded; FBtnClearLog.Visible := FLogExpanded; FLogMemo.Visible := FLogExpanded;
  FBtnTestConn.SetBounds(12,45,140,32); FBtnSendLog.SetBounds(162,45,170,32);
  FBtnCopyLog.SetBounds(342,45,88,32); FBtnClearLog.SetBounds(440,45,88,32);
  FLogMemo.SetBounds(12,86,RowW-24,LogHeight-98);
  BottomY := BottomY-LogHeight-12;
  FDiscoveryCard.SetBounds(28,BottomY-70,RowW,70); FDiscSubtitle.Width := RowW-226;
  FBtnTransfer.SetBounds(RowW-194,17,176,36);
  BottomY := BottomY-82;
  if FActiveSessionPanel.Visible then begin
    FActiveSessionPanel.SetBounds(28,BottomY-52,RowW,52); FActiveSessionText.Width := RowW-206;
    FBtnStop.SetBounds(RowW-184,9,168,34); BottomY := BottomY-64;
  end;
  if FIncomingPanel.Visible then begin
    FIncomingPanel.SetBounds(28,BottomY-104,RowW,104); FIncomingText.Width := RowW-32;
    FBtnAcceptControl.SetBounds(16,60,270,32); FBtnAcceptView.SetBounds(298,60,140,32); FBtnReject.SetBounds(450,60,106,32);
    BottomY := BottomY-116;
  end;
  FTopCardsPanel.Visible := (BottomY >= 373) and (FNavigation=0);
  FIntro.Visible := BottomY >= 105;
  FHeading.Visible := BottomY >= 85;
  // Keep the connection cards usable when diagnostics or consent occupy the lower area.
  if BottomY < RecentTop+110 then begin
    FRecentHeaderPanel.Visible := False; FCardsScrollBox.Visible := False;
  end else begin
    FRecentHeaderPanel.Visible := True; FCardsScrollBox.Visible := True;
    FCardsScrollBox.SetBounds(28,RecentTop+50,RowW,BottomY-RecentTop-50);
  end;
  Columns := RowW div 280; if Columns < 1 then Columns := 1; if Columns > 3 then Columns := 3;
  if (FGridColumns <> Columns) and (FCardsScrollBox <> nil) then begin FGridColumns := Columns; RebuildFavoriteCards; end;
end;

procedure TMainForm.ToggleLog(Sender: TObject);
begin FLogExpanded := not FLogExpanded; LayoutModern(Self); end;
procedure TMainForm.TargetKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if Key = 13 then begin Key := 0; ConnectClick(Sender); end; end;
procedure TMainForm.NavigationClick(Sender: TObject);
begin
  FNavigation := TControl(Sender).Tag;
  FNavConnect.Selected := FNavigation=0; FNavFavorites.Selected := FNavigation=1; FNavHistory.Selected := FNavigation=2;
  case FNavigation of 1: FRecentTitle.Caption := 'Favoritos'; 2: FRecentTitle.Caption := 'Histórico'; else FRecentTitle.Caption := 'Conexões recentes'; end;
  RebuildFavoriteCards;
  LayoutModern(Self);
end;
procedure TMainForm.RestoreFromTray(Sender: TObject);
begin WindowState := wsNormal; Show; BringToFront; Application.BringToFront; end;
procedure TMainForm.ExitFromTray(Sender: TObject);
begin FExitRequested := True; Close; end;
procedure TMainForm.WindowStateChanged(Sender: TObject);
begin if (WindowState = wsMinimized) and FTrayAvailable then Hide; end;

procedure TMainForm.InitializeTrayIcon;
begin
  if FTrayAvailable then Exit;
  try
    FTrayIcon.Hide;
    FTrayIcon.Icon.LoadFromResourceName(HInstance,'MAINICON');
    if FTrayIcon.Icon.Empty then raise Exception.Create('Icone nao carregado');
    Application.Icon.Assign(FTrayIcon.Icon); Icon.Assign(FTrayIcon.Icon);
    FTrayAvailable:=FTrayIcon.Show;
    if FTrayAvailable then LogMsg('[BANDEJA] Icone MaurinDesk adicionado a area do relogio.')
    else begin FTrayIcon.Hide; LogMsg('[BANDEJA AVISO] O Windows nao confirmou o icone. A janela permanecera acessivel.'); end;
  except on E: Exception do begin FTrayAvailable:=False; LogMsg('[BANDEJA ERRO] '+E.Message); end; end;
end;
procedure TMainForm.FileTransferMenuClick(Sender: TObject);
var P: TPoint;
begin P:=FBtnTransfer.ClientToScreen(Point(0,FBtnTransfer.Height)); FTransferMenu.Popup(P.X,P.Y); end;
procedure TMainForm.QueueSelectedFiles(Sender: TObject; Paths: TStrings);
begin
  if (FClipboardThread=nil) or FClipboardThread.Finished or FStoppingSession then begin
    ShowMessage('Conecte-se com permissao de area de transferencia antes de enviar arquivos.'); Exit;
  end;
  FClipboardThread.QueueFiles(Paths);
  HandleStreamLog(Self,'[CLIPBOARD] Arquivos ou pasta selecionados. Preparando envio...');
end;
procedure TMainForm.ChooseFiles(Sender: TObject);
var Dialog: TOpenDialog;
begin
  Dialog:=TOpenDialog.Create(Self);
  try Dialog.Title:='Enviar arquivos para o outro computador'; Dialog.Options:=[ofAllowMultiSelect,ofFileMustExist,ofEnableSizing];
    if Dialog.Execute then QueueSelectedFiles(Self,Dialog.Files);
  finally Dialog.Free; end;
end;
procedure TMainForm.ChooseFolder(Sender: TObject);
var Folder: string; Paths: TStringList;
begin
  Paths:=TStringList.Create; Folder:='';
  try if SelectDirectory('Enviar pasta para o outro computador','',Folder) then begin Paths.Add(Folder); QueueSelectedFiles(Self,Paths); end;
  finally Paths.Free; end;
end;
procedure TMainForm.OpenReceivedFiles(Sender: TObject);
var Folder: string;
begin
  Folder:=''; if FClipboardThread<>nil then Folder:=FClipboardThread.ReceivedDirectory;
  if (Folder='') or not DirectoryExists(Folder) then ShowMessage('Nenhum arquivo recebido nesta sessao ainda.')
  else OpenDocument(Folder);
end;

procedure TMainForm.WndProc(var TheMessage: TLMessage);
begin
  if TheMessage.Msg=$0011 then FExitRequested:=True; // WM_QUERYENDSESSION: never block Windows shutdown.
  inherited WndProc(TheMessage);
end;

procedure TMainForm.CheckUpdates(Sender: TObject);
begin
  if FClosing then Exit;
  if FPendingUpdate<>'' then begin
    if (FSessionId='') and not FBusy and (Application.ModalLevel=0) then begin
      try
        LaunchVerifiedUpdate(FPendingUpdate,Application.ExeName,FPendingUpdateHash);
        FExitRequested:=True; Close;
      except on E: Exception do begin
        LogMsg('[ATUALIZAÇÃO ERRO] '+E.Message); FPendingUpdate:=''; FUpdateTimer.Interval:=86400000;
      end; end;
    end;
    Exit;
  end;
  if not FSetMain.AutoUpdate then Exit;
  if FUpdater<>nil then begin
    if FUpdater.Finished then begin FUpdater.WaitFor; FreeAndNil(FUpdater); end else Exit;
  end;
  FUpdater:=TDeskUpdateThread.Create; FUpdater.OnReady:=@UpdateReady; FUpdater.Start;
  FUpdateTimer.Interval:=86400000;
end;

procedure TMainForm.UpdateReady(Sender: TObject);
begin
  if FClosing then Exit;
  if FUpdater.Failure<>'' then LogMsg('[ATUALIZAÇÃO] '+FUpdater.Failure)
  else if FUpdater.NewVersion<>'' then begin
    FPendingUpdate:=FUpdater.StagedExe; FPendingUpdateHash:=FUpdater.Checksum;
    LogMsg('[ATUALIZAÇÃO] Versão '+FUpdater.NewVersion+' verificada. Será aplicada quando não houver sessão ativa.');
    FUpdateTimer.Interval:=1000;
  end else LogMsg('[ATUALIZAÇÃO] O aplicativo está atualizado.');
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  I: Integer;
  Prefix: string;
  MI: TMenuItem;
  NeedsElev: Boolean;
begin
  inherited CreateNew(AOwner);
  Caption := 'MaurinDesk v0.6.6 — Conexão Remota Assistida';
  SetBounds(100, 60, 1220, 840);
  Constraints.MinWidth := 1000;
  Constraints.MinHeight := 700;
  Position := poScreenCenter;
  Color := RGBToColor(245, 246, 248);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnCloseQuery := @Closing;

  FIncomingIds := TStringList.Create;

  // Address defaults to: https://maurinsoft.com.br/MaurinDesk/api
  FURL := 'https://maurinsoft.com.br/MaurinDesk/api';
  FStreamPort := DEFAULT_DESK_PORT;
  if DeskOption('--ui-preview') or DeskOption('--render-preview') or DeskOption('--self-test') then
    FSetMain:=TSetMain.Create(ExpandFileName(ExtractFilePath(Application.ExeName)+'../build/ui-preview'),'')
  else
  FSetMain := TSetMain.Create(IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA'))+'MaurinDesk',
    IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName))+'MaurinDesk.ini');
  FConfigFile := FSetMain.Filename;
  LoadConfig;
  Width := FSetMain.WindowWidth; Height := FSetMain.WindowHeight;

  // Command-line override support
  Prefix := '--dev-local-api=';
  for I := 1 to ParamCount do begin
    if Copy(ParamStr(I), 1, Length(Prefix)) = Prefix then begin
      FURL := Copy(ParamStr(I), Length(Prefix) + 1, MaxInt);
      FAllowLocal := True;
    end;
    if Copy(ParamStr(I), 1, 10) = '--api-url=' then
      FURL := Copy(ParamStr(I), 11, MaxInt);
  end;

  FProfile := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + MD5Print(MD5String(FURL)) + DirectorySeparator;
  if DeskOption('--ui-preview') or DeskOption('--render-preview') or DeskOption('--self-test') then
    FProfile:=IncludeTrailingPathDelimiter(ExpandFileName(ExtractFilePath(Application.ExeName)+'../build/ui-preview'));
  ForceDirectories(FProfile);
  FIdentityFile := FProfile + 'identity.dat';

  // Popup Menu for Cards
  FCardPopupMenu := TPopupMenu.Create(Self);
  MI := TMenuItem.Create(FCardPopupMenu);
  MI.Caption := 'Conectar a este computador';
  MI.OnClick := @PopupConnectClick;
  FCardPopupMenu.Items.Add(MI);
  MI := TMenuItem.Create(FCardPopupMenu);
  MI.Caption := 'Remover dos favoritos';
  MI.OnClick := @PopupDeleteClick;
  FCardPopupMenu.Items.Add(MI);

  BuildModernLayout;
  UpdateServerLabels;
  LoadFavorites;
  ApplyLanguage;

  // Initial Log messages
  LogMsg('MaurinDesk v0.6.6 (Build 2026-11-14) inicializado.');
  LogMsg('Servidor configurado: ' + FURL);
  LogMsg('Perfil local: ' + FProfile);

  // Assegura automaticamente as regras do Windows Firewall (porta de streaming e binário)
  if not (DeskOption('--ui-preview') or DeskOption('--render-preview') or DeskOption('--self-test')) then begin
  if EnsureFirewallRule(NeedsElev, FStreamPort) then begin
    if NeedsElev then
      LogMsg('[FIREWALL] Solicitada liberação automática do Windows Firewall (UAC).')
    else
      LogMsg('[FIREWALL] Porta TCP ' + IntToStr(FStreamPort) + ' e aplicativo liberados no Windows Firewall.');
  end else
    LogMsg('[FIREWALL AVISO] Não foi possível registrar regras no Windows Firewall.');
  end;

  // Polling timer
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 15000;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := not (DeskOption('--ui-preview') or DeskOption('--render-preview') or DeskOption('--self-test'));
  FUpdateTimer := TTimer.Create(Self); FUpdateTimer.Interval := 30000;
  FUpdateTimer.OnTimer := @CheckUpdates;
  FUpdateTimer.Enabled := FSetMain.AutoUpdate and FTimer.Enabled;

  // Auto-register or test connection on startup
  if FTimer.Enabled then begin
  if FileExists(FIdentityFile) then begin
    LogMsg('Identidade encontrada no disco. Verificando registro...');
    Start(opRegister);
  end else begin
    LogMsg('Preparando a chave deste computador...'); Start(opRegister);
  end;
  end;
end;

destructor TMainForm.Destroy;
begin
  FClosing := True;
  Application.RemoveAsyncCalls(Self);
  if FTimer <> nil then FTimer.Enabled := False;
  if FUpdateTimer <> nil then FUpdateTimer.Enabled := False;
  if FUpdater <> nil then begin FUpdater.Terminate; FUpdater.WaitFor; FreeAndNil(FUpdater); end;
  StopStreaming;
  if FWorker <> nil then begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FIncomingIds.Free;
  if FSetMain <> nil then begin
    if not (DeskOption('--ui-preview') or DeskOption('--render-preview') or DeskOption('--self-test')) then SaveConfig;
    FreeAndNil(FSetMain);
  end;
  inherited Destroy;
end;

procedure TMainForm.LogMsg(const Msg: string);
var
  T: string;
begin
  T := FormatDateTime('hh:nn:ss', Now);
  FLogMemo.Lines.Add('[' + T + '] ' + Msg);
  while FLogMemo.Lines.Count>2000 do FLogMemo.Lines.Delete(0);
  FLogMemo.SelStart := Length(FLogMemo.Text);
end;

function TMainForm.FormatDeskKey(const Key: string): string;
begin
  Result := FormatDeskKeyHelper(Key);
end;

procedure TMainForm.UpdateServerLabels;
begin
  FServerStatusLabel.Hint := FURL; FServerStatusLabel.ShowHint := True;
  FDiscServerLabel.Caption := 'Servidor: ' + FURL;
end;

procedure TMainForm.LoadConfig;
begin
  FURL := FSetMain.ServerURL; FStreamPort := FSetMain.StreamPort;
  SetDeskLanguage(StrToDeskLang(FSetMain.Language));
end;

procedure TMainForm.SaveConfig;
begin
  FSetMain.ServerURL := FURL; FSetMain.StreamPort := FStreamPort;
  FSetMain.Language := DeskLangToStr(GetDeskLanguage);
  if WindowState=wsNormal then begin FSetMain.WindowWidth := Width; FSetMain.WindowHeight := Height; end;
  FSetMain.Save;
end;

procedure TMainForm.DrawLogo(Sender: TObject);
var
  PB: TPaintBox;
begin
  PB := TPaintBox(Sender);
  PB.Canvas.Brush.Color := FTopBar.Color;
  PB.Canvas.FillRect(0, 0, PB.Width, PB.Height);

  // Red AnyDesk overlapping diamonds
  PB.Canvas.Brush.Color := RGBToColor(229, 57, 53);
  PB.Canvas.Pen.Color := RGBToColor(198, 40, 40);
  PB.Canvas.Polygon([Point(14, 8), Point(22, 16), Point(14, 24), Point(6, 16)]);

  PB.Canvas.Brush.Color := RGBToColor(239, 83, 80);
  PB.Canvas.Polygon([Point(20, 14), Point(28, 22), Point(20, 30), Point(12, 22)]);
end;

procedure TMainForm.DrawKeyIcon(Sender: TObject);
var
  PB: TPaintBox;
begin
  PB := TPaintBox(Sender);
  PB.Canvas.Brush.Color := FKeyBox.Color;
  PB.Canvas.FillRect(0, 0, PB.Width, PB.Height);

  // Red badge box with down-arrow / monitor icon
  PB.Canvas.Brush.Color := RGBToColor(229, 57, 53);
  PB.Canvas.Pen.Color := RGBToColor(198, 40, 40);
  PB.Canvas.RoundRect(2, 4, 28, 28, 6, 6);

  // White down arrow inside
  PB.Canvas.Brush.Color := clWhite;
  PB.Canvas.Pen.Color := clWhite;
  PB.Canvas.Polygon([Point(8, 11), Point(22, 11), Point(15, 20)]);
  PB.Canvas.Rectangle(13, 19, 17, 24);
end;

procedure TMainForm.DrawCardThumbnail(Sender: TObject);
var PB: TPaintBox;
begin
  PB:=TPaintBox(Sender); PB.Canvas.Brush.Color:=RGBToColor(245,247,250); PB.Canvas.Pen.Color:=RGBToColor(102,114,132);
  PB.Canvas.RoundRect(3,3,31,24,4,4); PB.Canvas.Line(17,24,17,31); PB.Canvas.Line(9,31,25,31);
end;

procedure TMainForm.KeyBoxClick(Sender: TObject);
begin
  if FRawPublicKey <> '' then begin
    Clipboard.AsText := FRawPublicKey;
    LogMsg('Chave ' + FormatDeskKey(FRawPublicKey) + ' copiada para a área de transferência.');
    FStatusMsgLabel.Caption := 'Chave copiada para a área de transferência.';
  end else
    Start(opRegister);
end;

procedure TMainForm.RegisterClick(Sender: TObject);
begin
  LogMsg('Iniciando registro de máquina...');
  Start(opRegister);
end;

procedure TMainForm.ConnectClick(Sender: TObject);
var
  TargetText, CleanTarget, DirectHost: string;
  ColonPos, TargetPort: Integer;
begin
  if FBusy then begin FStatusMsgLabel.Caption:='Aguarde a comunicação atual terminar.'; Exit; end;
  if FSessionId<>'' then begin ShowMessage('Encerre a sessão atual antes de iniciar outra conexão.'); Exit; end;
  FStoppingSession:=False;
  TargetText := Trim(FTarget.Text);
  CleanTarget := StringReplace(TargetText, ' ', '', [rfReplaceAll]);

  // Se for endereço IP direto (ex: 172.17.241.157 ou 172.17.241.157:7071)
  if (Pos('.', TargetText) > 0) and not AIRemoteValidKey(CleanTarget) then
  begin
    TargetPort := FStreamPort;
    ColonPos := Pos(':', TargetText);
    if ColonPos > 0 then begin
      DirectHost := Copy(TargetText, 1, ColonPos - 1);
      TargetPort := StrToIntDef(Copy(TargetText, ColonPos + 1, Length(TargetText)), FStreamPort);
    end else
      DirectHost := TargetText;

    FIsController := True;
    LogMsg('[CONEXÃO DIRETA] Conectando diretamente ao host IP: ' + DirectHost + ':' + IntToStr(TargetPort) + '...');
    if FStreamClient <> nil then StopStreaming;
    FStreamClient := TDeskStreamClient.Create(DirectHost, TargetPort, DirectHost);
    FStreamClient.OnLog := @HandleStreamLog;
    FRemoteViewer := TfRemoteViewer.CreateViewer(Self, DirectHost, True, FStreamClient);
    FRemoteViewer.OnCloseSession := @ViewerClosed;
    FRemoteViewer.Show;
    FStreamClient.Start;
    LogMsg('[VIEWER] Janela do visualizador remoto aberta!');
    Exit;
  end;

  if not AIRemoteValidKey(CleanTarget) then begin
    LogMsg('[AVISO] Digite uma chave remota válida com 10 dígitos ou um endereço IP.');
    ShowMessage('Informe uma chave remota de 10 dígitos (ex: 650 449 1499) ou um IP direto (ex: 172.17.241.150).');
    Exit;
  end;
  FIsController := True;
  FSessionTargetKey := CleanTarget;
  FSessionWasAccepted := False;
  FTarget.Text := CleanTarget;
  LogMsg('Solicitando conexão para chave: ' + FormatDeskKey(CleanTarget) + '...');
  Start(opConnect);
end;

procedure TMainForm.TopConnectClick(Sender: TObject);
begin
  if FTopSearchEdit.Text <> '' then
    FTarget.Text := FTopSearchEdit.Text;
  FIsController := True;
  ConnectClick(Sender);
end;

procedure TMainForm.Tick(Sender: TObject);
begin
  if not FTrayAvailable then InitializeTrayIcon;
  if FToken <> '' then
    Start(opPoll);
end;

procedure TMainForm.TestConnClick(Sender: TObject);
begin
  LogMsg('[TESTE] Verificando comunicação HTTP com ' + FURL + '...');
  Start(opHealth);
end;

procedure TMainForm.ClearLogClick(Sender: TObject);
begin
  FLogMemo.Clear;
  LogMsg('Log limpo.');
end;

procedure TMainForm.CopyLogClick(Sender: TObject);
begin
  Clipboard.AsText := FLogMemo.Text;
  LogMsg('Log copiado para a área de transferência.');
  ShowMessage('Log copiado com sucesso!');
end;

procedure TMainForm.Start(Operation: TOperation; const Id: string);
begin
  if FClosing then Exit;
  if FBusy then
  begin
    // Enfileira ações do usuário para não perder cliques se o poll estiver ativo
    if Operation in [opConnect, opAcceptView, opAcceptControl, opReject, opClose] then
    begin
      FPendingOp := Operation;
      FPendingId := Id;
      FHasPendingOp := True;
      LogMsg('[FILA] Ação agendada para execução imediata após sincronização...');
    end;
    Exit;
  end;

  if (Operation <> opRegister) and (Operation <> opHealth) and (FToken = '') then begin
    FStatusMsgLabel.Caption := 'Registre esta máquina primeiro.';
    LogMsg('[AVISO] Registre esta máquina primeiro para executar operações de sessão.');
    Exit;
  end;
  if FWorker <> nil then begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;

  FBusy := True;
  FWorker := TAPIWorker.Create(Self);
  FWorker.Operation := Operation;
  FWorker.URL := FURL;
  FWorker.Token := FToken;
  FWorker.IdentityFile := FIdentityFile;
  FWorker.RemoteKey := FTarget.Text;
  FWorker.SessionId := Id;
  FWorker.AllowLocal := FAllowLocal;
  FWorker.Control := True;
  FWorker.StreamPort := FStreamPort;
  FWorker.CloseReason:=FRequestedCloseReason;
  if FWorker.CloseReason='' then FWorker.CloseReason:='local_stop';
  if Operation = opPoll then
    FWorker.SessionId := FSessionId;

  case Operation of
    opRegister: LogMsg('[REQ] Registrando máquina em: ' + FURL + '/devices...');
    opPoll: LogMsg('[REQ] Polling presença / pedidos em: ' + FURL + '...');
    opConnect: LogMsg('[REQ] Solicitando sessão para ' + FormatDeskKey(FTarget.Text) + '...');
    opHealth: LogMsg('[REQ] Testando rota /health em: ' + FURL + '...');
    opClose: LogMsg('[REQ] Encerrando sessão ' + Id + '...');
    opSendLog: LogMsg('[REQ] Enviando relatório de diagnóstico ao servidor...');
  end;

  FStatusMsgLabel.Caption := 'Comunicando com o servidor...';
  FWorker.Start;
end;

procedure TMainForm.Finished(W: TAPIWorker);
var
  A, Grants, Events: TJSONArray;
  J, CommObj, HostObj, RequesterObj, LastEvent, ClosedBy: TJSONObject;
  State, ReqKey, ReqName, CommStatus: string;
  I: Integer;
begin
  // Diagnostic uploads are independent workers and must not release the session worker's busy state.
  if W.Operation=opSendLog then begin
    if not FClosing then begin
      if W.Failure<>'' then LogMsg('[DIAGNOSTICO ERRO] '+W.Failure)
      else LogMsg('[DIAGNOSTICO] Relatorio enviado.');
    end;
    Exit;
  end;
  FBusy := False;
  if FClosing then Exit;

  if W.Failure <> '' then begin
    FStatusMsgLabel.Caption := W.Failure;
    FSidebarStatus.Caption := _T(strStatusCommError);
    FSidebarStatus.Font.Color := RGBToColor(239, 68, 68);
    LogMsg('[FALHA] ' + W.Failure);
    if W.Operation in [opPoll,opRegister,opHealth] then begin
      FServerStatusLabel.Caption:='● Verifique a conexão ao servidor'; FServerStatusLabel.Font.Color:=RGBToColor(205,87,43);
    end;

    if Pos('403', W.Failure) > 0 then
      LogMsg('[DICA 403] Servidor retornou Acesso Proibido. Certifique-se de que a pasta server/api foi copiada para public_html/MaurinDesk/api/.')
    else if Pos('404', W.Failure) > 0 then
      LogMsg('[DICA 404] URL não encontrada no servidor. Confira a rota configurada em ⚙ Config Servidor.')
    else if (Pos('12007', W.Failure) > 0) or (Pos('12029', W.Failure) > 0) then
      LogMsg('[DICA REDE] Falha ao conectar ao host. Verifique sua conexão com a internet.');

    if W.Operation <> opSendLog then
      SendFailureLogToServer('API_ERROR', W.Failure);

    if FHasPendingOp then Application.QueueAsyncCall(@ProcessPendingOperation,0);
    Exit;
  end;
  if W.Data = nil then Exit;

  case W.Operation of
    opRegister: begin
      FToken := W.Data.Get('device_token', '');
      FRawPublicKey := W.Data.Get('public_key', '');
      FKeyTextLabel.Caption := FormatDeskKey(FRawPublicKey);
      FSidebarStatus.Caption := '● Registrado e Online';
      FSidebarStatus.Font.Color := RGBToColor(34, 197, 94);
      FServerStatusLabel.Caption := '● Conectado ao servidor'; FServerStatusLabel.Font.Color := RGBToColor(29,157,83);
      FStatusMsgLabel.Caption := 'Máquina registrada. Chave: ' + FormatDeskKey(FRawPublicKey);
      LogMsg('[SUCESSO] Registrado no servidor! Sua chave é: ' + FormatDeskKey(FRawPublicKey) +
        ' | Token: ' + Copy(FToken, 1, 8) + '...');
    end;

    opPoll: begin
      FServerStatusLabel.Caption:='● Conectado ao servidor'; FServerStatusLabel.Font.Color:=RGBToColor(29,157,83);
      A := W.Data.Arrays['items'];
      FIncomingIds.Clear;
      if A.Count > 0 then begin
        J := TJSONObject(A[0]);
        FIncomingIds.Add(J.Get('id', ''));
        ReqKey := FormatDeskKey(J.Get('requester_key', ''));
        ReqName := J.Get('requester_name', '');
        FIncomingText.Caption := 'Solicitação recebida de: ' + ReqKey + ' (' + ReqName + ')' +
          #13#10'Autorize apenas quem você conhece.';
        FIncomingPanel.Visible := True;
        if FLastIncomingId<>J.Get('id','') then begin
          FLastIncomingId:=J.Get('id','');
          if not Visible then begin
            FTrayIcon.BalloonTitle:='Solicitação de conexão';
            FTrayIcon.BalloonHint:=ReqName+' solicita acesso. Abra o MaurinDesk para autorizar.';
            FTrayIcon.ShowBalloonHint;
          end;
        end;
        LogMsg('[PEDIDO RECEBIDO] ' + ReqKey + ' (' + ReqName + ') solicitou acesso.');
      end else
        FIncomingPanel.Visible := False;

      J := TJSONObject(W.Data.Find('current_session'));
      if J <> nil then begin
        State := J.Get('state', '');
        FActiveSessionText.Caption := 'Sessão atual: ' + State + ' (Chave: ' + FTarget.Text + ')';
        FActiveSessionPanel.Visible := (State = 'accepted') or (State = 'active') or (State = 'pending');
        LogMsg('[STATUS SESSÃO] Estado atual: ' + State);
        if (State = 'accepted') or (State = 'active') or (State = 'connecting') then StartClipboard(J);
        if (State = 'accepted') and FIsController then RememberRemote;
        CommObj := TJSONObject(J.Find('communication'));
        if CommObj <> nil then begin
          HostObj := CommObj.Objects['host'];
          RequesterObj := CommObj.Objects['requester'];
          CommStatus := CommObj.Get('status', 'desconhecido');
          LogMsg('[PHP COMUNICACAO] ' + CommStatus + ' | quadro=' +
            IntToStr(CommObj.Get('frame_id', 0)));
          Events := CommObj.Arrays['events'];
          if (Events <> nil) and (Events.Count > 0) then begin
            LastEvent := TJSONObject(Events.Items[Events.Count - 1]);
            LogMsg('[PHP ETAPA] ' + LastEvent.Get('event_type', '') +
              ' | horario UTC=' + DateTimeToStr(UnixToDateTime(LastEvent.Get('occurred_at', Int64(0)))));
          end;
          if (HostObj <> nil) and (RequesterObj <> nil) then
            LogMsg('[PHP REDE] Host IP=' + HostObj.Get('observed_ip', '') +
              ' LAN=' + HostObj.Get('local_ip', '') + ' online=' + BoolToStr(HostObj.Get('online', False), True) +
              ' | Controlador IP=' + RequesterObj.Get('observed_ip', '') +
              ' LAN=' + RequesterObj.Get('local_ip', '') + ' online=' + BoolToStr(RequesterObj.Get('online', False), True));
          if (CommStatus = 'waiting_host_frame') or (CommStatus = 'frame_stalled') then
            if FRemoteViewer <> nil then
              FRemoteViewer.SetErrorMessage('O PHP ainda nao recebeu imagem recente do host. Consulte o log do computador remoto.');
        end;

        // Se a sessão foi aceita e este computador é o controlador, conecta ao stream e abre o Viewer!
        if (State = 'accepted') and FIsController and (FRemoteViewer = nil) and not FStoppingSession then begin
          begin
            Grants := J.Arrays['granted_permissions'];
            FSessionCanControl := False;
            if Grants <> nil then
              for I := 0 to Grants.Count - 1 do
                if (Grants.Strings[I] = 'input.mouse') or (Grants.Strings[I] = 'input.keyboard') then
                  FSessionCanControl := True;
            FRemoteViewer := TfRemoteViewer.CreateViewer(Self, FTarget.Text, FSessionCanControl, nil);
            FRemoteViewer.OnCloseSession := @ViewerClosed;
            FRemoteViewer.OnSendFiles:=@QueueSelectedFiles; FRemoteViewer.OnOpenReceived:=@OpenReceivedFiles;
            FRemoteViewer.Show;
            LogMsg('[VIEWER] Janela do visualizador remoto aberta!');

            // Relay-first: a primeira imagem nao depende de portas TCP de entrada.
            // P2P permanece disponivel no codigo para uma futura troca de transporte
            // somente depois que o primeiro quadro for confirmado.
            LogMsg('[PONTE] Modo relay-first: iniciando imagem via HTTPS, sem tentativa P2P.');
            StartRelayStreaming;
          end;
        end;

        // Se a sessão foi aceita e este computador é o host, garante que o stream server e a ponte estão ativos
        if (State = 'accepted') and not FIsController and not FStoppingSession then begin
          if FStreamServer = nil then begin
            FStreamServer := TDeskStreamServer.Create(FStreamPort, FSessionCanControl, FSessionId, FToken);
            FStreamServer.OnLog := @HandleStreamLog;
            FStreamServer.Start;
          end;
          if FRelayHost = nil then begin
            FRelayHost := TDeskRelayHost.Create(FURL, FToken, FSessionId, FAllowLocal);
            FRelayHost.OnLog := @HandleStreamLog;
            FRelayHost.Start;
            LogMsg('[PONTE HOST] Transmissão em Modo Ponte ativada em segundo plano.');
          end;
        end;

        if (State = 'closed') or (State = 'expired') or (State = 'rejected') or (State = 'cancelled') then begin
          ClosedBy:=TJSONObject(J.Find('closed_by'));
          if ClosedBy<>nil then LogMsg('[SESSAO ENCERRADA] Origem='+ClosedBy.Get('role','')+' | motivo='+J.Get('reason',''))
          else LogMsg('[SESSAO ENCERRADA] Estado='+State+' | motivo='+J.Get('reason','nao informado pela API'));
          FSessionId := '';
          FIsController := False;
          FActiveSessionPanel.Visible := False;
          StopStreaming;
          NameRemote;
        end;
      end else begin
        FActiveSessionPanel.Visible := False;
        FIsController := False;
        StopStreaming;
      end;

      FStatusMsgLabel.Caption := 'Online. ' + IntToStr(A.Count) + ' pedido(s) pendente(s).';
      LogMsg('[HEARTBEAT OK] Presença renovada. ' + IntToStr(W.Data.Arrays['items'].Count) + ' pedido(s) pendente(s).');
    end;

    opConnect: begin
      FSessionId := W.Data.Get('id', '');
      FActiveSessionText.Caption := 'Sessão: ' + W.Data.Get('state', '') + ' (Aguardando aceite)';
      FActiveSessionPanel.Visible := True;
      FIncomingPanel.Visible := False;
      FStatusMsgLabel.Caption := 'Sessão solicitada: ' + W.Data.Get('state', '');
      LogMsg('[CONECTADO] Sessão ID ' + FSessionId + ' iniciada. Estado: ' + W.Data.Get('state', ''));
    end;

    opAcceptView, opAcceptControl: begin
      FStoppingSession:=False;
      FSessionId := W.Data.Get('id', '');
      FActiveSessionText.Caption := 'Sessão: ' + W.Data.Get('state', '') + ' (Conectado)';
      FActiveSessionPanel.Visible := True;
      FIncomingPanel.Visible := False;
      FStatusMsgLabel.Caption := 'Sessão iniciada: ' + W.Data.Get('state', '');
      LogMsg('[CONECTADO] Sessão ID ' + FSessionId + ' iniciada. Estado: ' + W.Data.Get('state', ''));

      // Armazena a permissão explicitamente decidida pelo usuário no consentimento
      FSessionCanControl := (W.Operation = opAcceptControl);
      StartClipboard(W.Data);

      // Inicia servidor de captura de tela no Host com controle rigoroso e autenticação por token
      if FStreamServer = nil then begin
        FStreamServer := TDeskStreamServer.Create(FStreamPort, FSessionCanControl, FSessionId, FToken);
        FStreamServer.OnLog := @HandleStreamLog;
        FStreamServer.Start;
      end;
      // Inicia retaguarda do Modo Ponte no Servidor
      if FRelayHost = nil then begin
        FRelayHost := TDeskRelayHost.Create(FURL, FToken, FSessionId, FAllowLocal);
        FRelayHost.OnLog := @HandleStreamLog;
        FRelayHost.Start;
        LogMsg('[PONTE HOST] Transmissão em Modo Ponte ativada em segundo plano.');
      end;
    end;

    opReject: begin
      FIncomingPanel.Visible := False;
      FStatusMsgLabel.Caption := 'Pedido recusado.';
      LogMsg('[CONSENTIMENTO] Pedido de acesso remoto foi recusado.');
    end;

    opClose: begin
      FSessionId := '';
      FIsController := False;
      FActiveSessionPanel.Visible := False;
      StopStreaming;
      FStatusMsgLabel.Caption := 'Sessão encerrada.';
      LogMsg('[SESSÃO] Sessão encerrada com sucesso.');
      NameRemote;
    end;

    opHealth: begin
      LogMsg('[TESTE OK] Servidor respondeu com sucesso!');
      LogMsg('[TESTE RESPOSTA] Status: ' + W.Data.Get('status', 'ok') +
        ' | Versão do banco: ' + W.Data.Get('version', '0.2') +
        ' | Estágio: ' + W.Data.Get('stage', 'p2p-discovery'));
      FStatusMsgLabel.Caption := 'Servidor online e respondendo.';
      FSidebarStatus.Caption := '● Servidor Online';
      FSidebarStatus.Font.Color := RGBToColor(34, 197, 94);
    end;

    opSendLog: begin
      if W.Data <> nil then
        LogMsg(_T(strLogSentSuccess) + Copy(W.Data.Get('id', ''), 1, 8) + '...)')
      else
        LogMsg(_T(strLogSentSuccess) + 'OK)');
    end;
  end;
  LayoutModern(Self);

  // Processa operação do usuário que estava aguardando na fila
  if FHasPendingOp and not FClosing then
    Application.QueueAsyncCall(@ProcessPendingOperation,0);
end;

procedure TMainForm.ProcessPendingOperation(Data: PtrInt);
var Operation: TOperation; Id: string;
begin
  if FClosing or FBusy or not FHasPendingOp then Exit;
  Operation:=FPendingOp; Id:=FPendingId; FHasPendingOp:=False;
  Start(Operation,Id);
end;

procedure TMainForm.AcceptControlClick(Sender: TObject);
begin
  if FIncomingIds.Count > 0 then begin
    LogMsg('Autorizando controle (mouse, teclado e area de transferencia solicitada)...');
    Start(opAcceptControl, FIncomingIds[0]);
  end;
end;

procedure TMainForm.AcceptViewClick(Sender: TObject);
begin
  if FIncomingIds.Count > 0 then begin
    LogMsg('Autorizando conexão com permissão apenas de visualização...');
    Start(opAcceptView, FIncomingIds[0]);
  end;
end;

procedure TMainForm.RejectClick(Sender: TObject);
begin
  if FIncomingIds.Count > 0 then begin
    LogMsg('Recusando conexão recebida...');
    Start(opReject, FIncomingIds[0]);
  end;
end;

procedure TMainForm.StopClick(Sender: TObject);
begin
  FRequestedCloseReason:='stop_button';
  FStoppingSession:=True;
  StopStreaming;
  if FSessionId <> '' then begin
    LogMsg('Encerrando sessão ativa ' + FSessionId + '...');
    Start(opClose, FSessionId);
  end;
end;

procedure TMainForm.ViewerClosed(Sender: TObject);
begin
  FRequestedCloseReason:=TfRemoteViewer(Sender).CloseReason;
  LogMsg('[VIEWER ENCERRADO] Motivo='+FRequestedCloseReason);
  FStoppingSession:=True;
  TfRemoteViewer(Sender).DetachClients;
  LogMsg('[VIEWER] Janela do visualizador foi fechada.');
  FRemoteViewer := nil;
  StopStreaming;
  if FSessionId <> '' then
    Start(opClose, FSessionId);
end;

procedure TMainForm.StopStreaming;
begin
  if FStoppingStreams then Exit;
  FStoppingStreams:=True;
  try
  if FClipboardThread <> nil then begin
    FClipboardThread.Terminate;
    FClipboardThread.WaitFor;
    FreeAndNil(FClipboardThread);
    FDiscSubtitle.Caption:='Sincronização encerrada. Texto e arquivos durante a sessão autorizada.';
  end;
  if FRemoteViewer <> nil then begin
    FRemoteViewer.OnCloseSession := nil;
    FRemoteViewer.DetachClients;
    FRemoteViewer.Close;
    FRemoteViewer := nil;
  end;
  if FStreamClient <> nil then begin
    FStreamClient.StopClient;
    FStreamClient.WaitFor;
    FreeAndNil(FStreamClient);
  end;
  if FStreamServer <> nil then begin
    FStreamServer.StopServer;
    FStreamServer.WaitFor;
    FreeAndNil(FStreamServer);
  end;
  if FRelayClient <> nil then begin
    FRelayClient.StopRelay;
    FRelayClient.WaitFor;
    FreeAndNil(FRelayClient);
  end;
  if FRelayHost <> nil then begin
    FRelayHost.StopRelay;
    FRelayHost.WaitFor;
    FreeAndNil(FRelayHost);
  end;
  finally FStoppingStreams:=False; end;
end;

procedure TMainForm.StartClipboard(Session: TJSONObject);
var Permissions: TJSONArray; I: Integer;
begin
  if (Session = nil) or (FClipboardThread <> nil) or FStoppingSession then Exit;
  Permissions := Session.Arrays['granted_permissions'];
  if Permissions = nil then Exit;
  for I := 0 to Permissions.Count - 1 do
    if Permissions.Strings[I] = 'clipboard.sync' then begin
      FClipboardThread := TDeskClipboardThread.Create(FURL, FToken, FSessionId, FAllowLocal);
      FClipboardThread.OnLog := @HandleStreamLog;
      FClipboardThread.Start;
      Exit;
    end;
  FDiscSubtitle.Caption:='Área de transferência não autorizada nesta sessão.';
end;

procedure TMainForm.StartRelayStreaming;
begin
  if FRelayClient <> nil then Exit;
  LogMsg('[PONTE] Conectando à ponte do Servidor MaurinDesk...');
  FRelayClient := TDeskRelayClient.Create(FURL, FToken, FSessionId, FAllowLocal);
  FRelayClient.OnLog := @HandleStreamLog;
  if FRemoteViewer <> nil then
    FRemoteViewer.SetRelayClient(FRelayClient);
  FRelayClient.Start;
end;

procedure TMainForm.HandleFallbackToRelay(Sender: TObject);
begin
  LogMsg('[PONTE] Todas as portas P2P diretas estão bloqueadas. Alternando automaticamente para Modo Ponte...');
  StartRelayStreaming;
end;

procedure TMainForm.HandlePortSuccess(Sender: TObject; APort: Integer);
begin
  LogMsg('[P2P SUCESSO] Conexão P2P direta estabelecida com sucesso na porta ' + IntToStr(APort) + '!');
  if FRemoteViewer <> nil then
    FRemoteViewer.SetPortConnected(APort);
end;

procedure TMainForm.HandleStreamLog(Sender: TObject; const Msg: string);
var ClipText: string; P: Integer;
begin
  LogMsg(Msg);
  if Pos('[CLIPBOARD',Msg)=1 then begin
    P:=Pos('] ',Msg); if P>0 then ClipText:=Copy(Msg,P+2,MaxInt) else ClipText:=Msg;
    if Pos('[CLIPBOARD ERRO]',Msg)=1 then ClipText:='Falha na transferencia: '+ClipText;
    FDiscSubtitle.Caption:=ClipText; FDiscSubtitle.Hint:=ClipText; FDiscSubtitle.ShowHint:=True;
    if FRemoteViewer<>nil then FRemoteViewer.SetTransferStatus(ClipText);
  end;
  if (Pos('[STREAM CLIENT ERRO]', Msg) > 0) or (Pos('Falha ao conectar', Msg) > 0) or
    (Pos('[PONTE CLIENTE ERRO]', Msg) > 0) then begin
    SendFailureLogToServer('STREAM_ERROR', Msg);
    if FRemoteViewer <> nil then
      FRemoteViewer.SetErrorMessage(Msg);
  end;
end;

procedure TMainForm.ApplyLanguage;
  function Text(const PT, EN, ES: string): string;
  begin case GetDeskLanguage of dlEnglish: Result:=EN; dlSpanish: Result:=ES; else Result:=PT; end; end;
begin
  Caption := _T(strAppTitle); FTabLabel.Caption := 'MaurinDesk';
  FHeading.Caption := Text('Conecte-se com facilidade','Connect with ease','Conéctese fácilmente');
  FIntro.Caption := Text('Acesse outro computador ou compartilhe o seu com segurança.','Access another computer or securely share your own.','Acceda a otro equipo o comparta el suyo con seguridad.');
  FBtnSettings.Caption := Text('Configurações','Settings','Configuración');
  FBtnLang.Caption := UpperCase(DeskLangToStr(GetDeskLanguage));
  FNavConnect.Caption := Text('Conexões','Connections','Conexiones');
  FNavFavorites.Caption := Text('Favoritos','Favorites','Favoritos');
  FNavHistory.Caption := Text('Histórico','History','Historial');
  FDeskTitle.Caption := _T(strThisDeskTitle);
  FDeskSubtitle.Caption := Text('Compartilhe esta chave com quem vai acessar seu computador.','Share this key with the person accessing your computer.','Comparta esta clave con quien accederá a su equipo.');
  FBtnRegister.Caption := Text('Copiar chave','Copy key','Copiar clave');
  FRemoteTitle.Caption := Text('Acessar outro computador','Access another computer','Acceder a otro equipo');
  FRemoteSubtitle.Caption := Text('Chave do computador remoto','Remote computer key','Clave del equipo remoto');
  FTarget.TextHint := '000 000 0000'; FBtnConnect.Caption := Text('Conectar  →','Connect  →','Conectar  →');
  FBtnSaveFav.Caption := Text('☆  Salvar nos favoritos','☆  Save to favorites','☆  Guardar en favoritos');
  FDiscTitle.Caption := Text('Área de transferência','Clipboard','Portapapeles');
  if FClipboardThread=nil then FDiscSubtitle.Caption := Text('Texto e arquivos durante a sessão autorizada.','Text and files during the authorized session.','Texto y archivos durante la sesión autorizada.');
  FRecentTitle.Caption := Text('Conexões recentes','Recent connections','Conexiones recientes');
  if FNavigation=1 then FRecentTitle.Caption:=FNavFavorites.Caption else if FNavigation=2 then FRecentTitle.Caption:=FNavHistory.Caption;
  FRecentHint.Caption := Text('Duplo clique para conectar','Double-click to connect','Doble clic para conectar');
  FBtnAcceptControl.Caption := Text('Controle + área de transferência','Control + clipboard','Control + portapapeles');
  FBtnAcceptView.Caption := _T(strBtnAcceptView); FBtnReject.Caption := _T(strBtnReject); FBtnStop.Caption := _T(strBtnEndSession);
  FLogTitleLabel.Caption := Text('⌄  Diagnóstico da conexão','⌄  Connection diagnostics','⌄  Diagnóstico de conexión');
  FBtnTestConn.Caption := _T(strBtnTestConn); FBtnCopyLog.Caption := _T(strBtnCopyLog);
  FBtnClearLog.Caption := _T(strBtnClearLog); FBtnSendLog.Caption := Text('Enviar diagnóstico','Send diagnostics','Enviar diagnóstico');
  FBannerBuildLabel.Caption := 'v'+DESK_VERSION; LayoutModern(Self);
end;

procedure TMainForm.BtnLangClick(Sender: TObject);
begin
  case GetDeskLanguage of
    dlPortuguese: SetDeskLanguage(dlEnglish);
    dlEnglish: SetDeskLanguage(dlSpanish);
    dlSpanish: SetDeskLanguage(dlPortuguese);
  end;
  SaveConfig;
  ApplyLanguage;
  LogMsg('[IDIOMA] ' + UpperCase(DeskLangToStr(GetDeskLanguage)));
end;

procedure TMainForm.SendLogClick(Sender: TObject);
begin
  LogMsg('[DIAGNÓSTICO] Enviando log de diagnóstico ao servidor...');
  SendFailureLogToServer('USER_REQUEST', 'Log enviado manualmente pelo usuário');
end;

procedure TMainForm.SendFailureLogToServer(const Category, Message: string);
var
  Worker: TAPIWorker;
begin
  if FClosing then Exit;
  Worker := TAPIWorker.Create(Self);
  Worker.Operation := opSendLog;
  Worker.URL := FURL;
  Worker.Token := FToken;
  Worker.IdentityFile := FIdentityFile;
  Worker.SessionId := FSessionId;
  Worker.AllowLocal := FAllowLocal;
  Worker.LogCategory := Category;
  Worker.LogMessage := Copy(Message, 1, 250);
  Worker.LogContent := FLogMemo.Lines.Text;
  Worker.FreeOnTerminate := True;
  Worker.Start;
end;

procedure TMainForm.SettingsClick(Sender: TObject);
var OldURL: string;
begin
  if FSessionId<>'' then begin ShowMessage('Encerre a sessão antes de alterar as configurações.'); Exit; end;
  OldURL:=FURL;
  if FBusy then begin ShowMessage('Aguarde a comunicação atual terminar para alterar as configurações.'); Exit; end;
  if EditDeskSettings(FSetMain) then begin
    LoadConfig; ApplyLanguage; UpdateServerLabels;
    if FUpdateTimer<>nil then FUpdateTimer.Enabled:=FSetMain.AutoUpdate;
    if OldURL<>FURL then begin
      FProfile:=IncludeTrailingPathDelimiter(GetAppConfigDir(False))+MD5Print(MD5String(FURL))+DirectorySeparator;
      ForceDirectories(FProfile); FIdentityFile:=FProfile+'identity.dat'; FToken:=''; FRawPublicKey:='';
      FKeyTextLabel.Caption:='--- --- ----'; LoadFavorites; Start(opRegister);
    end;
  end;
end;

procedure TMainForm.LoadFavorites;
var
  Ini: TIniFile;
  Keys: TStringList;
begin
  Ini := TIniFile.Create(FProfile + 'favorites.ini');
  Keys := TStringList.Create;
  try
    Ini.ReadSection('favorites', Keys);
    RebuildFavoriteCards;
  finally
    Keys.Free;
    Ini.Free;
  end;
end;

procedure TMainForm.SaveFavClick(Sender: TObject);
var
  Key, AliasName: string;
  Ini: TIniFile;
begin
  Key := StringReplace(Trim(FTarget.Text), ' ', '', [rfReplaceAll]);
  if not AIRemoteValidKey(Key) then begin
    LogMsg('[AVISO] Chave inválida para salvar favorito.');
    ShowMessage('Informe uma chave válida de 10 dígitos para salvar.');
    Exit;
  end;

  AliasName := InputBox('Salvar Favorito', 'Apelido do Computador:', 'Computador ' + FormatDeskKey(Key));
  AliasName := Trim(AliasName);
  if AliasName = '' then AliasName := Key;

  Ini := TIniFile.Create(FProfile + 'favorites.ini');
  try
    Ini.WriteString('favorites', Key, AliasName);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  RebuildFavoriteCards;
  LogMsg('[FAVORITO] Computador ' + FormatDeskKey(Key) + ' salvo como "' + AliasName + '".');
  ShowMessage('Computador ' + FormatDeskKey(Key) + ' salvo com sucesso!');
end;

procedure TMainForm.RebuildFavoriteCards;
var Favorites, History: TIniFile; Keys, Recent: TStringList;
    I, Cols, CardW, X, Y: Integer; Card: TPanel; ThumbIcon: TPaintBox; AliasLabel, KeyLabel, StarLabel: TLabel;
    Key, AliasName: string;
  function LabelAt(const Caption: string; Left, Top, Width, Size: Integer; Bold: Boolean): TLabel;
  begin
    Result:=TLabel.Create(Card); Result.Parent:=Card; Result.AutoSize:=False; Result.SetBounds(Left,Top,Width,22);
    Result.Caption:=Caption; Result.Font.Name:='Segoe UI'; Result.Font.Size:=Size;
    Result.Font.Color:=RGBToColor(57,67,83); if Bold then Result.Font.Style:=[fsBold];
    Result.Hint:=Key; Result.Cursor:=crHandPoint; Result.OnClick:=@CardClick; Result.OnDblClick:=@CardDblClick;
  end;
begin
  if FCardsScrollBox=nil then Exit;
  while FCardsScrollBox.ControlCount>0 do FCardsScrollBox.Controls[0].Free;
  Favorites:=TIniFile.Create(FProfile+'favorites.ini'); History:=TIniFile.Create(FProfile+'history.ini');
  Keys:=TStringList.Create; Recent:=TStringList.Create;
  try
    if FNavigation<>2 then Favorites.ReadSection('favorites',Keys);
    if FNavigation<>1 then begin
      History.ReadSection('recent',Recent);
      for I:=Recent.Count-1 downto 0 do if Keys.IndexOf(Recent[I])<0 then Keys.Add(Recent[I]);
    end;
    Cols:=FGridColumns; if Cols<1 then Cols:=1;
    CardW:=(FContentArea.ClientWidth-56-(Cols-1)*14) div Cols;
    if Keys.Count=0 then begin
      with TLabel.Create(FCardsScrollBox) do begin
        Parent:=FCardsScrollBox; AutoSize:=False; SetBounds(2,16,FContentArea.ClientWidth-72,48); WordWrap:=True;
        Caption:='Seus computadores aparecerão aqui após uma conexão. Você também pode salvar uma chave nos favoritos.';
        Font.Color:=RGBToColor(128,139,155); Font.Size:=10;
      end; Exit;
    end;
    for I:=0 to Keys.Count-1 do begin
      Key:=Keys[I]; AliasName:=History.ReadString('names',Key,Favorites.ReadString('favorites',Key,''));
      if (AliasName='') or (AliasName=Key) then AliasName:=FormatDeskKey(Key);
      X:=(I mod Cols)*(CardW+14); Y:=(I div Cols)*100;
      Card:=TDeskCard.Create(FCardsScrollBox); Card.Parent:=FCardsScrollBox; Card.SetBounds(X,Y,CardW,86);
      Card.Hint:=Key; Card.Cursor:=crHandPoint; Card.OnClick:=@CardClick; Card.OnDblClick:=@CardDblClick;
      Card.PopupMenu:=FCardPopupMenu;
      ThumbIcon:=TPaintBox.Create(Card); ThumbIcon.Parent:=Card; ThumbIcon.SetBounds(14,25,36,36); ThumbIcon.OnPaint:=@DrawCardThumbnail;
      ThumbIcon.Hint:=Key; ThumbIcon.OnClick:=@CardClick; ThumbIcon.OnDblClick:=@CardDblClick;
      AliasLabel:=LabelAt(AliasName,62,18,CardW-100,10,True);
      AliasLabel.ShowHint:=True; AliasLabel.Hint:=Key;
      KeyLabel:=LabelAt(FormatDeskKey(Key),62,46,CardW-88,9,False); KeyLabel.Font.Color:=RGBToColor(128,139,155);
      StarLabel:=LabelAt('☆',CardW-30,24,24,15,False); StarLabel.OnClick:=@CardClick;
      if Favorites.ValueExists('favorites',Key) then StarLabel.Caption:='★';
    end;
  finally Recent.Free; Keys.Free; History.Free; Favorites.Free; end;
end;

procedure TMainForm.RememberRemote;
var History: TIniFile;
begin
  if (FSessionId='') or (FRecordedSession=FSessionId) or not AIRemoteValidKey(FSessionTargetKey) then Exit;
  FRecordedSession:=FSessionId; FSessionWasAccepted:=True;
  History:=TIniFile.Create(FProfile+'history.ini');
  try History.WriteInt64('recent',FSessionTargetKey,DateTimeToUnix(Now,False)); History.UpdateFile;
  finally History.Free; end;
  RebuildFavoriteCards;
end;

procedure TMainForm.NameRemote;
begin
  if not FSessionWasAccepted or not AIRemoteValidKey(FSessionTargetKey) then Exit;
  FNamePromptKey:=FSessionTargetKey; FSessionTargetKey:=''; FSessionWasAccepted:=False;
  Application.QueueAsyncCall(@PromptRemoteName,0);
end;

procedure TMainForm.PromptRemoteName(Data: PtrInt);
var History, Favorites: TIniFile; Key, AliasText: string;
begin
  if FClosing then Exit;
  Key:=FNamePromptKey; FNamePromptKey:=''; if not AIRemoteValidKey(Key) then Exit;
  History:=TIniFile.Create(FProfile+'history.ini'); Favorites:=TIniFile.Create(FProfile+'favorites.ini');
  try
    AliasText:=History.ReadString('names',Key,Favorites.ReadString('favorites',Key,'')); if AliasText=Key then AliasText:='';
    if InputQuery('Identificar computador','Nome para '+FormatDeskKey(Key)+' (opcional; vazio mantém o número):',AliasText) then begin
      AliasText:=Trim(AliasText); if Length(AliasText)>120 then AliasText:=Copy(AliasText,1,120);
      if AliasText='' then History.DeleteKey('names',Key) else History.WriteString('names',Key,AliasText);
      if Favorites.ValueExists('favorites',Key) then begin
        if AliasText='' then Favorites.WriteString('favorites',Key,Key) else Favorites.WriteString('favorites',Key,AliasText);
        Favorites.UpdateFile;
      end;
      History.UpdateFile;
    end;
  finally Favorites.Free; History.Free; end;
  RebuildFavoriteCards;
end;

procedure TMainForm.CardClick(Sender: TObject);
var
  K: string;
begin
  if Sender is TControl then begin
    K := TControl(Sender).Hint;
    if K = '' then
      if TControl(Sender).Parent <> nil then
        K := TControl(Sender).Parent.Hint;
    if K <> '' then begin
      FTarget.Text := K;
      FTopSearchEdit.Text := K;
      FPopupTargetKey := K;
      LogMsg('[CARTÃO] Selecionado computador remoto: ' + FormatDeskKey(K));
    end;
  end;
end;

procedure TMainForm.CardDblClick(Sender: TObject);
begin
  CardClick(Sender);
  ConnectClick(Sender);
end;

procedure TMainForm.PopupConnectClick(Sender: TObject);
begin
  if FPopupTargetKey <> '' then begin
    FTarget.Text := FPopupTargetKey;
    ConnectClick(Sender);
  end;
end;

procedure TMainForm.PopupDeleteClick(Sender: TObject);
var
  Ini: TIniFile;
begin
  if FPopupTargetKey <> '' then begin
    Ini := TIniFile.Create(FProfile + 'favorites.ini');
    try
      Ini.DeleteKey('favorites', FPopupTargetKey);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
    LogMsg('[FAVORITO] Computador ' + FormatDeskKey(FPopupTargetKey) + ' removido dos favoritos.');
    RebuildFavoriteCards;
  end;
end;

type
  TQuickCloseThread = class(TThread)
  private
    FURL, FToken, FSessionId: string;
    FAllowLocal: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AURL, AToken, ASessionId: string; AAllowLocal: Boolean);
  end;

constructor TQuickCloseThread.Create(const AURL, AToken, ASessionId: string; AAllowLocal: Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FURL := AURL;
  FToken := AToken;
  FSessionId := ASessionId;
  FAllowLocal := AAllowLocal;
  Start;
end;

procedure TQuickCloseThread.Execute;
var
  Cli: TAIRemoteSignalingClient;
  Resp: TJSONObject;
begin
  try
    Cli := TAIRemoteSignalingClient.Create;
    try
      Cli.BaseURL := FURL;
      Cli.DeviceToken := FToken;
      Cli.AllowLocalHTTP := FAllowLocal;
      Resp := Cli.CloseSession(FSessionId, 'app_closed');
      if Resp <> nil then Resp.Free;
    finally
      Cli.Free;
    end;
  except
  end;
end;

procedure TMainForm.Closing(Sender: TObject; var CanClose: Boolean);
var
  CloseSessionId: string;
begin
  if not FExitRequested and FTrayAvailable and (FSetMain<>nil) and FSetMain.MinimizeToTray then begin
    CanClose:=False; Hide; Exit;
  end;
  FClosing := True;
  FTimer.Enabled := False;
  StopStreaming;

  CloseSessionId := FSessionId;
  FSessionId := '';
  FIsController := False;

  // Se havia sessão aberta, notifica o encerramento de forma não-bloqueante
  if (CloseSessionId <> '') and (FToken <> '') then
  begin
    try
      TQuickCloseThread.Create(FURL, FToken, CloseSessionId, FAllowLocal);
    except
    end;
  end;

  CanClose := True; // Permite fechar a janela imediatamente sem travar
end;

end.
