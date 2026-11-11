unit uRemoteViewer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, Buttons,
  uDeskStream, uDeskProtocol;

type
  { Janela do visualizador da área de trabalho remota }
  TfRemoteViewer = class(TForm)
  private
    FStreamClient: TDeskStreamClient;
    FRemoteBmp: TBitmap;
    FTopBar: TPanel;
    FPaintBox: TPaintBox;
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
    FOnCloseSession: TNotifyEvent;
    procedure PaintBoxPaint(Sender: TObject);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
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
    property OnCloseSession: TNotifyEvent read FOnCloseSession write FOnCloseSession;
  end;

implementation

constructor TfRemoteViewer.CreateViewer(AOwner: TComponent; const ARemoteKey: string; ACanControl: Boolean; AStreamClient: TDeskStreamClient);
begin
  inherited CreateNew(AOwner);

  FRemoteKey := ARemoteKey;
  FCanControl := ACanControl;
  FStreamClient := AStreamClient;
  FFitToWindow := True;
  FFrameCount := 0;
  FLastFPSTime := GetTickCount64;
  FRemoteBmp := TBitmap.Create;

  Caption := 'MaurinDesk - Conexão Ativa: ' + ARemoteKey;
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
  FStatusLabel.Caption := '● Conectado a: ' + ARemoteKey;

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
  FBtnFit.Caption := 'Ajustar à Janela';
  FBtnFit.OnClick := @BtnFitClick;

  FBtnFullScreen := TSpeedButton.Create(Self);
  FBtnFullScreen.Parent := FTopBar;
  FBtnFullScreen.Left := 540;
  FBtnFullScreen.Top := 7;
  FBtnFullScreen.Width := 110;
  FBtnFullScreen.Height := 28;
  FBtnFullScreen.Caption := 'Tela Cheia';
  FBtnFullScreen.OnClick := @BtnFullScreenClick;

  FBtnDisconnect := TBitBtn.Create(Self);
  FBtnDisconnect.Parent := FTopBar;
  FBtnDisconnect.Left := 660;
  FBtnDisconnect.Top := 7;
  FBtnDisconnect.Width := 120;
  FBtnDisconnect.Height := 28;
  FBtnDisconnect.Caption := 'Desconectar';
  FBtnDisconnect.Font.Color := clRed;
  FBtnDisconnect.Font.Style := [fsBold];
  FBtnDisconnect.OnClick := @BtnDisconnectClick;

  // Área central de renderização
  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := Self;
  FPaintBox.Align := alClient;
  FPaintBox.OnPaint := @PaintBoxPaint;
  FPaintBox.OnMouseMove := @PaintBoxMouseMove;
  FPaintBox.OnMouseDown := @PaintBoxMouseDown;
  FPaintBox.OnMouseUp := @PaintBoxMouseUp;
  FPaintBox.OnMouseWheel := @PaintBoxMouseWheel;

  OnKeyDown := @FormKeyDown;
  OnKeyUp := @FormKeyUp;

  if FStreamClient <> nil then
    FStreamClient.OnFrame := @HandleFrameReceived;
end;

destructor TfRemoteViewer.Destroy;
begin
  if FStreamClient <> nil then
    FStreamClient.OnFrame := nil;
  if FRemoteBmp <> nil then
    FreeAndNil(FRemoteBmp);
  inherited Destroy;
end;

procedure TfRemoteViewer.DoClose(var CloseAction: TCloseAction);
begin
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

procedure TfRemoteViewer.PaintBoxPaint(Sender: TObject);
var
  DestR: TRect;
begin
  FPaintBox.Canvas.Brush.Color := $1E1E2E;
  FPaintBox.Canvas.FillRect(0, 0, FPaintBox.Width, FPaintBox.Height);

  if (FRemoteBmp <> nil) and (FRemoteBmp.Width > 0) and (FRemoteBmp.Height > 0) then
  begin
    GetDestRect(DestR);
    FPaintBox.Canvas.StretchDraw(DestR, FRemoteBmp);
  end
  else
  begin
    FPaintBox.Canvas.Font.Color := $A6ADC8;
    FPaintBox.Canvas.TextOut((FPaintBox.Width div 2) - 100, (FPaintBox.Height div 2) - 10,
      'Aguardando transmissão da tela remota...');
  end;
end;

procedure TfRemoteViewer.HandleFrameReceived(Sender: TObject; FrameBmp: TBitmap; FrameId: Cardinal);
var
  NowTime: QWord;
begin
  if (FrameBmp = nil) or (FrameBmp.Width = 0) then Exit;

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
  if not FCanControl or (FStreamClient = nil) then Exit;
  if ScreenToRemote(X, Y, NormX, NormY) then
    FStreamClient.SendMouseMove(NormX, NormY);
end;

procedure TfRemoteViewer.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  NormX, NormY: Word;
  BtnCode: Byte;
begin
  if not FCanControl or (FStreamClient = nil) then Exit;
  if ScreenToRemote(X, Y, NormX, NormY) then
  begin
    case Button of
      mbLeft: BtnCode := 1;
      mbRight: BtnCode := 2;
      mbMiddle: BtnCode := 3;
    else
      Exit;
    end;
    FStreamClient.SendMouseButton(BtnCode, True, NormX, NormY);
  end;
end;

procedure TfRemoteViewer.PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  NormX, NormY: Word;
  BtnCode: Byte;
begin
  if not FCanControl or (FStreamClient = nil) then Exit;
  if ScreenToRemote(X, Y, NormX, NormY) then
  begin
    case Button of
      mbLeft: BtnCode := 1;
      mbRight: BtnCode := 2;
      mbMiddle: BtnCode := 3;
    else
      Exit;
    end;
    FStreamClient.SendMouseButton(BtnCode, False, NormX, NormY);
  end;
end;

procedure TfRemoteViewer.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if not FCanControl or (FStreamClient = nil) then Exit;
  FStreamClient.SendMouseWheel(SmallInt(WheelDelta));
  Handled := True;
end;

procedure TfRemoteViewer.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not FCanControl or (FStreamClient = nil) then Exit;
  FStreamClient.SendKeyEvent(Key, True);
end;

procedure TfRemoteViewer.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not FCanControl or (FStreamClient = nil) then Exit;
  FStreamClient.SendKeyEvent(Key, False);
end;

procedure TfRemoteViewer.BtnFitClick(Sender: TObject);
begin
  FFitToWindow := not FFitToWindow;
  if FFitToWindow then
    FBtnFit.Caption := 'Ajustar à Janela'
  else
    FBtnFit.Caption := 'Tamanho Real (1:1)';
  FPaintBox.Invalidate;
end;

procedure TfRemoteViewer.BtnFullScreenClick(Sender: TObject);
begin
  if WindowState = wsFullScreen then
  begin
    WindowState := wsNormal;
    FBtnFullScreen.Caption := 'Tela Cheia';
    FTopBar.Visible := True;
  end
  else
  begin
    WindowState := wsFullScreen;
    FBtnFullScreen.Caption := 'Sair da Tela Cheia';
  end;
end;

procedure TfRemoteViewer.BtnDisconnectClick(Sender: TObject);
begin
  Close;
end;

end.
