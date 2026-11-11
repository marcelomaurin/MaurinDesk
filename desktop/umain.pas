unit umain;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  Graphics, Menus, Clipbrd, IniFiles, md5,
  fpjson, jsonparser, airemoteidentity, airemotesignaling,
  uDeskProtocol, uScreenCapture, uDeskStream, uRemoteViewer, uDeskI18n, uDeskFirewall;

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
    FRemoteViewer: TfRemoteViewer;
    FIsController: Boolean;

    // Header Controls
    FTopBar: TPanel;
    FLogoBox: TPaintBox;
    FTabPanel: TPanel;
    FTabLabel: TLabel;
    FTopSearchPanel: TPanel;
    FTopSearchEdit: TEdit;
    FTopConnectBtn: TPanel;
    FBtnLang: TButton;
    FBtnSettings: TButton;

    // Sidebar Controls
    FSidebar: TPanel;
    FDeskTitle: TLabel;
    FDeskSubtitle: TLabel;
    FKeyBox: TPanel;
    FKeyIconBox: TPaintBox;
    FKeyTextLabel: TLabel;
    FBtnRegister: TButton;
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
    FBtnConnect: TButton;
    FBtnSaveFav: TButton;

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
    FBtnAcceptControl: TButton;
    FBtnAcceptView: TButton;
    FBtnReject: TButton;
    FIncomingIds: TStringList;

    FActiveSessionPanel: TPanel;
    FActiveSessionText: TLabel;
    FBtnStop: TButton;

    // Log Console Panel (Bottom)
    FLogPanel: TPanel;
    FLogHeader: TPanel;
    FLogTitleLabel: TLabel;
    FBtnTestConn: TButton;
    FBtnSendLog: TButton;
    FBtnCopyLog: TButton;
    FBtnClearLog: TButton;
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
    procedure HandleStreamLog(Sender: TObject; const Msg: string);

    procedure LogMsg(const Msg: string);
    procedure LoadConfig;
    procedure SaveConfig;
    procedure LoadFavorites;
    procedure RebuildFavoriteCards;
    procedure UpdateServerLabels;
    function FormatDeskKey(const Key: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

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
                J := C.Heartbeat;
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
                '0.5.0'
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
          J := C.Heartbeat;
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

        opConnect: Data := C.RequestSession(RemoteKey, Control);
        opAcceptView: begin
          Data := C.Decide(SessionId, True, False);
          try
            J := C.AnnounceEndpoint(StreamPort, 'tcp', GetLocalIPAddress);
            J.Free;
          except
          end;
        end;
        opAcceptControl: begin
          Data := C.Decide(SessionId, True, True);
          try
            J := C.AnnounceEndpoint(StreamPort, 'tcp', GetLocalIPAddress);
            J.Free;
          except
          end;
        end;
        opReject: Data := C.Decide(SessionId, False, False);
        opClose: Data := C.CloseSession(SessionId, 'local_stop');
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

constructor TMainForm.Create(AOwner: TComponent);
var
  I: Integer;
  Prefix: string;
  SepLine: TPanel;
  MI: TMenuItem;
  NeedsElev: Boolean;
begin
  inherited CreateNew(AOwner);
  Caption := 'MaurinDesk v0.5.0 — Conexão Remota Assistida';
  SetBounds(100, 60, 980, 680);
  Constraints.MinWidth := 860;
  Constraints.MinHeight := 580;
  Position := poScreenCenter;
  Color := RGBToColor(245, 246, 248);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnCloseQuery := @Closing;

  FIncomingIds := TStringList.Create;

  // Address defaults to: https://maurinsoft.com.br/MaurinDesk/api
  FURL := 'https://maurinsoft.com.br/MaurinDesk/api';
  FStreamPort := DEFAULT_DESK_PORT;
  FConfigFile := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) + 'MaurinDesk.ini';
  LoadConfig;

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

  // -------------------------------------------------------------
  // 1. TOP BAR (AnyDesk header with red diamond logo & tab)
  // -------------------------------------------------------------
  FTopBar := TPanel.Create(Self);
  FTopBar.Parent := Self;
  FTopBar.Align := alTop;
  FTopBar.Height := 44;
  FTopBar.BevelOuter := bvNone;
  FTopBar.Color := RGBToColor(238, 240, 244);

  // MaurinDesk / AnyDesk red diamond logo
  FLogoBox := TPaintBox.Create(Self);
  FLogoBox.Parent := FTopBar;
  FLogoBox.SetBounds(8, 4, 36, 36);
  FLogoBox.OnPaint := @DrawLogo;

  // "Nova Conexão" tab
  FTabPanel := TPanel.Create(Self);
  FTabPanel.Parent := FTopBar;
  FTabPanel.SetBounds(48, 6, 155, 38);
  FTabPanel.BevelOuter := bvNone;
  FTabPanel.Color := clWhite;
  FTabLabel := TLabel.Create(Self);
  FTabLabel.Parent := FTabPanel;
  FTabLabel.SetBounds(14, 10, 125, 20);
  FTabLabel.Caption := 'Nova Conexão';
  FTabLabel.Font.Style := [fsBold];
  FTabLabel.Font.Color := RGBToColor(30, 41, 59);
  FTabLabel.Transparent := True;

  // Top Search/Address Bar
  FTopSearchPanel := TPanel.Create(Self);
  FTopSearchPanel.Parent := FTopBar;
  FTopSearchPanel.SetBounds(215, 6, 420, 32);
  FTopSearchPanel.BevelOuter := bvNone;
  FTopSearchPanel.Color := clWhite;

  with TLabel.Create(Self) do begin
    Parent := FTopSearchPanel;
    SetBounds(8, 7, 16, 20);
    Caption := '●';
    Font.Color := RGBToColor(34, 197, 94); // Green dot
    Font.Size := 11;
    Transparent := True;
  end;

  FTopSearchEdit := TEdit.Create(Self);
  FTopSearchEdit.Parent := FTopSearchPanel;
  FTopSearchEdit.SetBounds(28, 4, 350, 24);
  FTopSearchEdit.BorderStyle := bsNone;
  FTopSearchEdit.Font.Size := 10;
  FTopSearchEdit.TextHint := 'Chave Desk ou IP Remoto...';

  FTopConnectBtn := TPanel.Create(Self);
  FTopConnectBtn.Parent := FTopSearchPanel;
  FTopConnectBtn.SetBounds(385, 3, 28, 26);
  FTopConnectBtn.BevelOuter := bvNone;
  FTopConnectBtn.Color := RGBToColor(238, 240, 244);
  FTopConnectBtn.Cursor := crHandPoint;
  FTopConnectBtn.OnClick := @TopConnectClick;
  with TLabel.Create(Self) do begin
    Parent := FTopConnectBtn;
    SetBounds(8, 4, 16, 18);
    Caption := '➔';
    Font.Color := RGBToColor(30, 41, 59);
    Font.Style := [fsBold];
    Transparent := True;
    OnClick := @TopConnectClick;
  end;

  // Language Button
  FBtnLang := TButton.Create(Self);
  FBtnLang.Parent := FTopBar;
  FBtnLang.SetBounds(740, 6, 80, 32);
  FBtnLang.Anchors := [akTop, akRight];
  FBtnLang.Caption := '🌐 PT';
  FBtnLang.OnClick := @BtnLangClick;

  // Settings Button on right
  FBtnSettings := TButton.Create(Self);
  FBtnSettings.Parent := FTopBar;
  FBtnSettings.SetBounds(825, 6, 135, 32);
  FBtnSettings.Anchors := [akTop, akRight];
  FBtnSettings.Caption := '⚙ Config Servidor';
  FBtnSettings.OnClick := @SettingsClick;

  // -------------------------------------------------------------
  // 2. BOTTOM STATUS BAR
  // -------------------------------------------------------------
  FStatusBar := TPanel.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.Height := 26;
  FStatusBar.BevelOuter := bvNone;
  FStatusBar.Color := RGBToColor(241, 245, 249);

  FStatusDot := TLabel.Create(Self);
  FStatusDot.Parent := FStatusBar;
  FStatusDot.SetBounds(12, 5, 16, 18);
  FStatusDot.Caption := '●';
  FStatusDot.Font.Color := RGBToColor(34, 197, 94);
  FStatusDot.Transparent := True;

  FServerStatusLabel := TLabel.Create(Self);
  FServerStatusLabel.Parent := FStatusBar;
  FServerStatusLabel.SetBounds(30, 6, 320, 16);
  FServerStatusLabel.Caption := 'Servidor: ' + FURL;
  FServerStatusLabel.Font.Size := 8;
  FServerStatusLabel.Font.Color := RGBToColor(71, 85, 105);
  FServerStatusLabel.Transparent := True;

  FStatusMsgLabel := TLabel.Create(Self);
  FStatusMsgLabel.Parent := FStatusBar;
  FStatusMsgLabel.SetBounds(360, 6, 500, 16);
  FStatusMsgLabel.Caption := 'Pronto.';
  FStatusMsgLabel.Font.Size := 8;
  FStatusMsgLabel.Font.Color := RGBToColor(100, 116, 139);
  FStatusMsgLabel.Transparent := True;

  with TLabel.Create(Self) do begin
    Parent := FStatusBar;
    Align := alRight;
    Alignment := taRightJustify;
    Width := 160;
    Caption := 'MaurinDesk v0.5.0  ';
    Font.Size := 9;
    Font.Style := [fsBold];
    Font.Color := RGBToColor(220, 38, 38);
    Transparent := True;
  end;

  // -------------------------------------------------------------
  // 3. LEFT SIDEBAR ("This Desk" / "Este Computador")
  // -------------------------------------------------------------
  FSidebar := TPanel.Create(Self);
  FSidebar.Parent := Self;
  FSidebar.Align := alLeft;
  FSidebar.Width := 240;
  FSidebar.BevelOuter := bvNone;
  FSidebar.Color := clWhite;

  SepLine := TPanel.Create(Self);
  SepLine.Parent := FSidebar;
  SepLine.Align := alRight;
  SepLine.Width := 1;
  SepLine.BevelOuter := bvNone;
  SepLine.Color := RGBToColor(226, 232, 240);

  FDeskTitle := TLabel.Create(Self);
  FDeskTitle.Parent := FSidebar;
  FDeskTitle.SetBounds(18, 14, 200, 22);
  FDeskTitle.Caption := 'Este Computador';
  FDeskTitle.Font.Size := 13;
  FDeskTitle.Font.Style := [fsBold];
  FDeskTitle.Font.Color := RGBToColor(229, 57, 53);

  with TLabel.Create(Self) do begin
    Parent := FSidebar;
    SetBounds(18, 36, 204, 16);
    Caption := '● Software v0.5.0 (Build 2026-11-11)';
    Font.Size := 8;
    Font.Style := [fsBold];
    Font.Color := RGBToColor(14, 165, 233);
    Transparent := True;
  end;

  FDeskSubtitle := TLabel.Create(Self);
  FDeskSubtitle.Parent := FSidebar;
  FDeskSubtitle.SetBounds(18, 54, 204, 32);
  FDeskSubtitle.Caption := 'Seu computador pode ser acessado por este endereço.';
  FDeskSubtitle.Font.Size := 8;
  FDeskSubtitle.Font.Color := RGBToColor(100, 116, 139);
  FDeskSubtitle.WordWrap := True;

  // AnyDesk ID Box
  FKeyBox := TPanel.Create(Self);
  FKeyBox.Parent := FSidebar;
  FKeyBox.SetBounds(18, 88, 200, 48);
  FKeyBox.BevelOuter := bvNone;
  FKeyBox.Color := RGBToColor(255, 245, 245);
  FKeyBox.Cursor := crHandPoint;
  FKeyBox.OnClick := @KeyBoxClick;

  FKeyIconBox := TPaintBox.Create(Self);
  FKeyIconBox.Parent := FKeyBox;
  FKeyIconBox.SetBounds(6, 8, 30, 32);
  FKeyIconBox.OnPaint := @DrawKeyIcon;
  FKeyIconBox.OnClick := @KeyBoxClick;

  FKeyTextLabel := TLabel.Create(Self);
  FKeyTextLabel.Parent := FKeyBox;
  FKeyTextLabel.SetBounds(42, 13, 150, 24);
  FKeyTextLabel.Caption := '--- --- ---';
  FKeyTextLabel.Font.Size := 13;
  FKeyTextLabel.Font.Style := [fsBold];
  FKeyTextLabel.Font.Color := RGBToColor(30, 41, 59);
  FKeyTextLabel.Cursor := crHandPoint;
  FKeyTextLabel.OnClick := @KeyBoxClick;
  FKeyTextLabel.Hint := 'Clique para copiar a chave';
  FKeyTextLabel.ShowHint := True;

  FBtnRegister := TButton.Create(Self);
  FBtnRegister.Parent := FSidebar;
  FBtnRegister.SetBounds(18, 142, 200, 30);
  FBtnRegister.Caption := 'Registrar / Obter Chave';
  FBtnRegister.OnClick := @RegisterClick;

  FSidebarStatus := TLabel.Create(Self);
  FSidebarStatus.Parent := FSidebar;
  FSidebarStatus.SetBounds(18, 178, 200, 18);
  FSidebarStatus.Caption := '● Não conectado';
  FSidebarStatus.Font.Size := 8;
  FSidebarStatus.Font.Color := RGBToColor(156, 163, 175);

  FBannerPanel := TPanel.Create(Self);
  FBannerPanel.Parent := FSidebar;
  FBannerPanel.Align := alBottom;
  FBannerPanel.Height := 115;
  FBannerPanel.BevelOuter := bvNone;
  FBannerPanel.Color := RGBToColor(239, 68, 68);

  FBannerTitleLabel := TLabel.Create(Self);
  FBannerTitleLabel.Parent := FBannerPanel;
  FBannerTitleLabel.SetBounds(16, 10, 208, 20);
  FBannerTitleLabel.Caption := 'MaurinDesk v0.5.0';
  FBannerTitleLabel.Font.Size := 11;
  FBannerTitleLabel.Font.Style := [fsBold];
  FBannerTitleLabel.Font.Color := clWhite;
  FBannerTitleLabel.Transparent := True;

  FBannerBuildLabel := TLabel.Create(Self);
  FBannerBuildLabel.Parent := FBannerPanel;
  FBannerBuildLabel.SetBounds(16, 32, 208, 16);
  FBannerBuildLabel.Caption := 'Build: 2026-11-11 | Stream Ativo';
  FBannerBuildLabel.Font.Size := 8;
  FBannerBuildLabel.Font.Color := RGBToColor(254, 226, 226);
  FBannerBuildLabel.Transparent := True;

  FBannerTagLabel := TLabel.Create(Self);
  FBannerTagLabel.Parent := FBannerPanel;
  FBannerTagLabel.SetBounds(16, 52, 208, 30);
  FBannerTagLabel.Caption := 'Acesso remoto assistido e seguro.';
  FBannerTagLabel.Font.Size := 8;
  FBannerTagLabel.Font.Color := RGBToColor(254, 226, 226);
  FBannerTagLabel.Transparent := True;
  FBannerTagLabel.WordWrap := True;

  FBannerWebLabel := TLabel.Create(Self);
  FBannerWebLabel.Parent := FBannerPanel;
  FBannerWebLabel.SetBounds(16, 88, 208, 16);
  FBannerWebLabel.Caption := 'maurinsoft.com.br';
  FBannerWebLabel.Font.Size := 8;
  FBannerWebLabel.Font.Style := [fsBold];
  FBannerWebLabel.Font.Color := clWhite;
  FBannerWebLabel.Transparent := True;

  // -------------------------------------------------------------
  // 4. MAIN RIGHT CONTENT AREA
  // -------------------------------------------------------------
  FContentArea := TPanel.Create(Self);
  FContentArea.Parent := Self;
  FContentArea.Align := alClient;
  FContentArea.BevelOuter := bvNone;
  FContentArea.Color := RGBToColor(245, 246, 248);

  // Top Cards Panel (Remote Desk Card + Discovery Card)
  FTopCardsPanel := TPanel.Create(Self);
  FTopCardsPanel.Parent := FContentArea;
  FTopCardsPanel.Align := alTop;
  FTopCardsPanel.Height := 155;
  FTopCardsPanel.BevelOuter := bvNone;
  FTopCardsPanel.Color := RGBToColor(245, 246, 248);

  // Card 1: Remote Desk Card
  FRemoteDeskCard := TPanel.Create(Self);
  FRemoteDeskCard.Parent := FTopCardsPanel;
  FRemoteDeskCard.SetBounds(20, 10, 400, 135);
  FRemoteDeskCard.BevelOuter := bvNone;
  FRemoteDeskCard.Color := clWhite;

  FRemoteAccentBar := TPanel.Create(Self);
  FRemoteAccentBar.Parent := FRemoteDeskCard;
  FRemoteAccentBar.Align := alLeft;
  FRemoteAccentBar.Width := 5;
  FRemoteAccentBar.BevelOuter := bvNone;
  FRemoteAccentBar.Color := RGBToColor(255, 107, 0);

  FRemoteTitle := TLabel.Create(Self);
  FRemoteTitle.Parent := FRemoteDeskCard;
  FRemoteTitle.SetBounds(18, 12, 200, 20);
  FRemoteTitle.Caption := 'Computador Remoto';
  FRemoteTitle.Font.Size := 11;
  FRemoteTitle.Font.Style := [fsBold];
  FRemoteTitle.Font.Color := RGBToColor(230, 81, 0);
  FRemoteTitle.Transparent := True;

  FRemoteSubtitle := TLabel.Create(Self);
  FRemoteSubtitle.Parent := FRemoteDeskCard;
  FRemoteSubtitle.SetBounds(18, 34, 360, 26);
  FRemoteSubtitle.Caption := 'Informe o endereço do computador que você gostaria de acessar.';
  FRemoteSubtitle.Font.Size := 8;
  FRemoteSubtitle.Font.Color := RGBToColor(100, 116, 139);
  FRemoteSubtitle.Transparent := True;

  FTarget := TEdit.Create(Self);
  FTarget.Parent := FRemoteDeskCard;
  FTarget.SetBounds(18, 60, 360, 28);
  FTarget.Font.Size := 11;
  FTarget.MaxLength := 10;
  FTarget.TextHint := 'Informe o ID ou Apelido remoto';

  FBtnSaveFav := TButton.Create(Self);
  FBtnSaveFav.Parent := FRemoteDeskCard;
  FBtnSaveFav.SetBounds(176, 94, 102, 30);
  FBtnSaveFav.Caption := 'Salvar Favorito';
  FBtnSaveFav.OnClick := @SaveFavClick;

  FBtnConnect := TButton.Create(Self);
  FBtnConnect.Parent := FRemoteDeskCard;
  FBtnConnect.SetBounds(286, 94, 92, 30);
  FBtnConnect.Caption := 'Conectar';
  FBtnConnect.Font.Style := [fsBold];
  FBtnConnect.OnClick := @ConnectClick;

  // Card 2: Discovery Card
  FDiscoveryCard := TPanel.Create(Self);
  FDiscoveryCard.Parent := FTopCardsPanel;
  FDiscoveryCard.SetBounds(435, 10, 310, 135);
  FDiscoveryCard.BevelOuter := bvNone;
  FDiscoveryCard.Color := RGBToColor(25, 118, 210);

  FDiscTitle := TLabel.Create(Self);
  FDiscTitle.Parent := FDiscoveryCard;
  FDiscTitle.SetBounds(16, 12, 280, 20);
  FDiscTitle.Caption := 'Descoberta / Servidor';
  FDiscTitle.Font.Size := 11;
  FDiscTitle.Font.Style := [fsBold];
  FDiscTitle.Font.Color := clWhite;
  FDiscTitle.Transparent := True;

  FDiscSubtitle := TLabel.Create(Self);
  FDiscSubtitle.Parent := FDiscoveryCard;
  FDiscSubtitle.SetBounds(16, 36, 280, 50);
  FDiscSubtitle.Caption := 'Conectado à API MaurinDesk na nuvem. Sessões gerenciadas por consentimento.';
  FDiscSubtitle.Font.Size := 8;
  FDiscSubtitle.Font.Color := RGBToColor(224, 242, 254);
  FDiscSubtitle.WordWrap := True;
  FDiscSubtitle.Transparent := True;

  FDiscServerLabel := TLabel.Create(Self);
  FDiscServerLabel.Parent := FDiscoveryCard;
  FDiscServerLabel.SetBounds(16, 90, 280, 38);
  FDiscServerLabel.Caption := 'API: /MaurinDesk/api';
  FDiscServerLabel.Font.Size := 8;
  FDiscServerLabel.Font.Color := clWhite;
  FDiscServerLabel.WordWrap := True;
  FDiscServerLabel.Transparent := True;

  // -------------------------------------------------------------
  // 5. LOG CONSOLE PANEL AT THE BOTTOM (Visual Connection Log)
  // -------------------------------------------------------------
  FLogPanel := TPanel.Create(Self);
  FLogPanel.Parent := FContentArea;
  FLogPanel.Align := alBottom;
  FLogPanel.Height := 155;
  FLogPanel.BevelOuter := bvNone;
  FLogPanel.Color := RGBToColor(241, 245, 249);

  FLogHeader := TPanel.Create(Self);
  FLogHeader.Parent := FLogPanel;
  FLogHeader.Align := alTop;
  FLogHeader.Height := 28;
  FLogHeader.BevelOuter := bvNone;
  FLogHeader.Color := RGBToColor(241, 245, 249);

  FLogTitleLabel := TLabel.Create(Self);
  FLogTitleLabel.Parent := FLogHeader;
  FLogTitleLabel.SetBounds(12, 6, 240, 16);
  FLogTitleLabel.ShowAccelChar := False;
  FLogTitleLabel.Caption := 'REGISTRO DE CONEXÃO E REDE (LOG)';
  FLogTitleLabel.Font.Size := 8;
  FLogTitleLabel.Font.Style := [fsBold];
  FLogTitleLabel.Font.Color := RGBToColor(71, 85, 105);

  FBtnTestConn := TButton.Create(Self);
  FBtnTestConn.Parent := FLogHeader;
  FBtnTestConn.SetBounds(310, 2, 95, 24);
  FBtnTestConn.Anchors := [akTop, akRight];
  FBtnTestConn.Caption := 'Testar Conexão';
  FBtnTestConn.OnClick := @TestConnClick;

  FBtnSendLog := TButton.Create(Self);
  FBtnSendLog.Parent := FLogHeader;
  FBtnSendLog.SetBounds(410, 2, 145, 24);
  FBtnSendLog.Anchors := [akTop, akRight];
  FBtnSendLog.Caption := 'Enviar Log ao Servidor';
  FBtnSendLog.OnClick := @SendLogClick;

  FBtnCopyLog := TButton.Create(Self);
  FBtnCopyLog.Parent := FLogHeader;
  FBtnCopyLog.SetBounds(560, 2, 75, 24);
  FBtnCopyLog.Anchors := [akTop, akRight];
  FBtnCopyLog.Caption := 'Copiar Log';
  FBtnCopyLog.OnClick := @CopyLogClick;

  FBtnClearLog := TButton.Create(Self);
  FBtnClearLog.Parent := FLogHeader;
  FBtnClearLog.SetBounds(640, 2, 60, 24);
  FBtnClearLog.Anchors := [akTop, akRight];
  FBtnClearLog.Caption := 'Limpar';
  FBtnClearLog.OnClick := @ClearLogClick;

  FLogMemo := TMemo.Create(Self);
  FLogMemo.Parent := FLogPanel;
  FLogMemo.Align := alClient;
  FLogMemo.Color := RGBToColor(15, 23, 42); // Dark terminal slate
  FLogMemo.Font.Name := 'Consolas';
  FLogMemo.Font.Size := 9;
  FLogMemo.Font.Color := RGBToColor(241, 245, 249);
  FLogMemo.ReadOnly := True;
  FLogMemo.ScrollBars := ssAutoBoth;
  FLogMemo.BorderStyle := bsNone;

  // Active Session Panel (Above Log)
  FActiveSessionPanel := TPanel.Create(Self);
  FActiveSessionPanel.Parent := FContentArea;
  FActiveSessionPanel.Align := alBottom;
  FActiveSessionPanel.Height := 46;
  FActiveSessionPanel.BevelOuter := bvNone;
  FActiveSessionPanel.Color := RGBToColor(220, 252, 231);
  FActiveSessionPanel.Visible := False;

  FActiveSessionText := TLabel.Create(Self);
  FActiveSessionText.Parent := FActiveSessionPanel;
  FActiveSessionText.SetBounds(18, 14, 480, 20);
  FActiveSessionText.Caption := 'Sessão ativa.';
  FActiveSessionText.Font.Style := [fsBold];
  FActiveSessionText.Font.Color := RGBToColor(22, 101, 52);

  FBtnStop := TButton.Create(Self);
  FBtnStop.Parent := FActiveSessionPanel;
  FBtnStop.SetBounds(510, 8, 140, 30);
  FBtnStop.Caption := 'Encerrar Sessão';
  FBtnStop.OnClick := @StopClick;

  // Incoming Consent Alert Panel (Above Active/Log)
  FIncomingPanel := TPanel.Create(Self);
  FIncomingPanel.Parent := FContentArea;
  FIncomingPanel.Align := alBottom;
  FIncomingPanel.Height := 65;
  FIncomingPanel.BevelOuter := bvNone;
  FIncomingPanel.Color := RGBToColor(254, 243, 199);
  FIncomingPanel.Visible := False;

  FIncomingText := TLabel.Create(Self);
  FIncomingText.Parent := FIncomingPanel;
  FIncomingText.SetBounds(18, 12, 380, 40);
  FIncomingText.Caption := 'Solicitação de conexão recebida!';
  FIncomingText.Font.Style := [fsBold];
  FIncomingText.Font.Color := RGBToColor(146, 64, 14);
  FIncomingText.WordWrap := True;

  FBtnAcceptControl := TButton.Create(Self);
  FBtnAcceptControl.Parent := FIncomingPanel;
  FBtnAcceptControl.SetBounds(410, 16, 130, 32);
  FBtnAcceptControl.Caption := 'Permitir Controle';
  FBtnAcceptControl.OnClick := @AcceptControlClick;

  FBtnAcceptView := TButton.Create(Self);
  FBtnAcceptView.Parent := FIncomingPanel;
  FBtnAcceptView.SetBounds(548, 16, 110, 32);
  FBtnAcceptView.Caption := 'Só Visualizar';
  FBtnAcceptView.OnClick := @AcceptViewClick;

  FBtnReject := TButton.Create(Self);
  FBtnReject.Parent := FIncomingPanel;
  FBtnReject.SetBounds(666, 16, 90, 32);
  FBtnReject.Caption := 'Recusar';
  FBtnReject.OnClick := @RejectClick;

  // Recent Sessions Header
  FRecentHeaderPanel := TPanel.Create(Self);
  FRecentHeaderPanel.Parent := FContentArea;
  FRecentHeaderPanel.Align := alTop;
  FRecentHeaderPanel.Height := 32;
  FRecentHeaderPanel.BevelOuter := bvNone;
  FRecentHeaderPanel.Color := RGBToColor(245, 246, 248);

  FRecentTitle := TLabel.Create(Self);
  FRecentTitle.Parent := FRecentHeaderPanel;
  FRecentTitle.SetBounds(22, 8, 140, 18);
  FRecentTitle.Caption := 'SESSÕES RECENTES';
  FRecentTitle.Font.Size := 9;
  FRecentTitle.Font.Style := [fsBold];
  FRecentTitle.Font.Color := RGBToColor(100, 116, 139);

  FRecentHint := TLabel.Create(Self);
  FRecentHint.Parent := FRecentHeaderPanel;
  FRecentHint.SetBounds(170, 9, 350, 18);
  FRecentHint.Caption := '• Duplo clique no cartão para conectar';
  FRecentHint.Font.Size := 8;
  FRecentHint.Font.Color := RGBToColor(148, 163, 184);

  // Cards ScrollBox (Fills remaining space in FContentArea)
  FCardsScrollBox := TScrollBox.Create(Self);
  FCardsScrollBox.Parent := FContentArea;
  FCardsScrollBox.Align := alClient;
  FCardsScrollBox.BorderStyle := bsNone;
  FCardsScrollBox.Color := RGBToColor(245, 246, 248);

  UpdateServerLabels;
  LoadFavorites;
  ApplyLanguage;

  // Initial Log messages
  LogMsg('MaurinDesk v0.5.0 (Build 2026-11-11) inicializado.');
  LogMsg('Servidor configurado: ' + FURL);
  LogMsg('Perfil local: ' + FProfile);

  // Assegura automaticamente as regras do Windows Firewall (porta de streaming e binário)
  if EnsureFirewallRule(NeedsElev, FStreamPort) then begin
    if NeedsElev then
      LogMsg('[FIREWALL] Solicitada liberação automática do Windows Firewall (UAC).')
    else
      LogMsg('[FIREWALL] Porta TCP ' + IntToStr(FStreamPort) + ' e aplicativo liberados no Windows Firewall.');
  end else
    LogMsg('[FIREWALL AVISO] Não foi possível registrar regras no Windows Firewall.');

  // Polling timer
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 15000;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := True;

  // Auto-register or test connection on startup
  if FileExists(FIdentityFile) then begin
    LogMsg('Identidade encontrada no disco. Verificando registro...');
    Start(opRegister);
  end else
    LogMsg('Máquina ainda não registrada. Clique em "Registrar / Obter Chave".');
end;

destructor TMainForm.Destroy;
begin
  FClosing := True;
  FTimer.Enabled := False;
  StopStreaming;
  if FWorker <> nil then begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FIncomingIds.Free;
  inherited Destroy;
end;

procedure TMainForm.LogMsg(const Msg: string);
var
  T: string;
begin
  T := FormatDateTime('hh:nn:ss', Now);
  FLogMemo.Lines.Add('[' + T + '] ' + Msg);
  FLogMemo.SelStart := Length(FLogMemo.Text);
end;

function TMainForm.FormatDeskKey(const Key: string): string;
begin
  Result := FormatDeskKeyHelper(Key);
end;

procedure TMainForm.UpdateServerLabels;
begin
  FServerStatusLabel.Caption := 'Servidor: ' + FURL;
  FDiscServerLabel.Caption := 'Servidor: ' + FURL;
end;

procedure TMainForm.LoadConfig;
var
  Ini: TIniFile;
begin
  if FileExists(FConfigFile) then begin
    Ini := TIniFile.Create(FConfigFile);
    try
      FURL := Ini.ReadString('Server', 'URL', FURL);
      FStreamPort := Ini.ReadInteger('Network', 'Port', DEFAULT_DESK_PORT);
      SetDeskLanguage(StrToDeskLang(Ini.ReadString('General', 'Language', 'pt')));
    finally
      Ini.Free;
    end;
  end;
end;

procedure TMainForm.SaveConfig;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FConfigFile);
  try
    Ini.WriteString('Server', 'URL', FURL);
    Ini.WriteInteger('Network', 'Port', FStreamPort);
    Ini.WriteString('General', 'Language', DeskLangToStr(GetDeskLanguage));
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
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
var
  PB: TPaintBox;
  W, H: Integer;
begin
  PB := TPaintBox(Sender);
  W := PB.Width;
  H := PB.Height;

  // Background scenic wallpaper gradient (Blue sky to water/ocean)
  PB.Canvas.GradientFill(Rect(0, 0, W, H), RGBToColor(37, 99, 235), RGBToColor(147, 197, 253), gdVertical);

  // Horizon / mountain silhouettes
  PB.Canvas.Brush.Color := RGBToColor(30, 58, 138);
  PB.Canvas.Pen.Color := RGBToColor(30, 58, 138);
  PB.Canvas.Polygon([Point(0, H), Point(0, H - 28), Point(W div 3, H - 42), Point(2 * W div 3, H - 24), Point(W, H - 34), Point(W, H)]);

  // Status Circle Top-Left (Green = Online / Favorite)
  PB.Canvas.Brush.Color := RGBToColor(34, 197, 94);
  PB.Canvas.Pen.Color := clWhite;
  PB.Canvas.Ellipse(10, 10, 22, 22);

  // Favorite Star Top-Right
  PB.Canvas.Font.Size := 12;
  PB.Canvas.Font.Color := RGBToColor(251, 191, 36);
  PB.Canvas.Brush.Style := bsClear;
  PB.Canvas.TextOut(W - 22, 8, '★');
end;

procedure TMainForm.KeyBoxClick(Sender: TObject);
begin
  if FRawPublicKey <> '' then begin
    Clipboard.AsText := FRawPublicKey;
    LogMsg('Chave ' + FormatDeskKey(FRawPublicKey) + ' copiada para a área de transferência.');
    ShowMessage('Chave ' + FormatDeskKey(FRawPublicKey) + ' copiada para a área de transferência!');
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
  if FBusy or FClosing then Exit;
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
  A: TJSONArray;
  J, PeerObj: TJSONObject;
  State, ReqKey, ReqName, PeerLocalIP, PeerObservedIP: string;
  PeerPort: Integer;
begin
  FBusy := False;
  if FClosing then Exit;

  if W.Failure <> '' then begin
    FStatusMsgLabel.Caption := W.Failure;
    FSidebarStatus.Caption := _T(strStatusCommError);
    FSidebarStatus.Font.Color := RGBToColor(239, 68, 68);
    LogMsg('[FALHA] ' + W.Failure);

    if Pos('403', W.Failure) > 0 then
      LogMsg('[DICA 403] Servidor retornou Acesso Proibido. Certifique-se de que a pasta server/api foi copiada para public_html/MaurinDesk/php/.')
    else if Pos('404', W.Failure) > 0 then
      LogMsg('[DICA 404] URL não encontrada no servidor. Confira a rota configurada em ⚙ Config Servidor.')
    else if (Pos('12007', W.Failure) > 0) or (Pos('12029', W.Failure) > 0) then
      LogMsg('[DICA REDE] Falha ao conectar ao host. Verifique sua conexão com a internet.');

    if W.Operation <> opSendLog then
      SendFailureLogToServer('API_ERROR', W.Failure);

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
      FStatusMsgLabel.Caption := 'Máquina registrada. Chave: ' + FormatDeskKey(FRawPublicKey);
      LogMsg('[SUCESSO] Registrado no servidor! Sua chave é: ' + FormatDeskKey(FRawPublicKey) +
        ' | Token: ' + Copy(FToken, 1, 8) + '...');
    end;

    opPoll: begin
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
        LogMsg('[PEDIDO RECEBIDO] ' + ReqKey + ' (' + ReqName + ') solicitou acesso.');
      end else
        FIncomingPanel.Visible := False;

      J := TJSONObject(W.Data.Find('current_session'));
      if J <> nil then begin
        State := J.Get('state', '');
        FActiveSessionText.Caption := 'Sessão atual: ' + State + ' (Chave: ' + FTarget.Text + ')';
        FActiveSessionPanel.Visible := (State = 'accepted') or (State = 'active') or (State = 'pending');
        LogMsg('[STATUS SESSÃO] Estado atual: ' + State);

        // Se a sessão foi aceita e este computador é o controlador, conecta ao stream e abre o Viewer!
        if (State = 'accepted') and FIsController and (FRemoteViewer = nil) then begin
          PeerObj := TJSONObject(W.Data.Find('peer_endpoint'));
          if PeerObj <> nil then begin
            PeerLocalIP := PeerObj.Get('local_ip', '');
            PeerObservedIP := PeerObj.Get('observed_ip', '');
            PeerPort := PeerObj.Get('port', FStreamPort);

            LogMsg('[STREAM] Solicitando conexão com host (Local: ' + PeerLocalIP + ', Remoto: ' + PeerObservedIP + ':' + IntToStr(PeerPort) + ')...');
            FStreamClient := TDeskStreamClient.Create(PeerObservedIP, PeerPort, PeerLocalIP);
            FStreamClient.OnLog := @HandleStreamLog;
            FRemoteViewer := TfRemoteViewer.CreateViewer(Self, FTarget.Text, True, FStreamClient);
            FRemoteViewer.OnCloseSession := @ViewerClosed;
            FRemoteViewer.Show;
            FStreamClient.Start;
            LogMsg('[VIEWER] Janela do visualizador remoto aberta!');
          end else begin
            if W.Data.Find('peer_endpoint_error') <> nil then
              LogMsg('[STREAM] Aguardando endpoint do host: ' + W.Data.Get('peer_endpoint_error', ''))
            else
              LogMsg('[STREAM] Aguardando o host anunciar seu endpoint de rede...');
          end;
        end;

        // Se a sessão foi aceita e este computador é o host, garante que o stream server está ativo
        if (State = 'accepted') and not FIsController and (FStreamServer = nil) then begin
          FStreamServer := TDeskStreamServer.Create(FStreamPort, True);
          FStreamServer.OnLog := @HandleStreamLog;
          FStreamServer.Start;
        end;

        if (State = 'closed') or (State = 'expired') or (State = 'rejected') or (State = 'cancelled') then begin
          FSessionId := '';
          FActiveSessionPanel.Visible := False;
          StopStreaming;
        end;
      end else begin
        FActiveSessionPanel.Visible := False;
        StopStreaming;
      end;

      FStatusMsgLabel.Caption := 'Online. ' + IntToStr(A.Count) + ' pedido(s) pendente(s).';
      LogMsg('[HEARTBEAT OK] Presença renovada. ' + IntToStr(A.Count) + ' pedido(s) pendente(s).');
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
      FSessionId := W.Data.Get('id', '');
      FActiveSessionText.Caption := 'Sessão: ' + W.Data.Get('state', '') + ' (Conectado)';
      FActiveSessionPanel.Visible := True;
      FIncomingPanel.Visible := False;
      FStatusMsgLabel.Caption := 'Sessão iniciada: ' + W.Data.Get('state', '');
      LogMsg('[CONECTADO] Sessão ID ' + FSessionId + ' iniciada. Estado: ' + W.Data.Get('state', ''));

      // Inicia servidor de captura de tela no Host
      if FStreamServer = nil then begin
        FStreamServer := TDeskStreamServer.Create(FStreamPort, W.Operation = opAcceptControl);
        FStreamServer.OnLog := @HandleStreamLog;
        FStreamServer.Start;
      end;
    end;

    opReject: begin
      FIncomingPanel.Visible := False;
      FStatusMsgLabel.Caption := 'Pedido recusado.';
      LogMsg('[CONSENTIMENTO] Pedido de acesso remoto foi recusado.');
    end;

    opClose: begin
      FSessionId := '';
      FActiveSessionPanel.Visible := False;
      StopStreaming;
      FStatusMsgLabel.Caption := 'Sessão encerrada.';
      LogMsg('[SESSÃO] Sessão encerrada com sucesso.');
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
end;

procedure TMainForm.AcceptControlClick(Sender: TObject);
begin
  if FIncomingIds.Count > 0 then begin
    LogMsg('Autorizando conexão com permissões completas (mouse e teclado)...');
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
  StopStreaming;
  if FSessionId <> '' then begin
    LogMsg('Encerrando sessão ativa ' + FSessionId + '...');
    Start(opClose, FSessionId);
  end;
end;

procedure TMainForm.ViewerClosed(Sender: TObject);
begin
  LogMsg('[VIEWER] Janela do visualizador foi fechada.');
  FRemoteViewer := nil;
  StopStreaming;
  if FSessionId <> '' then
    Start(opClose, FSessionId);
end;

procedure TMainForm.StopStreaming;
begin
  if FRemoteViewer <> nil then begin
    FRemoteViewer.OnCloseSession := nil;
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
  FIsController := False;
end;

procedure TMainForm.HandleStreamLog(Sender: TObject; const Msg: string);
begin
  LogMsg(Msg);
  if (Pos('[STREAM CLIENT ERRO]', Msg) > 0) or (Pos('Falha ao conectar', Msg) > 0) then begin
    SendFailureLogToServer('STREAM_ERROR', Msg);
    if FRemoteViewer <> nil then
      FRemoteViewer.SetErrorMessage(Msg);
  end;
end;

procedure TMainForm.ApplyLanguage;
begin
  Caption := _T(strAppTitle);
  if FTabLabel <> nil then FTabLabel.Caption := _T(strTabNewConnection);
  if FBtnSettings <> nil then FBtnSettings.Caption := _T(strBtnSettings);
  if FBtnLang <> nil then FBtnLang.Caption := '🌐 ' + UpperCase(DeskLangToStr(GetDeskLanguage));
  if FDeskTitle <> nil then FDeskTitle.Caption := _T(strThisDeskTitle);
  if FDeskSubtitle <> nil then FDeskSubtitle.Caption := _T(strThisDeskSubtitle);
  if FBtnRegister <> nil then FBtnRegister.Caption := _T(strBtnRegister);
  if FRemoteTitle <> nil then FRemoteTitle.Caption := _T(strRemoteDeskTitle);
  if FRemoteSubtitle <> nil then FRemoteSubtitle.Caption := _T(strRemoteDeskSubtitle);
  if FTarget <> nil then FTarget.TextHint := _T(strTargetHint);
  if FBtnConnect <> nil then FBtnConnect.Caption := _T(strBtnConnect);
  if FBtnSaveFav <> nil then FBtnSaveFav.Caption := _T(strBtnSaveFav);
  if FDiscTitle <> nil then FDiscTitle.Caption := _T(strDiscoveryTitle);
  if FDiscSubtitle <> nil then FDiscSubtitle.Caption := _T(strDiscoverySubtitle);
  if FRecentTitle <> nil then FRecentTitle.Caption := _T(strRecentTitle);
  if FRecentHint <> nil then FRecentHint.Caption := _T(strRecentHint);
  if FBtnAcceptControl <> nil then FBtnAcceptControl.Caption := _T(strBtnAcceptControl);
  if FBtnAcceptView <> nil then FBtnAcceptView.Caption := _T(strBtnAcceptView);
  if FBtnReject <> nil then FBtnReject.Caption := _T(strBtnReject);
  if FBtnStop <> nil then FBtnStop.Caption := _T(strBtnEndSession);
  if FLogTitleLabel <> nil then FLogTitleLabel.Caption := _T(strLogTitle);
  if FBtnTestConn <> nil then FBtnTestConn.Caption := _T(strBtnTestConn);
  if FBtnCopyLog <> nil then FBtnCopyLog.Caption := _T(strBtnCopyLog);
  if FBtnClearLog <> nil then FBtnClearLog.Caption := _T(strBtnClearLog);
  if FBtnSendLog <> nil then FBtnSendLog.Caption := _T(strBtnSendLog);
  if FBannerTagLabel <> nil then FBannerTagLabel.Caption := _T(strBannerTagline);
  if FBannerBuildLabel <> nil then FBannerBuildLabel.Caption := _T(strBannerBuild);
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
var
  NewURL, PortChoice, LangChoice: string;
  NewPort: Integer;
begin
  NewURL := InputBox(_T(strDialogSettingsTitle), _T(strDialogServerPrompt), FURL);
  NewURL := Trim(NewURL);
  if (NewURL <> '') and (NewURL <> FURL) then begin
    FURL := NewURL;
    SaveConfig;
    UpdateServerLabels;
    FProfile := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + MD5Print(MD5String(FURL)) + DirectorySeparator;
    ForceDirectories(FProfile);
    FIdentityFile := FProfile + 'identity.dat';
    FToken := '';
    FRawPublicKey := '';
    FKeyTextLabel.Caption := '--- --- ---';
    FSidebarStatus.Caption := _T(strStatusServerChanged);
    LogMsg('[CONFIG] Servidor alterado para: ' + FURL);
  end;

  PortChoice := InputBox(_T(strDialogSettingsTitle), 'Porta TCP de Streaming P2P (padrão: 7071):', IntToStr(FStreamPort));
  if TryStrToInt(Trim(PortChoice), NewPort) and (NewPort > 0) and (NewPort < 65536) then begin
    if NewPort <> FStreamPort then begin
      FStreamPort := NewPort;
      SaveConfig;
      LogMsg('[CONFIG] Porta de streaming alterada para: ' + IntToStr(FStreamPort));
    end;
  end;

  LangChoice := InputBox(_T(strDialogLanguageTitle), _T(strDialogLanguagePrompt), DeskLangToStr(GetDeskLanguage));
  if Trim(LangChoice) <> '' then begin
    SetDeskLanguage(StrToDeskLang(LangChoice));
    SaveConfig;
    ApplyLanguage;
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
  Key := FTarget.Text;
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
var
  Ini: TIniFile;
  Keys: TStringList;
  I, CardX, CardY, CardW, CardH, Spacing: Integer;
  CardPanel, BottomPanel: TPanel;
  Thumb: TPaintBox;
  LblKey, LblAlias, LblMenu: TLabel;
  CardKey, CardAlias: string;
begin
  while FCardsScrollBox.ControlCount > 0 do
    FCardsScrollBox.Controls[0].Free;

  Ini := TIniFile.Create(FProfile + 'favorites.ini');
  Keys := TStringList.Create;
  try
    Ini.ReadSection('favorites', Keys);
    CardW := 190;
    CardH := 148;
    Spacing := 16;

    if Keys.Count = 0 then begin
      with TLabel.Create(FCardsScrollBox) do begin
        Parent := FCardsScrollBox;
        SetBounds(24, 20, 500, 30);
        Caption := 'Nenhuma sessão recente. Digite uma chave e clique em "Salvar Favorito" ou "Conectar".';
        Font.Color := RGBToColor(148, 163, 184);
        Font.Size := 9;
      end;
      Exit;
    end;

    for I := 0 to Keys.Count - 1 do begin
      CardKey := Keys[I];
      CardAlias := Ini.ReadString('favorites', CardKey, CardKey);

      CardX := 20 + I * (CardW + Spacing);
      CardY := 10;

      CardPanel := TPanel.Create(FCardsScrollBox);
      CardPanel.Parent := FCardsScrollBox;
      CardPanel.SetBounds(CardX, CardY, CardW, CardH);
      CardPanel.BevelOuter := bvNone;
      CardPanel.Color := clWhite;
      CardPanel.Cursor := crHandPoint;
      CardPanel.OnClick := @CardClick;
      CardPanel.OnDblClick := @CardDblClick;
      CardPanel.Hint := CardKey;

      Thumb := TPaintBox.Create(CardPanel);
      Thumb.Parent := CardPanel;
      Thumb.SetBounds(0, 0, CardW, 95);
      Thumb.OnPaint := @DrawCardThumbnail;
      Thumb.OnClick := @CardClick;
      Thumb.OnDblClick := @CardDblClick;
      Thumb.Cursor := crHandPoint;
      Thumb.Hint := CardKey;

      BottomPanel := TPanel.Create(CardPanel);
      BottomPanel.Parent := CardPanel;
      BottomPanel.SetBounds(0, 95, CardW, 53);
      BottomPanel.BevelOuter := bvNone;
      BottomPanel.Color := clWhite;
      BottomPanel.OnClick := @CardClick;
      BottomPanel.OnDblClick := @CardDblClick;
      BottomPanel.Cursor := crHandPoint;
      BottomPanel.Hint := CardKey;

      LblKey := TLabel.Create(BottomPanel);
      LblKey.Parent := BottomPanel;
      LblKey.SetBounds(10, 8, CardW - 35, 18);
      LblKey.Caption := FormatDeskKey(CardKey);
      LblKey.Font.Style := [fsBold];
      LblKey.Font.Size := 10;
      LblKey.Font.Color := RGBToColor(30, 41, 59);
      LblKey.OnClick := @CardClick;
      LblKey.OnDblClick := @CardDblClick;
      LblKey.Cursor := crHandPoint;

      LblAlias := TLabel.Create(BottomPanel);
      LblAlias.Parent := BottomPanel;
      LblAlias.SetBounds(10, 28, CardW - 35, 16);
      LblAlias.Caption := CardAlias;
      LblAlias.Font.Size := 8;
      LblAlias.Font.Color := RGBToColor(100, 116, 139);
      LblAlias.OnClick := @CardClick;
      LblAlias.OnDblClick := @CardDblClick;
      LblAlias.Cursor := crHandPoint;

      LblMenu := TLabel.Create(BottomPanel);
      LblMenu.Parent := BottomPanel;
      LblMenu.SetBounds(CardW - 22, 16, 16, 20);
      LblMenu.Caption := '⋮';
      LblMenu.Font.Size := 12;
      LblMenu.Font.Style := [fsBold];
      LblMenu.Font.Color := RGBToColor(148, 163, 184);
      LblMenu.Cursor := crHandPoint;
      LblMenu.Hint := CardKey;
      LblMenu.OnClick := @CardClick;
    end;
  finally
    Keys.Free;
    Ini.Free;
  end;
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

procedure TMainForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FBusy;
  if FBusy then begin
    LogMsg('[AVISO] Aguarde a operação atual terminar antes de fechar.');
    ShowMessage('Aguarde a operação em andamento terminar para fechar.');
  end;
  if CanClose and (FSessionId <> '') then begin
    Start(opClose, FSessionId);
    CanClose := False;
  end;
end;

end.
