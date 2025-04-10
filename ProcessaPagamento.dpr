program ProcessaPagamento;

uses
  Vcl.Forms,
  FormProcessaPagamento in 'FormProcessaPagamento.pas' {frmPrincipalTerminal},
  StompClient in 'StompClient.pas',
  uModeloPagamento in 'uModeloPagamento.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmPrincipalTerminal, frmPrincipalTerminal);
  Application.Run;
end.
