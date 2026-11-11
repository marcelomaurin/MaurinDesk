program MaurinDesk;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, umain;
begin
  RequireDerivedFormResource:=False;
  Application.Initialize;
  Application.Title:='MaurinDesk';
  Application.CreateForm(TMainForm,MainForm);
  if (ParamCount=1) and (ParamStr(1)='--self-test') then begin
    MainForm.Free;
    Exit;
  end;
  Application.Run;
end.
