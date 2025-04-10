unit uModeloPagamento;

interface

uses
  System.SysUtils, System.JSON, Winapi.Windows, IOUtils;

type

  TPagamento = class
  private
    FCodOperadoora: string;
    FCodigo: string;
  public
    property CodOperadoora : string read FCodOperadoora write FCodOperadoora;
    property Codigo : string read FCodigo write FCodigo;

    function ToJsonString : string;
    procedure FromJsonString(const ADados : string);
  end;

implementation


{ TPagamento }

procedure TPagamento.FromJsonString(const ADados: string);
var
  lJson: TJSONObject;
begin
  lJson := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(ADados), 0) as TJsonObject;
  try
    if lJson.Get('codOperadora') <> nil then
      FCodOperadoora := lJson.Get('codOperadora').JsonValue.Value;
    if lJson.Get('codigo') <> nil then
      FCodigo := lJson.Get('codigo').JsonValue.Value;
  finally
    lJson.Free;
  end;
end;

function TPagamento.ToJsonString: string;
var
  lJson: TJSONObject;
begin
  lJson := TJsonObject.Create;
  try
    lJson.AddPair('codOperadoora', FCodOperadoora);
    lJson.AddPair('codigo', FCodigo);
    Result := lJson.ToString;
  finally
    lJson.Free;
  end;
end;


initialization

finalization


end.
