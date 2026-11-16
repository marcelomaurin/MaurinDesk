unit uScreenCapture;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}
  Windows, MultiMon,
  {$ENDIF}
  Classes, SysUtils, Graphics;

{ Captura a tela inteira do monitor selecionado em um TBitmap 24 bits }
function CaptureScreenBitmap(out Bmp: Graphics.TBitmap): Boolean;

{ Gerenciamento de múltiplos monitores para captura }
function GetCaptureMonitorCount: Integer;
function GetCaptureMonitorIndex: Integer;
procedure SetCaptureMonitorIndex(Index: Integer);
function GetCaptureMonitorCaption(Index: Integer): string;
function GetCaptureMonitorBounds(Index: Integer; out R: TRect): Boolean;

{ Converte um TBitmap em fluxo JPEG com compressão configurável (padrão 65%) }
procedure CompressBitmapToJpegStream(Bmp: Graphics.TBitmap; Stream: TStream; Quality: Integer = 65);

{ Simula ações de mouse e teclado no Windows }
procedure InjectMouseMove(NormX, NormY: Word);
procedure InjectMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word);
procedure InjectMouseWheel(Delta: SmallInt);
procedure InjectKeyEvent(VirtualKey: Word; IsDown: Boolean);
procedure ReleaseAllInputKeys;

implementation

{$IFDEF WINDOWS}
type
  TEnumMonitorItem = record
    Bounds: TRect;
    IsPrimary: Boolean;
  end;
  PEnumMonitorList = ^TEnumMonitorList;
  TEnumMonitorList = array of TEnumMonitorItem;

var
  GCaptureMonitorIndex: LongInt = 0;

function EnumMonitorProc(hm: HMONITOR; dc: HDC; r: PRect; data: LPARAM): BOOL; stdcall;
var
  List: PEnumMonitorList;
  Info: TMonitorInfo;
  Idx: Integer;
begin
  List := PEnumMonitorList(data);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if GetMonitorInfo(hm, @Info) then
  begin
    Idx := Length(List^);
    SetLength(List^, Idx + 1);
    List^[Idx].Bounds := Info.rcMonitor;
    List^[Idx].IsPrimary := (Info.dwFlags and MONITORINFOF_PRIMARY) <> 0;
  end;
  Result := True;
end;

procedure CollectMonitors(out List: TEnumMonitorList);
begin
  List := nil;
  EnumDisplayMonitors(0, nil, @EnumMonitorProc, LPARAM(@List));
end;

function GetCaptureMonitorCount: Integer;
var
  List: TEnumMonitorList;
begin
  CollectMonitors(List);
  Result := Length(List);
  if Result <= 0 then Result := 1;
end;

function GetCaptureMonitorIndex: Integer;
var
  Count, Idx: Integer;
begin
  Count := GetCaptureMonitorCount;
  Idx := InterlockedCompareExchange(GCaptureMonitorIndex, 0, 0);
  if (Idx < 0) or (Idx >= Count) then Idx := 0;
  Result := Idx;
end;

procedure SetCaptureMonitorIndex(Index: Integer);
var
  Count: Integer;
begin
  Count := GetCaptureMonitorCount;
  if (Index < 0) or (Index >= Count) then Index := 0;
  InterlockedExchange(GCaptureMonitorIndex, Index);
end;

function GetCaptureMonitorBounds(Index: Integer; out R: TRect): Boolean;
var
  List: TEnumMonitorList;
begin
  CollectMonitors(List);
  if (Index >= 0) and (Index < Length(List)) then
  begin
    R := List[Index].Bounds;
    Result := (R.Right > R.Left) and (R.Bottom > R.Top);
  end
  else
    Result := False;
end;

function GetCaptureMonitorCaption(Index: Integer): string;
var
  List: TEnumMonitorList;
  W, H: Integer;
begin
  CollectMonitors(List);
  if (Index >= 0) and (Index < Length(List)) then
  begin
    W := List[Index].Bounds.Right - List[Index].Bounds.Left;
    H := List[Index].Bounds.Bottom - List[Index].Bounds.Top;
    Result := Format('Monitor %d (%dx%d)', [Index + 1, W, H]);
    if List[Index].IsPrimary then
      Result := Result + ' - Principal';
  end
  else
    Result := Format('Monitor %d', [Index + 1]);
end;
{$ELSE}
function GetCaptureMonitorCount: Integer; begin Result := 1; end;
function GetCaptureMonitorIndex: Integer; begin Result := 0; end;
procedure SetCaptureMonitorIndex(Index: Integer); begin end;
function GetCaptureMonitorBounds(Index: Integer; out R: TRect): Boolean; begin R := Rect(0,0,0,0); Result := False; end;
function GetCaptureMonitorCaption(Index: Integer): string; begin Result := 'Monitor 1'; end;
{$ENDIF}

function CaptureScreenBitmap(out Bmp: Graphics.TBitmap): Boolean;
{$IFDEF WINDOWS}
var
  ScreenDC: HDC;
  MonitorRect: TRect;
  ScreenWidth, ScreenHeight: Integer;
  CursorInfo: TCursorInfo;
  IconInfo: TIconInfo;
begin
  Result := False;
  Bmp := nil;
  if not GetCaptureMonitorBounds(GetCaptureMonitorIndex, MonitorRect) then
    MonitorRect := Rect(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
  ScreenWidth := MonitorRect.Right - MonitorRect.Left;
  ScreenHeight := MonitorRect.Bottom - MonitorRect.Top;
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
    Result := BitBlt(Bmp.Canvas.Handle, 0, 0, ScreenWidth, ScreenHeight, ScreenDC, MonitorRect.Left, MonitorRect.Top, SRCCOPY);
    if Result then
    begin
      // Desenha o ponteiro real do mouse sobre a imagem quando estiver no monitor capturado
      FillChar(CursorInfo, SizeOf(CursorInfo), 0);
      CursorInfo.cbSize := SizeOf(CursorInfo);
      if GetCursorInfo(CursorInfo) and (CursorInfo.flags = 1) and PtInRect(MonitorRect, CursorInfo.ptScreenPos) then
      begin
        FillChar(IconInfo, SizeOf(IconInfo), 0);
        if GetIconInfo(CursorInfo.hCursor, IconInfo) then
        begin
          DrawIconEx(Bmp.Canvas.Handle,
            CursorInfo.ptScreenPos.x - MonitorRect.Left - Integer(IconInfo.xHotspot),
            CursorInfo.ptScreenPos.y - MonitorRect.Top - Integer(IconInfo.yHotspot),
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
  MonitorRect: TRect;
  PixelsX, PixelsY: Integer;
  ScreenWidth, ScreenHeight: Integer;
begin
  if not GetCaptureMonitorBounds(GetCaptureMonitorIndex, MonitorRect) then
    MonitorRect := Rect(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
  ScreenWidth := MonitorRect.Right - MonitorRect.Left;
  ScreenHeight := MonitorRect.Bottom - MonitorRect.Top;
  PixelsX := MonitorRect.Left + Round((NormX / 65535.0) * ScreenWidth);
  PixelsY := MonitorRect.Top + Round((NormY / 65535.0) * ScreenHeight);
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
