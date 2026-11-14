unit uDeskFileSystem;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, fpjson;
function NormalizeDiskPath(const Path: string; RequireDirectory: Boolean): string;
function ReadDiskDirectory(const Path, Filter: string; Offset: Integer = 0): TJSONObject;
procedure MakeDiskDirectory(const Parent, Name: string);
function PlaceFilePackage(const PackagePath, StagingDirectory, Destination: string; Overwrite: Boolean): TJSONObject;
implementation
uses Windows, LazFileUtils, LazUTF8, DateUtils, airemoteidentity, uDeskClipboardData;

function NormalizeDiskPath(const Path: string; RequireDirectory: Boolean): string;
var P, Ancestor, Drive: string; I: Integer; Attr, DriveType: DWORD;
begin
  P:=Path; if P='@home' then P:=SysUtils.GetEnvironmentVariable('USERPROFILE');
  P:=StringReplace(P,'/','\',[rfReplaceAll]);
  if (Length(P)=2) and (P[2]=':') then P:=P+'\';
  if (Length(P)<3) or not (P[1] in ['a'..'z','A'..'Z']) or (P[2]<>':') or (P[3]<>'\') or (Length(P)>2048) then
    raise Exception.Create('Selecione um caminho absoluto de uma unidade local, por exemplo C:\Users.');
  for I:=3 to Length(P) do if (Ord(P[I])<32) or (P[I] in [':','*','?','"','<','>','|']) then
    raise Exception.Create('Caminho de arquivos inválido.');
  Result:=ExpandFileName(P); Drive:=Copy(Result,1,3); DriveType:=GetDriveTypeW(PWideChar(UTF8Decode(Drive)));
  if (DriveType=DRIVE_REMOTE) or (DriveType=DRIVE_UNKNOWN) or (DriveType=DRIVE_NO_ROOT_DIR) then
    raise Exception.Create('Unidades de rede ou indisponíveis não são suportadas.');
  if Length(Result)>3 then Result:=ExcludeTrailingPathDelimiter(Result);
  for I:=3 to Length(Result)+1 do if (I>Length(Result)) or (Result[I]='\') then begin
    Ancestor:=Copy(Result,1,I-1); if Length(Ancestor)=2 then Ancestor:=Ancestor+'\';
    Attr:=GetFileAttributesW(PWideChar(UTF8Decode(Ancestor)));
    if Attr=INVALID_FILE_ATTRIBUTES then raise Exception.Create('Caminho indisponível ou sem permissão: '+Ancestor);
    if (Attr and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then raise Exception.Create('Links e junções não são acessados pelo gerenciador.');
  end;
  if RequireDirectory and not DirectoryExistsUTF8(Result) then raise Exception.Create('A pasta de destino não existe: '+Result);
end;

function ReadDiskDirectory(const Path, Filter: string; Offset: Integer): TJSONObject;
var DirectoryPath, ParentPath, Name, Kind, SortKey: string; Entries: TJSONArray; Sorted: TStringList;
    Search: TSearchRec; Item: TJSONObject; I, Last, Matched, FindResult: Integer; Mask, Attr: DWORD; Stamp: Int64;
begin
  if (Offset<0) or (Offset>1000000) then raise Exception.Create('Página inválida.');
  Result:=TJSONObject.Create; Entries:=TJSONArray.Create; Result.Add('entries',Entries);
  Sorted:=TStringList.Create; Sorted.Sorted:=True; Sorted.Duplicates:=dupAccept;
  try
    try
      DirectoryPath:=Path; ParentPath:='';
      if Path='' then begin
        Mask:=GetLogicalDrives;
        for I:=0 to 25 do if (Mask and (DWORD(1) shl I))<>0 then begin
          Name:=Chr(Ord('A')+I)+':\'; Attr:=GetDriveTypeW(PWideChar(UTF8Decode(Name)));
          if (Attr<>DRIVE_REMOTE) and (Attr<>DRIVE_UNKNOWN) and (Attr<>DRIVE_NO_ROOT_DIR) then
            Sorted.AddObject(Name,TJSONObject.Create(['name',Name,'kind','drive','size',Int64(0),'modified',Int64(0)]));
        end;
      end else begin
        DirectoryPath:=NormalizeDiskPath(Path,True);
        if Length(DirectoryPath)>3 then ParentPath:=ExtractFileDir(DirectoryPath);
        FindResult:=FindFirstUTF8(IncludeTrailingPathDelimiter(DirectoryPath)+'*',faAnyFile,Search);
        if (FindResult<>0) and (FindResult<>ERROR_FILE_NOT_FOUND) and (FindResult<>ERROR_NO_MORE_FILES) then
          raise Exception.Create('Nao foi possivel listar a pasta: '+SysErrorMessage(FindResult));
        if FindResult=0 then
        try
          repeat
            Name:=Search.Name;
            if (Name='.') or (Name='..') then Continue;
            if (Filter<>'') and (Pos(UTF8LowerCase(Filter),UTF8LowerCase(Name))=0) then Continue;
            Attr:=GetFileAttributesW(PWideChar(UTF8Decode(IncludeTrailingPathDelimiter(DirectoryPath)+Name)));
            if Attr=INVALID_FILE_ATTRIBUTES then Continue;
            Kind:='file'; SortKey:='1';
            if (Attr and FILE_ATTRIBUTE_DIRECTORY)<>0 then begin Kind:='dir'; SortKey:='0'; end;
            if (Attr and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then begin Kind:='link'; SortKey:='2'; end;
            Stamp:=0; if Search.Time>0 then Stamp:=DateTimeToUnix(FileDateToDateTime(Search.Time),False);
            Item:=TJSONObject.Create(['name',Name,'kind',Kind,'size',Search.Size,'modified',Stamp]);
            Sorted.AddObject(SortKey+UTF8LowerCase(Name),Item);
            if Sorted.Count>50000 then raise Exception.Create('Muitos itens nesta pasta. Use o filtro para restringir a busca.');
          until FindNextUTF8(Search)<>0;
        finally FindCloseUTF8(Search); end;
      end;
      Matched:=Sorted.Count; Last:=Offset+199; if Last>=Matched then Last:=Matched-1;
      for I:=Offset to Last do begin Entries.Add(TJSONObject(Sorted.Objects[I])); Sorted.Objects[I]:=nil; end;
      Result.Add('path',DirectoryPath); Result.Add('parent',ParentPath); Result.Add('offset',Offset);
      Result.Add('has_more',Last<Matched-1); Result.Add('next_offset',Last+1); Result.Add('total',Matched);
    except Result.Free; raise; end;
  finally
    for I:=0 to Sorted.Count-1 do Sorted.Objects[I].Free;
    Sorted.Free;
  end;
end;

procedure MakeDiskDirectory(const Parent, Name: string);
var P: string;
begin
  if not SafeClipboardPath(Name) or (Pos('/',Name)>0) then raise Exception.Create('Nome de pasta inválido.');
  P:=IncludeTrailingPathDelimiter(NormalizeDiskPath(Parent,True))+Name;
  if FileExistsUTF8(P) or DirectoryExistsUTF8(P) then raise Exception.Create('Já existe um item com esse nome.');
  if not CreateDirUTF8(P) then raise Exception.Create('Não foi possível criar a pasta. Verifique as permissões.');
end;

function PlaceFilePackage(const PackagePath, StagingDirectory, Destination: string; Overwrite: Boolean): TJSONObject;
var Roots: TStringList; DestRoot, Target: string; I: Integer;
  procedure CheckTarget(const Source, Dest: string);
  var Search: TSearchRec;
  begin
    if FileExistsUTF8(Dest) or DirectoryExistsUTF8(Dest) then begin
      NormalizeDiskPath(Dest,False);
      if DirectoryExistsUTF8(Source)<>DirectoryExistsUTF8(Dest) then raise Exception.Create('Arquivo e pasta incompatíveis no destino: '+Dest);
    end;
    if DirectoryExistsUTF8(Source) and (FindFirstUTF8(IncludeTrailingPathDelimiter(Source)+'*',faAnyFile,Search)=0) then
    try
      repeat
        if (Search.Name<>'.') and (Search.Name<>'..') then CheckTarget(IncludeTrailingPathDelimiter(Source)+Search.Name,IncludeTrailingPathDelimiter(Dest)+Search.Name);
      until FindNextUTF8(Search)<>0;
    finally FindCloseUTF8(Search); end;
  end;
  procedure CopyItem(const Source, Dest: string);
  var Search: TSearchRec; Temp: string; Flags: DWORD;
  begin
    if DirectoryExistsUTF8(Source) then begin
      if not DirectoryExistsUTF8(Dest) and not CreateDirUTF8(Dest) then raise Exception.Create('Não foi possível criar: '+Dest);
      NormalizeDiskPath(Dest,True);
      if FindFirstUTF8(IncludeTrailingPathDelimiter(Source)+'*',faAnyFile,Search)=0 then
      try
        repeat if (Search.Name<>'.') and (Search.Name<>'..') then
          CopyItem(IncludeTrailingPathDelimiter(Source)+Search.Name,IncludeTrailingPathDelimiter(Dest)+Search.Name);
        until FindNextUTF8(Search)<>0;
      finally FindCloseUTF8(Search); end;
    end else begin
      NormalizeDiskPath(ExtractFileDir(Dest),True);
      if FileExistsUTF8(Dest) then begin
        NormalizeDiskPath(Dest,False);
        if not Overwrite then raise Exception.Create('Já existe no destino: '+Dest);
      end;
      Temp:=IncludeTrailingPathDelimiter(ExtractFileDir(Dest))+'.MaurinDesk-'+AIRemoteUUID+'.part';
      try
        if not CopyFileW(PWideChar(UTF8Decode(Source)),PWideChar(UTF8Decode(Temp)),True) then
          raise Exception.Create('Falha ao copiar para '+Dest+': '+SysErrorMessage(GetLastError));
        Flags:=$00000008; if Overwrite then Flags:=Flags or MOVEFILE_REPLACE_EXISTING;
        if not MoveFileExW(PWideChar(UTF8Decode(Temp)),PWideChar(UTF8Decode(Dest)),Flags) then
          raise Exception.Create('Falha ao gravar '+Dest+': '+SysErrorMessage(GetLastError));
      finally if FileExistsUTF8(Temp) then DeleteFileUTF8(Temp); end;
    end;
  end;
begin
  DestRoot:=NormalizeDiskPath(Destination,True); Roots:=TStringList.Create;
  try
    ExtractClipboardFiles(PackagePath,StagingDirectory,Roots);
    // Preflight all root conflicts before writing anything into the selected destination.
    for I:=0 to Roots.Count-1 do begin
      Target:=IncludeTrailingPathDelimiter(DestRoot)+ExtractFileName(ExcludeTrailingPathDelimiter(Roots[I]));
      if not Overwrite and (FileExistsUTF8(Target) or DirectoryExistsUTF8(Target)) then
        raise Exception.Create('Já existe no destino: '+Target+'. Ative a substituição ou escolha outra pasta.');
      CheckTarget(Roots[I],Target);
    end;
    for I:=0 to Roots.Count-1 do CopyItem(Roots[I],IncludeTrailingPathDelimiter(DestRoot)+ExtractFileName(ExcludeTrailingPathDelimiter(Roots[I])));
    Result:=TJSONObject.Create(['destination',DestRoot,'count',Roots.Count]);
  finally Roots.Free; end;
end;
end.
