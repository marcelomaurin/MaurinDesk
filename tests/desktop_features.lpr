program desktop_features;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, Windows, SysUtils, Graphics, fpjson, uDeskFileSystem, uDeskClipboardData, uDeskUpdate, setmain;
var Root, SourceDir, DestDir, PackageName, HashFile: string; Paths, Received: TStringList;
    Settings, Reloaded: TSetMain; Data: TJSONObject; Count, IconSize: Integer; Rejected: Boolean; IconModule: HMODULE; LoadedIcon: HICON; LoadedGraphic: TIcon;
procedure Check(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create('FAIL: '+Msg); Inc(Count); WriteLn('OK ',Msg); end;
procedure WriteBytes(const Path, Data: string);
var S: TFileStream;
begin S:=TFileStream.Create(Path,fmCreate); try if Data<>'' then S.WriteBuffer(Data[1],Length(Data)); finally S.Free; end; end;
function ReadBytes(const Path: string): string;
var S: TFileStream;
begin S:=TFileStream.Create(Path,fmOpenRead); try SetLength(Result,S.Size); if Result<>'' then S.ReadBuffer(Result[1],Length(Result)); finally S.Free; end; end;
procedure BadPath(const S: string);
begin Check(not SafeClipboardPath(S),'reject unsafe path '+S); end;
procedure RejectManifest;
var Rejected: Boolean;
begin Rejected:=False; try ValidateUpdateManifest(Data); except on E: Exception do Rejected:=True; end;
  Check(Rejected,'reject unsafe update manifest'); end;
begin
  try
    Application.Initialize;
    Root:=IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(1))); if ParamCount<>1 then raise Exception.Create('Expected test directory');
    ForceDirectories(Root); SourceDir:=Root+'Origem'; DestDir:=Root+'Received'; PackageName:=Root+'package.bin'; HashFile:=Root+'hash.txt';
    ForceDirectories(SourceDir+PathDelim+'Pasta vazia');
    WriteBytes(SourceDir+PathDelim+'ação.txt','Olá! 漢字 😀'+#13#10+'linha dois');
    WriteBytes(SourceDir+PathDelim+'binary.dat',#0#255#1#127+StringOfChar('Z',10*1024*1024));
    WriteBytes(Root+'outro.txt','Segundo arquivo');
    Paths:=TStringList.Create; Received:=TStringList.Create;
    try
      Paths.Add(SourceDir); Paths.Add(Root+'outro.txt'); BuildClipboardFiles(Paths,PackageName);
      ExtractClipboardFiles(PackageName,DestDir,Received);
      Check(Received.Count=2,'multiple copied roots preserved');
      Check(ReadBytes(DestDir+PathDelim+'Origem'+PathDelim+'ação.txt')=ReadBytes(SourceDir+PathDelim+'ação.txt'),'Unicode filename and text preserved');
      Check(ReadBytes(DestDir+PathDelim+'Origem'+PathDelim+'binary.dat')=ReadBytes(SourceDir+PathDelim+'binary.dat'),'binary file survives package roundtrip');
      Check(DirectoryExists(DestDir+PathDelim+'Origem'+PathDelim+'Pasta vazia'),'empty directory preserved');
      Check(ReadBytes(DestDir+PathDelim+'outro.txt')='Segundo arquivo','second root content preserved');
      BadPath('../escape'); BadPath('/absolute'); BadPath('C:/absolute'); BadPath('dir\escape'); BadPath('a/../b');
      BadPath('a//b'); BadPath('NUL.txt'); BadPath('COM1'); BadPath('name:stream'); BadPath('trailing.'); BadPath('trailing ');
      Check(SafeClipboardPath('Pasta/ação.txt'),'safe Unicode relative paths accepted');
    finally Received.Free; Paths.Free; end;
    ForceDirectories(Root+'Final');
    Data:=PlaceFilePackage(PackageName,Root+'Stage1',Root+'Final',False); Data.Free;
    Check(ReadBytes(Root+'Final/Origem/ação.txt')=ReadBytes(SourceDir+'/ação.txt'),'explicit final destination preserves Unicode');
    Check(DirectoryExists(Root+'Final/Origem/Pasta vazia'),'explicit final destination preserves empty folders');
    WriteBytes(Root+'Final/outro.txt','Preserve');
    Rejected:=False; try Data:=PlaceFilePackage(PackageName,Root+'Stage2',Root+'Final',False); Data.Free; except on E: Exception do Rejected:=True; end;
    Check(Rejected and (ReadBytes(Root+'Final/outro.txt')='Preserve'),'existing files preserved without overwrite');
    WriteBytes(Root+'Final/Origem/keep.txt','Keep extra');
    Data:=PlaceFilePackage(PackageName,Root+'Stage3',Root+'Final',True); Data.Free;
    Check(ReadBytes(Root+'Final/outro.txt')='Segundo arquivo','explicit overwrite replaces contents');
    Check(ReadBytes(Root+'Final/Origem/keep.txt')='Keep extra','folder merge preserves extra files');
    Data:=ReadDiskDirectory(Root+'Final','outro',0);
    Check(Data.Arrays['entries'].Count=1,'directory filtering lists actual destination'); Data.Free;
    MakeDiskDirectory(Root+'Final','Nova pasta'); Check(DirectoryExists(Root+'Final/Nova pasta'),'create directory in selected destination');
    Rejected:=False; try MakeDiskDirectory(Root+'Final','../outside'); except on E: Exception do Rejected:=True; end; Check(Rejected,'mkdir traversal blocked');
    Rejected:=False; try NormalizeDiskPath('C:relative',False); except on E: Exception do Rejected:=True; end; Check(Rejected,'relative drive path blocked');
    WriteBytes(HashFile,'abc');
    Check(FileSHA256(HashFile)='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad','native SHA-256 known vector');
    Check(VersionIsNewer('0.6.10','0.6.9'),'numeric version order handles double digits');
    Check(not VersionIsNewer('0.6.6','0.6.6'),'equal version does not update');
    Check(not VersionIsNewer('0.6.4','0.6.6'),'older version does not update');
    Check(not VersionIsNewer('malicious','0.6.6'),'invalid version does not update');
    Check(not VersionIsNewer('0."7".0','0.6.6'),'quoted version does not update');
    Check(ExecutableVersion(ExpandFileName(Root+'../../bin/MaurinDesk.exe'))='0.6.8.0','executable version resource matches release');
    IconModule:=LoadLibraryExW(PWideChar(UTF8Decode(ExpandFileName(Root+'../../bin/MaurinDesk.exe'))),0,LOAD_LIBRARY_AS_DATAFILE);
    Check(IconModule<>0,'executable resources available');
    try
      LoadedGraphic:=TIcon.Create;
      try LoadedGraphic.LoadFromResourceName(IconModule,'MAINICON');
        Check(not LoadedGraphic.Empty,'Lazarus decodes the embedded application and tray icon');
      finally LoadedGraphic.Free; end;
      for IconSize in [16,32,48] do begin
        LoadedIcon:=LoadImageW(IconModule,'MAINICON',IMAGE_ICON,IconSize,IconSize,0);
        Check(LoadedIcon<>0,'real application icon embedded at size '+IntToStr(IconSize));
        DestroyIcon(LoadedIcon);
      end;
    finally FreeLibrary(IconModule); end;
    Data:=TJSONObject.Create(['version','0.6.6','platform','windows-x64','filename','MaurinDesk.exe',
      'download_url',DESK_DOWNLOAD_URL,'bytes',27000000,'sha256',StringOfChar('a',64)]);
    try
      ValidateUpdateManifest(Data); Check(True,'valid pinned GitHub update accepted');
      Data.Strings['download_url']:='https://example.com/other.exe'; RejectManifest; Data.Strings['download_url']:=DESK_DOWNLOAD_URL;
      Data.Strings['filename']:='other.exe'; RejectManifest; Data.Strings['filename']:='MaurinDesk.exe';
      Data.Strings['sha256']:='invalid'; RejectManifest;
    finally Data.Free; end;
    Settings:=TSetMain.Create(Root+'Settings','');
    try
      Settings.ServerURL:='https://example.org/MaurinDesk/api'; Settings.Language:='es';
      Settings.StartWithWindows:=True; Settings.AutoUpdate:=False; Settings.StreamPort:=9876; Settings.Save;
      Reloaded:=TSetMain.Create(Root+'Settings','');
      try
        Check(Reloaded.ServerURL=Settings.ServerURL,'fsetmain persists server URL');
        Check((Reloaded.Language='es') and (Reloaded.StreamPort=9876),'fsetmain persists language and port');
        Check(Reloaded.StartWithWindows and not Reloaded.AutoUpdate,'fsetmain persists startup and updater choices');
      finally Reloaded.Free; end;
    finally Settings.Free; end;
    WriteLn(Count,' desktop feature assertions passed');
  except on E: Exception do begin WriteLn(E.Message); Halt(1); end; end;
end.
