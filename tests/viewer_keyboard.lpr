program viewer_keyboard;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, Buttons, Windows, uRemoteViewer;
type TObserver = class
  Closed: Boolean; FilesOpened: Integer;
  procedure OnFiles(Sender: TObject);
  procedure OnClose(Sender: TObject);
end;
procedure TObserver.OnFiles(Sender: TObject);
begin Inc(FilesOpened); end;
procedure TObserver.OnClose(Sender: TObject);
begin Closed:=True; end;
const Widths: array[0..3] of Integer=(640,800,1024,1280);
var Viewer: TfRemoteViewer; Observer: TObserver; Target: HWND; K: Word; W: Integer; FilesButton: TSpeedButton;
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
      Viewer:=TfRemoteViewer.CreateViewer(nil,'0123456789',True,nil);
      try
        Viewer.OnOpenFileManager:=@Observer.OnFiles; Viewer.Show;
        FilesButton:=TSpeedButton(Viewer.FindComponent('TransferFilesButton'));
        if FilesButton=nil then raise Exception.Create('Transfer files button missing');
        for W in Widths do begin
          Viewer.Width:=W; Application.ProcessMessages;
          if not FilesButton.IsVisible or (FilesButton.Left<0) or (FilesButton.Top<0) or
            (FilesButton.Left+FilesButton.Width>FilesButton.Parent.ClientWidth) or
            (FilesButton.Top+FilesButton.Height>FilesButton.Parent.ClientHeight) then
            raise Exception.Create('Transfer files action clipped at width '+IntToStr(W));
          FilesButton.Click;
        end;
        if Observer.FilesOpened<>4 then raise Exception.Create('Visible transfer action did not open manager');
        WriteLn('PASS: transfer action visible and clickable at 640, 800, 1024 and 1280 pixels');
      finally Viewer.Free; end;
    finally Observer.Free; end;
    WriteLn('PASS: Enter, space, Tab and Escape do not disconnect remote session');
  except on E: Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end; end;
end.
