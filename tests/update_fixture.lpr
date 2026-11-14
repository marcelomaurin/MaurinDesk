program update_fixture;
{$mode objfpc}{$H+}
uses Classes, SysUtils;
var Marker: TStringList;
begin
  Marker:=TStringList.Create;
  try Marker.Text:='updated and restarted'; Marker.SaveToFile(ParamStr(0)+'.started'); finally Marker.Free; end;
end.
