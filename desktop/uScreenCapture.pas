unit uScreenCapture;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  Classes, SysUtils, Graphics;

{ Captura a tela inteira do monitor principal em um TBitmap 24 bits }
function CaptureScreenBitmap(out Bmp: Graphics.TBitmap): Boolean;

{ Converte um TBitmap em fluxo JPEG com compressão configurável (padrão 65%) }
procedure CompressBitmapToJpegStream(Bmp: Graphics.TBitmap; Stream: TStream; Quality: Integer = 65);

{ Simula ações de mouse e teclado no Windows }
procedure InjectMouseMove(NormX, NormY: Word);
procedure InjectMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word);
procedure InjectMouseWheel(Delta: SmallInt);
procedure InjectKeyEvent(VirtualKey: Word; IsDown: Boolean);

implementation

function CaptureScreenBitmap(out Bmp: Graphics.TBitmap): Boolean;
{$IFDEF WINDOWS}
var
  ScreenDC: HDC;
  ScreenWidth, ScreenHeight: Integer;
begin
  Result := False;
  Bmp := nil;
  ScreenWidth := GetSystemMetrics(SM_CXSCREEN);
  ScreenHeight := GetSystemMetrics(SM_CYSCREEN);
  if (ScreenWidth <= 0) or (ScreenHeight <= 0) then Exit;

  Bmp := Graphics.TBitmap.Create;
  Bmp.PixelFormat := pf24bit;
  Bmp.Width := ScreenWidth;
  Bmp.Height := ScreenHeight;

  ScreenDC := GetDC(0);
  if ScreenDC = 0 then
  begin
    FreeAndNil(Bmp);
    Exit;
  end;

  try
    Result := BitBlt(Bmp.Canvas.Handle, 0, 0, ScreenWidth, ScreenHeight, ScreenDC, 0, 0, SRCCOPY);
  finally
    ReleaseDC(0, ScreenDC);
  end;

  if not Result then
    FreeAndNil(Bmp);
end;
{$ELSE}
begin
  Bmp := nil;
  Result := False;
end;
{$ENDIF}

procedure CompressBitmapToJpegStream(Bmp: Graphics.TBitmap; Stream: TStream; Quality: Integer);
var
  Jpg: TJPEGImage;
begin
  if (Bmp = nil) or (Stream = nil) then Exit;
  Jpg := TJPEGImage.Create;
  try
    Jpg.Assign(Bmp);
    Jpg.CompressionQuality := Quality;
    Jpg.SaveToStream(Stream);
  finally
    Jpg.Free;
  end;
end;

procedure InjectMouseMove(NormX, NormY: Word);
{$IFDEF WINDOWS}
var
  PixelsX, PixelsY: Integer;
  ScreenWidth, ScreenHeight: Integer;
begin
  ScreenWidth := GetSystemMetrics(SM_CXSCREEN);
  ScreenHeight := GetSystemMetrics(SM_CYSCREEN);
  PixelsX := Round((NormX / 65535.0) * ScreenWidth);
  PixelsY := Round((NormY / 65535.0) * ScreenHeight);
  SetCursorPos(PixelsX, PixelsY);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure InjectMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word);
{$IFDEF WINDOWS}
var
  Flags: DWORD;
begin
  InjectMouseMove(NormX, NormY);
  Flags := 0;
  case Button of
    1: // Esquerdo
      if IsDown then Flags := MOUSEEVENTF_LEFTDOWN else Flags := MOUSEEVENTF_LEFTUP;
    2: // Direito
      if IsDown then Flags := MOUSEEVENTF_RIGHTDOWN else Flags := MOUSEEVENTF_RIGHTUP;
    3: // Meio
      if IsDown then Flags := MOUSEEVENTF_MIDDLEDOWN else Flags := MOUSEEVENTF_MIDDLEUP;
  end;
  if Flags <> 0 then
    mouse_event(Flags, 0, 0, 0, 0);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure InjectMouseWheel(Delta: SmallInt);
{$IFDEF WINDOWS}
begin
  mouse_event(MOUSEEVENTF_WHEEL, 0, 0, DWORD(Delta), 0);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure InjectKeyEvent(VirtualKey: Word; IsDown: Boolean);
{$IFDEF WINDOWS}
var
  Flags: DWORD;
begin
  Flags := 0;
  if not IsDown then
    Flags := KEYEVENTF_KEYUP;
  keybd_event(Byte(VirtualKey), 0, Flags, 0);
end;
{$ELSE}
begin
end;
{$ENDIF}

end.
