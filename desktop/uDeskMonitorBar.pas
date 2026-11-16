unit uDeskMonitorBar;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls;
type
  TMonitorChangedEvent = procedure(Sender: TObject; MonitorIndex: Integer; const Description: string) of object;

  TDeskMonitorBar = class(TForm)
  private
    FPanel: TPanel;
    FLabel: TLabel;
    FCombo: TComboBox;
    FUpdating: Boolean;
    FOnMonitorChanged: TMonitorChangedEvent;
    procedure ComboChange(Sender: TObject);
    procedure PositionAtTop;
  public
    constructor CreateBar(AOwner: TComponent);
    procedure RefreshMonitors;
    procedure ShowIfMultiMonitor;
    procedure HideBar;
    property OnMonitorChanged: TMonitorChangedEvent read FOnMonitorChanged write FOnMonitorChanged;
  end;

implementation
uses
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  uScreenCapture;

constructor TDeskMonitorBar.CreateBar(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  ShowInTaskbar := stNever;
  Position := poDesigned;
  Width := 360;
  Height := 42;
  Color := RGBToColor(24, 24, 37);
  Font.Name := 'Segoe UI';
  Font.Size := 9;

  FPanel := TPanel.Create(Self);
  FPanel.Parent := Self;
  FPanel.Align := alClient;
  FPanel.BevelOuter := bvRaised;
  FPanel.Color := RGBToColor(24, 24, 37);

  FLabel := TLabel.Create(Self);
  FLabel.Parent := FPanel;
  FLabel.SetBounds(12, 12, 62, 18);
  FLabel.Caption := 'Monitor:';
  FLabel.Font.Color := clWhite;
  FLabel.Font.Style := [fsBold];
  FLabel.Transparent := True;

  FCombo := TComboBox.Create(Self);
  FCombo.Parent := FPanel;
  FCombo.SetBounds(78, 8, 268, 26);
  FCombo.Style := csDropDownList;
  FCombo.OnChange := @ComboChange;
end;

procedure TDeskMonitorBar.PositionAtTop;
var
  Mon: TMonitor;
begin
  Mon := Screen.PrimaryMonitor;
  if Mon = nil then Exit;
  Left := Mon.Left + (Mon.Width - Width) div 2;
  Top := Mon.Top;
end;

procedure TDeskMonitorBar.RefreshMonitors;
var
  I, Count, Current: Integer;
begin
  FUpdating := True;
  try
    FCombo.Items.BeginUpdate;
    try
      FCombo.Items.Clear;
      Count := GetCaptureMonitorCount;
      for I := 0 to Count - 1 do
        FCombo.Items.Add(GetCaptureMonitorCaption(I));
      Current := GetCaptureMonitorIndex;
      if (Current >= 0) and (Current < FCombo.Items.Count) then
        FCombo.ItemIndex := Current
      else if FCombo.Items.Count > 0 then
        FCombo.ItemIndex := 0;
    finally
      FCombo.Items.EndUpdate;
    end;
  finally
    FUpdating := False;
  end;
  PositionAtTop;
end;

procedure TDeskMonitorBar.ComboChange(Sender: TObject);
var
  Idx: Integer;
begin
  if FUpdating then Exit;
  Idx := FCombo.ItemIndex;
  if Idx < 0 then Exit;
  SetCaptureMonitorIndex(Idx);
  if Assigned(FOnMonitorChanged) then
    FOnMonitorChanged(Self, Idx, GetCaptureMonitorCaption(Idx));
end;

procedure TDeskMonitorBar.ShowIfMultiMonitor;
begin
  if GetCaptureMonitorCount <= 1 then begin
    HideBar;
    Exit;
  end;
  RefreshMonitors;
  if not Visible then begin
    {$IFDEF WINDOWS}
    HandleNeeded;
    ShowWindow(Handle, SW_SHOWNOACTIVATE);
    Visible := True;
    {$ELSE}
    Show;
    {$ENDIF}
  end;
end;

procedure TDeskMonitorBar.HideBar;
begin
  if Visible then Hide;
end;

end.
