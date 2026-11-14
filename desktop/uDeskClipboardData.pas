unit uDeskClipboardData;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Windows;
const
  CLIP_CHUNK_BYTES = 262144;
  CLIP_MAX_BYTES = 268435456;
  CLIP_MAX_TEXT = 1048576;
function GetClipboardSequenceNumber: DWORD; stdcall; external 'user32.dll';
function SafeClipboardPath(const S: string): Boolean;
procedure BuildClipboardFiles(Paths: TStrings; const Target: string);
procedure ExtractClipboardFiles(const Source, TargetDir: string; Roots: TStrings);
function ReadWindowsClipboard(Owner: HWND; out Sequence: DWORD; out Text: string; Paths: TStrings): Boolean;
function WriteWindowsClipboard(Owner: HWND; ExpectedSequence: DWORD; const Text: string; Paths: TStrings; out AppliedSequence: DWORD): Boolean;
implementation
uses ShellAPI, fpjson, jsonparser, LazFileUtils;
type
  TDropHeader = packed record
    Offset: DWORD;
    Point: TPoint;
    NonClient, Wide: BOOL;
  end;

function SafeClipboardPath(const S: string): Boolean;
var Parts: TStringList; Part, Stem: string; I, J: Integer;
begin
  Result := False;
  if (S = '') or (Length(S) > 1024) or (S[1] = '/') or (Pos('\', S) > 0) then Exit;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True; Parts.Delimiter := '/'; Parts.DelimitedText := S;
    for I := 0 to Parts.Count - 1 do begin
      Part := Parts[I];
      if (Part = '') or (Part = '.') or (Part = '..') or
        (Part[Length(Part)] in [' ', '.']) then Exit;
      for J := 1 to Length(Part) do
        if (Ord(Part[J]) < 32) or (Part[J] in [':','*','?','"','<','>','|']) then Exit;
      Stem := UpperCase(Copy(Part, 1, Pos('.', Part + '.') - 1));
      if (Stem = 'CON') or (Stem = 'PRN') or (Stem = 'AUX') or (Stem = 'NUL') or
        ((Length(Stem) = 4) and ((Copy(Stem,1,3) = 'COM') or (Copy(Stem,1,3) = 'LPT')) and (Stem[4] in ['0'..'9'])) then Exit;
    end;
    Result := Parts.Count > 0;
  finally Parts.Free; end;
end;

procedure RejectReparse(const Path: string);
var Attr: DWORD;
begin
  Attr := GetFileAttributesW(PWideChar(UTF8Decode(Path)));
  if (Attr = INVALID_FILE_ATTRIBUTES) or ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
    raise Exception.Create('Caminho indisponivel ou link de arquivo/pasta nao suportado');
end;

procedure BuildClipboardFiles(Paths: TStrings; const Target: string);
var Manifest: TJSONObject; Entries, RootNames: TJSONArray; Sources, Names: TStringList;
    OutFile, Input: TFileStream; Raw: string; Len: Cardinal; Total, Size: Int64; I: Integer;
  procedure AddPath(const DiskPath, Relative: string; Depth: Integer);
  var Search: TSearchRec; F: TFileStream;
  begin
    if (Depth > 64) or (Entries.Count >= 10000) or not SafeClipboardPath(Relative) then
      raise Exception.Create('Quantidade ou nome de arquivos nao suportado');
    RejectReparse(DiskPath);
    if DirectoryExistsUTF8(DiskPath) then begin
      Entries.Add(TJSONObject.Create(['path', Relative, 'kind', 'dir', 'size', 0])); Sources.Add('');
      if FindFirstUTF8(IncludeTrailingPathDelimiter(DiskPath) + '*', faAnyFile, Search) = 0 then
      try
        repeat
          if (Search.Name <> '.') and (Search.Name <> '..') then
            AddPath(IncludeTrailingPathDelimiter(DiskPath) + Search.Name, Relative + '/' + Search.Name, Depth + 1);
        until FindNextUTF8(Search) <> 0;
      finally FindCloseUTF8(Search); end;
    end else begin
      F := TFileStream.Create(DiskPath, fmOpenRead or fmShareDenyWrite);
      try Size := F.Size; finally F.Free; end;
      Inc(Total, Size);
      if Total > CLIP_MAX_BYTES - 1048580 then raise Exception.Create('Arquivos excedem o limite de 255 MiB por copia');
      Entries.Add(TJSONObject.Create(['path', Relative, 'kind', 'file', 'size', Size])); Sources.Add(DiskPath);
    end;
  end;
begin
  if (Paths.Count = 0) or (Paths.Count > 10000) then raise Exception.Create('Lista de arquivos invalida');
  Manifest := TJSONObject.Create; Sources := TStringList.Create; Names := TStringList.Create;
  Entries := TJSONArray.Create; RootNames := TJSONArray.Create;
  Manifest.Add('entries', Entries); Manifest.Add('roots', RootNames); Total := 0;
  try
    Names.CaseSensitive := False;
    for I := 0 to Paths.Count - 1 do begin
      Raw := ExtractFileName(ExcludeTrailingPathDelimiter(Paths[I]));
      if not SafeClipboardPath(Raw) or (Names.IndexOf(Raw) >= 0) then
        raise Exception.Create('Itens copiados tem nomes invalidos ou repetidos');
      Names.Add(Raw); RootNames.Add(Raw); AddPath(Paths[I], Raw, 0);
    end;
    Raw := Manifest.AsJSON; Len := Length(Raw);
    if Len > 1048576 then raise Exception.Create('Lista de arquivos muito grande');
    OutFile := TFileStream.Create(Target, fmCreate);
    try
      OutFile.WriteBuffer(Len, SizeOf(Len));
      if Len > 0 then OutFile.WriteBuffer(Raw[1], Len);
      for I := 0 to Entries.Count - 1 do if Sources[I] <> '' then begin
        RejectReparse(Sources[I]);
        Input := TFileStream.Create(Sources[I], fmOpenRead or fmShareDenyWrite);
        try
          Size := TJSONObject(Entries[I]).Get('size', Int64(0));
          if Input.Size <> Size then raise Exception.Create('Arquivo alterado durante a copia; copie novamente');
          if Size > 0 then OutFile.CopyFrom(Input, Size);
        finally Input.Free; end;
      end;
    finally OutFile.Free; end;
  finally Names.Free; Sources.Free; Manifest.Free; end;
end;

procedure ExtractClipboardFiles(const Source, TargetDir: string; Roots: TStrings);
var Input, OutputFile: TFileStream; Manifest: TJSONData; Entries, Names: TJSONArray;
    Seen: TStringList; Obj: TJSONObject; Raw, Relative, Kind, Dest: string;
    Len: Cardinal; I, J: Integer; Size, Total: Int64;
  procedure EnsureDirectory(const Path: string);
  begin
    if not DirectoryExistsUTF8(Path) then begin
      if not ForceDirectoriesUTF8(Path) then raise Exception.Create('Nao foi possivel criar pasta de recebimento');
    end;
    RejectReparse(Path);
  end;
begin
  Roots.Clear;
  Input := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite); Manifest := nil; Seen := TStringList.Create;
  try
    if (Input.Size < 4) or (Input.Size > CLIP_MAX_BYTES) then raise Exception.Create('Pacote de arquivos invalido');
    Input.ReadBuffer(Len, SizeOf(Len));
    if (Len = 0) or (Len > 1048576) or (Len > Input.Size - 4) then raise Exception.Create('Lista de arquivos invalida');
    SetLength(Raw, Len); Input.ReadBuffer(Raw[1], Len); Manifest := GetJSON(Raw);
    if not (Manifest is TJSONObject) then raise Exception.Create('Pacote invalido');
    Entries := TJSONObject(Manifest).Arrays['entries']; Names := TJSONObject(Manifest).Arrays['roots'];
    if (Entries = nil) or (Names = nil) or (Entries.Count > 10000) or (Names.Count = 0) then raise Exception.Create('Pacote invalido');
    // Validate the entire manifest before creating any received files.
    Seen.CaseSensitive := False; Total := Input.Position;
    for I := 0 to Entries.Count - 1 do begin
      if not (Entries[I] is TJSONObject) then raise Exception.Create('Entrada invalida');
      Obj := TJSONObject(Entries[I]); Relative := Obj.Get('path', ''); Kind := Obj.Get('kind', ''); Size := Obj.Get('size', Int64(-1));
      if not SafeClipboardPath(Relative) or (Seen.IndexOf(Relative) >= 0) or
        not ((Kind = 'file') or (Kind = 'dir')) or (Size < 0) or (Size > CLIP_MAX_BYTES) or ((Kind = 'dir') and (Size <> 0)) then
        raise Exception.Create('Caminho ou tamanho de arquivo invalido');
      Seen.Add(Relative); Inc(Total, Size);
      if Total > Input.Size then raise Exception.Create('Pacote de arquivos truncado');
    end;
    if Total <> Input.Size then raise Exception.Create('Tamanho do pacote incorreto');
    for I := 0 to Names.Count - 1 do
      if not SafeClipboardPath(Names.Strings[I]) or (Pos('/', Names.Strings[I]) > 0) or (Seen.IndexOf(Names.Strings[I]) < 0) then
        raise Exception.Create('Raiz de arquivo invalida');
    EnsureDirectory(TargetDir);
    for I := 0 to Entries.Count - 1 do begin
      Obj := TJSONObject(Entries[I]); Relative := StringReplace(Obj.Get('path',''), '/', PathDelim, [rfReplaceAll]);
      // Verify each existing ancestor; never follow junctions within the cache.
      Dest := IncludeTrailingPathDelimiter(TargetDir);
      for J := 1 to Length(Relative) do if Relative[J] = PathDelim then
        EnsureDirectory(Dest + Copy(Relative, 1, J - 1));
      Dest := Dest + Relative;
      if Obj.Get('kind','') = 'dir' then EnsureDirectory(Dest)
      else begin
        if FileExistsUTF8(Dest) or DirectoryExistsUTF8(Dest) then RejectReparse(Dest);
        OutputFile := TFileStream.Create(Dest, fmCreate);
        try Size := Obj.Get('size', Int64(0)); if Size > 0 then OutputFile.CopyFrom(Input, Size);
        finally OutputFile.Free; end;
      end;
    end;
    for I := 0 to Names.Count - 1 do Roots.Add(IncludeTrailingPathDelimiter(TargetDir) + Names.Strings[I]);
  finally Seen.Free; Manifest.Free; Input.Free; end;
end;

function ReadWindowsClipboard(Owner: HWND; out Sequence: DWORD; out Text: string; Paths: TStrings): Boolean;
var H: THandle; P: PWideChar; I, Count, Len, Capacity: UINT; W: UnicodeString;
begin
  Result := False; Text := ''; Paths.Clear;
  if not OpenClipboard(Owner) then Exit;
  try
    Sequence := GetClipboardSequenceNumber;
    if IsClipboardFormatAvailable(CF_HDROP) then begin
      H := GetClipboardData(CF_HDROP); if H = 0 then Exit;
      Count := DragQueryFileW(H, $FFFFFFFF, nil, 0);
      if Count > 10000 then raise Exception.Create('Muitos arquivos na area de transferencia');
      if Count > 0 then for I := 0 to Count - 1 do begin
        Len := DragQueryFileW(H, I, nil, 0); SetLength(W, Len + 1);
        DragQueryFileW(H, I, PWideChar(W), Len + 1); SetLength(W, Len); Paths.Add(UTF8Encode(W));
      end;
      Result := Count > 0;
    end else if IsClipboardFormatAvailable(CF_UNICODETEXT) then begin
      H := GetClipboardData(CF_UNICODETEXT); if H = 0 then Exit;
      if GlobalSize(H) > CLIP_MAX_TEXT * 2 + 2 then raise Exception.Create('Texto excede o limite de 1 MiB');
      P := GlobalLock(H); if P = nil then Exit;
      try
        Capacity:=GlobalSize(H) div SizeOf(WideChar); Len:=0;
        while (Len<Capacity) and (P[Len]<>#0) do Inc(Len);
        if Len=Capacity then raise Exception.Create('Texto da area de transferencia invalido');
        SetString(W,P,Len); Text := UTF8Encode(W);
      finally GlobalUnlock(H); end;
      if Length(Text) > CLIP_MAX_TEXT then raise Exception.Create('Texto excede o limite de 1 MiB');
      Result := True;
    end;
  finally CloseClipboard; end;
end;

function WriteWindowsClipboard(Owner: HWND; ExpectedSequence: DWORD; const Text: string; Paths: TStrings; out AppliedSequence: DWORD): Boolean;
var H, Effect: HGLOBAL; P: Pointer; Header: TDropHeader; W: UnicodeString; I: Integer; Format: UINT;
begin
  Result := False; H := 0; Effect := 0;
  if Paths.Count > 0 then begin
    W := ''; for I := 0 to Paths.Count - 1 do W := W + UTF8Decode(Paths[I]) + #0;
    W := W + #0; Format := CF_HDROP;
    H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, SizeOf(Header) + Length(W) * SizeOf(WideChar));
    if H = 0 then RaiseLastOSError;
    P := GlobalLock(H); if P = nil then begin GlobalFree(H); RaiseLastOSError; end;
    FillChar(Header, SizeOf(Header), 0); Header.Offset := SizeOf(Header); Header.Wide := True;
    Move(Header, P^, SizeOf(Header)); Move(W[1], (PByte(P) + SizeOf(Header))^, Length(W) * SizeOf(WideChar)); GlobalUnlock(H);
  end else begin
    W := UTF8Decode(Text) + #0; Format := CF_UNICODETEXT;
    H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, Length(W) * SizeOf(WideChar));
    if H = 0 then RaiseLastOSError;
    P := GlobalLock(H); if P = nil then begin GlobalFree(H); RaiseLastOSError; end;
    Move(W[1], P^, Length(W) * SizeOf(WideChar)); GlobalUnlock(H);
  end;
  try
    if not OpenClipboard(Owner) then Exit;
    try
      if GetClipboardSequenceNumber <> ExpectedSequence then Exit;
      if not EmptyClipboard then RaiseLastOSError;
      if SetClipboardData(Format, H) = 0 then RaiseLastOSError;
      H := 0; // Ownership transferred to Windows.
      if Paths.Count > 0 then begin
        Effect := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, SizeOf(DWORD));
        if Effect <> 0 then begin
          P := GlobalLock(Effect);
          if P <> nil then begin PDWORD(P)^ := 1; GlobalUnlock(Effect);
            if SetClipboardData(RegisterClipboardFormatW('Preferred DropEffect'), Effect) <> 0 then Effect := 0;
          end;
        end;
      end;
      AppliedSequence:=GetClipboardSequenceNumber;
      Result := True;
    finally CloseClipboard; end;
  finally if H <> 0 then GlobalFree(H); if Effect <> 0 then GlobalFree(Effect); end;
end;
end.
