unit uDeskRelay;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, base64, fpjson, jsonparser,
  uScreenCapture, uDeskProtocol, airemotesignaling;

type
  TRelayLogEvent = procedure(Sender: TObject; const Msg: string) of object;
  TRelayFrameEvent = procedure(Sender: TObject; FrameBmp: Graphics.TBitmap; FrameId: Cardinal) of object;

  { Host Relay: captura quadros da tela e envia ao servidor como ponte }
  TDeskRelayHost = class(TThread)
  private
    FAPIURL: string;
    FToken: string;
    FSessionId: string;
    FAllowLocal: Boolean;
    FQuality: Integer;
    FRunning: Boolean;
    FOnLog: TRelayLogEvent;
    FSyncMsg: string;
    procedure Log(const S: string);
    procedure DoSyncLog;
  protected
    procedure Execute; override;
  public
    constructor Create(const APIURL, Token, SessionId: string; AllowLocal: Boolean; AQuality: Integer = 55);
    destructor Destroy; override;
    procedure StopRelay;
    property OnLog: TRelayLogEvent read FOnLog write FOnLog;
  end;

  { Client Relay: consulta quadros na ponte do servidor e enfileira comandos do usuario }
  TDeskRelayClient = class(TThread)
  private
    FAPIURL: string;
    FToken: string;
    FSessionId: string;
    FAllowLocal: Boolean;
    FRunning: Boolean;
    FLatestFrameId: Cardinal;
    FLatestBmp: Graphics.TBitmap;
    FSyncBmp: Graphics.TBitmap;
    FSyncFrameId: Cardinal;
    FInputQueue: TJSONArray;
    FLock: TRTLCriticalSection;
    FOnLog: TRelayLogEvent;
    FOnFrame: TRelayFrameEvent;
    FSyncMsg: string;
    procedure Log(const S: string);
    procedure DoSyncLog;
    procedure DoSyncFrame;
    function ExtractPendingInputs: TJSONArray;
  protected
    procedure Execute; override;
  public
    constructor Create(const APIURL, Token, SessionId: string; AllowLocal: Boolean);
    destructor Destroy; override;
    procedure StopRelay;
    procedure SendMouseMove(NormX, NormY: Word);
    procedure SendMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word);
    procedure SendMouseWheel(Delta: SmallInt);
    procedure SendKey(KeyCode: Word; IsDown: Boolean);
    property OnLog: TRelayLogEvent read FOnLog write FOnLog;
    property OnFrame: TRelayFrameEvent read FOnFrame write FOnFrame;
  end;

implementation

{ TDeskRelayHost }

constructor TDeskRelayHost.Create(const APIURL, Token, SessionId: string; AllowLocal: Boolean; AQuality: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FAPIURL := APIURL;
  FToken := Token;
  FSessionId := SessionId;
  FAllowLocal := AllowLocal;
  FQuality := AQuality;
  FRunning := True;
end;

destructor TDeskRelayHost.Destroy;
begin
  StopRelay;
  inherited Destroy;
end;

procedure TDeskRelayHost.StopRelay;
begin
  FRunning := False;
  Terminate;
end;

procedure TDeskRelayHost.Log(const S: string);
begin
  FSyncMsg := S;
  Synchronize(@DoSyncLog);
end;

procedure TDeskRelayHost.DoSyncLog;
begin
  if Assigned(FOnLog) then
    FOnLog(Self, FSyncMsg);
end;

procedure TDeskRelayHost.Execute;
var
  Client: TAIRemoteSignalingClient;
  Bmp: Graphics.TBitmap;
  JpegStream: TMemoryStream;
  RawBytes: string;
  Base64Data: string;
  FrameId: Cardinal;
  FirstFrameConfirmed: Boolean;
  Resp: TJSONObject;
  InputResp: TJSONObject;
  EventsArr: TJSONArray;
  I: Integer;
  EvObj: TJSONObject;
  EvType: string;
  X, Y: Integer;
  Btn: Integer;
  IsDown: Boolean;
  WheelDelta, KeyCode: Integer;
begin
  Log('[PONTE HOST] Iniciando transmissão em Modo Ponte através do Servidor...');
  Client := TAIRemoteSignalingClient.Create;
  Client.BaseURL := FAPIURL;
  Client.DeviceToken := FToken;
  Client.AllowLocalHTTP := FAllowLocal;
  FrameId := 0;
  FirstFrameConfirmed := False;

  try
    while FRunning and not Terminated do
    begin
      // 1. Captura a tela e compacta em JPEG
      if CaptureScreenBitmap(Bmp) then
      begin
        try
          JpegStream := TMemoryStream.Create;
          try
            CompressBitmapToJpegStream(Bmp, JpegStream, FQuality);
            Inc(FrameId);

            // Converte fluxo JPEG para string Base64
            SetLength(RawBytes, JpegStream.Size);
            if JpegStream.Size > 0 then
            begin
              Move(JpegStream.Memory^, RawBytes[1], JpegStream.Size);
              Base64Data := EncodeStringBase64(RawBytes);

              // Envia quadro à ponte no servidor
              try
                Resp := Client.PostRelayFrame(FSessionId, FrameId, Base64Data);
                if Resp <> nil then
                begin
                  try
                    if not FirstFrameConfirmed then
                    begin
                      Log('[PONTE HOST] Primeiro quadro enviado ao servidor (HTTP relay).');
                      FirstFrameConfirmed := True;
                    end;
                  finally
                    Resp.Free;
                  end;
                end
                else if FrameId = 1 then
                  Log('[PONTE HOST ERRO] Servidor nao confirmou o primeiro quadro.');
              except
                on E: Exception do
                begin
                  if (FrameId <= 3) or (FrameId mod 30 = 0) then
                    Log('[PONTE HOST ERRO] Falha ao enviar quadro ' + IntToStr(FrameId) + ': ' + E.Message);
                end;
              end;
            end;
          finally
            JpegStream.Free;
          end;
        finally
          Bmp.Free;
        end;
      end;

      // 2. Consulta comandos de mouse/teclado pendentes na ponte
      try
        InputResp := Client.GetRelayInput(FSessionId);
        if InputResp <> nil then
        begin
          try
            EventsArr := TJSONArray(InputResp.Find('events'));
            if EventsArr <> nil then
            begin
              for I := 0 to EventsArr.Count - 1 do
              begin
                EvObj := TJSONObject(EventsArr.Items[I]);
                if EvObj = nil then Continue;
                EvType := EvObj.Get('type', '');
                if EvType = 'move' then
                begin
                  X := EvObj.Get('x', 0);
                  Y := EvObj.Get('y', 0);
                  InjectMouseMove(Word(X), Word(Y));
                end
                else if EvType = 'button' then
                begin
                  Btn := EvObj.Get('btn', 1);
                  IsDown := EvObj.Get('down', true);
                  X := EvObj.Get('x', 0);
                  Y := EvObj.Get('y', 0);
                  InjectMouseButton(Byte(Btn), IsDown, Word(X), Word(Y));
                end
                else if EvType = 'wheel' then
                begin
                  WheelDelta := EvObj.Get('delta', 0);
                  InjectMouseWheel(SmallInt(WheelDelta));
                end
                else if EvType = 'key' then
                begin
                  KeyCode := EvObj.Get('key', 0);
                  IsDown := EvObj.Get('down', true);
                  InjectKeyEvent(Word(KeyCode), IsDown);
                end;
              end;
            end;
          finally
            InputResp.Free;
          end;
        end;
      except
      end;

      // Intervalo entre transmissões pela ponte (150ms ~ 6-7 FPS estáveis via HTTP)
      Sleep(150);
    end;
  finally
    Client.Free;
    Log('[PONTE HOST] Transmissão em Modo Ponte finalizada.');
  end;
end;

{ TDeskRelayClient }

constructor TDeskRelayClient.Create(const APIURL, Token, SessionId: string; AllowLocal: Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FAPIURL := APIURL;
  FToken := Token;
  FSessionId := SessionId;
  FAllowLocal := AllowLocal;
  FRunning := True;
  FLatestFrameId := 0;
  FLatestBmp := Graphics.TBitmap.Create;
  FSyncBmp := Graphics.TBitmap.Create;
  FInputQueue := TJSONArray.Create;
  InitCriticalSection(FLock);
end;

destructor TDeskRelayClient.Destroy;
begin
  StopRelay;
  DoneCriticalSection(FLock);
  FLatestBmp.Free;
  FSyncBmp.Free;
  FInputQueue.Free;
  inherited Destroy;
end;

procedure TDeskRelayClient.StopRelay;
begin
  FRunning := False;
  Terminate;
end;

procedure TDeskRelayClient.Log(const S: string);
begin
  FSyncMsg := S;
  Synchronize(@DoSyncLog);
end;

procedure TDeskRelayClient.DoSyncLog;
begin
  if Assigned(FOnLog) then
    FOnLog(Self, FSyncMsg);
end;

procedure TDeskRelayClient.DoSyncFrame;
begin
  if Assigned(FOnFrame) then
    FOnFrame(Self, FSyncBmp, FSyncFrameId);
end;

function TDeskRelayClient.ExtractPendingInputs: TJSONArray;
begin
  EnterCriticalSection(FLock);
  try
    Result := FInputQueue;
    FInputQueue := TJSONArray.Create;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDeskRelayClient.SendMouseMove(NormX, NormY: Word);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create(['type', 'move', 'x', NormX, 'y', NormY]);
  EnterCriticalSection(FLock);
  try
    FInputQueue.Add(Obj);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDeskRelayClient.SendMouseButton(Button: Byte; IsDown: Boolean; NormX, NormY: Word);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create(['type', 'button', 'btn', Button, 'down', IsDown, 'x', NormX, 'y', NormY]);
  EnterCriticalSection(FLock);
  try
    FInputQueue.Add(Obj);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDeskRelayClient.SendMouseWheel(Delta: SmallInt);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create(['type', 'wheel', 'delta', Delta]);
  EnterCriticalSection(FLock);
  try
    FInputQueue.Add(Obj);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDeskRelayClient.SendKey(KeyCode: Word; IsDown: Boolean);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create(['type', 'key', 'key', KeyCode, 'down', IsDown]);
  EnterCriticalSection(FLock);
  try
    FInputQueue.Add(Obj);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDeskRelayClient.Execute;
var
  Client: TAIRemoteSignalingClient;
  Resp: TJSONObject;
  FrameId: Cardinal;
  Base64Data, RawBytes: string;
  JpegStream: TMemoryStream;
  Jpg: TJPEGImage;
  PendingInputs: TJSONArray;
  PostResp: TJSONObject;
begin
  Log('[PONTE CLIENTE] Conectando à ponte do servidor...');
  Client := TAIRemoteSignalingClient.Create;
  Client.BaseURL := FAPIURL;
  Client.DeviceToken := FToken;
  Client.AllowLocalHTTP := FAllowLocal;

  try
    while FRunning and not Terminated do
    begin
      // 1. Envia inputs pendentes do usuário para a ponte
      PendingInputs := ExtractPendingInputs;
      if (PendingInputs <> nil) and (PendingInputs.Count > 0) then
      begin
        try
          PostResp := Client.PostRelayInput(FSessionId, PendingInputs);
          if PostResp <> nil then PostResp.Free;
        finally
          PendingInputs.Free;
        end;
      end
      else if PendingInputs <> nil then
        PendingInputs.Free;

      // 2. Consulta o quadro mais recente da tela remota na ponte
      try
        Resp := Client.GetRelayFrame(FSessionId);
        if Resp <> nil then
        begin
          try
            FrameId := Cardinal(Resp.Get('frame_id', 0));
            Base64Data := Resp.Get('frame_data', '');

            if (FrameId > FLatestFrameId) and (Base64Data <> '') then
            begin
              FLatestFrameId := FrameId;
              RawBytes := DecodeStringBase64(Base64Data);

              if Length(RawBytes) > 0 then
              begin
                JpegStream := TMemoryStream.Create;
                Jpg := TJPEGImage.Create;
                try
                  JpegStream.WriteBuffer(RawBytes[1], Length(RawBytes));
                  JpegStream.Position := 0;
                  Jpg.LoadFromStream(JpegStream);
                  FLatestBmp.Assign(Jpg);

                  FSyncBmp.Assign(FLatestBmp);
                  FSyncFrameId := FrameId;
                  if FLatestFrameId = FrameId then
                    if FrameId = 1 then Log('[PONTE CLIENTE] Primeiro JPEG recebido e decodificado.');
                  Synchronize(@DoSyncFrame);
                finally
                  Jpg.Free;
                  JpegStream.Free;
                end;
              end;
            end;
          finally
            Resp.Free;
          end;
        end;
      except
        on E: Exception do
          Log('[PONTE CLIENTE ERRO] ' + E.Message);
      end;

      // Polling a cada 100ms
      Sleep(100);
    end;
  finally
    Client.Free;
    Log('[PONTE CLIENTE] Conexão com a ponte do servidor encerrada.');
  end;
end;

end.
