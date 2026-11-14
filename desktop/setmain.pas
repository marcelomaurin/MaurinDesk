unit setmain;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, IniFiles;
type
  { Adaptacao do TSetMain usado nos projetos MaurinSoft. Identidade e tokens ficam fora deste arquivo. }
  TSetMain = class
  private FFilename: string;
  public
    ServerURL, Language, InstallDirectory: string;
    StreamPort, WindowWidth, WindowHeight: Integer;
    StartWithWindows, MinimizeToTray, AutoUpdate: Boolean;
    constructor Create(const ConfigDirectory, LegacyFile: string);
    procedure Load;
    procedure Save;
    property Filename: string read FFilename;
  end;
implementation
constructor TSetMain.Create(const ConfigDirectory, LegacyFile: string);
var Legacy, Dest: TFileStream;
begin
  ForceDirectories(ConfigDirectory);
  FFilename := IncludeTrailingPathDelimiter(ConfigDirectory)+'Setmain.cfg';
  if not FileExists(FFilename) and FileExists(LegacyFile) then begin
    Legacy := TFileStream.Create(LegacyFile,fmOpenRead or fmShareDenyWrite);
    try Dest := TFileStream.Create(FFilename,fmCreate); try Dest.CopyFrom(Legacy,0); finally Dest.Free; end;
    finally Legacy.Free; end;
  end;
  Load;
end;
procedure TSetMain.Load;
var Ini: TIniFile;
begin
  Ini := TIniFile.Create(FFilename);
  try
    ServerURL := Ini.ReadString('Server','URL','https://maurinsoft.com.br/MaurinDesk/api');
    StreamPort := Ini.ReadInteger('Network','Port',7071);
    Language := Ini.ReadString('General','Language','pt');
    StartWithWindows := Ini.ReadBool('General','StartWithWindows',False);
    MinimizeToTray := Ini.ReadBool('General','MinimizeToTray',True);
    AutoUpdate := Ini.ReadBool('Updates','Automatic',True);
    InstallDirectory := Ini.ReadString('Installation','Directory','');
    WindowWidth := Ini.ReadInteger('Window','Width',1220); WindowHeight := Ini.ReadInteger('Window','Height',840);
  finally Ini.Free; end;
end;
procedure TSetMain.Save;
var Ini: TMemIniFile;
begin
  Ini := TMemIniFile.Create(FFilename);
  try
    Ini.WriteString('Server','URL',ServerURL); Ini.WriteInteger('Network','Port',StreamPort);
    Ini.WriteString('General','Language',Language);
    Ini.WriteBool('General','StartWithWindows',StartWithWindows);
    Ini.WriteBool('General','MinimizeToTray',MinimizeToTray);
    Ini.WriteBool('Updates','Automatic',AutoUpdate);
    Ini.WriteString('Installation','Directory',InstallDirectory);
    Ini.WriteInteger('Window','Width',WindowWidth); Ini.WriteInteger('Window','Height',WindowHeight);
    Ini.UpdateFile;
  finally Ini.Free; end;
end;
end.
