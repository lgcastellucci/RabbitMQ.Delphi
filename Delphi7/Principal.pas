unit Principal;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, IdSSLOpenSSL, IdTCPClient;

type
  TFPrincipal = class(TForm)
    edtOperadora: TEdit;
    edtPagamento: TEdit;
    lblOperadora: TLabel;
    lblPagamento: TLabel;
    btnGerarPagamento: TButton;
    procedure btnGerarPagamentoClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  FPrincipal: TFPrincipal;
  serverIp, serverUser, serverPass, queuePath: string;

implementation


{$R *.dfm}

procedure TFPrincipal.btnGerarPagamentoClick(Sender: TObject);
var
  FUseSSL: Boolean;
  FTCP: TIdTCPClient;
  FIOHandlerSocketOpenSSL: TIdSSLIOHandlerSocketOpenSSL;
  FHost: string;
  FPort: Integer;
  FConnectionTimeout: Integer;
  Output, Conteudo: string;
begin
  FHost := '192.168.0.150';
  FPort := 61613;
  FConnectionTimeout := 1000 * 10; // 10secs
  serverUser := 'admin';
  serverPass := '123';
  queuePath := '/queue/ProcessarPagamento';
  FUseSSL := False;

  FTCP := TIdTCPClient.Create;
  if FUseSSL then
  begin
  end
  else
  begin
    FTCP.IOHandler := nil;
  end;

  FTCP.ConnectTimeout := FConnectionTimeout;
  FTCP.Connect(FHost, FPort);
  FTCP.IOHandler.MaxLineLength := MaxInt;

  Output := 'CONNECT' + #10 + 'accept-version:1.0' + #10 + 'login:' + serverUser + #10 + 'passcode:' + serverPass + #10 + #10 + #0;
  FTCP.IOHandler.Write(Output);

  Conteudo := '{"codOperadora":"' + edtOperadora.Text + '", "codigo":"' + edtPagamento.Text + '"}';

  Output := '';
  Output := Output + 'SEND' + #10;
  Output := Output + 'destination:' + queuePath + #10;
  Output := Output + 'content-length:' + IntToStr(Length(Conteudo)) + #10 + #10;
  Output := Output + Conteudo + #0;

  FTCP.IOHandler.Write(Output);

  FreeAndNil(FTCP);
  FreeAndNil(FIOHandlerSocketOpenSSL);
  
end;

end.

