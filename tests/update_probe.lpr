program update_probe;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, uDeskUpdate;
begin
  try
    Application.Initialize;
    if ParamCount<>2 then raise Exception.Create('Expected staged and target paths');
    LaunchVerifiedUpdate(ParamStr(1),ParamStr(2),FileSHA256(ParamStr(1)));
    WriteLn('Verified update helper started');
  except on E: Exception do begin WriteLn(E.Message); Halt(1); end; end;
end.
