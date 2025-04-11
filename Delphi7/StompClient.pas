unit StompClient;

interface

uses
  SysUtils,
  DateUtils,
  IdTCPClient,
  IdException,
  IdExceptionCore,
  IdHeaderList,
  IdIOHandler, IdIOHandlerSocket, IdIOHandlerStack, IdSSL, IdSSLOpenSSL, // SSL
  SyncObjs,
  Classes;

const
  LINE_END: char = #10;
  BYTE_LINE_END: Byte = 10;
  COMMAND_END: char = #0;
  DEFAULT_STOMP_HOST = '127.0.0.1';
  DEFAULT_STOMP_PORT = 61613;

const
  StompHeaders_MESSAGE_ID:     string = 'message-id';
  StompHeaders_TRANSACTION:    string = 'transaction';
  StompHeaders_REPLY_TO:       string = 'reply-to';
  StompHeaders_AUTO_DELETE:    string = 'auto-delete';
  StompHeaders_CONTENT_LENGTH: string = 'content-length';
  StompHeaders_CONTENT_TYPE:   string = 'content-type';
  StompHeaders_RECEIPT:        string = 'receipt';
  // RabbitMQ specific headers
  StompHeaders_PREFETCH_COUNT: string = 'prefetch-count';
  StompHeaders_X_MESSAGE_TTL:  string = 'x-message-ttl';
  StompHeaders_X_EXPIRES:      string = 'x-expires';
  StompHeaders_TIMESTAMP:      string = 'timestamp';

type
  TKeyValue = record
    Key: string;
    Value: string;
  end;

  TAddress = record
    Host: string;
    Port: Integer;
    UserName: string;
    Password: string;
  end;

implementation

uses
  IdGlobal,
  IdGlobalProtocols;

type
  { TStompClient }
  TStompClient = class
  private
    FTCP: TIdTCPClient;
    FIOHandlerSocketOpenSSL : TIdSSLIOHandlerSocketOpenSSL;
    FPassword: string;
    FUserName: string;
    FTimeout: Integer;
    FSession: string;
    FInTransaction: boolean;
    FTransactions: TStringList;
    FReceiptTimeout: Integer;
    FServerProtocolVersion: string;
    FServer: string;
    FHost: string;
    FPort: Integer;
    FVirtualHost: string;
    FClientID: string;

    FUseSSL   : boolean;      // SSL
    FsslKeyFile : string;     // SSL
    FsslCertFile : string;    // SSL
    FsslKeyPass   : string;   // SSL

    FConnectionTimeout: Integer;
    FOutgoingHeartBeats: Integer;
    FIncomingHeartBeats: Integer;
    FLock: TObject;
    FServerIncomingHeartBeats: Integer;
    FServerOutgoingHeartBeats: Integer;
    FOnHeartBeatError: TNotifyEvent;
  protected

  public
    procedure SetHost(Host: string);
    procedure SetPort(Port: Integer);
    function Connect: Boolean;    
  end;

{ TStompClient }

procedure TStompClient.SetHost(Host: string);
begin
  FHost := Host;
end;

procedure TStompClient.SetPort(Port: Integer);
begin
  FPort := Port;
end;

function TStompClient.Connect: Boolean;
begin
  try

    if FUseSSL then
    begin
      //FIOHandlerSocketOpenSSL.OnGetPassword := OpenSSLGetPassword;
      //FIOHandlerSocketOpenSSL.Port := 0  ;
      //FIOHandlerSocketOpenSSL.DefaultPort := 0       ;
      //FIOHandlerSocketOpenSSL.SSLOptions.Method := sslvTLSv1_2; //sslvSSLv3; //sslvSSLv23;
      //FIOHandlerSocketOpenSSL.SSLOptions.KeyFile  := FsslKeyFile;
      //FIOHandlerSocketOpenSSL.SSLOptions.CertFile := FsslCertFile;
      //FIOHandlerSocketOpenSSL.SSLOptions.Mode := sslmUnassigned; //sslmClient;
      //FIOHandlerSocketOpenSSL.SSLOptions.VerifyMode := [];
      //FIOHandlerSocketOpenSSL.SSLOptions.VerifyDepth := 0;
      //FTCP.IOHandler := FIOHandlerSocketOpenSSL;
    end
    else
    begin
      FTCP.IOHandler := nil;
    end;

    FTCP.ConnectTimeout := FConnectionTimeout;
    FTCP.Connect(FHost, FPort);
    FTCP.IOHandler.MaxLineLength := MaxInt;

    Frame := TStompFrame.Create;
    Frame.Command := 'CONNECT';

    FClientAcceptProtocolVersion := FAcceptVersion;
    if TStompAcceptProtocol.Ver_1_1 in [FClientAcceptProtocolVersion]
    then
    begin
      Frame.Headers.Add('accept-version', '1.1'); // stomp 1.1
      lHeartBeat := Format('%d,%d', [FOutgoingHeartBeats, FIncomingHeartBeats]);
      Frame.Headers.Add('heart-beat', lHeartBeat); // stomp 1.1
    end
    else
    begin
      Frame.Headers.Add('accept-version', '1.0'); // stomp 1.0
    end;

    if FVirtualHost <> '' then
    begin
      Frame.Headers.Add('host', FVirtualHost);
    end;

    Frame.Headers.Add('login', FUserName).Add('passcode', FPassword);
    if FClientID <> '' then
    begin
      Frame.Headers.Add('client-id', FClientID);
    end;
    SendFrame(Frame);
    Frame := nil;
    while Frame = nil do
      Frame := Receive;
    if Frame.Command = 'ERROR' then
      raise EStomp.Create(FormatErrorFrame(Frame));
    if Frame.Command = 'CONNECTED' then
    begin
      FSession := Frame.Headers.Value('session');
      FServerProtocolVersion := Frame.Headers.Value('version'); // stomp 1.1
      FServer := Frame.Headers.Value('server'); // stomp 1.1
      ParseHeartBeat(Frame.Headers);
    end;

    // Let's start the hearbeat thread
    if ServerSupportsHeartBeat then
    begin
      FHeartBeatThread := THeartBeatThread.Create(Self, FLock, FServerOutgoingHeartBeats);
      FHeartBeatThread.OnHeartBeatError := OnHeartBeatErrorHandler;
      FHeartBeatThread.Start;
    end;

    { todo: 'Call event?' -> by Gc}
    // Add by GC 26/01/2011
    if Assigned(FOnConnect) then
      FOnConnect(Self, Frame);

  except
    on E: Exception do
    begin
      raise EStomp.Create(E.message);
    end;
  end;

  Result := Self;
end;

function TStompClient.Connected: boolean;
begin
  Result := Assigned(FTCP) and FTCP.Connected and (not FTCP.IOHandler.ClosedGracefully);
end;

constructor TStompClient.Create;
begin
  inherited;
  FLock := TObject.Create;
  FInTransaction := False;
  FSession := '';
  FUserName := 'guest';
  FPassword := 'guest';
  FUseSSL := false;
  FHeaders := TStompHeaders.Create;
  FTimeout := 200;
  FReceiptTimeout := FTimeout;
  FConnectionTimeout := 1000 * 10; // 10secs
  FIncomingHeartBeats := 10000; // 10secs
  FOutgoingHeartBeats := 0; // disabled

  FHost := '127.0.0.1';
  FPort := DEFAULT_STOMP_PORT;
  FVirtualHost := '';
  FClientID := '';
  FAcceptVersion := TStompAcceptProtocol.Ver_1_0;
end;

procedure TStompClient.DeInit;
begin
  FreeAndNil(FTCP);
  FreeAndNil(FIOHandlerSocketOpenSSL);
  FreeAndNil(FTransactions);
end;

destructor TStompClient.Destroy;
begin
  Disconnect;
  DeInit;
  FLock.Free;

  inherited;
end;

procedure TStompClient.Disconnect;
var
  Frame: IStompFrame;
begin
  if Connected then
  begin
    if ServerSupportsHeartBeat then
    begin
      Assert(Assigned(FHeartBeatThread), 'HeartBeat thread not created');
      FHeartBeatThread.Terminate;
      FHeartBeatThread.WaitFor;
      FHeartBeatThread.Free;
    end;

    Frame := TStompFrame.Create;
    Frame.Command := 'DISCONNECT';

    SendFrame(Frame);

{$IFDEF USESYNAPSE}
    FSynapseTCP.CloseSocket;
    FSynapseConnected := False;
{$ELSE}
    FTCP.Disconnect;
{$ENDIF}
  end;
  DeInit;
end;

procedure TStompClient.DoHeartBeatErrorHandler;
begin
  if Assigned(FOnHeartBeatError) then
  begin
    try
      FOnHeartBeatError(Self);
    except
    end;
  end;
end;

function TStompClient.FormatErrorFrame(const AErrorFrame: IStompFrame): string;
begin
  if AErrorFrame.Command <> 'ERROR' then
    raise EStomp.Create('Not an ERROR frame');
  Result := AErrorFrame.Headers.Value('message') + ': ' +
    AErrorFrame.Body;
end;

function TStompClient.GetOnConnect: TStompConnectNotifyEvent;
begin
  Result := FOnConnect;
end;

function TStompClient.GetProtocolVersion: string;
begin
  Result := FServerProtocolVersion;
end;

function TStompClient.GetServer: string;
begin
  Result := FServer;
end;

function TStompClient.GetSession: string;
begin
  Result := FSession;
end;

procedure TStompClient.Init;
begin
  DeInit;

{$IFDEF USESYNAPSE}
  FSynapseTCP := TTCPBlockSocket.Create;
  FSynapseTCP.OnStatus := SynapseSocketCallBack;
  FSynapseTCP.RaiseExcept := True;

{$ELSE}
  FIOHandlerSocketOpenSSL := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
  FTCP := TIdTCPClient.Create(nil);

{$ENDIF}
  FTransactions := TStringList.Create;
end;

{$IFDEF USESYNAPSE}
procedure TStompClient.SynapseSocketCallBack(Sender: TObject;
  Reason: THookSocketReason; const Value: string);
begin
  // As seen at TBlockSocket.ExceptCheck procedure, it SEEMS safe to say
  // when an error occurred and is not a Timeout, the connection is broken
  if (Reason = HR_Error) and (FSynapseTCP.LastError <> WSAETIMEDOUT) then
  begin
    FSynapseConnected := False;
  end;
end;
{$ENDIF}

procedure TStompClient.MergeHeaders(var AFrame: IStompFrame;
  var AHeaders: IStompHeaders);
var
  i: Integer;
  h: TKeyValue;
begin
  if Assigned(AHeaders) then
    if AHeaders.Count > 0 then
      for i := 0 to AHeaders.Count - 1 do
      begin
        h := AHeaders.GetAt(i);
        AFrame.Headers.Add(h.Key, h.Value);
      end;

  // If the frame has some content, then set the length of that content.
  if (AFrame.ContentLength > 0) then
    AFrame.Headers.Add(StompHeaders.CONTENT_LENGTH, intToStr(AFrame.ContentLength));
end;

procedure TStompClient.Nack(const MessageID, subscriptionId, TransactionIdentifier: string);
var
  Frame: IStompFrame;
begin
  Frame := TStompFrame.Create;
  Frame.Command := 'NACK';
  Frame.Headers.Add('message-id', MessageID);

  if subscriptionId <> '' then
    Frame.Headers.Add('subscription', subscriptionId);

  if TransactionIdentifier <> '' then
    Frame.Headers.Add('transaction', TransactionIdentifier);
  SendFrame(Frame);
end;

procedure TStompClient.OnHeartBeatErrorHandler(Sender: TObject);
begin
  FHeartBeatThread.Terminate;
  FHeartBeatThread.WaitFor;
  FHeartBeatThread.Free;
  FHeartBeatThread := nil;
  Disconnect;
  DoHeartBeatErrorHandler;
end;

procedure TStompClient.OpenSSLGetPassword(var Password: String);
begin
  Password := FsslKeyPass;
end;

procedure TStompClient.ParseHeartBeat(Headers: IStompHeaders);
var
  lValue: string;
  lIntValue: string;
begin
  FServerOutgoingHeartBeats := 0;
  FServerIncomingHeartBeats := 0;
  // WARNING!! server heart beat is reversed
  lValue := Headers.Value('heart-beat');
  if Trim(lValue) <> '' then
  begin
    lIntValue := Fetch(lValue, ',');
    FServerIncomingHeartBeats := StrToInt(lIntValue);
    FServerOutgoingHeartBeats := StrToInt(lValue);
  end;
end;

procedure TStompClient.Receipt(const ReceiptID: string);
var
  Frame: IStompFrame;
begin
  if Receive(Frame, FReceiptTimeout) then
  begin
    if Frame.Command <> 'RECEIPT' then
      raise EStomp.Create('Receipt command error');
    if Frame.Headers.Value('receipt-id') <> ReceiptID then
      raise EStomp.Create('Receipt receipt-id error');
  end;
end;

function TStompClient.Receive(out StompFrame: IStompFrame;
  ATimeout: Integer): boolean;
begin
  StompFrame := nil;
  StompFrame := Receive(ATimeout);
  Result := Assigned(StompFrame);
end;

function TStompClient.Receive(ATimeout: Integer): IStompFrame;
// Considering that no one apparently discovered this bug (CreateFrame called with parameters)
// in the Synapse's version, one might consider whether one should deprecate Synapse support
// all together.
{$IFDEF USESYNAPSE}
  function InternalReceiveSynapse(ATimeout: Integer): IStompFrame;
  var
    c: char;
    s: string;
    tout: boolean;
  begin
    tout := False;
    Result := nil;
    try
      try
        FSynapseTCP.SetRecvTimeout(ATimeout);
        s := '';
        try
          while True do
          begin
            c := Chr(FSynapseTCP.RecvByte(ATimeout));
            if c <> CHAR0 then
              s := s + c
              // should be improved with a string buffer (daniele.teti)
            else
            begin
              c := Chr(FSynapseTCP.RecvByte(ATimeout));
              Break;
            end;
          end;
        except
          on E: ESynapseError do
          begin
            if E.ErrorCode = WSAETIMEDOUT then
              tout := True
            else
              raise;
          end;
          on E: Exception do
          begin
            raise;
          end;
        end;
        if not tout then
        begin
          Result := StompUtils.CreateFrameWithBuffer(s + CHAR0);
        end;
      finally
        s := '';
      end;
    except
      on E: Exception do
      begin
        raise;
      end;
    end;
  end;

{$ELSE}
  function InternalReceiveINDY(ATimeout: Integer): IStompFrame;
  var
    lLine: string;
    SStream: TStringStream;
    Buffer: TBytes;
    AsBytes: Boolean;
    ReadNull: Boolean;
    Headers: TIdHeaderList;
    ContentLength: Integer;
    Charset: string;
    lHeartBeat: boolean;
    lTimestampFirstReadLn: TDateTime;
{$IF CompilerVersion < 24}
    Encoding: TIdTextEncoding;
    FreeEncoding: boolean;
{$ELSE}
    Encoding: IIdTextEncoding;
{$ENDIF}
  begin
    Result := nil;
    SStream := TStringStream.Create;
    try
      FTCP.Socket.ReadTimeout := ATimeout;
      FTCP.Socket.DefStringEncoding :=
{$IF CompilerVersion < 24}TIdTextEncoding.UTF8{$ELSE}IndyTextEncoding_UTF8{$ENDIF};
      AsBytes := true;

      try
        lTimestampFirstReadLn := Now;
        // read command line
        while True do
        begin
          lLine := FTCP.Socket.ReadLn(LF, ATimeout, -1,
            FTCP.Socket.DefStringEncoding);

          if FTCP.Socket.ReadLnTimedout then
            Break;

          lHeartBeat := lLine = ''; // here is not timeout because of the previous line

          if FServerProtocolVersion = '1.1' then // 1.1 supports heart-beats
          begin
            if (not lHeartBeat) or (lLine <> '') then
              Break;
            if MilliSecondsBetween(lTimestampFirstReadLn, Now) >= ATimeout then
              Break;
          end
          else
            Break; // 1.0
        end;

        if lLine = '' then
          Exit(nil);
        SStream.WriteString(lLine + LF);
        ReadNull := false;

        // read headers
        Headers := TIdHeaderList.Create(QuotePlain);
        try
          repeat
            lLine := FTCP.Socket.ReadLn;
            SStream.WriteString(lLine + LF);
            if lLine = '' then
              Break;
            // in case of duplicated header, only the first is considered
            // https://stomp.github.io/stomp-specification-1.1.html#Repeated_Header_Entries
            if Headers.IndexOfName(Fetch(lLine, ':', False, False)) = -1 then
              Headers.Add(lLine);
          until False;

          ContentLength := -1;
          if Headers.IndexOfName(StompHeaders.CONTENT_LENGTH) <> -1 then
          begin
            // length specified, read exactly that many bytes
            ContentLength := IndyStrToInt(Headers.Values[StompHeaders.CONTENT_LENGTH]);
          end;

          // read body
          if IsHeaderMediaType(Headers.Values[StompHeaders.CONTENT_TYPE], 'text') then
          begin
            Charset := Headers.Params[StompHeaders.CONTENT_TYPE, 'charset'];
            if Charset = '' then
              Charset := 'utf-8';
            Encoding := CharsetToEncoding(Charset);
{$IF CompilerVersion < 24}
            try
{$ENDIF}
              if ContentLength > 0 then
              begin
                lLine := FTCP.Socket.ReadString(ContentLength, Encoding);
                SStream.WriteString(lLine);
              end
              else
              begin
                // no length specified, body terminated by frame terminating null
                lLine := FTCP.Socket.ReadLn(#0 + LF, Encoding);
                SStream.WriteString(lLine);
                ReadNull := true;
              end;
{$IF CompilerVersion < 24}
            finally
              Encoding.Free;
            end;
{$ENDIF}
            AsBytes := false;
          end
          else
          begin
            if ContentLength > 0 then
              FTCP.Socket.ReadStream(SStream, ContentLength, false)
            else
            begin
              if FTCP.Socket.CheckForDataOnSource(ATimeOut) then
                FTCP.Socket.ReadStream(SStream, -1, true);
            end;
            AsBytes := true;
          end;
          if not ReadNull then
          begin
            // frame must still be terminated by a null
            SStream.WriteString(#0);
            FTCP.Socket.ReadLn(#0 + LF);
          end;
        finally
          Headers.Free;
        end;
      except
        on E: Exception do
        begin
          if SStream.Size > 0 then
          begin
            SStream.Position := 0;
            raise EStomp.Create(E.message + sLineBreak + SStream.ReadString(SStream.Size))
          end
          else
            raise;
        end;
      end;

      SStream.Position := 0;

      if AsBytes then
      begin
        SetLength(Buffer, SStream.Size);
        SStream.Read(Buffer[0], SStream.Size);
        Result := StompUtils.CreateFrameWithBuffer(Buffer);
      end
      else
      begin
        Result := StompUtils.CreateFrameWithBuffer(SStream.ReadString(SStream.Size));
      end;

      if Result.Command = 'ERROR' then
        raise EStomp.Create(FormatErrorFrame(Result));
    finally
//      lSBuilder.Free;
      SStream.Free;
    end;
  end;
{$ENDIF}

begin
{$IFDEF USESYNAPSE}
  Result := InternalReceiveSynapse(ATimeout);
{$ELSE}
  Result := InternalReceiveINDY(ATimeout);
{$ENDIF}
end;

function TStompClient.Receive: IStompFrame;
begin
  Result := Receive(FTimeout);
end;

procedure TStompClient.Send(QueueOrTopicName: string; TextMessage: string;
  Headers: IStompHeaders);
var
  Frame: IStompFrame;
begin
  Frame := TStompFrame.Create;
  Frame.Command := 'SEND';
  Frame.Headers.Add('destination', QueueOrTopicName);
  Frame.Body := TextMessage;
  MergeHeaders(Frame, Headers);
  SendFrame(Frame);
end;

procedure TStompClient.Send(QueueOrTopicName: string; TextMessage: string;
  TransactionIdentifier: string; Headers: IStompHeaders);
var
  Frame: IStompFrame;
begin
  Frame := TStompFrame.Create;
  Frame.Command := 'SEND';
  Frame.Headers.Add('destination', QueueOrTopicName);
  Frame.Headers.Add('transaction', TransactionIdentifier);
  Frame.Body := TextMessage;
  MergeHeaders(Frame, Headers);
  SendFrame(Frame);
end;

procedure TStompClient.Send(QueueOrTopicName: string; ByteMessage: TBytes;
  Headers: IStompHeaders);
var
  Frame: IStompFrame;
begin
  Frame := TStompFrame.Create;
  Frame.Command := 'SEND';
  Frame.Headers.Add('destination', QueueOrTopicName);
  Frame.BytesBody := ByteMessage;
  MergeHeaders(Frame, Headers);
  SendFrame(Frame, true);
end;

procedure TStompClient.Send(QueueOrTopicName: string; ByteMessage: TBytes;
  TransactionIdentifier: string; Headers: IStompHeaders);
var
  Frame: IStompFrame;
begin
  Frame := TStompFrame.Create;
  Frame.Command := 'SEND';
  Frame.Headers.Add('destination', QueueOrTopicName);
  Frame.Headers.Add('transaction', TransactionIdentifier);
  Frame.BytesBody := ByteMessage;
  MergeHeaders(Frame, Headers);
  SendFrame(Frame, true);
end;


procedure TStompClient.SendFrame(AFrame: IStompFrame; AsBytes: boolean = false);
begin
  TMonitor.Enter(FLock);
  Try
    if Connected then // Test if error on Socket
    begin
      {$IFDEF USESYNAPSE}
          if Assigned(FOnBeforeSendFrame) then
            FOnBeforeSendFrame(AFrame);
          if AsBytes then
            FSynapseTCP.SendBytes(AFrame.OutputBytes)
          else
            FSynapseTCP.SendString(AFrame.Output);
          if Assigned(FOnAfterSendFrame) then
            FOnAfterSendFrame(AFrame);
      {$ELSE}
          // FTCP.IOHandler.write(TEncoding.ASCII.GetBytes(AFrame.output));
          if Assigned(FOnBeforeSendFrame) then
            FOnBeforeSendFrame(AFrame);

      {$IF CompilerVersion < 25}
          if AsBytes then
            FTCP.IOHandler.Write(AFrame.OutputBytes)
          else
            FTCP.IOHandler.write(TEncoding.UTF8.GetBytes(AFrame.output));
      {$IFEND}
      {$IF CompilerVersion >= 25}
          if AsBytes then
            FTCP.IOHandler.Write(TIdBytes(AFrame.OutputBytes))
          else
            FTCP.IOHandler.write(IndyTextEncoding_UTF8.GetBytes(AFrame.output));
      {$IFEND}

          if Assigned(FOnAfterSendFrame) then
            FOnAfterSendFrame(AFrame);
      {$ENDIF}
    end;
  Finally
    TMonitor.Exit(FLock);
  End;
end;

procedure TStompClient.SendHeartBeat;
begin
  TMonitor.Enter(FLock);
  Try
    if Connected then
    begin
        // Winapi.Windows.Beep(600, 200);
    {$IFDEF USESYNAPSE}
        FSynapseTCP.SendString(LF);
    {$ELSE}

    {$IF CompilerVersion < 25}
        FTCP.IOHandler.write(TEncoding.UTF8.GetBytes(LF));
    {$IFEND}
    {$IF CompilerVersion >= 25}
        FTCP.IOHandler.write(IndyTextEncoding_UTF8.GetBytes(LF));
    {$IFEND}

    {$ENDIF}
    end;
  Finally
    TMonitor.Exit(FLock);
  End;
end;

function TStompClient.ServerSupportsHeartBeat: boolean;
begin
  Result := (FServerProtocolVersion = '1.1') and (FServerOutgoingHeartBeats > 0)
end;

function TStompClient.SetConnectionTimeout(const Value: UInt32): IStompClient;
begin
  FConnectionTimeout := Value;
  Result := Self;
end;

function TStompClient.SetHeartBeat(const OutgoingHeartBeats, IncomingHeartBeats: Int64)
  : IStompClient;
begin
  FOutgoingHeartBeats := OutgoingHeartBeats;
  FIncomingHeartBeats := IncomingHeartBeats;
  Result := Self;
end;

function TStompClient.SetOnAfterSendFrame(const Value: TSenderFrameEvent): IStompClient;
begin
  FOnAfterSendFrame := Value;
  Result := Self;
end;

function TStompClient.SetOnBeforeSendFrame(const Value: TSenderFrameEvent): IStompClient;
begin
  FOnBeforeSendFrame := Value;
  Result := Self;
end;

procedure TStompClient.SetOnConnect(const Value: TStompConnectNotifyEvent);
begin
  FOnConnect := Value;
end;

function TStompClient.SetOnHeartBeatError(const Value: TNotifyEvent): IStompClient;
begin
  FOnHeartBeatError := Value;
  Result := Self;
end;

function TStompClient.SetPassword(const Value: string): IStompClient;
begin
  FPassword := Value;
  Result := Self;
end;

procedure TStompClient.SetReceiptTimeout(const Value: Integer);
begin
  FReceiptTimeout := Value;
end;

function TStompClient.SetReceiveTimeout(const AMilliSeconds: Cardinal)
  : IStompClient;
begin
  FTimeout := AMilliSeconds;
  Result := Self;
end;

function TStompClient.SetUserName(const Value: string): IStompClient;
begin
  FUserName := Value;
  Result := Self;
end;

function TStompClient.SetUseSSL(const boUseSSL: boolean; const KeyFile,
  CertFile, PassPhrase: string): IStompClient;
begin
  FUseSSL := boUseSSL;
  FsslKeyFile   := KeyFile;
  FsslCertFile := CertFile;
  FsslKeyPass  := PassPhrase;
  Result := Self;

end;

procedure TStompClient.Subscribe(QueueOrTopicName: string;
  Ack: TAckMode = TAckMode.amAuto; Headers: IStompHeaders = nil);
var
  Frame: IStompFrame;
begin
  Frame := TStompFrame.Create;
  Frame.Command := 'SUBSCRIBE';
  Frame.Headers.Add('destination', QueueOrTopicName)
    .Add('ack', StompUtils.AckModeToStr(Ack));
  if Headers <> nil then
    MergeHeaders(Frame, Headers);
  SendFrame(Frame);
end;

procedure TStompClient.Unsubscribe(Queue: string; const subscriptionId: string = '');
var
  Frame: IStompFrame;
begin
  Frame := TStompFrame.Create;
  Frame.Command := 'UNSUBSCRIBE';
  Frame.Headers.Add('destination', Queue);

  if subscriptionId <> '' then
    Frame.Headers.Add('id', subscriptionId);

  SendFrame(Frame);
end;

{ THeartBeatThread }

constructor THeartBeatThread.Create(StompClient: TStompClient; Lock: TObject;
  OutgoingHeatBeatTimeout: Int64);
begin
  inherited Create(True);
  FStompClient := StompClient;
  FLock := Lock;
  FOutgoingHeatBeatTimeout := OutgoingHeatBeatTimeout;
end;

procedure THeartBeatThread.DoHeartBeatError;
begin
  if Assigned(FOnHeartBeatError) then
  begin
    try
      // TThread.Synchronize(nil,
      // procedure
      // begin
      // FOnHeartBeatError(Self);
      // end);
    except
      // do nothing here
    end;
  end;
end;

procedure THeartBeatThread.Execute;
var
  lStart: TDateTime;
begin
  while not Terminated do
  begin
    lStart := Now;
    while (not Terminated) and (MilliSecondsBetween(Now, lStart) < FOutgoingHeatBeatTimeout) do
    begin
      Sleep(100);
    end;
    if not Terminated then
    begin
      // If the connection is down, the socket is invalidated so
      // it is not necessary to informa the main thread about
      // such kind of disconnection.
      FStompClient.SendHeartBeat;
    end;
  end;
end;

{ StompUtils }

class function StompUtils.StompClient: IStompClient;
begin
  Result := TStompClient.Create;
end;

class function StompUtils.StompClientAndConnect(Host: string; Port: Integer;
  VirtualHost: string; ClientID: string;
  AcceptVersion: TStompAcceptProtocol): IStompClient;
begin
  Result := Self.StompClient
                .SetHost(Host)
                .SetPort(Port)
                .SetVirtualHost(VirtualHost)
                .SetClientID(ClientID)
                .SetAcceptVersion(AcceptVersion)
                .Connect;
end;

class function StompUtils.NewDurableSubscriptionHeader(const SubscriptionName: string): TKeyValue;
begin
  Result := TStompHeaders.Subscription(SubscriptionName);
end;

class function StompUtils.NewPersistentHeader(const Value: Boolean): TKeyValue;
begin
  Result := TStompHeaders.Persistent(Value);
end;

class function StompUtils.NewReplyToHeader(const DestinationName: string): TKeyValue;
begin
  Result := TStompHeaders.ReplyTo(DestinationName);
end;

class function StompUtils.CreateListener(const StompClient: IStompClient;
  const StompClientListener: IStompClientListener): IStompListener;
begin
  Result := TStompClientListener.Create(StompClient, StompClientListener);
end;

class function StompUtils.StripLastChar(Buf: string): string;
var
  p: Integer;
begin
  p := Pos(COMMAND_END, Buf);
  if (p = 0) then
    raise EStomp.Create('frame no ending');
  Result := Copy(Buf, 1, p - 1);
end;

class function StompUtils.TimestampAsDateTime(const HeaderValue: string)
  : TDateTime;
begin
  Result := EncodeDateTime(1970, 1, 1, 0, 0, 0, 0) + StrToInt64(HeaderValue)
    / 86400000;
end;

class function StompUtils.AckModeToStr(AckMode: TAckMode): string;
begin
  case AckMode of
    amAuto:
      Result := 'auto';
    amClient:
      Result := 'client';
    amClientIndividual:
      Result := 'client-individual'; // stomp 1.1
  else
    raise EStomp.Create('Unknown AckMode');
  end;
end;

class function StompUtils.NewHeaders: IStompHeaders;
begin
  Result := Headers;
end;

class function StompUtils.CreateFrame: IStompFrame;
begin
  Result := TStompFrame.Create;
end;

class function StompUtils.CreateFrameWithBuffer(Buf: string): IStompFrame;
var
  line: string;
  i: Integer;
  p: Integer;
  Key, Value: string;
  other: string;
  contLen: Integer;
  sContLen: string;
begin
  Result := TStompFrame.Create;
  i := 1;
  try
    Result.Command := GetLine(Buf, i);
    while true do
    begin
      line := GetLine(Buf, i);
      if (line = '') then
        break;
      p := Pos(':', line);
      if (p = 0) then
        raise Exception.Create('header line error');
      Key := Copy(line, 1, p - 1);
      Value := Copy(line, p + 1, Length(line) - p);
      Result.Headers.Add(Key, Value);
    end;
    other := Copy(Buf, i, high(Integer));
    sContLen := Result.Headers.Value(StompHeaders.CONTENT_LENGTH);
    if (sContLen <> '') then
    begin
      if other[Length(other)] <> #0 then
        raise EStomp.Create('frame no ending');
      contLen := StrToInt(sContLen);
      other := StripLastChar(other);

      if TEncoding.UTF8.GetByteCount(other) <> contLen then
        // there is still the command_end
        raise EStomp.Create('frame too short');
      Result.Body := other;
    end
    else
    begin
      Result.Body := StripLastChar(other);
    end;
  except
    on EStomp do
    begin
      // ignore
      Result := nil;
    end;
    on e: Exception do
    begin
      Result := nil;
      raise EStomp.Create(e.Message);
    end;
  end;
end;

class function StompUtils.CreateFrameWithBuffer(Buf: TBytes): IStompFrame;
var
  headerLine: string;
  i: Integer;
  p: Integer;
  Key, Value: string;
  other: TBytes;
  contLen: Integer;
  sContLen: string;
begin
  Result := TStompFrame.Create;
  i := 0;
  try
    Result.Command := TEncoding.UTF8.GetString(GetByteLine(Buf, i)); // convert to string
    while true do
    begin
      headerLine := TEncoding.UTF8.GetString(GetByteLine(Buf, i)); // convert to string
      if (headerLine = '') then
        break;
      p := Pos(':', headerLine);
      if (p = 0) then
        raise Exception.Create('header line error');
      Key := Copy(headerLine, 1, p - 1);
      Value := Copy(headerLine, p + 1, Length(headerLine) - p);
      Result.Headers.Add(Key, Value);
    end;
    SetLength(other, Length(buf) - i);
    other := Copy(Buf, i, high(Integer));
    sContLen := Result.Headers.Value(StompHeaders.CONTENT_LENGTH);
    if (sContLen <> '') then
    begin
      if other[Length(other)-1] <> 0 then
        raise EStomp.Create('frame no ending');
      contLen := StrToInt(sContLen);
      other := Copy(other, 0, Length(other) - 1);

      if Length(other) <> contLen then
        // there is still the command_end
        raise EStomp.Create('frame too short');
      Result.BytesBody := other;
    end
    else
    begin
      Result.BytesBody := Copy(other, 0, Length(other) - 1);
    end;
  except
    on EStomp do
    begin
      // ignore
      Result := nil;
    end;
    on e: Exception do
    begin
      Result := nil;
      raise EStomp.Create(e.Message);
    end;
  end;
end;

class function StompUtils.Headers: IStompHeaders;
begin
  Result := TStompHeaders.Create;
end;

class function StompUtils.NewFrame: IStompFrame;
begin
  Result := TStompFrame.Create;
end;


constructor TKeyValue.Create(const Key: String; const Value: String);
begin
//  inherited Create;
  Self.Key := Key;
  Self.Value := Value;
end;

end.

