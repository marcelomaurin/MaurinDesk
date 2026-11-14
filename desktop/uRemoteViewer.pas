unit uRemoteViewer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, Buttons, Dialogs, Menus,
  uDeskStream, uDeskRelay, uDeskProtocol, uDeskI18n;

type
  TSendFilesEvent = procedure(Sender: TObject; Paths: TStrings) of object;
  { Janela do visualizador da área de trabalho remota }
  TfRemoteViewer = class(TForm)
  private
    FStreamClient: TDeskStreamClient;
    FRelayClient: TDeskRelayClient;
    FRemoteBmp: TBitmap;
    FTopBar: TPanel;
    FPaintBox: TPaintBox;
    FInputSurface: TPanel;
    FPressedKeys: array[0..255] of Boolean;
    FBtnFiles: TSpeedButton;
    FFilesMenu: TPopupMenu;
    FTransferStatus: TLabel;
    FOnSendFiles: TSendFilesEvent;
    FOnOpenReceived: TNotifyEvent;
    FOnOpenFileManager: TNotifyEvent;
    FCloseReason: string;
    FStatusLabel: TLabel;
    FFPSLabel: TLabel;
    FBtnFit: TSpeedButton;
    FBtnFullScreen: TSpeedButton;
    FBtnDisconnect: TBitBtn;
    FFitToWindow: Boolean;
    FCanControl: Boolean;
    FFrameCount: Integer;
    FLastFPSTime: QWord;
    FRemoteKey: string;
    FErrorMessage: string;
    FOnCloseSession: TNotifyEvent;
    procedure PaintBoxPaint(Sender: TObject);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ViewerShown(Sender: TObject);
    procedure ViewerDeactivated(Sender: TObject);
    procedure ReleaseRemoteKeys;
    procedure FilesMenuClick(Sender: TObject);
    procedure SendFilesClick(Sender: TObject);
    procedure SendFolderClick(Sender: TObject);
    procedure OpenReceivedClick(Sender: TObject);
    procedure BtnFitClick(Sender: TObject);
    procedure BtnFullScreenClick(Sender: TObject);
    procedure BtnDisconnectClick(Sender: TObject);
    procedure HandleFrameReceived(Sender: TObject; FrameBmp: TBitmap; FrameId: Cardinal);
    function ScreenToRemote(X, Y: Integer; out NormX, NormY: Word): Boolean;
    procedure GetDestRect(out R: TRect);
  protected
    procedure DoClose(var CloseAction: TCloseAction); override;
  public
    constructor CreateViewer(AOwner: TComponent; const ARemoteKey: string; ACanControl: Boolean; AStreamClient: TDeskStreamClient);
    destructor Destroy; override;
    procedure SetRelayClient(ARelayClient: TDeskRelayClient);
    procedure DetachClients;
    procedure SetPortConnected(APort: Integer);
    procedure SetErrorMessage(const Msg: string);
    procedure SetTransferStatus(const Msg: string);
    property OnOpenFileManager: TNotifyEvent read FOnOpenFileManager write FOnOpenFileManager;
    property OnSendFiles: TSendFilesEvent read FOnSendFiles write FOnSendFiles;
    property OnOpenReceived: TNotifyEvent read FOnOpenReceived write FOnOpenReceived;
    property CloseReason: string read FCloseReason;
    property OnCloseSession: TNotifyEvent read FOnCloseSession write FOnCloseSession;
  end;

implementation

constructor TfRemoteViewer.CreateViewer(AOwner: TComponent; const ARemoteKey: string; ACanControl: Boolean; AStreamClient: TDeskStreamClient);
var Item: TMenuItem;
begin
  inherited CreateNew(AOwner);

  FRemoteKey := ARemoteKey;
  FCanControl := ACanControl;
  FCloseReason:='viewer_window_closed';
  FStreamClient := AStreamClient;
  FFitToWindow := True;
  FFrameCount := 0;
  FLastFPSTime := GetTickCount64;
  FRemoteBmp := TBitmap.Create;

  Caption := _T(strViewerActiveConnection) + ARemoteKey;
  Width := 1024;
  Height := 720;
  Position := poScreenCenter;
  Color := $1E1E2E;
  KeyPreview := True;

  // Barra de ferramentas superior
  FTopBar := TPanel.Create(Self);
  FTopBar.Parent := Self;
  FTopBar.Align := alTop;
  FTopBar.Height := 42;
  FTopBar.Color := $181825;
  FTopBar.BevelOuter := bvNone;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FTopBar;
  FStatusLabel.Left := 16;
  FStatusLabel.Top := 12;
  FStatusLabel.Font.Color := $CDD6F4;
  FStatusLabel.Font.Style := [fsBold];
  FStatusLabel.Caption := _T(strViewerConnectedTo) + ARemoteKey;

  FFPSLabel := TLabel.Create(Self);
  FFPSLabel.Parent := FTopBar;
  FFPSLabel.Left := 280;
  FFPSLabel.Top := 12;
  FFPSLabel.Font.Color := $A6ADC8;
  FFPSLabel.Caption := '0 FPS';

  FBtnFit := TSpeedButton.Create(Self);
  FBtnFit.Parent := FTopBar;
  FBtnFit.Left := 400;
  FBtnFit.Top := 7;
  FBtnFit.Width := 130;
  FBtnFit.Height := 28;
  FBtnFit.Caption := _T(strViewerFitWindow);
  FBtnFit.OnClick := @BtnFitClick;

  FBtnFullScreen := TSpeedButton.Create(Self);
  FBtnFullScreen.Parent := FTopBar;
  FBtnFullScreen.Left := 540;
  FBtnFullScreen.Top := 7;
  FBtnFullScreen.Width := 110;
  FBtnFullScreen.Height := 28;
  FBtnFullScreen.Caption := _T(strViewerFullScreen);
  FBtnFullScreen.OnClick := @BtnFullScreenClick;

  FBtnDisconnect := TBitBtn.Create(Self);
  FBtnDisconnect.Parent := FTopBar;
  FBtnDisconnect.Left := 660;
  FBtnDisconnect.Top := 7;
  FBtnDisconnect.Width := 120;
  FBtnDisconnect.Height := 28;
  FBtnDisconnect.Caption := _T(strViewerDisconnect);
  FBtnDisconnect.Font.Color := clRed;
  FBtnDisconnect.Font.Style := [fsBold];
  FBtnDisconnect.OnClick := @BtnDisconnectClick;
  FBtnDisconnect.TabStop:=False; FBtnDisconnect.Default:=False; FBtnDisconnect.Cancel:=False;

  FFilesMenu:=TPopupMenu.Create(Self);
  Item:=TMenuItem.Create(FFilesMenu); Item.Caption:='Enviar arquivos...'; Item.OnClick:=@SendFilesClick; FFilesMenu.Items.Add(Item);
  Item:=TMenuItem.Create(FFilesMenu); Item.Caption:='Enviar pasta...'; Item.OnClick:=@SendFolderClick; FFilesMenu.Items.Add(Item);
  Item:=TMenuItem.Create(FFilesMenu); Item.Caption:='Abrir arquivos recebidos'; Item.OnClick:=@OpenReceivedClick; FFilesMenu.Items.Add(Item);
  FBtnFiles:=TSpeedButton.Create(Self); FBtnFiles.Parent:=FTopBar; FBtnFiles.SetBounds(790,7,150,28);
  FBtnFiles.Caption:='Arquivos e pastas'; FBtnFiles.OnClick:=@FilesMenuClick;
  FTransferStatus:=TLabel.Create(Self); FTransferStatus.Parent:=Self; FTransferStatus.Align:=alBottom;
  FTransferStatus.AutoSize:=False; FTransferStatus.Height:=28; FTransferStatus.Font.Color:=clWhite;
  FTransferStatus.Caption:='Arquivos: copie com Ctrl+C ou use "Arquivos e pastas".';

  // Área central de renderização
  FInputSurface:=TPanel.Create(Self); FInputSurface.Parent:=Self; FInputSurface.Align:=alClient;
  FInputSurface.BevelOuter:=bvNone; FInputSurface.Color:=Color; FInputSurface.TabStop:=True;
  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := FInputSurface;
  FPaintBox.Align := alClient;
  FPaintBox.OnPaint := @PaintBoxPaint;
  FPaintBox.OnMouseMove := @PaintBoxMouseMove;
  FPaintBox.OnMouseDown := @PaintBoxMouseDown;
  FPaintBox.OnMouseUp := @PaintBoxMouseUp;
  FPaintBox.OnMouseWheel := @PaintBoxMouseWheel;

  OnKeyDown := @FormKeyDown;
  OnKeyUp := @FormKeyUp;
  OnShow:=@ViewerShown; OnDeactivate:=@ViewerDeactivated;

  if FStreamClient <> nil then
    FStreamClient.OnFrame := @HandleFrameReceived;
end;

destructor TfRemoteViewer.Destroy;
begin
  if FStreamClient <> nil then
    FStreamClient.OnFrame := nil;
  if FRelayClient <> nil then
    FRelayClient.OnFrame := nil;
  if FRemoteBmp <> nil then
    FreeAndNil(FRemoteBmp);
  inherited Destroy;
end;

procedure TfRemoteViewer.SetRelayClient(ARelayClient: TDeskRelayClient);
begin
  FRelayClient := ARelayClient;
  if FRelayClient <> nil then
  begin
    FRelayClient.OnFrame := @HandleFrameReceived;
    FErrorMessage := '';
    FStatusLabel.Caption := 'Aguardando primeira imagem de ' + FRemoteKey + ' (Ponte HTTPS)';
    FStatusLabel.Font.Color := RGBToColor(59, 130, 246);
    FFPSLabel.Caption := 'Ponte HTTP';
    FFPSLabel.Font.Color := RGBToColor(59, 130, 246);
    FPaintBox.Invalidate;
  end;
end;

procedure TfRemoteViewer.DetachClients;
begin
  ReleaseRemoteKeys;
  if FRelayClient<>nil then FRelayClient.OnFrame:=nil;
  if FStreamClient<>nil then FStreamClient.OnFrame:=nil;
  FRelayClient:=nil; FStreamClient:=nil;
end;

procedure TfRemoteViewer.SetPortConnected(APort: Integer);
begin
  FErrorMessage := '';
  FStatusLabel.Caption := '● ' + _T(strViewerConnectedTo) + FRemoteKey + ' (P2P Porta ' + IntToStr(APort) + ')';
  FStatusLabel.Font.Color := RGBToColor(34, 197, 94);
  FPaintBox.Invalidate;
end;

procedure TfRemoteViewer.DoClose(var CloseAction: TCloseAction);
begin
  ReleaseRemoteKeys;
  if Assigned(FOnCloseSession) then
    FOnCloseSession(Self);
  CloseAction := caFree;
  inherited DoClose(CloseAction);
end;

procedure TfRemoteViewer.GetDestRect(out R: TRect);
var
  ScaleX, ScaleY, Scale: Double;
  TargetW, TargetH: Integer;
begin
  if (FRemoteBmp = nil) or (FRemoteBmp.Width = 0) or (FRemoteBmp.Height = 0) then
  begin
    R := Rect(0, 0, FPaintBox.Width, FPaintBox.Height);
    Exit;
  end;

  if FFitToWindow then
  begin
    ScaleX := FPaintBox.Width / FRemoteBmp.Width;
    ScaleY := FPaintBox.Height / FRemoteBmp.Height;
    if ScaleX < ScaleY then
      Scale := ScaleX
    else
      Scale := ScaleY;
    TargetW := Round(FRemoteBmp.Width * Scale);
    TargetH := Round(FRemoteBmp.Height * Scale);
    R.Left := (FPaintBox.Width - TargetW) div 2;
    R.Top := (FPaintBox.Height - TargetH) div 2;
    R.Right := R.Left + TargetW;
    R.Bottom := R.Top + TargetH;
  end
  else
  begin
    R := Rect(0, 0, FRemoteBmp.Width, FRemoteBmp.Height);
  end;
end;

function TfRemoteViewer.ScreenToRemote(X, Y: Integer; out NormX, NormY: Word): Boolean;
var
  R: TRect;
  RelX, RelY: Integer;
begin
  Result := False;
  NormX := 0;
  NormY := 0;
  GetDestRect(R);
  if (X < R.Left) or (X > R.Right) or (Y < R.Top) or (Y > R.Bottom) then Exit;
  if (R.Right - R.Left <= 0) or (R.Bottom - R.Top <= 0) then Exit;

  RelX := X - R.Left;
  RelY := Y - R.Top;
  NormX := Round((RelX / (R.Right - R.Left)) * 65535.0);
  NormY := Round((RelY / (R.Bottom - R.Top)) * 65535.0);
  Result := True;
end;

procedure TfRemoteViewer.SetErrorMessage(const Msg: string);
begin
  FErrorMessage := Msg;
  FStatusLabel.Caption := '● ' + _T(strErrConnectionFailed);
  FStatusLabel.Font.Color := RGBToColor(239, 68, 68);
  FFPSLabel.Caption := 'DESCONECTADO';
  FFPSLabel.Font.Color := RGBToColor(239, 68, 68);
  FPaintBox.Invalidate;
end;

procedure TfRemoteViewer.PaintBoxPaint(Sender: TObject);
var
  DestR: TRect;
  BoxX, BoxY: Integer;
begin
  FPaintBox.Canvas.Brush.Color := $1E1E2E;
  FPaintBox.Canvas.FillRect(0, 0, FPaintBox.Width, FPaintBox.Height);

  if FErrorMessage <> '' then
  begin
    BoxX := (FPaintBox.Width - 620) div 2;
    BoxY := (FPaintBox.Height - 260) div 2;
    if BoxX < 10 then BoxX := 10;
    if BoxY < 10 then BoxY := 10;

    // Fundo do alerta
    FPaintBox.Canvas.Brush.Color := $28181F;
    FPaintBox.Canvas.Pen.Color := $EF4444;
    FPaintBox.Canvas.Rectangle(BoxX, BoxY, BoxX + 620, BoxY + 250);

    FPaintBox.Canvas.Font.Size := 12;
    FPaintBox.Canvas.Font.Style := [fsBold];
    FPaintBox.Canvas.Font.Color := $EF4444;
    FPaintBox.Canvas.TextOut(BoxX + 25, BoxY + 20, '⚠ ' + _T(strErrConnectionFailed));

    FPaintBox.Canvas.Font.Size := 9;
    FPaintBox.Canvas.Font.Style := [];
    FPaintBox.Canvas.Font.Color := $FFFFFF;
    FPaintBox.Canvas.TextOut(BoxX + 25, BoxY + 52, Copy(FErrorMessage, 1, 80));

    FPaintBox.Canvas.Font.Color := $A6ADC8;
    FPaintBox.Canvas.TextOut(BoxX + 25, BoxY + 84, '• Verifique se a máquina remota está conectada e online.');
    FPaintBox.Canvas.TextOut(BoxX + 25, BoxY + 106, '• Confira o envio do primeiro quadro no log do computador remoto.');
    FPaintBox.Canvas.TextOut(BoxX + 25, BoxY + 128, '• Confira o acesso HTTPS ao servidor nas duas maquinas.');
    FPaintBox.Canvas.TextOut(BoxX + 25, BoxY + 150, '• A ponte continua tentando receber a imagem automaticamente.');

    FPaintBox.Canvas.Font.Style := [fsBold];
    FPaintBox.Canvas.Font.Color := $F59E0B;
    FPaintBox.Canvas.TextOut(BoxX + 25, BoxY + 195, 'Clique no botão vermelho "Desconectar" acima para fechar.');
    Exit;
  end;

  if (FRemoteBmp <> nil) and (FRemoteBmp.Width > 0) and (FRemoteBmp.Height > 0) then
  begin
    GetDestRect(DestR);
    FPaintBox.Canvas.StretchDraw(DestR, FRemoteBmp);
  end
  else
  begin
    FPaintBox.Canvas.Font.Size := 10;
    FPaintBox.Canvas.Font.Color := $A6ADC8;
    FPaintBox.Canvas.TextOut((FPaintBox.Width div 2) - 130, (FPaintBox.Height div 2) - 10,
      _T(strViewerWaiting));
  end;
end;

procedure TfRemoteViewer.HandleFrameReceived(Sender: TObject; FrameBmp: TBitmap; FrameId: Cardinal);
var
  NowTime: QWord;
begin
  if (FrameBmp = nil) or (FrameBmp.Width = 0) then Exit;
  FErrorMessage := '';
  FStatusLabel.Caption := '● ' + _T(strViewerConnectedTo) + FRemoteKey;
  FStatusLabel.Font.Color := RGBToColor(34, 197, 94);

  FRemoteBmp.Assign(FrameBmp);
  FPaintBox.Invalidate;

  Inc(FFrameCount);
  NowTime := GetTickCount64;
  if NowTime - FLastFPSTime >= 1000 then
  begin
    FFPSLabel.Caption := IntToStr(FFrameCount) + ' FPS (' + IntToStr(FRemoteBmp.Width) + 'x' + IntToStr(FRemoteBmp.Height) + ')';
    FFrameCount := 0;
    FLastFPSTime := NowTime;
  end;
end;

procedure TfRemoteViewer.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  NormX, NormY: Word;
begin
  if not FCanControl then Exit;
  if ScreenToRemote(X, Y, NormX, NormY) then
  begin
    if FRelayClient <> nil then
      FRelayClient.SendMouseMove(NormX, NormY)
    else if FStreamClient <> nil then
      FStreamClient.SendMouseMove(NormX, NormY);
  end;
end;

procedure TfRemoteViewer.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  NormX, NormY: Word;
  BtnCode: Byte;
begin
  if FInputSurface.CanFocus then FInputSurface.SetFocus;
  if not FCanControl then Exit;
  if ScreenToRemote(X, Y, NormX, NormY) then
  begin
    case Button of
      mbLeft: BtnCode := 1;
      mbRight: BtnCode := 2;
      mbMiddle: BtnCode := 3;
    else
      Exit;
    end;
    if FRelayClient <> nil then
      FRelayClient.SendMouseButton(BtnCode, True, NormX, NormY)
    else if FStreamClient <> nil then
      FStreamClient.SendMouseButton(BtnCode, True, NormX, NormY);
  end;
end;

procedure TfRemoteViewer.PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  NormX, NormY: Word;
  BtnCode: Byte;
begin
  if not FCanControl then Exit;
  if ScreenToRemote(X, Y, NormX, NormY) then
  begin
    case Button of
      mbLeft: BtnCode := 1;
      mbRight: BtnCode := 2;
      mbMiddle: BtnCode := 3;
    else
      Exit;
    end;
    if FRelayClient <> nil then
      FRelayClient.SendMouseButton(BtnCode, False, NormX, NormY)
    else if FStreamClient <> nil then
      FStreamClient.SendMouseButton(BtnCode, False, NormX, NormY);
  end;
end;

procedure TfRemoteViewer.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if not FCanControl then Exit;
  if FRelayClient <> nil then
    FRelayClient.SendMouseWheel(SmallInt(WheelDelta))
  else if FStreamClient <> nil then
    FStreamClient.SendMouseWheel(SmallInt(WheelDelta));
  Handled := True;
end;

procedure TfRemoteViewer.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ActiveControl<>FInputSurface then Exit;
  if not FCanControl then begin Key:=0; Exit; end;
  if Key<=High(FPressedKeys) then FPressedKeys[Key]:=True;
  if FRelayClient <> nil then
    FRelayClient.SendKey(Key, True)
  else if FStreamClient <> nil then
    FStreamClient.SendKeyEvent(Key, True);
  Key:=0; // A remote Enter/space/Tab must never activate a local toolbar button.
end;

procedure TfRemoteViewer.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ActiveControl<>FInputSurface then Exit;
  if not FCanControl then begin Key:=0; Exit; end;
  if Key<=High(FPressedKeys) then FPressedKeys[Key]:=False;
  if FRelayClient <> nil then
    FRelayClient.SendKey(Key, False)
  else if FStreamClient <> nil then
    FStreamClient.SendKeyEvent(Key, False);
  Key:=0;
end;

procedure TfRemoteViewer.ViewerShown(Sender: TObject);
begin ActiveControl:=FInputSurface; if FInputSurface.CanFocus then FInputSurface.SetFocus; end;
procedure TfRemoteViewer.ViewerDeactivated(Sender: TObject);
begin ReleaseRemoteKeys; end;
procedure TfRemoteViewer.ReleaseRemoteKeys;
var K: Integer;
begin
  for K:=0 to High(FPressedKeys) do if FPressedKeys[K] then begin
    if FRelayClient<>nil then FRelayClient.SendKey(K,False)
    else if FStreamClient<>nil then FStreamClient.SendKeyEvent(K,False);
    FPressedKeys[K]:=False;
  end;
end;
procedure TfRemoteViewer.SetTransferStatus(const Msg: string);
begin FTransferStatus.Caption:=Msg; end;
procedure TfRemoteViewer.FilesMenuClick(Sender: TObject);
var P: TPoint;
begin ReleaseRemoteKeys; if Assigned(FOnOpenFileManager) then begin FOnOpenFileManager(Self); Exit; end; P:=FBtnFiles.ClientToScreen(Point(0,FBtnFiles.Height)); FFilesMenu.PopUp(P.X,P.Y); end;
procedure TfRemoteViewer.SendFilesClick(Sender: TObject);
var Dialog: TOpenDialog;
begin
  if not Assigned(FOnSendFiles) then Exit;
  Dialog:=TOpenDialog.Create(Self);
  try Dialog.Title:='Enviar arquivos para o outro computador'; Dialog.Options:=[ofAllowMultiSelect,ofFileMustExist,ofEnableSizing];
    if Dialog.Execute then FOnSendFiles(Self,Dialog.Files);
  finally Dialog.Free; ViewerShown(Self); end;
end;
procedure TfRemoteViewer.SendFolderClick(Sender: TObject);
var Folder: string; Paths: TStringList;
begin
  if not Assigned(FOnSendFiles) then Exit;
  Folder:=''; Paths:=TStringList.Create;
  try if SelectDirectory('Enviar pasta para o outro computador','',Folder) then begin Paths.Add(Folder); FOnSendFiles(Self,Paths); end;
  finally Paths.Free; ViewerShown(Self); end;
end;
procedure TfRemoteViewer.OpenReceivedClick(Sender: TObject);
begin if Assigned(FOnOpenReceived) then FOnOpenReceived(Self); ViewerShown(Self); end;

procedure TfRemoteViewer.BtnFitClick(Sender: TObject);
begin
  FFitToWindow := not FFitToWindow;
  if FFitToWindow then
    FBtnFit.Caption := _T(strViewerFitWindow)
  else
    FBtnFit.Caption := _T(strViewerOriginalSize);
  FPaintBox.Invalidate;
end;

procedure TfRemoteViewer.BtnFullScreenClick(Sender: TObject);
begin
  if WindowState = wsFullScreen then
  begin
    WindowState := wsNormal;
    FBtnFullScreen.Caption := _T(strViewerFullScreen);
    FTopBar.Visible := True;
  end
  else
  begin
    WindowState := wsFullScreen;
    FBtnFullScreen.Caption := _T(strViewerExitFullScreen);
  end;
end;

procedure TfRemoteViewer.BtnDisconnectClick(Sender: TObject);
begin
  FCloseReason:='viewer_disconnect_button';
  Close;
end;

end.
