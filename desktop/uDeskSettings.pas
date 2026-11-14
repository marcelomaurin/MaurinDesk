unit uDeskSettings;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Forms, setmain;
function EditDeskSettings(Settings: TSetMain): Boolean;
procedure RenderSettingsPreview(Settings: TSetMain; const Filename: string);
implementation
uses Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Dialogs, Graphics, uDeskUI, uDeskInstall;
type
  TDeskSettingsForm = class(TForm)
  private
    FSettings: TSetMain;
    FURL, FPort: TEdit;
    FLanguage: TComboBox;
    FStartup, FTray, FUpdates: TCheckBox;
    FInstallation: TLabel;
    procedure SaveClick(Sender: TObject);
    procedure InstallClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public constructor CreateSettings(Settings: TSetMain);
  end;
constructor TDeskSettingsForm.CreateSettings(Settings: TSetMain);
  procedure LabelAt(const Text: string; X,Y,W,H,Size: Integer; Bold: Boolean = False);
  var L: TLabel;
  begin L := TLabel.Create(Self); L.Parent := Self; L.SetBounds(X,Y,W,H); L.AutoSize := False; L.Caption := Text;
    L.Font.Size := Size; L.Font.Color := RGBToColor(44,53,69); if Bold then L.Font.Style := [fsBold]; end;
  function CheckAt(const Text: string; Y: Integer; Checked: Boolean): TCheckBox;
  begin Result := TCheckBox.Create(Self); Result.Parent := Self; Result.SetBounds(28,Y,540,26); Result.Caption := Text; Result.Checked := Checked; end;
var Btn: TDeskButton;
begin
  inherited CreateNew(nil); FSettings := Settings; Caption := 'Configurações do MaurinDesk';
  Position := poScreenCenter; BorderStyle := bsDialog; ClientWidth := 610; ClientHeight := 620;
  Font.Name := 'Segoe UI'; Font.Size := 10; Color := RGBToColor(248,249,252);
  LabelAt('Configurações',28,22,550,36,22,True);
  LabelAt('Inicialização e comportamento',28,80,550,26,12,True);
  FStartup := CheckAt('Iniciar com o Windows, na área do relógio',119,Settings.StartWithWindows);
  FTray := CheckAt('Continuar na área do relógio ao fechar a janela',154,Settings.MinimizeToTray);
  FUpdates := CheckAt('Baixar e instalar novas versões automaticamente',189,Settings.AutoUpdate);
  LabelAt('Conexão e idioma',28,236,550,24,12,True);
  LabelAt('Servidor HTTPS',28,276,400,20,9);
  FURL := TEdit.Create(Self); FURL.Parent := Self; FURL.SetBounds(28,301,550,30); FURL.Text := Settings.ServerURL;
  LabelAt('Porta P2P',28,345,150,20,9); LabelAt('Idioma',220,345,220,20,9);
  FPort := TEdit.Create(Self); FPort.Parent := Self; FPort.SetBounds(28,369,150,30); FPort.Text := IntToStr(Settings.StreamPort);
  FLanguage := TComboBox.Create(Self); FLanguage.Parent := Self; FLanguage.SetBounds(220,369,220,30); FLanguage.Style := csDropDownList;
  FLanguage.Items.Add('Português'); FLanguage.Items.Add('English'); FLanguage.Items.Add('Español'); FLanguage.ItemIndex := 0;
  if Settings.Language='en' then FLanguage.ItemIndex := 1 else if Settings.Language='es' then FLanguage.ItemIndex := 2;
  Btn := TDeskButton.Create(Self); Btn.Parent := Self; Btn.SetBounds(28,433,220,40); Btn.Caption := 'Instalar neste computador'; Btn.OnClick := @InstallClick;
  FInstallation := TLabel.Create(Self); FInstallation.Parent := Self; FInstallation.AutoSize := False; FInstallation.WordWrap := True;
  FInstallation.SetBounds(28,485,550,44); FInstallation.Font.Size := 9;
  FInstallation.Caption := 'Copia o MaurinDesk para a pasta do usuário e cria um atalho no menu Iniciar.';
  if Settings.InstallDirectory<>'' then FInstallation.Caption := 'Instalado em: '+Settings.InstallDirectory;
  Btn := TDeskButton.Create(Self); Btn.Parent := Self; Btn.SetBounds(300,556,130,40); Btn.Caption := 'Cancelar'; Btn.OnClick := @CancelClick;
  Btn := TDeskButton.Create(Self); Btn.Parent := Self; Btn.SetBounds(446,556,132,40); Btn.Caption := 'Salvar'; Btn.Primary := True; Btn.OnClick := @SaveClick;
end;
procedure TDeskSettingsForm.CancelClick(Sender: TObject);
begin ModalResult := mrCancel; end;
procedure TDeskSettingsForm.InstallClick(Sender: TObject);
var Exe: string;
begin
  try Exe := InstallMaurinDesk; FSettings.InstallDirectory := ExtractFileDir(Exe); FSettings.Save;
    if FSettings.StartWithWindows then ConfigureWindowsStartup(True,Exe);
    FInstallation.Caption := 'Instalado em: '+FSettings.InstallDirectory;
  except on E: Exception do ShowMessage(E.Message); end;
end;
procedure TDeskSettingsForm.SaveClick(Sender: TObject);
var Port: Integer; URL, Exe: string;
begin
  URL := Trim(FURL.Text);
  if (Copy(LowerCase(URL),1,8)<>'https://') or (Pos('?',URL)>0) or (Pos('#',URL)>0) then begin ShowMessage('Informe um endereço HTTPS válido.'); Exit; end;
  if not TryStrToInt(FPort.Text,Port) or (Port<1024) or (Port>65535) then begin ShowMessage('Informe uma porta entre 1024 e 65535.'); Exit; end;
  try
    Exe := ParamStr(0); if FSettings.InstallDirectory<>'' then Exe := IncludeTrailingPathDelimiter(FSettings.InstallDirectory)+'MaurinDesk.exe';
    if FStartup.Checked and not FileExists(Exe) then raise Exception.Create('Instale o aplicativo antes de ativar a inicialização');
    ConfigureWindowsStartup(FStartup.Checked,Exe);
    FSettings.ServerURL := ExcludeTrailingPathDelimiter(URL); FSettings.StreamPort := Port;
    FSettings.StartWithWindows := FStartup.Checked; FSettings.MinimizeToTray := FTray.Checked; FSettings.AutoUpdate := FUpdates.Checked;
    case FLanguage.ItemIndex of 1: FSettings.Language := 'en'; 2: FSettings.Language := 'es'; else FSettings.Language := 'pt'; end;
    FSettings.Save; ModalResult := mrOK;
  except on E: Exception do ShowMessage(E.Message); end;
end;
function EditDeskSettings(Settings: TSetMain): Boolean;
var Form: TDeskSettingsForm;
begin Form := TDeskSettingsForm.CreateSettings(Settings); try Result := Form.ShowModal=mrOK; finally Form.Free; end; end;
procedure RenderSettingsPreview(Settings: TSetMain; const Filename: string);
var Form: TDeskSettingsForm; Bitmap: TBitmap; PNG: TPortableNetworkGraphic;
begin
  Form:=TDeskSettingsForm.CreateSettings(Settings); Bitmap:=TBitmap.Create; PNG:=TPortableNetworkGraphic.Create;
  try Form.Show; Application.ProcessMessages; Bitmap.SetSize(Form.Width,Form.Height);
    Form.PaintTo(Bitmap.Canvas,0,0); PNG.Assign(Bitmap); PNG.SaveToFile(Filename);
  finally PNG.Free; Bitmap.Free; Form.Free; end;
end;
end.
