object FPrincipal: TFPrincipal
  Left = 428
  Top = 128
  Width = 457
  Height = 156
  Caption = 'Recebimento de pagamento'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object lblOperadora: TLabel
    Left = 20
    Top = 13
    Width = 50
    Height = 13
    Caption = 'Operadora'
  end
  object lblPagamento: TLabel
    Left = 149
    Top = 13
    Width = 54
    Height = 13
    Caption = 'Pagamento'
  end
  object edtOperadora: TEdit
    Left = 20
    Top = 27
    Width = 121
    Height = 21
    TabOrder = 0
    Text = '54A3DB8A1F4A4E96'
  end
  object edtPagamento: TEdit
    Left = 150
    Top = 28
    Width = 121
    Height = 21
    TabOrder = 1
    Text = '123'
  end
  object btnGerarPagamento: TButton
    Left = 285
    Top = 24
    Width = 130
    Height = 25
    Caption = 'Gerar Pagamento'
    TabOrder = 2
    OnClick = btnGerarPagamentoClick
  end
end
