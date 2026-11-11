unit uDeskFirewall;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  {$IFDEF WINDOWS}
  Windows, ShellApi, process;
  {$ELSE}
  process;
  {$ENDIF}

function IsFirewallRuleConfigured: Boolean;
function EnsureFirewallRule(out NeedsElevation: Boolean; APort: Integer = 7071): Boolean;

implementation

function IsFirewallRuleConfigured: Boolean;
{$IFDEF WINDOWS}
var
  Proc: TProcess;
  OutputStr: string;
  StrList: TStringList;
begin
  Result := False;
  Proc := TProcess.Create(nil);
  StrList := TStringList.Create;
  try
    Proc.Executable := 'netsh.exe';
    Proc.Parameters.Add('advfirewall');
    Proc.Parameters.Add('firewall');
    Proc.Parameters.Add('show');
    Proc.Parameters.Add('rule');
    Proc.Parameters.Add('name=MaurinDesk');
    Proc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    Proc.Execute;
    StrList.LoadFromStream(Proc.Output);
    Proc.WaitOnExit;
    OutputStr := StrList.Text;
    if (Proc.ExitCode = 0) and (Pos('MaurinDesk', OutputStr) > 0) then
      Result := True;
  except
    Result := False;
  end;
  StrList.Free;
  Proc.Free;
end;
{$ELSE}
begin
  Result := True;
end;
{$ENDIF}

function EnsureFirewallRule(out NeedsElevation: Boolean; APort: Integer = 7071): Boolean;
{$IFDEF WINDOWS}
var
  CmdParams: string;
  ExePath: string;
  Res: PtrInt;
begin
  NeedsElevation := False;
  if IsFirewallRuleConfigured then
  begin
    Result := True;
    Exit;
  end;

  NeedsElevation := True;
  ExePath := ParamStr(0);

  // Libera tanto o executavel quanto a porta TCP informada (padrao 7071) e 9876
  CmdParams := '/c netsh advfirewall firewall add rule name="MaurinDesk" dir=in action=allow program="' +
    ExePath + '" enable=yes profile=any & netsh advfirewall firewall add rule name="MaurinDesk Port ' +
    IntToStr(APort) + '" dir=in action=allow protocol=TCP localport=' + IntToStr(APort) + ' enable=yes profile=any';

  Res := ShellExecute(0, 'runas', 'cmd.exe', PChar(CmdParams), nil, SW_HIDE);
  Result := Res > 32;
end;
{$ELSE}
begin
  NeedsElevation := False;
  Result := True;
end;
{$ENDIF}

end.
