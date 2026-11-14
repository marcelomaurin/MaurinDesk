unit uDeskInstall;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
function InstallMaurinDesk: string;
procedure ConfigureWindowsStartup(Enabled: Boolean; const ExePath: string);
implementation
uses Windows, Registry, ComObj, Variants, ActiveX;
procedure ConfigureWindowsStartup(Enabled: Boolean; const ExePath: string);
var Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run',True) then
      raise Exception.Create('Nao foi possivel configurar o inicio com o Windows');
    if Enabled then Reg.WriteString('MaurinDesk','"'+ExePath+'" --minimized')
    else if Reg.ValueExists('MaurinDesk') then Reg.DeleteValue('MaurinDesk');
  finally Reg.Free; end;
end;
function InstallMaurinDesk: string;
var Dir, LinkPath, Stage: string; Shell, Shortcut: OleVariant; Init: HRESULT;
begin
  Dir := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('LOCALAPPDATA'))+'Programs\MaurinSoft\MaurinDesk';
  if not ForceDirectories(Dir) then raise Exception.Create('Nao foi possivel criar a pasta de instalacao');
  Result := IncludeTrailingPathDelimiter(Dir)+'MaurinDesk.exe';
  if CompareText(ExpandFileName(ParamStr(0)),ExpandFileName(Result))<>0 then begin
    Stage := Result+'.installing';
    if not CopyFileW(PWideChar(UTF8Decode(ParamStr(0))),PWideChar(UTF8Decode(Stage)),False) then RaiseLastOSError;
    if not MoveFileExW(PWideChar(UTF8Decode(Stage)),PWideChar(UTF8Decode(Result)),MOVEFILE_REPLACE_EXISTING or $00000008) then
      raise Exception.Create('Feche o MaurinDesk instalado antes de substituir o executavel');
  end;
  LinkPath := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA'))+'Microsoft\Windows\Start Menu\Programs\MaurinDesk.lnk';
  Init:=CoInitialize(nil);
  try
    Shell := CreateOleObject('WScript.Shell'); Shortcut := Shell.CreateShortcut(WideString(UTF8Decode(LinkPath)));
    Shortcut.TargetPath := WideString(UTF8Decode(Result)); Shortcut.WorkingDirectory := WideString(UTF8Decode(Dir));
    Shortcut.Description := 'MaurinDesk — acesso remoto assistido'; Shortcut.Save;
    Shortcut:=Unassigned; Shell:=Unassigned;
  finally if (Init=S_OK) or (Init=S_FALSE) then CoUninitialize; end;
end;
end.
