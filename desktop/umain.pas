unit umain;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  Graphics, Menus, Clipbrd, IniFiles, md5,
  fpjson, jsonparser, airemoteidentity, airemotesignaling;

type
  TMainForm = class;
  TOperation = (opRegister, opPoll, opConnect, opAcceptView, opAcceptControl, opReject, opClose, opHealth);

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
    FBusy, FClosing, FAllowLocal: Boolean;
    FWorker: TAPIWorker;
    FTimer: TTimer;

    // Header Controls
    FTopBar: TPanel;
    FLogoBox: TPaintBox;
    FTabPanel: TPanel;
    FTopSearchPanel: TPanel;
    FTopSearchEdit: TEdit;
    FTopConnectBtn: TPanel;
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
    FBtnClearLog: TButton;
    FBtnCopyLog: TButton;
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
                '0.3.0'
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
          Data := C.Incoming;
          if SessionId <> '' then begin
            J := C.GetSession(SessionId);
            Data.Add('current_session', J);
          end;
        end;

        opConnect: Data := C.RequestSession(RemoteKey, Control);
        opAcceptView: Data := C.Decide(SessionId, True, False);
        opAcceptControl: Data := C.Decide(SessionId, True, True);
        opReject: Data := C.Decide(SessionId, False, False);
        opClose: Data := C.CloseSession(SessionId, 'local_stop');
        opHealth: Data := C.Health;
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
begin
  inherited CreateNew(AOwner);
  Caption := 'MaurinDesk — Conexão Remota Assistida';
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
  with TLabel.Create(Self) do begin
    Parent := FTabPanel;
    SetBounds(14, 10, 115, 20);
    Caption := 'Nova Conexão';
    Font.Style := [fsBold];
    Font.Color := RGBToColor(30, 41, 59);
    Transparent := True;
  end;

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
  FTopSearchEdit.TextHint := 'Informe o ID MaurinDesk ou Apelido';
  FTopSearchEdit.MaxLength := 10;

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

  // Settings Button on right
  FBtnSettings := TButton.Create(Self);
  FBtnSettings.Parent := FTopBar;
  FBtnSettings.SetBounds(830, 6, 130, 32);
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
  FStatusMsgLabel.SetBounds(360, 6, 600, 16);
  FStatusMsgLabel.Caption := 'Pronto.';
  FStatusMsgLabel.Font.Size := 8;
  FStatusMsgLabel.Font.Color := RGBToColor(100, 116, 139);
  FStatusMsgLabel.Transparent := True;

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
  FDeskTitle.SetBounds(18, 16, 200, 22);
  FDeskTitle.Caption := 'Este Computador';
  FDeskTitle.Font.Size := 13;
  FDeskTitle.Font.Style := [fsBold];
  FDeskTitle.Font.Color := RGBToColor(229, 57, 53);

  FDeskSubtitle := TLabel.Create(Self);
  FDeskSubtitle.Parent := FSidebar;
  FDeskSubtitle.SetBounds(18, 40, 195, 34);
  FDeskSubtitle.Caption := 'Seu computador pode ser acessado por este endereço.';
  FDeskSubtitle.Font.Size := 8;
  FDeskSubtitle.Font.Color := RGBToColor(100, 116, 139);
  FDeskSubtitle.WordWrap := True;

  // AnyDesk ID Box
  FKeyBox := TPanel.Create(Self);
  FKeyBox.Parent := FSidebar;
  FKeyBox.SetBounds(18, 80, 200, 48);
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
  FBtnRegister.SetBounds(18, 136, 200, 30);
  FBtnRegister.Caption := 'Registrar / Obter Chave';
  FBtnRegister.OnClick := @RegisterClick;

  FSidebarStatus := TLabel.Create(Self);
  FSidebarStatus.Parent := FSidebar;
  FSidebarStatus.SetBounds(18, 174, 200, 18);
  FSidebarStatus.Caption := '● Não conectado';
  FSidebarStatus.Font.Size := 8;
  FSidebarStatus.Font.Color := RGBToColor(156, 163, 175);

  FBannerPanel := TPanel.Create(Self);
  FBannerPanel.Parent := FSidebar;
  FBannerPanel.Align := alBottom;
  FBannerPanel.Height := 95;
  FBannerPanel.BevelOuter := bvNone;
  FBannerPanel.Color := RGBToColor(239, 68, 68);

  with TLabel.Create(Self) do begin
    Parent := FBannerPanel;
    SetBounds(16, 12, 200, 20);
    Caption := 'MaurinDesk 0.3.0';
    Font.Size := 11;
    Font.Style := [fsBold];
    Font.Color := clWhite;
    Transparent := True;
  end;
  with TLabel.Create(Self) do begin
    Parent := FBannerPanel;
    SetBounds(16, 34, 200, 34);
    Caption := 'Acesso remoto assistido e seguro.'#13#10'maurinsoft.com.br';
    Font.Size := 8;
    Font.Color := RGBToColor(254, 226, 226);
    Transparent := True;
    WordWrap := True;
  end;

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
  FDiscoveryCard.SetBounds(435, 10, 265, 135);
  FDiscoveryCard.BevelOuter := bvNone;
  FDiscoveryCard.Color := RGBToColor(25, 118, 210);

  FDiscTitle := TLabel.Create(Self);
  FDiscTitle.Parent := FDiscoveryCard;
  FDiscTitle.SetBounds(16, 12, 200, 20);
  FDiscTitle.Caption := 'Descoberta / Servidor';
  FDiscTitle.Font.Size := 11;
  FDiscTitle.Font.Style := [fsBold];
  FDiscTitle.Font.Color := clWhite;
  FDiscTitle.Transparent := True;

  FDiscSubtitle := TLabel.Create(Self);
  FDiscSubtitle.Parent := FDiscoveryCard;
  FDiscSubtitle.SetBounds(16, 36, 230, 48);
  FDiscSubtitle.Caption := 'Conectado à API MaurinDesk na nuvem. Sessões gerenciadas por consentimento.';
  FDiscSubtitle.Font.Size := 8;
  FDiscSubtitle.Font.Color := RGBToColor(224, 242, 254);
  FDiscSubtitle.WordWrap := True;
  FDiscSubtitle.Transparent := True;

  FDiscServerLabel := TLabel.Create(Self);
  FDiscServerLabel.Parent := FDiscoveryCard;
  FDiscServerLabel.SetBounds(16, 90, 230, 36);
  FDiscServerLabel.Caption := 'API: /MaurinDesk/php';
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
  FLogPanel.Height := 140;
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
  FLogTitleLabel.SetBounds(12, 6, 280, 16);
  FLogTitleLabel.Caption := 'REGISTRO DE CONEXÃO & REDE (LOG)';
  FLogTitleLabel.Font.Size := 8;
  FLogTitleLabel.Font.Style := [fsBold];
  FLogTitleLabel.Font.Color := RGBToColor(71, 85, 105);

  FBtnTestConn := TButton.Create(Self);
  FBtnTestConn.Parent := FLogHeader;
  FBtnTestConn.SetBounds(420, 2, 115, 24);
  FBtnTestConn.Anchors := [akTop, akRight];
  FBtnTestConn.Caption := 'Testar Conexão';
  FBtnTestConn.OnClick := @TestConnClick;

  FBtnCopyLog := TButton.Create(Self);
  FBtnCopyLog.Parent := FLogHeader;
  FBtnCopyLog.SetBounds(540, 2, 80, 24);
  FBtnCopyLog.Anchors := [akTop, akRight];
  FBtnCopyLog.Caption := 'Copiar Log';
  FBtnCopyLog.OnClick := @CopyLogClick;

  FBtnClearLog := TButton.Create(Self);
  FBtnClearLog.Parent := FLogHeader;
  FBtnClearLog.SetBounds(625, 2, 75, 24);
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

  // Initial Log messages
  LogMsg('MaurinDesk 0.3.0 inicializado.');
  LogMsg('Servidor configurado: ' + FURL);
  LogMsg('Perfil local: ' + FProfile);

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
begin
  if not AIRemoteValidKey(FTarget.Text) then begin
    LogMsg('[AVISO] Digite uma chave remota válida com exatamente 10 dígitos.');
    ShowMessage('Informe uma chave remota válida com exatamente 10 dígitos.');
    Exit;
  end;
  LogMsg('Solicitando conexão para chave: ' + FormatDeskKey(FTarget.Text) + '...');
  Start(opConnect);
end;

procedure TMainForm.TopConnectClick(Sender: TObject);
begin
  if FTopSearchEdit.Text <> '' then
    FTarget.Text := FTopSearchEdit.Text;
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
  if Operation = opPoll then
    FWorker.SessionId := FSessionId;

  case Operation of
    opRegister: LogMsg('[REQ] Registrando máquina em: ' + FURL + '/devices...');
    opPoll: LogMsg('[REQ] Polling presença / pedidos em: ' + FURL + '...');
    opConnect: LogMsg('[REQ] Solicitando sessão para ' + FormatDeskKey(FTarget.Text) + '...');
    opHealth: LogMsg('[REQ] Testando rota /health em: ' + FURL + '...');
    opClose: LogMsg('[REQ] Encerrando sessão ' + Id + '...');
  end;

  FStatusMsgLabel.Caption := 'Comunicando com o servidor...';
  FWorker.Start;
end;

procedure TMainForm.Finished(W: TAPIWorker);
var
  A: TJSONArray;
  J: TJSONObject;
  State, ReqKey, ReqName: string;
begin
  FBusy := False;
  if FClosing then Exit;

  if W.Failure <> '' then begin
    FStatusMsgLabel.Caption := W.Failure;
    FSidebarStatus.Caption := '● Erro de comunicação';
    FSidebarStatus.Font.Color := RGBToColor(239, 68, 68);
    LogMsg('[FALHA] ' + W.Failure);

    if Pos('403', W.Failure) > 0 then
      LogMsg('[DICA 403] Servidor retornou Acesso Proibido. Certifique-se de que a pasta server/api foi copiada para public_html/MaurinDesk/php/.')
    else if Pos('404', W.Failure) > 0 then
      LogMsg('[DICA 404] URL não encontrada no servidor. Confira a rota configurada em ⚙ Config Servidor.')
    else if (Pos('12007', W.Failure) > 0) or (Pos('12029', W.Failure) > 0) then
      LogMsg('[DICA REDE] Falha ao conectar ao host. Verifique sua conexão com a internet.');

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
        if (State = 'closed') or (State = 'expired') or (State = 'rejected') or (State = 'cancelled') then begin
          FSessionId := '';
          FActiveSessionPanel.Visible := False;
        end;
      end else
        FActiveSessionPanel.Visible := False;

      FStatusMsgLabel.Caption := 'Online. ' + IntToStr(A.Count) + ' pedido(s) pendente(s).';
      LogMsg('[HEARTBEAT OK] Presença renovada. ' + IntToStr(A.Count) + ' pedido(s) pendente(s).');
    end;

    opConnect, opAcceptView, opAcceptControl: begin
      FSessionId := W.Data.Get('id', '');
      FActiveSessionText.Caption := 'Sessão: ' + W.Data.Get('state', '') + ' (Conectado)';
      FActiveSessionPanel.Visible := True;
      FIncomingPanel.Visible := False;
      FStatusMsgLabel.Caption := 'Sessão iniciada: ' + W.Data.Get('state', '');
      LogMsg('[CONECTADO] Sessão ID ' + FSessionId + ' iniciada. Estado: ' + W.Data.Get('state', ''));
    end;

    opReject: begin
      FIncomingPanel.Visible := False;
      FStatusMsgLabel.Caption := 'Pedido recusado.';
      LogMsg('[CONSENTIMENTO] Pedido de acesso remoto foi recusado.');
    end;

    opClose: begin
      FSessionId := '';
      FActiveSessionPanel.Visible := False;
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
  if FSessionId <> '' then begin
    LogMsg('Encerrando sessão ativa ' + FSessionId + '...');
    Start(opClose, FSessionId);
  end;
end;

procedure TMainForm.SettingsClick(Sender: TObject);
var
  NewURL: string;
begin
  NewURL := InputBox('Configuração MaurinDesk', 'Endereço da API do Servidor:', FURL);
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
    FSidebarStatus.Caption := '● Servidor alterado';
    LogMsg('[CONFIG] Servidor alterado para: ' + FURL);
    LogMsg('[CONFIG] Clique em "Testar Conexão" ou "Registrar / Obter Chave" para conectar.');
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
