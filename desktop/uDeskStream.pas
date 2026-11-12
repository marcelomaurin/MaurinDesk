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
  TFallbackRelayEvent = procedure(Sender: TObject) of object;
  TPortSuccessEvent = procedure(Sender: TObject; APort: Integer) of object;

  { Servidor de streaming do Host: captura a tela e recebe controles }
  TDeskStreamServer = class(TThread)
  private
    FPort: Integer;
    FListeningSocket: TSocket;
    FListenSockets: array of TSocket;
    FClientSocket: TSocket;
    FCanControl: Boolean;
    FQuality: Integer;
    FRunning: Boolean;
    FSessionId: string;
    FExpectedToken: string;
    FOnLog: TStreamLogEvent;
    FSyncLogMsg: string;
    procedure Log(const S: string);
    procedure DoSyncLog;
    function SendAll(ASock: TSocket; const ABuffer; ACount: Integer): Boolean;
    function RecvAll(ASock: TSocket; var ABuffer; ACount: Integer): Boolean;
    procedure ProcessClientCommands;
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Integer; ACanControl: Boolean; const ASessionId: string = ''; const AExpectedToken: string = ''; AQuality: Integer = 65);
    destructor Destroy; override;
    procedure StopServer;
    property OnLog: TStreamLogEvent read FOnLog write FOnLog;
  end;

  { Cliente de streaming do Controlador: recebe quadros e envia comandos }
  TDeskStreamClient = class(TThread)
  private
    FHost: string;
    FPort: Integer;
    FLocalIP: string;
    FSessionId: string;
    FAuthToken: string;
    FCanControl: Boolean;
    FSocket: TSocket;
    FRunning: Boolean;
    FConnected: Boolean;
    FLatestBmp: Graphics.TBitmap;
    FLatestFrameId: Cardinal;
    FOnFrame: TFrameEvent;
    FOnLog: TStreamLogEvent;
    FOnFallbackToRelay: TFallbackRelayEvent;
    FOnPortSuccess: TPortSuccessEvent;
    FSyncPort: Integer;
    FSyncLogMsg: string;
    FSendLock: TRTLCriticalSection;
    procedure Log(const S: string);
    procedure DoSyncLog;
    procedure DoSyncFallbackRelay;
    procedure DoSyncPortSuccess;
    procedure SyncFrame;
    function TryConnectTo(const TargetIP: string; TargetPort, TimeoutMs: Integer): TSocket;
    function SendAll(const ABuffer; ACount: Integer): Boolean;
    function RecvAll(var ABuffer; ACount: Integer): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost: string; APort: Integer; const ALocalIP: string = ''; const ASessionId: string = ''; const AAuthToken: string = ''; ARequestControl: Boolean = True);
    destructor Destroy; override;
    procedure StopClient;
    function SendMouseMove(NormX, NormY: Word): Boolean;
    function SendMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word): Boolean;
    function SendMouseWheel(Delta: SmallInt): Boolean;
    function SendKeyEvent(VirtualKey: Word; IsDown: Boolean): Boolean;
    property Connected: Boolean read FConnected;
    property CanControl: Boolean read FCanControl;
    property OnFrame: TFrameEvent read FOnFrame write FOnFrame;
    property OnLog: TStreamLogEvent read FOnLog write FOnLog;
    property OnFallbackToRelay: TFallbackRelayEvent read FOnFallbackToRelay write FOnFallbackToRelay;
    property OnPortSuccess: TPortSuccessEvent read FOnPortSuccess write FOnPortSuccess;
  end;

function GetLocalIPAddress: string;

implementation

function GetRouteLocalIP: string;
var
  UdpSock: TSocket;
  TargetAddr, BoundAddr: sockaddr_in;
  BoundLen: LongInt;
begin
  Result := '';
  UdpSock := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if UdpSock = INVALID_SOCKET then Exit;
  try
    FillChar(TargetAddr, SizeOf(TargetAddr), 0);
    TargetAddr.sin_family := AF_INET;
    TargetAddr.sin_port := htons(53);
    TargetAddr.sin_addr.s_addr := inet_addr('8.8.8.8');
    if connect(UdpSock, TargetAddr, SizeOf(TargetAddr)) = 0 then
    begin
      FillChar(BoundAddr, SizeOf(BoundAddr), 0);
      BoundLen := SizeOf(BoundAddr);
      if getsockname(UdpSock, BoundAddr, BoundLen) = 0 then
      begin
        Result := string(inet_ntoa(BoundAddr.sin_addr));
        if (Result = '0.0.0.0') or (Result = '127.0.0.1') then Result := '';
      end;
    end;
  finally
    closesocket(UdpSock);
  end;
end;

function GetLocalIPAddress: string;
{$IFDEF WINDOWS}
var
  WSAData: TWSAData;
  HostName: array[0..255] of AnsiChar;
  HostEnt: PHostEnt;
  I: Integer;
  CurAddr: PInAddr;
  IPStr, PriIPs, SecIPs, RouteIP: string;
begin
  Result := '127.0.0.1';
  PriIPs := '';
  SecIPs := '';
  if WSAStartup($0202, WSAData) = 0 then
  begin
    try
      // Obtem o IP real ativo na placa conectada ao gateway/internet
      RouteIP := GetRouteLocalIP;
      if RouteIP <> '' then
        PriIPs := RouteIP;

      if GetHostName(HostName, SizeOf(HostName)) = 0 then
      begin
        HostEnt := GetHostByName(HostName);
        if (HostEnt <> nil) and (HostEnt^.h_addr_list <> nil) then
        begin
          I := 0;
          while HostEnt^.h_addr_list[I] <> nil do
          begin
            CurAddr := PInAddr(HostEnt^.h_addr_list[I]);
            IPStr := string(inet_ntoa(CurAddr^));
            // Ignora loopback, link-local APIPA (169.254.x.x) e o proprio RouteIP
            if (IPStr <> '127.0.0.1') and not (Copy(IPStr, 1, 8) = '169.254.') and (IPStr <> RouteIP) then
            begin
              // 172.x.x.x e 192.168.x.x sao prioridade maxima (intranets e LANs de suporte)
              if (Copy(IPStr, 1, 4) = '172.') or (Copy(IPStr, 1, 8) = '192.168.') then
              begin
                if PriIPs <> '' then PriIPs := PriIPs + ',';
                PriIPs := PriIPs + IPStr;
              end
              else
              begin
                if SecIPs <> '' then SecIPs := SecIPs + ',';
                SecIPs := SecIPs + IPStr;
              end;
            end;
            Inc(I);
          end;
          if PriIPs <> '' then
          begin
            if SecIPs <> '' then
              Result := PriIPs + ',' + SecIPs
            else
              Result := PriIPs;
          end
          else if SecIPs <> '' then
            Result := SecIPs;
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

constructor TDeskStreamServer.Create(APort: Integer; ACanControl: Boolean; const ASessionId, AExpectedToken: string; AQuality: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPort := APort;
  FCanControl := ACanControl;
  FSessionId := ASessionId;
  FExpectedToken := AExpectedToken;
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
  FSyncLogMsg := S;
  Synchronize(@DoSyncLog);
end;

procedure TDeskStreamServer.DoSyncLog;
begin
  if Assigned(FOnLog) then
    FOnLog(Self, FSyncLogMsg);
end;

procedure TDeskStreamServer.StopServer;
var
  I: Integer;
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
  for I := 0 to High(FListenSockets) do
  begin
    if FListenSockets[I] <> INVALID_SOCKET then
    begin
      closesocket(FListenSockets[I]);
      FListenSockets[I] := INVALID_SOCKET;
    end;
  end;
  SetLength(FListenSockets, 0);
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
  Addr, ClientAddr: TSockAddrIn;
  ClientAddrLen: Integer;
  ClientIPStr: string;
  OptVal: Integer;
  Bmp: Graphics.TBitmap;
  JpegStream: TMemoryStream;
  Magic: Cardinal;
  PktType: Byte;
  Hdr: TFrameHeader;
  FrameCounter: Cardinal;
  PortsToBind: array[0..2] of Integer;
  CurPort, PIdx, I, Res: Integer;
  Sock: TSocket;
  FDSet: TFDSet;
  TimeVal: TTimeVal;
  PortAlreadyBound: Boolean;
  HelloPkt: THelloPacket;
  RecvSessionId, RecvToken: string;
  GrantedControlByte: Byte;
begin
  if WSAStartup($0202, WSAData) <> 0 then Exit;

  try
    SetLength(FListenSockets, 0);
    PortsToBind[0] := FPort;
    PortsToBind[1] := 8080;
    PortsToBind[2] := 9876;

    for PIdx := 0 to 2 do
    begin
      CurPort := PortsToBind[PIdx];
      if CurPort <= 0 then Continue;

      // Evita duplicar portas
      PortAlreadyBound := False;
      for I := 0 to PIdx - 1 do
        if PortsToBind[I] = CurPort then
        begin
          PortAlreadyBound := True;
          Break;
        end;
      if PortAlreadyBound then Continue;

      Sock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
      if Sock = INVALID_SOCKET then Continue;

      OptVal := 1;
      setsockopt(Sock, SOL_SOCKET, SO_REUSEADDR, PAnsiChar(@OptVal), SizeOf(OptVal));

      FillChar(Addr, SizeOf(Addr), 0);
      Addr.sin_family := AF_INET;
      Addr.sin_port := htons(CurPort);
      Addr.sin_addr.s_addr := INADDR_ANY;

      if bind(Sock, Addr, SizeOf(Addr)) = 0 then
      begin
        if listen(Sock, 2) = 0 then
        begin
          SetLength(FListenSockets, Length(FListenSockets) + 1);
          FListenSockets[High(FListenSockets)] := Sock;
          Log('[STREAM SERVER] Escutando na porta TCP ' + IntToStr(CurPort) + '...');
        end
        else
          closesocket(Sock);
      end
      else
        closesocket(Sock);
    end;

    if Length(FListenSockets) = 0 then
    begin
      Log('[STREAM SERVER ERRO] Não foi possível escutar em nenhuma porta candidata.');
      Exit;
    end;

    Log('[STREAM SERVER] Servidor pronto para conexões (IP Local: ' + GetLocalIPAddress + ').');

    FrameCounter := 0;
    Magic := DESK_MAGIC;
    PktType := PKT_FRAME;
    JpegStream := TMemoryStream.Create;
    try
      while FRunning and not Terminated do
      begin
        // Aguarda conexão de cliente em qualquer uma das portas escutadas
        FillChar(FDSet, SizeOf(FDSet), 0);
        for I := 0 to High(FListenSockets) do
          FD_SET(FListenSockets[I], FDSet);

        TimeVal.tv_sec := 0;
        TimeVal.tv_usec := 250000; // 250ms

        Res := select(0, @FDSet, nil, nil, @TimeVal);
        if Res <= 0 then Continue;

        FClientSocket := INVALID_SOCKET;
        for I := 0 to High(FListenSockets) do
        begin
          if FD_ISSET(FListenSockets[I], FDSet) then
          begin
            FillChar(ClientAddr, SizeOf(ClientAddr), 0);
            ClientAddrLen := SizeOf(ClientAddr);
            FClientSocket := accept(FListenSockets[I], @ClientAddr, @ClientAddrLen);
            Break;
          end;
        end;

        if FClientSocket = INVALID_SOCKET then Continue;

        ClientIPStr := string(inet_ntoa(ClientAddr.sin_addr));
        Log('[STREAM SERVER] Conexão recebida de ' + ClientIPStr + '. Verificando autenticação...');

        // Timeout de 3 segundos para o handshake obrigatório
        OptVal := 3000;
        setsockopt(FClientSocket, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@OptVal), SizeOf(OptVal));

        if not RecvAll(FClientSocket, Magic, SizeOf(Magic)) or (Magic <> DESK_MAGIC) or
           not RecvAll(FClientSocket, PktType, SizeOf(PktType)) or (PktType <> PKT_HELLO) or
           not RecvAll(FClientSocket, HelloPkt, SizeOf(HelloPkt)) then
        begin
          Log('[SEGURANÇA BLOQUEIO] Conexão não autenticada rejeitada de ' + ClientIPStr + '. Fechando porta.');
          closesocket(FClientSocket);
          FClientSocket := INVALID_SOCKET;
          Continue;
        end;

        RecvSessionId := Trim(string(HelloPkt.SessionId));
        RecvToken := Trim(string(HelloPkt.AuthToken));

        if (FSessionId <> '') and (RecvSessionId <> FSessionId) then
        begin
          Log('[SEGURANÇA BLOQUEIO] Sessão inválida (' + RecvSessionId + ') de ' + ClientIPStr + '. Rejeitando.');
          Magic := DESK_MAGIC;
          PktType := PKT_HELLO_REJ;
          SendAll(FClientSocket, Magic, SizeOf(Magic));
          SendAll(FClientSocket, PktType, SizeOf(PktType));
          closesocket(FClientSocket);
          FClientSocket := INVALID_SOCKET;
          Continue;
        end;

        if (FExpectedToken <> '') and (RecvToken <> FExpectedToken) then
        begin
          Log('[SEGURANÇA BLOQUEIO] Token de acesso inválido de ' + ClientIPStr + '. Rejeitando.');
          Magic := DESK_MAGIC;
          PktType := PKT_HELLO_REJ;
          SendAll(FClientSocket, Magic, SizeOf(Magic));
          SendAll(FClientSocket, PktType, SizeOf(PktType));
          closesocket(FClientSocket);
          FClientSocket := INVALID_SOCKET;
          Continue;
        end;

        // O Host impõe a permissão decidida no consentimento (não permite virar controle se for apenas visualização)
        GrantedControlByte := 0;
        if FCanControl and (HelloPkt.CanControl = 1) then
          GrantedControlByte := 1;

        Magic := DESK_MAGIC;
        PktType := PKT_HELLO_ACK;
        SendAll(FClientSocket, Magic, SizeOf(Magic));
        SendAll(FClientSocket, PktType, SizeOf(PktType));
        SendAll(FClientSocket, GrantedControlByte, 1);

        Log('[SEGURANÇA SUCESSO] Conexão P2P autorizada para ' + ClientIPStr + '! Permissão de controle: ' + BoolToStr(GrantedControlByte = 1, True));

        // Restaura timeout padrão
        OptVal := 0;
        setsockopt(FClientSocket, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@OptVal), SizeOf(OptVal));

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

              if FrameCounter = 1 then
                Log('[STREAM SERVER] Transmitindo quadros da tela (' + IntToStr(Bmp.Width) + 'x' + IntToStr(Bmp.Height) + ', qualidade ' + IntToStr(FQuality) + '%)...');
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
          ReleaseAllInputKeys;
          Log('[STREAM SERVER] Cliente ' + ClientIPStr + ' desconectado. Entradas liberadas.');
        end;
      end;
    finally
      JpegStream.Free;
    end;
  finally
    for I := 0 to High(FListenSockets) do
    begin
      if FListenSockets[I] <> INVALID_SOCKET then
      begin
        closesocket(FListenSockets[I]);
        FListenSockets[I] := INVALID_SOCKET;
      end;
    end;
    SetLength(FListenSockets, 0);
    WSACleanup;
    Log('[STREAM SERVER] Servidor de streaming finalizado.');
  end;
end;

{ TDeskStreamClient }

constructor TDeskStreamClient.Create(const AHost: string; APort: Integer; const ALocalIP, ASessionId, AAuthToken: string; ARequestControl: Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FHost := AHost;
  FPort := APort;
  FLocalIP := ALocalIP;
  FSessionId := ASessionId;
  FAuthToken := AAuthToken;
  FCanControl := ARequestControl;
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
  FSyncLogMsg := S;
  Synchronize(@DoSyncLog);
end;

procedure TDeskStreamClient.DoSyncLog;
begin
  if Assigned(FOnLog) then
    FOnLog(Self, FSyncLogMsg);
end;

procedure TDeskStreamClient.DoSyncFallbackRelay;
begin
  if Assigned(FOnFallbackToRelay) then
    FOnFallbackToRelay(Self);
end;

procedure TDeskStreamClient.DoSyncPortSuccess;
begin
  if Assigned(FOnPortSuccess) then
    FOnPortSuccess(Self, FSyncPort);
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

function TDeskStreamClient.TryConnectTo(const TargetIP: string; TargetPort, TimeoutMs: Integer): TSocket;
var
  S: TSocket;
  Addr: TSockAddrIn;
  HostEnt: PHostEnt;
  NonBlock: u_long;
  FDWrite, FDExcept: TFDSet;
  TimeVal: TTimeVal;
  OptVal, OptLen: Longint;
  Res: Integer;
begin
  Result := INVALID_SOCKET;
  if (TargetIP = '') or (TargetPort <= 0) then Exit;

  S := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if S = INVALID_SOCKET then Exit;

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(TargetPort);
  Addr.sin_addr.s_addr := inet_addr(PAnsiChar(AnsiString(TargetIP)));
  if Addr.sin_addr.s_addr = INADDR_NONE then
  begin
    HostEnt := GetHostByName(PAnsiChar(AnsiString(TargetIP)));
    if (HostEnt = nil) or (HostEnt^.h_addr_list = nil) or (HostEnt^.h_addr_list^ = nil) then
    begin
      closesocket(S);
      Exit;
    end;
    Addr.sin_addr.s_addr := PInAddr(HostEnt^.h_addr_list^)^.s_addr;
  end;

  // Ativa modo nao-bloqueante para respeitar o timeout configurado
  NonBlock := 1;
  ioctlsocket(S, Longint(Longword(FIONBIO)), NonBlock);

  Res := connect(S, Addr, SizeOf(Addr));
  if Res = SOCKET_ERROR then
  begin
    if WSAGetLastError = WSAEWOULDBLOCK then
    begin
      FD_ZERO(FDWrite);
      FD_SET(S, FDWrite);
      FD_ZERO(FDExcept);
      FD_SET(S, FDExcept);

      TimeVal.tv_sec := TimeoutMs div 1000;
      TimeVal.tv_usec := (TimeoutMs mod 1000) * 1000;

      Res := select(0, nil, @FDWrite, @FDExcept, @TimeVal);
      if (Res > 0) and FD_ISSET(S, FDWrite) then
      begin
        OptLen := SizeOf(OptVal);
        OptVal := 0;
        if (getsockopt(S, SOL_SOCKET, SO_ERROR, PAnsiChar(@OptVal), OptLen) = 0) and (OptVal = 0) then
          Result := S;
      end;
    end;
  end
  else
    Result := S; // Conectou de forma imediata (ex: localhost)

  if Result <> INVALID_SOCKET then
  begin
    // Restaura modo bloqueante para transferencia continua
    NonBlock := 0;
    ioctlsocket(S, Longint(Longword(FIONBIO)), NonBlock);

    // Desativa algoritmo Nagle para menor latência
    OptVal := 1;
    setsockopt(S, IPPROTO_TCP, TCP_NODELAY, PAnsiChar(@OptVal), SizeOf(OptVal));
  end
  else
  begin
    closesocket(S);
  end;
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
  Magic: Cardinal;
  PktType: Byte;
  Hdr: TFrameHeader;
  JpegStream: TMemoryStream;
  Jpg: TJPEGImage;
  FirstFrameLogged: Boolean;
  IPList: TStringList;
  CandidateIP: string;
  CandidatePorts: array[0..2] of Integer;
  PIdx, I, ConnectedPort, OptVal: Integer;
  HelloPkt: THelloPacket;
  GrantedControlByte: Byte;
begin
  if WSAStartup($0202, WSAData) <> 0 then
  begin
    Log('[STREAM CLIENT ERRO] Falha na inicialização do subsistema de rede (WSAStartup).');
    Exit;
  end;

  try
    CandidatePorts[0] := FPort;
    CandidatePorts[1] := 8080;
    CandidatePorts[2] := 9876;
    ConnectedPort := FPort;

    // 1. Se informou IP(s) local(is), tenta conectar na LAN em todas as portas candidatas
    if (FLocalIP <> '') and (FLocalIP <> '127.0.0.1') and (FLocalIP <> FHost) then
    begin
      IPList := TStringList.Create;
      try
        IPList.Delimiter := ',';
        IPList.StrictDelimiter := True;
        IPList.DelimitedText := FLocalIP;
        for I := 0 to IPList.Count - 1 do
        begin
          CandidateIP := Trim(IPList[I]);
          if (CandidateIP = '') or (CandidateIP = '127.0.0.1') then Continue;

          for PIdx := 0 to 2 do
          begin
            if not FRunning or Terminated then Break;
            Log('[STREAM CLIENT] Testando conexão LAN: ' + CandidateIP + ':' + IntToStr(CandidatePorts[PIdx]) + '...');
            FSocket := TryConnectTo(CandidateIP, CandidatePorts[PIdx], 1200);
            if FSocket <> INVALID_SOCKET then
            begin
              ConnectedPort := CandidatePorts[PIdx];
              Log('[STREAM CLIENT SUCESSO] Conectado via rede local (' + CandidateIP + ':' + IntToStr(ConnectedPort) + ')!');
              Break;
            end;
          end;
          if FSocket <> INVALID_SOCKET then Break;
        end;
      finally
        IPList.Free;
      end;
    end;

    // 2. Se a conexao local nao teve sucesso, tenta o endereço público em todas as portas candidatas
    if FSocket = INVALID_SOCKET then
    begin
      for PIdx := 0 to 2 do
      begin
        if not FRunning or Terminated then Break;
        Log('[STREAM CLIENT] Testando conexão pública: ' + FHost + ':' + IntToStr(CandidatePorts[PIdx]) + '...');
        FSocket := TryConnectTo(FHost, CandidatePorts[PIdx], 2500);
        if FSocket <> INVALID_SOCKET then
        begin
          ConnectedPort := CandidatePorts[PIdx];
          Log('[STREAM CLIENT SUCESSO] Conectado via endereço público (' + FHost + ':' + IntToStr(ConnectedPort) + ')!');
          Break;
        end;
      end;
    end;

    // 3. Se nenhuma porta P2P respondeu, aciona automaticamente o Modo Ponte (Servidor Relay)
    if FSocket = INVALID_SOCKET then
    begin
      Log('[STREAM CLIENT AVISO] Nenhuma porta P2P direta respondeu (' + FHost + ').');
      Log('[STREAM CLIENT AVISO] Acionando Modo Ponte automático através do Servidor...');
      Synchronize(@DoSyncFallbackRelay);
      Exit;
    end;

    // Realiza Handshake de autenticação com o Host
    Log('[STREAM CLIENT] Enviando credenciais de sessão para o host...');
    Magic := DESK_MAGIC;
    PktType := PKT_HELLO;
    FillChar(HelloPkt, SizeOf(HelloPkt), 0);
    HelloPkt.Version := 1;
    if FCanControl then HelloPkt.CanControl := 1 else HelloPkt.CanControl := 0;
    if FSessionId <> '' then
      Move(FSessionId[1], HelloPkt.SessionId[0], Length(FSessionId));
    if FAuthToken <> '' then
      Move(FAuthToken[1], HelloPkt.AuthToken[0], Length(FAuthToken));

    if not SendAll(Magic, SizeOf(Magic)) or
       not SendAll(PktType, SizeOf(PktType)) or
       not SendAll(HelloPkt, SizeOf(HelloPkt)) then
    begin
      Log('[STREAM CLIENT ERRO] Falha ao enviar aperto de mão ao host.');
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
      Synchronize(@DoSyncFallbackRelay);
      Exit;
    end;

    // Timeout de 3 segundos para resposta de autenticação
    OptVal := 3000;
    setsockopt(FSocket, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@OptVal), SizeOf(OptVal));

    if not RecvAll(Magic, SizeOf(Magic)) or (Magic <> DESK_MAGIC) or
       not RecvAll(PktType, SizeOf(PktType)) then
    begin
      Log('[STREAM CLIENT ERRO] Host não respondeu ao aperto de mão de segurança.');
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
      Synchronize(@DoSyncFallbackRelay);
      Exit;
    end;

    if PktType <> PKT_HELLO_ACK then
    begin
      Log('[STREAM CLIENT ERRO] Conexão recusada pelo host (código ' + IntToStr(PktType) + '). Token ou Sessão inválidos.');
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
      Exit;
    end;

    GrantedControlByte := 0;
    RecvAll(GrantedControlByte, 1);
    FCanControl := (GrantedControlByte = 1);
    Log('[STREAM CLIENT SUCESSO] Autenticado com sucesso no host! Permissão de controle concedida: ' + BoolToStr(FCanControl, True));

    OptVal := 0;
    setsockopt(FSocket, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@OptVal), SizeOf(OptVal));

    FConnected := True;
    FSyncPort := ConnectedPort;
    Synchronize(@DoSyncPortSuccess);

    FirstFrameLogged := False;
    Log('[STREAM CLIENT] Conexão de streaming ativa na porta ' + IntToStr(ConnectedPort) + '! Aguardando quadros de tela...');

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

            if not FirstFrameLogged then
            begin
              FirstFrameLogged := True;
              Log('[STREAM CLIENT] Primeiro quadro recebido (' + IntToStr(Hdr.Width) + 'x' + IntToStr(Hdr.Height) + ', ' + IntToStr(Hdr.JpegSize) + ' bytes)!');
            end
            else if (Hdr.FrameId mod 150) = 0 then
              Log('[STREAM CLIENT] ' + IntToStr(Hdr.FrameId) + ' quadros recebidos.');
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
    Log('[STREAM CLIENT] Conexão de streaming encerrada.');
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