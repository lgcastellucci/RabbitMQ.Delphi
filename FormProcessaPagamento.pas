unit FormProcessaPagamento;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.Buttons, Vcl.ExtCtrls, StompClient, uModeloPagamento,
  Vcl.Samples.Spin, IOUtils, Vcl.ComCtrls;

type
  TOnReceberPagamento = reference to procedure(const ACodOperadora: string; const ACodigo: string);

  TThreadTerminal = class(TThread)
  private
    FStompClient: IStompClient;
    FStompFrame: IStompFrame;
    FOnReceberPagamento: TOnReceberPagamento;
  protected
    procedure Execute; override;
  public
    procedure ReceberPagamento;

    constructor Create(CreateSuspended: Boolean; const AEndereco: string; const ATerminal: string; const AOnReceberPagamento: TOnReceberPagamento); overload;

    property StompClient: IStompClient read FStompClient write FStompClient;
    property OnReceberPagamento: TOnReceberPagamento read FOnReceberPagamento write FOnReceberPagamento;
  end;

  TfrmPrincipalTerminal = class(TForm)
    mmoPagamentos: TMemo;
    procedure FormDestroy(Sender: TObject);
    procedure FormActivate(Sender: TObject);
  private
    FThreadTerminal: TThreadTerminal;

    procedure InicializarTerminal;
  public
    { Public declarations }
  end;

var
  frmPrincipalTerminal: TfrmPrincipalTerminal;
  serverIp, serverUser, serverPass, queuePath: string;

implementation

{$R *.dfm}

procedure TfrmPrincipalTerminal.FormActivate(Sender: TObject);
begin
  serverIp := '192.168.0.150';
  serverUser := 'admin';
  serverPass := '123';
  queuePath := '/queue/ProcessarPagamento';

  InicializarTerminal;
end;

procedure TfrmPrincipalTerminal.FormDestroy(Sender: TObject);
begin
  FThreadTerminal.Free;
end;

procedure TfrmPrincipalTerminal.InicializarTerminal;
begin
  FThreadTerminal := TThreadTerminal.Create(True, serverIp, ExtractFileName(Application.ExeName),
    procedure(const ACodOperadora: string; const ACodigo: string)
    begin
      mmoPagamentos.Lines.Add(ACodOperadora + ' - ' + ACodigo);
    end);

  if not FThreadTerminal.Started then
    FThreadTerminal.Start;
end;

{ TThreadTerminal }

constructor TThreadTerminal.Create(CreateSuspended: Boolean; const AEndereco: string; const ATerminal: string; const AOnReceberPagamento: TOnReceberPagamento);
var
  Headers: IStompHeaders;
begin
  FStompClient := StompUtils.StompClient;
  FStompClient.SetHost(AEndereco);
  FStompClient.SetUserName(serverUser);
  FStompClient.SetPassword(serverPass);
  //FStompClient.SetClientId(ATerminal);
  FStompClient.Connect;

  //Headers.Add('ConsumerTAG', ATerminal); // aqui é o consumer tag

  FStompClient.Subscribe(queuePath, amAuto, Headers);

  FOnReceberPagamento := AOnReceberPagamento;

  FStompFrame := StompUtils.CreateFrame;

  inherited Create(CreateSuspended);
end;

procedure TThreadTerminal.Execute;
begin
  while not Terminated do
  begin
    if FStompClient.Receive(FStompFrame, 2000) then
    begin
      Sleep(100);
      Synchronize(ReceberPagamento);
    end;
  end;
end;

procedure TThreadTerminal.ReceberPagamento;
var
  lPagamento: TPagamento;
begin
  lPagamento := TPagamento.Create;
  try
    lPagamento.FromJsonString(StringReplace(FStompFrame.Body, #10, sLineBreak, [rfReplaceAll]));
    if Assigned(FOnReceberPagamento) then
      FOnReceberPagamento(lPagamento.CodOperadoora, lPagamento.Codigo);
  finally
    lPagamento.Free;
  end;
end;

end.

