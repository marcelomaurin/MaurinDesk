unit uDeskUI;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Controls, Graphics, ExtCtrls, LCLType;
const DESK_RED = $004343E5;
type
  TDeskCard = class(TPanel)
  protected procedure Paint; override;
  public constructor Create(AOwner: TComponent); override;
  end;
  TDeskButton = class(TCustomControl)
  private
    FPrimary, FSelected, FHover: Boolean;
    procedure SetPrimary(Value: Boolean);
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Primary: Boolean read FPrimary write SetPrimary;
    property Selected: Boolean read FSelected write SetSelected;
  published
    property Caption; property OnClick; property TabOrder; property TabStop;
  end;
implementation
constructor TDeskCard.Create(AOwner: TComponent);
begin inherited Create(AOwner); BevelOuter := bvNone; Color := clWhite; DoubleBuffered := True; end;
procedure TDeskCard.Paint;
begin
  if Parent <> nil then Canvas.Brush.Color := TPanel(Parent).Color else Canvas.Brush.Color := clWhite;
  Canvas.FillRect(ClientRect); Canvas.Brush.Color := Color; Canvas.Pen.Color := RGBToColor(225,229,235);
  Canvas.RoundRect(0,0,Width-1,Height-1,14,14);
end;
constructor TDeskButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner); Width := 160; Height := 42; TabStop := True;
  ControlStyle := ControlStyle + [csClickEvents,csCaptureMouse];
  Cursor := crHandPoint; Font.Name := 'Segoe UI'; Font.Size := 10; DoubleBuffered := True;
end;
procedure TDeskButton.SetPrimary(Value: Boolean);
begin FPrimary := Value; Invalidate; end;
procedure TDeskButton.SetSelected(Value: Boolean);
begin FSelected := Value; Invalidate; end;
procedure TDeskButton.MouseEnter;
begin inherited MouseEnter; FHover := True; Invalidate; end;
procedure TDeskButton.MouseLeave;
begin inherited MouseLeave; FHover := False; Invalidate; end;
procedure TDeskButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin if CanFocus then SetFocus; inherited MouseDown(Button,Shift,X,Y); end;
procedure TDeskButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key,Shift);
  if Enabled and ((Key = VK_RETURN) or (Key = VK_SPACE)) then begin Click; Key := 0; end;
end;
procedure TDeskButton.Paint;
var R: TRect; C, TextC: TColor;
begin
  Canvas.Brush.Color := TPanel(Parent).Color; Canvas.FillRect(ClientRect);
  C := clWhite; TextC := RGBToColor(37,44,57);
  if FHover then C := RGBToColor(245,246,249);
  if FSelected then begin C := RGBToColor(254,235,235); TextC := DESK_RED; end;
  if FPrimary then begin C := DESK_RED; TextC := clWhite; if FHover then C := RGBToColor(205,48,48); end;
  if not Enabled then begin C := RGBToColor(239,241,245); TextC := RGBToColor(152,160,172); end;
  Canvas.Brush.Color := C; Canvas.Pen.Color := RGBToColor(219,224,232);
  if FPrimary or FSelected then Canvas.Pen.Color := C;
  Canvas.RoundRect(0,0,Width-1,Height-1,10,10);
  Canvas.Font.Assign(Font); Canvas.Font.Color := TextC; Canvas.Brush.Style := bsClear;
  Canvas.TextOut((Width-Canvas.TextWidth(Caption)) div 2,(Height-Canvas.TextHeight(Caption)) div 2,Caption);
  if Focused then begin R := Rect(4,4,Width-5,Height-5); Canvas.DrawFocusRect(R); end;
end;
end.
