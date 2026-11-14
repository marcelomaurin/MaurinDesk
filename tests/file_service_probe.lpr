program file_service_probe;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, fpjson, jsonparser, Graphics,
  uDeskHTTP, uDeskFiles, uDeskFileManager, uDeskFileSystem;
type TObserver=class
  public Listings,Uploads,Downloads,ErrorReceipts: Integer; ExpectedError: Boolean; Controller: TObject; Failed: string; Manager: TDeskFileManager;
  procedure Event(Sender: TObject; Data: TJSONObject);
end;
procedure TObserver.Event(Sender: TObject; Data: TJSONObject);
begin
  if Data.Get('event','')<>'listing' then begin WriteLn(Data.AsJSON); Flush(Output); end;
  if Manager<>nil then Manager.HandleEvent(Data);
  if Data.Get('event','')='listing' then Inc(Listings);
  if (Data.Get('state','')='error') or (Data.Get('event','')='service_error') or (Data.Get('event','')='listing_error') then begin
    if ExpectedError and (Data.Get('state','')='error') then begin if Sender=Controller then Inc(ErrorReceipts); end
    else Failed:=Data.Get('message','Unknown error');
  end;
  if Data.Get('state','')='completed' then begin
    if Data.Get('direction','')='send' then Inc(Uploads) else Inc(Downloads);
  end;
end;
var Config: TJSONObject; Input: TStringList; A,B: TDeskFiles; Observer: TObserver;
  SessionData,Accepted: TJSONObject; EventData: TJSONObject; Paths: TStringList; Deadline: QWord; Bitmap: TBitmap; PNG: TPortableNetworkGraphic;
procedure WaitFor(Listings,Uploads,Downloads: Integer);
begin
  Deadline:=GetTickCount64+90000;
  while (Observer.Listings<Listings) or (Observer.Uploads<Uploads) or (Observer.Downloads<Downloads) do begin
    CheckSynchronize(10); Application.ProcessMessages;
    if Observer.Failed<>'' then raise Exception.Create(Observer.Failed);
    if GetTickCount64>Deadline then raise Exception.Create('Timeout waiting for actual peer delivery');
  end;
end;
begin
  try
  Application.Initialize; RequireDerivedFormResource:=False;
  Input:=TStringList.Create; Input.LoadFromFile(ParamStr(1)); Config:=TJSONObject(GetJSON(Input.Text)); Input.Free;
  SessionData:=DeskRequestSession(Config.Get('url',''),Config.Get('controller_token',''),Config.Get('host_key',''),True,True);
  try
    Config.Add('session',SessionData.Get('id',''));
    Accepted:=DeskAcceptControl(Config.Get('url',''),Config.Get('host_token',''),SessionData.Get('id',''),True,SessionData.Arrays['requested_permissions']);
    Accepted.Free;
  finally SessionData.Free; end;
  A:=TDeskFiles.Create(Config.Get('url',''),Config.Get('controller_token',''),Config.Get('session',''),True,Config.Get('cache',''));
  B:=TDeskFiles.Create(Config.Get('url',''),Config.Get('host_token',''),Config.Get('session',''),True,Config.Get('cache',''));
  Observer:=TObserver.Create; Paths:=TStringList.Create;
  try
    Observer.Controller:=A; A.OnEvent:=@Observer.Event; B.OnEvent:=@Observer.Event; B.IsRequester:=False;

    A.Start; B.Start;
    A.Browse(True,Config.Get('source',''),''); A.Browse(False,Config.Get('destination',''),'');
    WaitFor(2,0,0);
    Paths.Add(Config.Get('source','')+'\Arquivo.txt'); Paths.Add(Config.Get('source','')+'\Pasta');
    A.Send(Paths,Config.Get('destination',''),False); WaitFor(2,1,1);
    Paths.Clear; Paths.Add(Config.Get('destination','')+'\Arquivo.txt'); Paths.Add(Config.Get('destination','')+'\Pasta');
    A.Receive(Paths,Config.Get('download',''),False); WaitFor(2,2,2);
    Observer.ExpectedError:=True; Paths.Clear; Paths.Add(Config.Get('destination','')+'\Missing-file.txt');
    A.Receive(Paths,Config.Get('download',''),False);
    Deadline:=GetTickCount64+30000;
    while Observer.ErrorReceipts=0 do begin CheckSynchronize(10); Application.ProcessMessages;
      if Observer.Failed<>'' then raise Exception.Create(Observer.Failed);
      if GetTickCount64>Deadline then raise Exception.Create('Remote preparation failure not reported to requester');
    end;
    WriteLn('PASS: remote missing-source error reported back to requesting computer');
    Observer.Manager:=TDeskFileManager.CreateManager(nil,nil); Observer.Manager.Show;
    EventData:=TJSONObject.Create(['event','listing','local',True,'ticket','']); EventData.Add('data',ReadDiskDirectory(Config.Get('source',''),''));
    Observer.Manager.HandleEvent(EventData); EventData.Free;
    EventData:=TJSONObject.Create(['event','listing','local',False,'ticket','']); EventData.Add('data',ReadDiskDirectory(Config.Get('destination',''),''));
    Observer.Manager.HandleEvent(EventData); EventData.Free;
    Bitmap:=TBitmap.Create; PNG:=TPortableNetworkGraphic.Create;
    try Application.ProcessMessages; Bitmap.SetSize(Observer.Manager.Width,Observer.Manager.Height); Observer.Manager.PaintTo(Bitmap.Canvas,0,0);
      PNG.Assign(Bitmap); PNG.SaveToFile(Config.Get('preview',''));
    finally PNG.Free; Bitmap.Free; end;
    WriteLn('PASS: native local/remote browsing, upload, download, final disk receipts and file manager rendering');
  finally
    A.OnEvent:=nil; B.OnEvent:=nil; A.Terminate; B.Terminate; A.WaitFor; B.WaitFor;
    Observer.Manager.Free; A.Free; B.Free; Paths.Free; Observer.Free; Config.Free;
  end;
  except on E: Exception do begin WriteLn(E.ClassName,': ',E.Message); Flush(Output); Halt(1); end; end;
end.
