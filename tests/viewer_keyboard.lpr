program viewer_keyboard;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, Windows, uRemoteViewer;
type TObserver = class
  Closed: Boolean;
  procedure OnClose(Sender: TObject);
end;
procedure TObserver.OnClose(Sender: TObject);
begin Closed:=True; end;
var Viewer: TfRemoteViewer; Observer: TObserver; Target: HWND; K: Word;
begin
  try
    Application.Initialize; Observer:=TObserver.Create;
    try
      for K in [VK_RETURN,VK_SPACE,VK_TAB,VK_ESCAPE] do begin
        Observer.Closed:=False;
        Viewer:=TfRemoteViewer.CreateViewer(nil,'0123456789',True,nil);
        Viewer.OnCloseSession:=@Observer.OnClose; Viewer.Show; Application.ProcessMessages;
        if Viewer.ActiveControl<>nil then Target:=Viewer.ActiveControl.Handle else Target:=Viewer.Handle;
        PostMessage(Target,WM_KEYDOWN,K,0); PostMessage(Target,WM_KEYUP,K,0); Application.ProcessMessages;
        if Observer.Closed then raise Exception.Create('Remote key '+IntToStr(K)+' closed the viewer');
        Viewer.OnCloseSession:=nil; Viewer.Free;
      end;
    finally Observer.Free; end;
    WriteLn('PASS: Enter, space, Tab and Escape do not disconnect remote session');
  except on E: Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end; end;
end.
