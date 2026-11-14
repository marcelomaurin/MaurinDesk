program MaurinDesk;
{$mode objfpc}{$H+}
{$R *.res}
uses Interfaces, Forms, SysUtils, Graphics, umain, setmain, uDeskSettings;
var I: Integer; Bitmap: TBitmap; PNG: TPortableNetworkGraphic; Settings: TSetMain;
begin
  RequireDerivedFormResource:=False;
  Application.Initialize;
  Application.Title:='MaurinDesk';
  if (ParamCount>=2) and (ParamStr(1)='--render-settings') then begin
    Settings:=TSetMain.Create(ExpandFileName(ExtractFilePath(Application.ExeName)+'../build/ui-preview'),'');
    try RenderSettingsPreview(Settings,ParamStr(2)); finally Settings.Free; end;
    Exit;
  end;
  Application.CreateForm(TMainForm,MainForm);
  if (ParamCount>=2) and (ParamStr(1)='--render-preview') then begin
    if ParamCount>=4 then MainForm.SetBounds(0,0,StrToInt(ParamStr(3)),StrToInt(ParamStr(4)));
    MainForm.Show; Application.ProcessMessages;
    Bitmap:=TBitmap.Create; PNG:=TPortableNetworkGraphic.Create;
    try
      Bitmap.SetSize(MainForm.Width,MainForm.Height); MainForm.PaintTo(Bitmap.Canvas,0,0);
      PNG.Assign(Bitmap); PNG.SaveToFile(ParamStr(2));
    finally PNG.Free; Bitmap.Free; MainForm.Free; end;
    Exit;
  end;
  if (ParamCount=1) and (ParamStr(1)='--self-test') then begin
    MainForm.Free;
    Exit;
  end;
  for I:=1 to ParamCount do if ParamStr(I)='--minimized' then begin
    Application.ShowMainForm:=False; MainForm.Hide;
  end;
  Application.Run;
end.
