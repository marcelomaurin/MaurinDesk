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
procedure ReleaseAllInputKeys;

implementation

function CaptureScreenBitmap(out Bmp: Graphics.TBitmap): Boolean;
{$IFDEF WINDOWS}
var
  ScreenDC: HDC;
  ScreenWidth, ScreenHeight: Integer;
  CursorInfo: TCursorInfo;
  IconInfo: TIconInfo;
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
    Bmp.Canvas.Changing;
    Result := BitBlt(Bmp.Canvas.Handle, 0, 0, ScreenWidth, ScreenHeight, ScreenDC, 0, 0, SRCCOPY);
    if Result then
    begin
      // Desenha o ponteiro real do mouse sobre a imagem
      FillChar(CursorInfo, SizeOf(CursorInfo), 0);
      CursorInfo.cbSize := SizeOf(CursorInfo);
      if GetCursorInfo(CursorInfo) and (CursorInfo.flags = 1) then
      begin
        FillChar(IconInfo, SizeOf(IconInfo), 0);
        if GetIconInfo(CursorInfo.hCursor, IconInfo) then
        begin
          DrawIconEx(Bmp.Canvas.Handle,
            CursorInfo.ptScreenPos.x - Integer(IconInfo.xHotspot),
            CursorInfo.ptScreenPos.y - Integer(IconInfo.yHotspot),
            CursorInfo.hCursor, 0, 0, 0, 0, DI_NORMAL);
          if IconInfo.hbmMask <> 0 then DeleteObject(IconInfo.hbmMask);
          if IconInfo.hbmColor <> 0 then DeleteObject(IconInfo.hbmColor);
        end;
      end;
      // Native GDI writes bypass TCanvas and leave LCL's raw pixel cache stale.
      // JPEG encoding reads that cache, so publish the completed native writes.
      GdiFlush;
      Bmp.Canvas.Changed;
    end;
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
  {$IFDEF WINDOWS}
  GdiFlush;
  {$ENDIF}
  // Also cover callers which draw with native GDI outside CaptureScreenBitmap.
  Bmp.Canvas.Changed;
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
  ScanCode: Byte;
begin
  Flags := 0;
  ScanCode := Byte(MapVirtualKey(VirtualKey, 0));
  // Trata teclas estendidas (setas, blocos de navegação, Alt Gr, Win, etc.)
  case VirtualKey of
    VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT,
    VK_INSERT, VK_DELETE, VK_HOME, VK_END,
    VK_PRIOR, VK_NEXT, VK_RMENU, VK_RCONTROL,
    VK_LWIN, VK_RWIN:
      Flags := Flags or KEYEVENTF_EXTENDEDKEY;
  end;
  if not IsDown then
    Flags := Flags or KEYEVENTF_KEYUP;
  keybd_event(Byte(VirtualKey), ScanCode, Flags, 0);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure ReleaseAllInputKeys;
{$IFDEF WINDOWS}
begin
  // Libera botões do mouse caso tenham ficado pressionados
  mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
  mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0);
  mouse_event(MOUSEEVENTF_MIDDLEUP, 0, 0, 0, 0);

  // Libera teclas modificadoras comuns
  keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0);
  keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);
  keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
  keybd_event(VK_LWIN, 0, KEYEVENTF_EXTENDEDKEY or KEYEVENTF_KEYUP, 0);
  keybd_event(VK_RWIN, 0, KEYEVENTF_EXTENDEDKEY or KEYEVENTF_KEYUP, 0);
end;
{$ELSE}
begin
end;
{$ENDIF}

end.
