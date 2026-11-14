unit uDeskFileManager;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, fpjson, uDeskFiles, uDeskUI;
type
  TDeskFileManager = class(TForm)
  private
    FService: TDeskFiles;
    FHeader,FOperations,FBrowser,FQueuePanel: TPanel;
    FLocalPanel,FRemotePanel: TPanel;
    FPaths,FFilters: array[0..1] of TEdit;
    FLists: array[0..1] of TListView;
    FPanelStatus: array[0..1] of TLabel;
    FGo,FUp,FHome,FRefresh,FNew,FMore: array[0..1] of TDeskButton;
    FTickets,FActualPaths,FParents: array[0..1] of string;
    FNextOffset: array[0..1] of Integer;
    FSend,FReceive,FClear: TDeskButton;
    FOverwrite: TCheckBox;
    FQueue: TListView;
    FStatus: TLabel;
    FProgress: TProgressBar;
    procedure LayoutControls(Sender: TObject);
    procedure Navigate(Sender: TObject);
    procedure AddressKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure OpenDirectory(Sender: TObject);
    procedure DeleteEntry(Sender: TObject; Item: TListItem);
    procedure DeleteJob(Sender: TObject; Item: TListItem);
    procedure StartSend(Sender: TObject);
    procedure StartReceive(Sender: TObject);
    procedure ClearFinished(Sender: TObject);
    procedure OpenSavedDestination(Sender: TObject);
    procedure Browse(Side,Offset: Integer; const Path: string);
    procedure RefreshSide(Side: Integer);
    function Selection(Side: Integer): TStringList;
    procedure AddJob(const Id,Direction,Source,Destination: string);
    procedure UpdateJob(Data: TJSONObject);
  protected procedure DoClose(var CloseAction: TCloseAction); override;
  public
    constructor CreateManager(AOwner: TComponent; Service: TDeskFiles);
    procedure Bind(Service: TDeskFiles);
    procedure HandleEvent(Data: TJSONObject);
  end;
implementation
uses Dialogs, Graphics, DateUtils, LCLIntf;
type
  TTransferRow = class
    Id,Direction,Destination,State: string;
  end;

constructor TDeskFileManager.CreateManager(AOwner: TComponent; Service: TDeskFiles);
  function Panel(Parent: TWinControl): TPanel;
  begin Result:=TPanel.Create(Self); Result.Parent:=Parent; Result.BevelOuter:=bvNone; Result.Color:=clWhite; end;
  function LabelAt(Parent: TWinControl; const Text: string; X,Y,W,H,Size: Integer; Bold: Boolean=False): TLabel;
  begin
    Result:=TLabel.Create(Self); Result.Parent:=Parent; Result.AutoSize:=False; Result.SetBounds(X,Y,W,H); Result.Caption:=Text;
    Result.Font.Name:='Segoe UI'; Result.Font.Size:=Size; Result.Font.Color:=RGBToColor(44,53,69); if Bold then Result.Font.Style:=[fsBold];
  end;
  function ButtonAt(Parent: TWinControl; const Text: string; Tag: Integer; Handler: TNotifyEvent): TDeskButton;
  begin Result:=TDeskButton.Create(Self); Result.Parent:=Parent; Result.Caption:=Text; Result.Tag:=Tag; Result.OnClick:=Handler; Result.Font.Size:=9; end;
var I: Integer; P: TPanel;
begin
  inherited CreateNew(AOwner); Caption:='MaurinDesk — Arquivos locais e remotos'; Font.Name:='Segoe UI'; Font.Size:=10;
  Width:=1260; Height:=840; Constraints.MinWidth:=1000; Constraints.MinHeight:=700; Position:=poScreenCenter;
  Color:=RGBToColor(248,249,252); DoubleBuffered:=True;
  FHeader:=Panel(Self); FHeader.Align:=alTop; FHeader.Height:=72;
  LabelAt(FHeader,'Transferência de arquivos',20,12,700,28,19,True);
  LabelAt(FHeader,'Escolha os itens de origem e a pasta de destino no outro painel.',20,44,1000,22,10);
  FOperations:=Panel(Self); FOperations.Align:=alTop; FOperations.Top:=80; FOperations.Height:=50;
  FSend:=ButtonAt(FOperations,'Enviar →',0,@StartSend); FSend.Primary:=True;
  FReceive:=ButtonAt(FOperations,'← Receber',0,@StartReceive);
  FOverwrite:=TCheckBox.Create(Self); FOverwrite.Parent:=FOperations; FOverwrite.Caption:='Substituir arquivos existentes (mesclar pastas)';
  FOverwrite.Checked:=False; FOverwrite.SetBounds(410,13,650,26);
  FQueuePanel:=Panel(Self); FQueuePanel.Align:=alBottom; FQueuePanel.Height:=208;
  LabelAt(FQueuePanel,'Fila de transferências',16,9,500,26,12,True);
  FClear:=ButtonAt(FQueuePanel,'Limpar concluídos',0,@ClearFinished);
  FQueue:=TListView.Create(Self); FQueue.Parent:=FQueuePanel; FQueue.ViewStyle:=vsReport; FQueue.RowSelect:=True;
  FQueue.ReadOnly:=True; FQueue.OnDeletion:=@DeleteJob; FQueue.OnDblClick:=@OpenSavedDestination;
  with FQueue.Columns.Add do begin Caption:='Direção'; Width:=80; end;
  with FQueue.Columns.Add do begin Caption:='Origem'; Width:=260; end;
  with FQueue.Columns.Add do begin Caption:='Destino final'; Width:=320; end;
  with FQueue.Columns.Add do begin Caption:='Estado'; Width:=340; end;
  with FQueue.Columns.Add do begin Caption:='Progresso'; Width:=85; end;
  FStatus:=LabelAt(FQueuePanel,'Fechar esta janela mantém a fila; encerrar a sessão interrompe-a.',16,173,1100,22,9);
  FProgress:=TProgressBar.Create(Self); FProgress.Parent:=FQueuePanel; FProgress.Min:=0; FProgress.Max:=100; FProgress.Height:=6;
  FBrowser:=Panel(Self); FBrowser.Parent:=Self; FBrowser.Align:=alClient; FBrowser.Color:=Color;
  FLocalPanel:=Panel(FBrowser); FRemotePanel:=Panel(FBrowser);
  for I:=0 to 1 do begin
    if I=0 then P:=FLocalPanel else P:=FRemotePanel;
    if I=0 then LabelAt(P,'Este computador · Local',12,10,500,26,13,True)
    else LabelAt(P,'Outro computador · Remoto',12,10,500,26,13,True);
    FPaths[I]:=TEdit.Create(Self); FPaths[I].Parent:=P; FPaths[I].Tag:=I; FPaths[I].OnKeyDown:=@AddressKey;
    FGo[I]:=ButtonAt(P,'Abrir',I*10,@Navigate);
    FUp[I]:=ButtonAt(P,'↑ Acima',I*10+1,@Navigate);
    FHome[I]:=ButtonAt(P,'Início',I*10+2,@Navigate);
    FRefresh[I]:=ButtonAt(P,'Atualizar',I*10+3,@Navigate);
    FNew[I]:=ButtonAt(P,'Nova pasta',I*10+4,@Navigate);
    FMore[I]:=ButtonAt(P,'Mais',I*10+5,@Navigate); FMore[I].Enabled:=False;
    FFilters[I]:=TEdit.Create(Self); FFilters[I].Parent:=P; FFilters[I].Tag:=I; FFilters[I].TextHint:='Filtrar por nome · Enter para aplicar'; FFilters[I].OnKeyDown:=@AddressKey;
    FLists[I]:=TListView.Create(Self); FLists[I].Parent:=P; FLists[I].Tag:=I; FLists[I].ViewStyle:=vsReport;
    FLists[I].MultiSelect:=True; FLists[I].RowSelect:=True; FLists[I].ReadOnly:=True; FLists[I].OnDblClick:=@OpenDirectory; FLists[I].OnDeletion:=@DeleteEntry;
    with FLists[I].Columns.Add do begin Caption:='Nome'; Width:=260; end;
    with FLists[I].Columns.Add do begin Caption:='Tipo'; Width:=65; end;
    with FLists[I].Columns.Add do begin Caption:='Tamanho'; Width:=90; end;
    with FLists[I].Columns.Add do begin Caption:='Modificado'; Width:=140; end;
    FPanelStatus[I]:=LabelAt(P,'Conectando...',12,0,500,22,9);
  end;
  OnResize:=@LayoutControls; LayoutControls(Self); Bind(Service);
end;
procedure TDeskFileManager.DoClose(var CloseAction: TCloseAction);
begin CloseAction:=caHide; inherited DoClose(CloseAction); end;
procedure TDeskFileManager.Bind(Service: TDeskFiles);
begin
  FService:=Service; FSend.Enabled:=Service<>nil; FReceive.Enabled:=Service<>nil;
  if Service<>nil then begin
    Browse(0,0,'@home'); Browse(1,0,'@home');
  end else FStatus.Caption:='Sessão encerrada. Conecte novamente para transferir arquivos.';
end;
procedure TDeskFileManager.LayoutControls(Sender: TObject);
var Half,W,H,I: Integer; P: TPanel;
begin
  if FBrowser=nil then Exit;
  Half:=FBrowser.ClientWidth div 2; H:=FBrowser.ClientHeight;
  FLocalPanel.SetBounds(12,6,Half-18,H-12); FRemotePanel.SetBounds(Half+6,6,Half-18,H-12);
  FSend.SetBounds(16,6,170,36); FReceive.SetBounds(198,6,170,36); FOverwrite.Left:=392;
  FClear.SetBounds(FQueuePanel.ClientWidth-192,5,172,32);
  FQueue.SetBounds(12,42,FQueuePanel.ClientWidth-24,126);
  FStatus.Width:=FQueuePanel.ClientWidth-32; FProgress.SetBounds(0,FQueuePanel.ClientHeight-6,FQueuePanel.ClientWidth,6);
  for I:=0 to 1 do begin
    if I=0 then P:=FLocalPanel else P:=FRemotePanel; W:=P.ClientWidth;
    FPaths[I].SetBounds(12,43,W-104,30); FGo[I].SetBounds(W-82,41,70,32);
    FUp[I].SetBounds(12,82,76,30); FHome[I].SetBounds(94,82,70,30); FRefresh[I].SetBounds(170,82,90,30);
    FNew[I].SetBounds(266,82,102,30); FMore[I].SetBounds(374,82,64,30);
    FFilters[I].SetBounds(12,123,W-24,30);
    FLists[I].SetBounds(12,164,W-24,H-211); FLists[I].Columns[0].Width:=W-319;
    FPanelStatus[I].SetBounds(12,H-40,W-24,22);
  end;
end;
procedure TDeskFileManager.Browse(Side,Offset: Integer; const Path: string);
begin
  if FService=nil then Exit;
  FTickets[Side]:=FService.Browse(Side=0,Path,FFilters[Side].Text,Offset);
  FPanelStatus[Side].Caption:='Carregando...';
end;
procedure TDeskFileManager.RefreshSide(Side: Integer);
begin Browse(Side,0,FPaths[Side].Text); end;
procedure TDeskFileManager.Navigate(Sender: TObject);
var Side,Op: Integer; FolderName: string;
begin
  if FService=nil then Exit;
  Side:=TControl(Sender).Tag div 10; Op:=TControl(Sender).Tag mod 10;
  case Op of
    0,3: RefreshSide(Side);
    1: Browse(Side,0,FParents[Side]);
    2: Browse(Side,0,'@home');
    4: begin
      if FActualPaths[Side]='' then begin ShowMessage('Abra uma unidade antes de criar uma pasta.'); Exit; end;
      FolderName:=''; if InputQuery('Nova pasta','Nome da pasta:',FolderName) and (Trim(FolderName)<>'') then
        FService.MakeDirectory(Side=0,FActualPaths[Side],Trim(FolderName));
    end;
    5: Browse(Side,FNextOffset[Side],FActualPaths[Side]);
  end;
end;
procedure TDeskFileManager.AddressKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if Key=13 then begin Key:=0; RefreshSide(TControl(Sender).Tag); end; end;
procedure TDeskFileManager.OpenDirectory(Sender: TObject);
var Side: Integer; Item: TListItem; Entry: TJSONObject; P: string;
begin
  Side:=TControl(Sender).Tag; Item:=FLists[Side].Selected; if Item=nil then Exit;
  Entry:=TJSONObject(Item.Data); if Entry=nil then Exit;
  if Entry.Get('kind','')='drive' then Browse(Side,0,Entry.Get('name',''))
  else if Entry.Get('kind','')='dir' then begin
    P:=IncludeTrailingPathDelimiter(FActualPaths[Side])+Entry.Get('name',''); Browse(Side,0,P);
  end;
end;
procedure TDeskFileManager.DeleteEntry(Sender: TObject; Item: TListItem);
begin if Item.Data<>nil then begin TObject(Item.Data).Free; Item.Data:=nil; end; end;
procedure TDeskFileManager.DeleteJob(Sender: TObject; Item: TListItem);
begin if Item.Data<>nil then begin TObject(Item.Data).Free; Item.Data:=nil; end; end;
function TDeskFileManager.Selection(Side: Integer): TStringList;
var I: Integer; Entry: TJSONObject;
begin
  Result:=TStringList.Create;
  try
    for I:=0 to FLists[Side].Items.Count-1 do if FLists[Side].Items[I].Selected then begin
      Entry:=TJSONObject(FLists[Side].Items[I].Data);
      if (Entry.Get('kind','')<>'file') and (Entry.Get('kind','')<>'dir') then raise Exception.Create('Selecione arquivos ou pastas, não uma unidade ou link.');
      Result.Add(IncludeTrailingPathDelimiter(FActualPaths[Side])+Entry.Get('name',''));
    end;
    if Result.Count=0 then raise Exception.Create('Selecione os arquivos ou pastas no painel de origem.');
  except Result.Free; raise; end;
end;
procedure TDeskFileManager.AddJob(const Id,Direction,Source,Destination: string);
var Item: TListItem; Row: TTransferRow;
begin
  Row:=TTransferRow.Create; Row.Id:=Id; Row.Direction:=Direction; Row.Destination:=Destination; Row.State:='queued';
  Item:=FQueue.Items.Add; Item.Data:=Row;
  if Direction='send' then Item.Caption:='Enviar →' else Item.Caption:='← Receber';
  Item.SubItems.Add(Source); Item.SubItems.Add(Destination); Item.SubItems.Add('Na fila'); Item.SubItems.Add('0%');
end;
procedure TDeskFileManager.StartSend(Sender: TObject);
var Paths: TStringList; Id,Description,Destination: string;
begin
  if FService=nil then Exit;
  Paths:=nil;
  try
    Destination:=Trim(FPaths[1].Text); if Destination='' then raise Exception.Create('Escolha a pasta de destino no painel remoto.');
    Paths:=Selection(0); Description:=Paths[0]; if Paths.Count>1 then Description:=Description+' (+'+IntToStr(Paths.Count-1)+')';
    Id:=FService.Send(Paths,Destination,FOverwrite.Checked); AddJob(Id,'send',Description,Destination);
  except on E: Exception do ShowMessage(E.Message); end;
  Paths.Free;
end;
procedure TDeskFileManager.StartReceive(Sender: TObject);
var Paths: TStringList; Id,Description,Destination: string;
begin
  if FService=nil then Exit;
  Paths:=nil;
  try
    Destination:=Trim(FPaths[0].Text); if Destination='' then raise Exception.Create('Escolha a pasta de destino no painel local.');
    Paths:=Selection(1); Description:=Paths[0]; if Paths.Count>1 then Description:=Description+' (+'+IntToStr(Paths.Count-1)+')';
    Id:=FService.Receive(Paths,Destination,FOverwrite.Checked); AddJob(Id,'receive',Description,Destination);
  except on E: Exception do ShowMessage(E.Message); end;
  Paths.Free;
end;
procedure TDeskFileManager.UpdateJob(Data: TJSONObject);
var I,Percent: Integer; Item: TListItem; Row: TTransferRow; Id,State,MessageText: string;
begin
  Id:=Data.Get('job_id',''); Item:=nil;
  for I:=0 to FQueue.Items.Count-1 do if TTransferRow(FQueue.Items[I].Data).Id=Id then begin Item:=FQueue.Items[I]; Break; end;
  if Item=nil then begin AddJob(Id,Data.Get('direction','receive'),Data.Get('source',''),Data.Get('destination','')); Item:=FQueue.Items[FQueue.Items.Count-1]; end;
  Row:=TTransferRow(Item.Data); State:=Data.Get('state',''); Row.State:=State; Percent:=Data.Get('percent',0);
  MessageText:=Data.Get('message',''); Item.SubItems[2]:=MessageText; Item.SubItems[3]:=IntToStr(Percent)+'%';
  FStatus.Caption:=MessageText+'  '+Row.Destination; FStatus.Hint:=FStatus.Caption; FStatus.ShowHint:=True;
  FProgress.Position:=Percent;
  if State='completed' then begin
    if Row.Direction='receive' then RefreshSide(0) else RefreshSide(1);
  end;
end;
procedure TDeskFileManager.ClearFinished(Sender: TObject);
var I: Integer; Row: TTransferRow;
begin for I:=FQueue.Items.Count-1 downto 0 do begin Row:=TTransferRow(FQueue.Items[I].Data); if (Row.State='completed') or (Row.State='error') then FQueue.Items[I].Delete; end; end;
procedure TDeskFileManager.OpenSavedDestination(Sender: TObject);
var Item: TListItem; Row: TTransferRow;
begin Item:=FQueue.Selected; if Item=nil then Exit; Row:=TTransferRow(Item.Data);
  if (Row.Direction='receive') and (Row.State='completed') and DirectoryExists(Row.Destination) then OpenDocument(Row.Destination);
end;
procedure TDeskFileManager.HandleEvent(Data: TJSONObject);
var Side,I,Offset: Integer; Kind,Event,Ticket: string; Listing,Entry: TJSONObject; Entries: TJSONArray; Item: TListItem; Stamp: Int64;
begin
  Event:=Data.Get('event','');
  if Event='progress' then begin UpdateJob(Data); Exit; end;
  if Event='service_error' then begin FStatus.Caption:=Data.Get('message',''); Exit; end;
  Side:=1; if Data.Get('local',False) then Side:=0;
  if Event='changed' then begin RefreshSide(Side); Exit; end;
  Ticket:=Data.Get('ticket',''); if Ticket<>FTickets[Side] then Exit;
  if Event='listing_error' then begin FPanelStatus[Side].Caption:=Data.Get('message','Falha ao listar a pasta.'); FPanelStatus[Side].Hint:=FPanelStatus[Side].Caption; FPanelStatus[Side].ShowHint:=True; Exit; end;
  if Event<>'listing' then Exit;
  Listing:=Data.Objects['data']; if Listing=nil then Exit; Entries:=Listing.Arrays['entries']; if Entries=nil then Exit;
  Offset:=Listing.Get('offset',0);
  FLists[Side].Items.BeginUpdate;
  try
    if Offset=0 then FLists[Side].Items.Clear;
    FActualPaths[Side]:=Listing.Get('path',''); FPaths[Side].Text:=FActualPaths[Side]; FParents[Side]:=Listing.Get('parent','');
    FNextOffset[Side]:=Listing.Get('next_offset',0); FMore[Side].Enabled:=Listing.Get('has_more',False);
    for I:=0 to Entries.Count-1 do begin
      Entry:=TJSONObject(Entries[I]); Item:=FLists[Side].Items.Add; Item.Caption:=Entry.Get('name',''); Item.Data:=Entry.Clone;
      Kind:=Entry.Get('kind','');
      if Kind='dir' then Item.SubItems.Add('Pasta') else if Kind='drive' then Item.SubItems.Add('Unidade') else if Kind='link' then Item.SubItems.Add('Link') else Item.SubItems.Add('Arquivo');
      if Kind='file' then Item.SubItems.Add(FormatFloat('#,##0',Entry.Get('size',Int64(0)))+' B') else Item.SubItems.Add('');
      Stamp:=Entry.Get('modified',Int64(0)); if Stamp>0 then Item.SubItems.Add(FormatDateTime('dd/mm/yyyy hh:nn',UnixToDateTime(Stamp,False))) else Item.SubItems.Add('');
    end;
    FPanelStatus[Side].Caption:=IntToStr(FLists[Side].Items.Count)+' de '+IntToStr(Listing.Get('total',0))+' itens';
    if FActualPaths[Side]='' then FPanelStatus[Side].Caption:='Abra uma unidade para escolher arquivos ou o destino.';
  finally FLists[Side].Items.EndUpdate; end;
end;
end.
