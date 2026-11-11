unit uDeskStream;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}
  Windows, winsock2,
  {$ENDIF}
  Classes, SysUtils, Graphics, uDeskProtocol, uScreenCapture;

type
  TFrameEvent = procedure(Sender: TObject; FrameBmp: Graphics.TBitmap; FrameId: Cardinal) of object;
  TStreamLogEvent = procedure(Sender: TObject; const Msg: string) of object;

  { Servidor de streaming do Host: captura a tela e recebe controles }
  TDeskStreamServer = class(TThread)
  private
    FPort: Integer;
    FListeningSocket: TSocket;
    FClientSocket: TSocket;
    FCanControl: Boolean;
    FQuality: Integer;
    FRunning: Boolean;
    FOnLog: TStreamLogEvent;
    procedure Log(const S: string);
    function SendAll(ASock: TSocket; const ABuffer; ACount: Integer): Boolean;
    function RecvAll(ASock: TSocket; var ABuffer; ACount: Integer): Boolean;
    procedure ProcessClientCommands;
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Integer; ACanControl: Boolean; AQuality: Integer = 65);
    destructor Destroy; override;
    procedure StopServer;
    property OnLog: TStreamLogEvent read FOnLog write FOnLog;
  end;

  { Cliente de streaming do Controlador: recebe quadros e envia comandos }
  TDeskStreamClient = class(TThread)
  private
    FHost: string;
    FPort: Integer;
    FSocket: TSocket;
    FRunning: Boolean;
    FConnected: Boolean;
    FLatestBmp: Graphics.TBitmap;
    FLatestFrameId: Cardinal;
    FOnFrame: TFrameEvent;
    FOnLog: TStreamLogEvent;
    FSendLock: TRTLCriticalSection;
    procedure Log(const S: string);
    procedure SyncFrame;
    function SendAll(const ABuffer; ACount: Integer): Boolean;
    function RecvAll(var ABuffer; ACount: Integer): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost: string; APort: Integer);
    destructor Destroy; override;
    procedure StopClient;
    function SendMouseMove(NormX, NormY: Word): Boolean;
    function SendMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word): Boolean;
    function SendMouseWheel(Delta: SmallInt): Boolean;
    function SendKeyEvent(VirtualKey: Word; IsDown: Boolean): Boolean;
    property Connected: Boolean read FConnected;
    property OnFrame: TFrameEvent read FOnFrame write FOnFrame;
    property OnLog: TStreamLogEvent read FOnLog write FOnLog;
  end;

function GetLocalIPAddress: string;

implementation

function GetLocalIPAddress: string;
{$IFDEF WINDOWS}
var
  WSAData: TWSAData;
  HostName: array[0..255] of AnsiChar;
  HostEnt: PHostEnt;
  Addr: PInAddr;
begin
  Result := '127.0.0.1';
  if WSAStartup($0202, WSAData) = 0 then
  begin
    try
      if GetHostName(HostName, SizeOf(HostName)) = 0 then
      begin
        HostEnt := GetHostByName(HostName);
        if (HostEnt <> nil) and (HostEnt^.h_addr_list <> nil) and (HostEnt^.h_addr_list^ <> nil) then
        begin
          Addr := PInAddr(HostEnt^.h_addr_list^);
          Result := string(inet_ntoa(Addr^));
        end;
      end;
    finally
      WSACleanup;
    end;
  end;
end;
{$ELSE}
begin
  Result := '127.0.0.1';
end;
{$ENDIF}

{ TDeskStreamServer }

constructor TDeskStreamServer.Create(APort: Integer; ACanControl: Boolean; AQuality: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPort := APort;
  FCanControl := ACanControl;
  FQuality := AQuality;
  FListeningSocket := INVALID_SOCKET;
  FClientSocket := INVALID_SOCKET;
  FRunning := True;
end;

destructor TDeskStreamServer.Destroy;
begin
  StopServer;
  inherited Destroy;
end;

procedure TDeskStreamServer.Log(const S: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, S);
end;

procedure TDeskStreamServer.StopServer;
begin
  FRunning := False;
  if FClientSocket <> INVALID_SOCKET then
  begin
    closesocket(FClientSocket);
    FClientSocket := INVALID_SOCKET;
  end;
  if FListeningSocket <> INVALID_SOCKET then
  begin
    closesocket(FListeningSocket);
    FListeningSocket := INVALID_SOCKET;
  end;
  Terminate;
end;

function TDeskStreamServer.SendAll(ASock: TSocket; const ABuffer; ACount: Integer): Boolean;
var
  TotalSent, SentNow: Integer;
  Ptr: PAnsiChar;
begin
  Result := False;
  TotalSent := 0;
  Ptr := PAnsiChar(@ABuffer);
  while (TotalSent < ACount) and FRunning do
  begin
    SentNow := send(ASock, (Ptr + TotalSent)^, ACount - TotalSent, 0);
    if SentNow <= 0 then Exit;
    Inc(TotalSent, SentNow);
  end;
  Result := (TotalSent = ACount);
end;

function TDeskStreamServer.RecvAll(ASock: TSocket; var ABuffer; ACount: Integer): Boolean;
var
  TotalRecv, RecvNow: Integer;
  Ptr: PAnsiChar;
begin
  Result := False;
  TotalRecv := 0;
  Ptr := PAnsiChar(@ABuffer);
  while (TotalRecv < ACount) and FRunning do
  begin
    RecvNow := recv(ASock, (Ptr + TotalRecv)^, ACount - TotalRecv, 0);
    if RecvNow <= 0 then Exit;
    Inc(TotalRecv, RecvNow);
  end;
  Result := (TotalRecv = ACount);
end;

procedure TDeskStreamServer.ProcessClientCommands;
var
  FDSet: TFDSet;
  TimeVal: TTimeVal;
  PktType: Byte;
  MousePkt: TMousePacket;
  WheelDelta: SmallInt;
  KeyPkt: TKeyPacket;
begin
  if (FClientSocket = INVALID_SOCKET) or not FCanControl then Exit;

  // Verifica se há dados para ler sem bloquear o envio de quadros
  FD_ZERO(FDSet);
  FD_SET(FClientSocket, FDSet);
  TimeVal.tv_sec := 0;
  TimeVal.tv_usec := 0;

  while (select(0, @FDSet, nil, nil, @TimeVal) > 0) and FRunning do
  begin
    if not RecvAll(FClientSocket, PktType, 1) then Break;
    case PktType of
      PKT_MOUSE_MOVE:
      begin
        if RecvAll(FClientSocket, MousePkt.NormX, 4) then
          InjectMouseMove(MousePkt.NormX, MousePkt.NormY);
      end;
      PKT_MOUSE_DOWN:
      begin
        if RecvAll(FClientSocket, MousePkt, SizeOf(TMousePacket)) then
          InjectMouseButton(MousePkt.Button, True, MousePkt.NormX, MousePkt.NormY);
      end;
      PKT_MOUSE_UP:
      begin
        if RecvAll(FClientSocket, MousePkt, SizeOf(TMousePacket)) then
          InjectMouseButton(MousePkt.Button, False, MousePkt.NormX, MousePkt.NormY);
      end;
      PKT_MOUSE_WHEEL:
      begin
        if RecvAll(FClientSocket, WheelDelta, SizeOf(SmallInt)) then
          InjectMouseWheel(WheelDelta);
      end;
      PKT_KEY_DOWN:
      begin
        if RecvAll(FClientSocket, KeyPkt, SizeOf(TKeyPacket)) then
          InjectKeyEvent(KeyPkt.KeyCode, True);
      end;
      PKT_KEY_UP:
      begin
        if RecvAll(FClientSocket, KeyPkt, SizeOf(TKeyPacket)) then
          InjectKeyEvent(KeyPkt.KeyCode, False);
      end;
      PKT_CLOSE:
      begin
        Break;
      end;
    end;

    FD_ZERO(FDSet);
    FD_SET(FClientSocket, FDSet);
  end;
end;

procedure TDeskStreamServer.Execute;
var
  WSAData: TWSAData;
  Addr: TSockAddrIn;
  OptVal: Integer;
  Bmp: Graphics.TBitmap;
  JpegStream: TMemoryStream;
  Magic: Cardinal;
  PktType: Byte;
  Hdr: TFrameHeader;
  FrameCounter: Cardinal;
begin
  if WSAStartup($0202, WSAData) <> 0 then Exit;

  try
    FListeningSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if FListeningSocket = INVALID_SOCKET then Exit;

    OptVal := 1;
    setsockopt(FListeningSocket, SOL_SOCKET, SO_REUSEADDR, PAnsiChar(@OptVal), SizeOf(OptVal));

    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(FPort);
    Addr.sin_addr.s_addr := INADDR_ANY;

    if bind(FListeningSocket, Addr, SizeOf(Addr)) <> 0 then Exit;
    if listen(FListeningSocket, 1) <> 0 then Exit;

    FrameCounter := 0;
    Magic := DESK_MAGIC;
    PktType := PKT_FRAME;
    JpegStream := TMemoryStream.Create;
    try
      while FRunning and not Terminated do
      begin
        // Aguarda conexão do controlador
        FClientSocket := accept(FListeningSocket, nil, nil);
        if FClientSocket = INVALID_SOCKET then Break;

        // Desativa algoritmo Nagle para menor latência
        OptVal := 1;
        setsockopt(FClientSocket, IPPROTO_TCP, TCP_NODELAY, PAnsiChar(@OptVal), SizeOf(OptVal));

        while FRunning and not Terminated do
        begin
          ProcessClientCommands;

          // Captura a tela e comprime em JPEG
          if CaptureScreenBitmap(Bmp) then
          begin
            try
              JpegStream.Clear;
              CompressBitmapToJpegStream(Bmp, JpegStream, FQuality);

              Inc(FrameCounter);
              Hdr.FrameId := FrameCounter;
              Hdr.Width := Bmp.Width;
              Hdr.Height := Bmp.Height;
              Hdr.JpegSize := JpegStream.Size;

              // Envia pacote do quadro: Magic (4) + Tipo (1) + Header (12) + Bytes JPEG
              if not SendAll(FClientSocket, Magic, SizeOf(Magic)) then Break;
              if not SendAll(FClientSocket, PktType, SizeOf(PktType)) then Break;
              if not SendAll(FClientSocket, Hdr, SizeOf(Hdr)) then Break;
              if not SendAll(FClientSocket, JpegStream.Memory^, JpegStream.Size) then Break;
            finally
              Bmp.Free;
            end;
          end;

          // Throttle para ~15 FPS (~65ms)
          Sleep(65);
        end;

        if FClientSocket <> INVALID_SOCKET then
        begin
          closesocket(FClientSocket);
          FClientSocket := INVALID_SOCKET;
        end;
      end;
    finally
      JpegStream.Free;
    end;
  finally
    if FListeningSocket <> INVALID_SOCKET then
    begin
      closesocket(FListeningSocket);
      FListeningSocket := INVALID_SOCKET;
    end;
    WSACleanup;
  end;
end;

{ TDeskStreamClient }

constructor TDeskStreamClient.Create(const AHost: string; APort: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FHost := AHost;
  FPort := APort;
  FSocket := INVALID_SOCKET;
  FRunning := True;
  FConnected := False;
  FLatestBmp := nil;
  InitCriticalSection(FSendLock);
end;

destructor TDeskStreamClient.Destroy;
begin
  StopClient;
  DoneCriticalSection(FSendLock);
  if FLatestBmp <> nil then
    FreeAndNil(FLatestBmp);
  inherited Destroy;
end;

procedure TDeskStreamClient.Log(const S: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, S);
end;

procedure TDeskStreamClient.StopClient;
begin
  FRunning := False;
  if FSocket <> INVALID_SOCKET then
  begin
    closesocket(FSocket);
    FSocket := INVALID_SOCKET;
  end;
  Terminate;
end;

function TDeskStreamClient.SendAll(const ABuffer; ACount: Integer): Boolean;
var
  TotalSent, SentNow: Integer;
  Ptr: PAnsiChar;
begin
  Result := False;
  TotalSent := 0;
  Ptr := PAnsiChar(@ABuffer);
  while (TotalSent < ACount) and FRunning do
  begin
    SentNow := send(FSocket, (Ptr + TotalSent)^, ACount - TotalSent, 0);
    if SentNow <= 0 then Exit;
    Inc(TotalSent, SentNow);
  end;
  Result := (TotalSent = ACount);
end;

function TDeskStreamClient.RecvAll(var ABuffer; ACount: Integer): Boolean;
var
  TotalRecv, RecvNow: Integer;
  Ptr: PAnsiChar;
begin
  Result := False;
  TotalRecv := 0;
  Ptr := PAnsiChar(@ABuffer);
  while (TotalRecv < ACount) and FRunning do
  begin
    RecvNow := recv(FSocket, (Ptr + TotalRecv)^, ACount - TotalRecv, 0);
    if RecvNow <= 0 then Exit;
    Inc(TotalRecv, RecvNow);
  end;
  Result := (TotalRecv = ACount);
end;

procedure TDeskStreamClient.SyncFrame;
begin
  if Assigned(FOnFrame) and (FLatestBmp <> nil) then
    FOnFrame(Self, FLatestBmp, FLatestFrameId);
end;

procedure TDeskStreamClient.Execute;
var
  WSAData: TWSAData;
  Addr: TSockAddrIn;
  HostEnt: PHostEnt;
  OptVal: Integer;
  Magic: Cardinal;
  PktType: Byte;
  Hdr: TFrameHeader;
  JpegStream: TMemoryStream;
  Jpg: TJPEGImage;
begin
  if WSAStartup($0202, WSAData) <> 0 then Exit;

  try
    FSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if FSocket = INVALID_SOCKET then Exit;

    OptVal := 1;
    setsockopt(FSocket, IPPROTO_TCP, TCP_NODELAY, PAnsiChar(@OptVal), SizeOf(OptVal));

    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(FPort);
    Addr.sin_addr.s_addr := inet_addr(PAnsiChar(AnsiString(FHost)));
    if Addr.sin_addr.s_addr = INADDR_NONE then
    begin
      HostEnt := GetHostByName(PAnsiChar(AnsiString(FHost)));
      if (HostEnt = nil) or (HostEnt^.h_addr_list = nil) or (HostEnt^.h_addr_list^ = nil) then Exit;
      Addr.sin_addr.s_addr := PInAddr(HostEnt^.h_addr_list^)^.s_addr;
    end;

    if connect(FSocket, Addr, SizeOf(Addr)) <> 0 then
    begin
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
      Exit;
    end;

    FConnected := True;
    JpegStream := TMemoryStream.Create;
    Jpg := TJPEGImage.Create;
    try
      while FRunning and not Terminated do
      begin
        // Le Magic (4 bytes)
        if not RecvAll(Magic, SizeOf(Magic)) then Break;
        if Magic <> DESK_MAGIC then Break;

        // Le Tipo de Pacote
        if not RecvAll(PktType, SizeOf(PktType)) then Break;
        if PktType = PKT_FRAME then
        begin
          if not RecvAll(Hdr, SizeOf(Hdr)) then Break;
          if (Hdr.JpegSize = 0) or (Hdr.JpegSize > 10 * 1024 * 1024) then Break; // Proteção contra pacotes gigantes

          JpegStream.SetSize(Hdr.JpegSize);
          if not RecvAll(JpegStream.Memory^, Hdr.JpegSize) then Break;

          // Decodifica JPEG e atualiza o bitmap
          JpegStream.Position := 0;
          try
            Jpg.LoadFromStream(JpegStream);
            if FLatestBmp = nil then
              FLatestBmp := Graphics.TBitmap.Create;
            FLatestBmp.Assign(Jpg);
            FLatestFrameId := Hdr.FrameId;
            Synchronize(@SyncFrame);
          except
            // Ignora quadro corrompido e continua
          end;
        end;
      end;
    finally
      Jpg.Free;
      JpegStream.Free;
    end;
  finally
    FConnected := False;
    if FSocket <> INVALID_SOCKET then
    begin
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
    end;
    WSACleanup;
  end;
end;

function TDeskStreamClient.SendMouseMove(NormX, NormY: Word): Boolean;
var
  PktType: Byte;
begin
  Result := False;
  if not FConnected then Exit;
  EnterCriticalSection(FSendLock);
  try
    PktType := PKT_MOUSE_MOVE;
    if SendAll(PktType, 1) then
      if SendAll(NormX, 2) then
        Result := SendAll(NormY, 2);
  finally
    LeaveCriticalSection(FSendLock);
  end;
end;

function TDeskStreamClient.SendMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word): Boolean;
var
  PktType: Byte;
  Pkt: TMousePacket;
begin
  Result := False;
  if not FConnected then Exit;
  EnterCriticalSection(FSendLock);
  try
    if IsDown then PktType := PKT_MOUSE_DOWN else PktType := PKT_MOUSE_UP;
    Pkt.Button := Button;
    Pkt.NormX := NormX;
    Pkt.NormY := NormY;
    if SendAll(PktType, 1) then
      Result := SendAll(Pkt, SizeOf(TMousePacket));
  finally
    LeaveCriticalSection(FSendLock);
  end;
end;

function TDeskStreamClient.SendMouseWheel(Delta: SmallInt): Boolean;
var
  PktType: Byte;
begin
  Result := False;
  if not FConnected then Exit;
  EnterCriticalSection(FSendLock);
  try
    PktType := PKT_MOUSE_WHEEL;
    if SendAll(PktType, 1) then
      Result := SendAll(Delta, SizeOf(SmallInt));
  finally
    LeaveCriticalSection(FSendLock);
  end;
end;

function TDeskStreamClient.SendKeyEvent(VirtualKey: Word; IsDown: Boolean): Boolean;
var
  PktType: Byte;
  Pkt: TKeyPacket;
begin
  Result := False;
  if not FConnected then Exit;
  EnterCriticalSection(FSendLock);
  try
    if IsDown then PktType := PKT_KEY_DOWN else PktType := PKT_KEY_UP;
    Pkt.KeyCode := VirtualKey;
    Pkt.Reserved := 0;
    if SendAll(PktType, 1) then
      Result := SendAll(Pkt, SizeOf(TKeyPacket));
  finally
    LeaveCriticalSection(FSendLock);
  end;
end;

end.
