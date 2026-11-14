program clipboard_windows;
{$mode objfpc}{$H+}{$codepage utf8}
uses Windows, Classes, SysUtils, uDeskClipboardData;
var OldStation, Station: HWINSTA; OldDesktop, Desktop: HDESK; Owner: HWND;
    Sequence, Applied, ReadSequence: DWORD; Text, Root: string; Paths, Received: TStringList;
procedure Check(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create('FAIL: '+Msg); WriteLn('OK ',Msg); end;
begin
  try
    // Never read or change the user's clipboard: all tests run in a private window station.
    OldStation:=GetProcessWindowStation; OldDesktop:=GetThreadDesktop(GetCurrentThreadId);
    Station:=CreateWindowStationW(PWideChar(UnicodeString('MaurinDeskClipboardTest'+IntToStr(GetCurrentProcessId))),0,GENERIC_ALL,nil);
    if Station=0 then begin
      WriteLn('SKIP: isolated clipboard station unavailable; Windows error ',GetLastError);
      Halt(77);
    end;
    Check(True,'private clipboard window station created');
    try
      Check(SetProcessWindowStation(Station),'process switched to isolated window station');
      Desktop:=CreateDesktopW('ClipboardTest',nil,nil,0,GENERIC_ALL,nil);
      Check(Desktop<>0,'private desktop created');
      try
        Check(SetThreadDesktop(Desktop),'thread switched to private desktop');
        Owner:=CreateWindowExW(0,'STATIC','Clipboard test',0,0,0,0,0,0,0,HInstance,nil);
        Check(Owner<>0,'clipboard owner window created');
        Paths:=TStringList.Create; Received:=TStringList.Create;
        try
          Sequence:=GetClipboardSequenceNumber;
          Check(WriteWindowsClipboard(Owner,Sequence,'Olá, 漢字 😀',Paths,Applied),'Unicode text placed on native clipboard');
          Check(GetClipboardOwner=Owner,'received clipboard ownership identifies own writes');
          Check(ReadWindowsClipboard(Owner,ReadSequence,Text,Received),'native Unicode text read');
          Check((Text='Olá, 漢字 😀') and (Received.Count=0),'Unicode text roundtrip exact');
          Check(not WriteWindowsClipboard(Owner,Sequence,'do not overwrite',Paths,Applied),'outdated local sequence cannot be overwritten');
          Root:=IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(1)));
          Paths.Add(Root+'ação.txt'); Paths.Add(Root+'Folder');
          Sequence:=GetClipboardSequenceNumber;
          Check(WriteWindowsClipboard(Owner,Sequence,'',Paths,Applied),'native CF_HDROP file list written');
          Check(ReadWindowsClipboard(Owner,ReadSequence,Text,Received),'native file list read');
          Check((Received.Count=2) and (Received[0]=Paths[0]) and (Received[1]=Paths[1]),'Unicode file paths roundtrip exact');
          WriteLn('PASS: Windows clipboard text and files verified without accessing user clipboard');
        finally Received.Free; Paths.Free; DestroyWindow(Owner); end;
      finally SetProcessWindowStation(OldStation); SetThreadDesktop(OldDesktop); CloseDesktop(Desktop); end;
    finally SetProcessWindowStation(OldStation); CloseWindowStation(Station); end;
  except on E: Exception do begin WriteLn(E.Message); Halt(1); end; end;
end.
