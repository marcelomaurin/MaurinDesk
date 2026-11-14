unit uDeskUpdate;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, fpjson;
const
  DESK_VERSION = '0.6.7';
  DESK_UPDATE_URL = 'https://raw.githubusercontent.com/marcelomaurin/MaurinDesk/fila/update.json';
  DESK_DOWNLOAD_URL = 'https://raw.githubusercontent.com/marcelomaurin/MaurinDesk/fila/bin/MaurinDesk.exe';
function VersionIsNewer(const Candidate, Current: string): Boolean;
function FileSHA256(const Filename: string): string;
function ExecutableVersion(const Filename: string): string;
procedure ValidateUpdateManifest(Data: TJSONObject);
procedure LaunchVerifiedUpdate(const StagedExe, TargetExe, ExpectedHash: string);
type
  TDeskUpdateThread = class(TThread)
  private FOnReady: TNotifyEvent; procedure Deliver;
  protected procedure Execute; override;
  public
    NewVersion, StagedExe, Checksum, Failure: string;
    constructor Create;
    property OnReady: TNotifyEvent read FOnReady write FOnReady;
  end;
implementation
uses Windows, uDeskHTTP, airemoteidentity;
function DeskCryptAcquire(out Provider: PtrUInt; Container, ProviderName: PWideChar; ProviderType, Flags: DWORD): BOOL;
  stdcall; external 'advapi32.dll' name 'CryptAcquireContextW';
function DeskCryptCreate(Provider: PtrUInt; Algorithm: DWORD; Key: PtrUInt; Flags: DWORD; out Hash: PtrUInt): BOOL;
  stdcall; external 'advapi32.dll' name 'CryptCreateHash';
function DeskCryptData(Hash: PtrUInt; Data: Pointer; Len, Flags: DWORD): BOOL;
  stdcall; external 'advapi32.dll' name 'CryptHashData';
function DeskCryptGet(Hash: PtrUInt; Param: DWORD; Data: Pointer; var Len: DWORD; Flags: DWORD): BOOL;
  stdcall; external 'advapi32.dll' name 'CryptGetHashParam';
function DeskCryptDestroy(Hash: PtrUInt): BOOL; stdcall; external 'advapi32.dll' name 'CryptDestroyHash';
function DeskCryptRelease(Provider: PtrUInt; Flags: DWORD): BOOL; stdcall; external 'advapi32.dll' name 'CryptReleaseContext';

function ParseVersion(const S: string; out Parts: array of Integer): Boolean;
var List: TStringList; I,J: Integer;
begin
  Result := False; if (S='') or (Length(S)>40) then Exit;
  for I:=1 to Length(S) do if not (S[I] in ['0'..'9','.']) then Exit;
  List := TStringList.Create;
  try
    List.StrictDelimiter := True; List.Delimiter := '.'; List.DelimitedText := S;
    if (List.Count<2) or (List.Count>Length(Parts)) then Exit;
    for I := 0 to High(Parts) do Parts[I] := 0;
    for I := 0 to List.Count-1 do begin
      if List[I]='' then Exit;
      for J := 1 to Length(List[I]) do if not (List[I][J] in ['0'..'9']) then Exit;
      if not TryStrToInt(List[I],Parts[I]) or (Parts[I]<0) then Exit;
    end;
    Result := True;
  finally List.Free; end;
end;
function VersionIsNewer(const Candidate, Current: string): Boolean;
var A,B: array[0..3] of Integer; I: Integer;
begin
  Result := False;
  if not ParseVersion(Candidate,A) or not ParseVersion(Current,B) then Exit;
  for I := 0 to High(A) do begin
    if A[I]>B[I] then Exit(True);
    if A[I]<B[I] then Exit(False);
  end;
end;
function FileSHA256(const Filename: string): string;
var Provider, Hash: PtrUInt; Stream: TFileStream; Buffer: array[0..65535] of Byte;
    Digest: array[0..31] of Byte; ReadCount,I: Integer; Len: DWORD;
begin
  Result := ''; Provider := 0; Hash := 0;
  if not DeskCryptAcquire(Provider,nil,nil,24,$F0000000) then RaiseLastOSError;
  try
    if not DeskCryptCreate(Provider,$800C,0,0,Hash) then RaiseLastOSError;
    try
      Stream := TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
      try
        repeat ReadCount := Stream.Read(Buffer,SizeOf(Buffer));
          if (ReadCount>0) and not DeskCryptData(Hash,@Buffer[0],ReadCount,0) then RaiseLastOSError;
        until ReadCount=0;
      finally Stream.Free; end;
      Len := SizeOf(Digest); if not DeskCryptGet(Hash,2,@Digest[0],Len,0) or (Len<>32) then RaiseLastOSError;
      for I := 0 to High(Digest) do Result := Result+LowerCase(IntToHex(Digest[I],2));
    finally DeskCryptDestroy(Hash); end;
  finally DeskCryptRelease(Provider,0); end;
end;
procedure ValidateUpdateManifest(Data: TJSONObject);
var V,Hash: string; P: array[0..3] of Integer; I: Integer; Size: Int64;
begin
  V := Data.Get('version',''); Hash := Data.Get('sha256',''); Size := Data.Get('bytes',Int64(0));
  if not ParseVersion(V,P) or (Data.Get('filename','')<>'MaurinDesk.exe') or
    (Data.Get('platform','')<>'windows-x64') or (Data.Get('download_url','')<>DESK_DOWNLOAD_URL) or
    (Size<1024) or (Size>104857600) or (Length(Hash)<>64) then raise Exception.Create('Manifesto de atualização inválido');
  for I := 1 to Length(Hash) do if not (Hash[I] in ['0'..'9','a'..'f']) then raise Exception.Create('SHA-256 de atualização inválido');
end;
function ExecutableVersion(const Filename: string): string;
var Size, Dummy: DWORD; Buffer, Value: Pointer; Len: UINT; Info: PVSFixedFileInfo;
begin
  Result:=''; Dummy:=0;
  Size:=GetFileVersionInfoSizeW(PWideChar(UTF8Decode(Filename)),@Dummy);
  if Size=0 then Exit;
  GetMem(Buffer,Size);
  try
    if not GetFileVersionInfoW(PWideChar(UTF8Decode(Filename)),0,Size,Buffer) then Exit;
    Value:=nil; Len:=0;
    if not VerQueryValueW(Buffer,'\',@Value,@Len) or (Len<SizeOf(TVSFixedFileInfo)) then Exit;
    Info:=PVSFixedFileInfo(Value);
    if Info^.dwSignature<>$FEEF04BD then Exit;
    Result:=IntToStr(Info^.dwFileVersionMS shr 16)+'.'+IntToStr(Info^.dwFileVersionMS and $FFFF)+'.'+
      IntToStr(Info^.dwFileVersionLS shr 16)+'.'+IntToStr(Info^.dwFileVersionLS and $FFFF);
  finally FreeMem(Buffer); end;
end;
constructor TDeskUpdateThread.Create;
begin inherited Create(True); FreeOnTerminate := False; end;
procedure TDeskUpdateThread.Deliver;
begin if Assigned(FOnReady) then FOnReady(Self); end;
procedure TDeskUpdateThread.Execute;
var Data: TJSONObject; Dir, DownloadedVersion: string; FileInfo: TSearchRec;
begin
  try
    Data := DeskGetJSON(DESK_UPDATE_URL);
    try
      ValidateUpdateManifest(Data);
      if VersionIsNewer(Data.Get('version',''),DESK_VERSION) and not Terminated then begin
        NewVersion := Data.Get('version',''); Checksum := Data.Get('sha256','');
        Dir := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('LOCALAPPDATA'))+'MaurinDesk\Updates';
        if not ForceDirectories(Dir) then raise Exception.Create('Pasta de atualização indisponível');
        StagedExe := IncludeTrailingPathDelimiter(Dir)+'MaurinDesk-'+AIRemoteUUID+'.download';
        DeskDownloadFile(DESK_DOWNLOAD_URL,StagedExe,Data.Get('bytes',Int64(0)));
        if FindFirst(StagedExe,faAnyFile,FileInfo)<>0 then raise Exception.Create('Download indisponível');
        try if FileInfo.Size<>Data.Get('bytes',Int64(0)) then raise Exception.Create('Download incompleto'); finally SysUtils.FindClose(FileInfo); end;
        if FileSHA256(StagedExe)<>Checksum then raise Exception.Create('Verificação SHA-256 falhou; atualização descartada');
        DownloadedVersion:=ExecutableVersion(StagedExe);
        if (DownloadedVersion='') or VersionIsNewer(DownloadedVersion,NewVersion) or VersionIsNewer(NewVersion,DownloadedVersion) then
          raise Exception.Create('A versão do executável não corresponde ao JSON; atualização descartada');
      end;
    finally Data.Free; end;
  except on E: Exception do begin
    Failure := E.Message; NewVersion := '';
    if (StagedExe<>'') and FileExists(StagedExe) then SysUtils.DeleteFile(StagedExe); StagedExe := '';
  end; end;
  if not Terminated then Synchronize(@Deliver);
end;

function PSQuote(const S: string): string;
begin Result := ''''+StringReplace(S,'''','''''',[rfReplaceAll])+''''; end;
procedure LaunchVerifiedUpdate(const StagedExe, TargetExe, ExpectedHash: string);
var Lines: TStringList; Script, Raw: string; Stream: TFileStream; Startup: TStartupInfoW;
    Process: TProcessInformation; Command: UnicodeString; BOM: array[0..2] of Byte;
begin
  if FileSHA256(StagedExe)<>ExpectedHash then raise Exception.Create('Arquivo de atualização alterado');
  Script := ChangeFileExt(StagedExe,'.ps1'); Lines := TStringList.Create;
  try
    Lines.Add('$ErrorActionPreference = ''Stop''');
    Lines.Add('function Get-UpdateHash([string] $path) {');
    Lines.Add('  $stream = [System.IO.File]::OpenRead($path)');
    Lines.Add('  $sha = [System.Security.Cryptography.SHA256]::Create()');
    Lines.Add('  try { return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString(''x2'') }) }');
    Lines.Add('  finally { $sha.Dispose(); $stream.Dispose() }');
    Lines.Add('}');
    Lines.Add('$source = '+PSQuote(StagedExe)); Lines.Add('$target = '+PSQuote(TargetExe)); Lines.Add('$expected = '+PSQuote(ExpectedHash));
    Lines.Add('Wait-Process -Id '+IntToStr(GetCurrentProcessId)+' -ErrorAction SilentlyContinue');
    Lines.Add('try {');
    Lines.Add('  if ((Get-UpdateHash $source) -ne $expected) { throw ''SHA256'' }');
    Lines.Add('  $backup = $target + ''.previous''');
    Lines.Add('  Copy-Item -LiteralPath $target -Destination $backup -Force');
    Lines.Add('  $done = $false');
    Lines.Add('  for ($attempt = 0; $attempt -lt 30; $attempt++) {');
    Lines.Add('    try { Copy-Item -LiteralPath $source -Destination $target -Force; $done = $true; break } catch { Start-Sleep -Milliseconds 500 }');
    Lines.Add('  }');
    Lines.Add('  if (-not $done -or (Get-UpdateHash $target) -ne $expected) {');
    Lines.Add('    Copy-Item -LiteralPath $backup -Destination $target -Force; throw ''Falha ao substituir aplicativo''');
    Lines.Add('  }');
    Lines.Add('  Remove-Item -LiteralPath $source -Force');
    Lines.Add('  Start-Process -FilePath $target -ArgumentList ''--minimized'' -WindowStyle Hidden');
    Lines.Add('} catch { $_ | Out-String | Set-Content -LiteralPath ($target + ''.update-error.log''); Start-Process -FilePath $target -WindowStyle Hidden }');
    Raw := Lines.Text; Stream := TFileStream.Create(Script,fmCreate);
    try BOM[0]:=$EF; BOM[1]:=$BB; BOM[2]:=$BF; Stream.WriteBuffer(BOM,3); Stream.WriteBuffer(Raw[1],Length(Raw)); finally Stream.Free; end;
  finally Lines.Free; end;
  FillChar(Startup,SizeOf(Startup),0); Startup.cb:=SizeOf(Startup); Startup.dwFlags:=STARTF_USESHOWWINDOW; Startup.wShowWindow:=SW_HIDE;
  Command := '"'+UTF8Decode(SysUtils.GetEnvironmentVariable('SystemRoot'))+'\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+UTF8Decode(Script)+'"';
  if not CreateProcessW(nil,PWideChar(Command),nil,nil,False,CREATE_NO_WINDOW,nil,nil,Startup,Process) then RaiseLastOSError;
  CloseHandle(Process.hThread); CloseHandle(Process.hProcess);
end;
end.
