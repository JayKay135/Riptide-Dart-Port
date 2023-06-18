import 'dart:io';
import 'dart:typed_data';

import '_message.dart';
import 'transports/_connection.dart';
import 'transports/_eventArgs.dart' as event_args;
import 'transports/_iclient.dart';
import 'transports/udp/_udpClient.dart';
import 'utils/_delayedEvents.dart';
import 'utils/_eventHandler.dart';
import 'utils/_riptideLogger.dart';
import 'package:tuple/tuple.dart';

import 'transports/_ipeer.dart';
import '_eventArgs.dart';
import '_peer.dart';

/// Encapsulates a method that handles a message from a server.
/// [message] : The message that was received.
typedef MessageHandler = void Function(Message message);

/// A client that can connect to a Server.
class Client extends Peer {
  /// Invoked when a connection to the server is established.
  Event connected = Event();

  /// Invoked when a connection to the server fails to be established.
  Event connectionFailed = Event();

  /// Invoked when a message is received.
  Event<MessageReceivedEventArgs> messageReceived = Event<MessageReceivedEventArgs>();

  /// Invoked when disconnected from the server.
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  /// Invoked when another non-localclient connects.
  Event<ClientConnectedEventArgs> clientConnected = Event<ClientConnectedEventArgs>();

  /// Invoked when another non-local client disconnects.
  Event<ClientDisconnectedEventArgs> clientDisconnected = Event<ClientDisconnectedEventArgs>();

  /// The client's connection to a server.
  Connection? _connection;
  Connection? get connection => _connection;

  Map<int, MessageHandler> _messageHandlers = {};

  /// The client's numeric ID.
  int get id => _connection!.id;

  int get rtt => _connection!.rtt;

  /// This value is slower to accurately represent lasting changes in latency than rtt, but it is less susceptible to changing drastically due to significant—but temporary—jumps in latency.
  int get smoothRtt => _connection!.smoothRtt;

  /// Whether or not the client is currently not trying to connect, pending, nor actively connected.
  bool get isNotConnected => _connection!.isNotConnected();

  /// Whether or not the client is currently in the process of connecting.
  bool get isConnecting => _connection!.isConnecting();

  /// Whether or not the client's connection is currently pending (waiting to be accepted/rejected by the server).
  bool get isPending => _connection!.isPending();

  /// Whether or not the client is currently connected.
  bool get isConnected => _connection!.isConnected();

  /// How many connection attempts have been made so far.
  late int _connectionAttempts;

  /// How many connection attempts to make before giving up.
  late int _maxConnectionAttempts;

  /// The underlying transport's client that is used for sending and receiving data.
  late IClient _transport;

  /// Custom data to include when connecting.
  late Uint8List? connectBytes;

  /// Handles initial setup.
  /// [transport] : The transport to use for sending and receiving data.
  /// [logName] : The name to use when logging messages via RiptideLogger.
  Client({IClient? transport, String logname = "CLIENT"}) : super(logName: logname) {
    _transport = transport ?? UdpClient();
  }

  /// Disconnects the client if it's connected and swaps out the transport it's using.
  ///
  /// [newTransport] : The new transport to use for sending and receiving data.
  /// This method does not automatically reconnect to the server. To continue communicating with the server, connect must be called again.
  void changeTransport(IClient newTransport) {
    disconnect();
    _transport = newTransport;
  }

  /// Attempts to connect to a server at the given host address.
  ///
  /// [hostAddress] : The host address to connect to.
  /// [port] : The host port to connect to.
  /// [maxConnectionAttempts] : How many connection attempts to make before giving up.
  /// [message] : Data that should be sent to the server with the connection attempt. Use Message.create() to get an empty message instance.
  /// [useMessageHandlers] : Whether or not the client should use the built-in message handler system.
  ///
  /// Setting useMessageHandlers to false will disable the subscription system of the messageHandler, which is beneficial if you prefer to handle messages via the messageReceived event.
  /// Returns true if a connection attempt will be made. False if an issue occurred and a connection attempt will not be made.
  Future<bool> connect(InternetAddress hostAddress, int port, {int maxConnectionAttempts = 5, Message? message, bool useMessageHandlers = true}) async {
    disconnect();

    _subToTransportEvents();

    Tuple3 res = await _transport.connect(hostAddress, port);
    String connectError = res.item3;
    _connection = res.item2;

    if (!res.item1) {
      RiptideLogger.log2(LogType.error, logName, connectError);
      _unsubFromTransportEvents();
      return false;
    }

    _maxConnectionAttempts = maxConnectionAttempts;
    _connectionAttempts = 0;
    _connection!.peer = this;
    Peer.increaseActiveCount();
    this.useMessageHandlers = useMessageHandlers;

    if (message != null) {
      connectBytes = message.getBytes(message.writtenLength);
      message.release();
    } else {
      connectBytes = null;
    }

    heartbeat();
    RiptideLogger.log2(LogType.info, logName, "Connecting to $connection...");
    return true;
  }

  /// Subscribes appropriate methods to the transport's events.
  void _subToTransportEvents() {
    _transport.connected.subscribe((args) => _transportConnected);
    _transport.connectionFailed.subscribe((args) => _transportConnnectionFailed);
    _transport.dataReceived.subscribe((args) => handleData(args!));
    _transport.disconnected.subscribe((args) => _transportDisconnected(args!));
  }

  /// Unsubscribes methods from all of the transport's events.
  void _unsubFromTransportEvents() {
    _transport.connected.unsubscribe((args) => _transportConnected);
    _transport.connectionFailed.unsubscribe((args) => _transportConnnectionFailed);
    _transport.dataReceived.unsubscribe((args) => handleData(args!));
    _transport.disconnected.unsubscribe((args) => _transportDisconnected(args!));
  }

  /// Registers a callback handler for a specifc [messageID] when messages with this particular id are received.
  void registerMessageHandler(int messageID, Function(Message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  @override
  void heartbeat() {
    if (isConnecting) {
      // If still trying to connect, send connect messages instead of heartbeats
      if (_connectionAttempts < _maxConnectionAttempts) {
        Message message = Message.createFromHeader(MessageHeader.connect);
        if (connectBytes != null) {
          message.addBytes(connectBytes!, includeLength: false);
        }

        send(message);
        _connectionAttempts++;
      } else {
        localDisconnect(DisconnectReason.neverConnected);
      }
    } else if (isPending) {
      // If waiting for the server to accept/reject the connection attempt
      if (connection!.hasConnectAttemptTimedOut) {
        localDisconnect(DisconnectReason.timedOut);
        return;
      }
    } else if (isConnected) {
      // If connected and not timed out, send heartbeats
      if (connection!.hasTimedOut) {
        localDisconnect(DisconnectReason.timedOut);
        return;
      }

      connection!.sendHeartbeat();
    }

    executeLater(heartbeatInterval, HeartbeatEvent(this));
  }

  @override
  void update() {
    super.update();
    _transport.poll();
    handleMessages();
  }

  @override
  void handle(Message message, MessageHeader header, Connection connection) {
    switch (header) {
      // User messages
      case MessageHeader.unreliable:
      case MessageHeader.reliable:
        _onMessageReceived(message);
        break;

      // Internal messages
      case MessageHeader.ack:
        connection.handleAck(message);
        break;
      case MessageHeader.ackExtra:
        connection.handleAckExtra(message);
        break;
      case MessageHeader.connect:
        connection.setPending();
        break;
      case MessageHeader.reject:
        if (!isConnected) {
          // Don't disconnect if we are connected
          localDisconnect(DisconnectReason.connectionRejected, message: message, rejectReason: RejectReason.values[message.getByte()]);
        }
        break;
      case MessageHeader.heartbeat:
        connection.handleHeartbeatResponse(message);
        break;
      case MessageHeader.disconnect:
        localDisconnect(DisconnectReason.values[message.getByte()], message: message);
        break;
      case MessageHeader.welcome:
        if (isConnecting || isPending) {
          connection.handleWelcome(message);
          _onConnected();
        }
        break;
      case MessageHeader.clientConnected:
        _onClientConnected(message.getUShort());
        break;
      case MessageHeader.clientDisconnected:
        _onClientDisconnected(message.getUShort());
        break;
      default:
        RiptideLogger.log2(LogType.warning, logName, "Unexpected message header '$header'! Discarding ${message.writtenLength} bytes.");
        break;
    }

    message.release();
  }

  /// Sends a message to the server.
  ///
  /// [message] : The message to send.
  /// [shouldRelease] : Whether or not to return the message to the pool after it is sent.
  ///  If you intend to continue using the message instance after calling this method, you must set [shouldRelease]
  ///  to false. Message.release can be used to manually return the message to the pool at a later time.
  void send(Message message, {bool shouldRelease = true}) {
    _connection!.sendMessage(message, shouldRelease: shouldRelease);
  }

  /// Disconnects from the server.
  void disconnect() {
    if (_connection == null || isNotConnected) {
      return;
    }

    send(Message.createFromHeader(MessageHeader.disconnect));
    localDisconnect(DisconnectReason.disconnected);
  }

  /// Cleans up the local side of the connection.
  ///
  /// [reason] : The reason why the client has disconnected.
  /// [message] : The disconnection or rejection message, potentially containing extra data to be handled externally.
  /// [rejectReason] : TData that should be sent to the client being disconnected. Use Message.create to get an empty message instance. Unused if the connection wasn't rejected.
  void localDisconnect(DisconnectReason reason, {Message? message, RejectReason rejectReason = RejectReason.noConnection}) {
    if (isNotConnected) return;

    _unsubFromTransportEvents();
    Peer.decreaseActiveCount();

    stopTime();
    _transport.disconnect();

    _connection!.localDisconnect();

    if (reason == DisconnectReason.neverConnected) {
      _onConnectionFailed(RejectReason.noConnection);
    } else if (reason == DisconnectReason.connectionRejected) {
      _onConnectionFailed(rejectReason, message: message);
    } else {
      _onDisconnected(reason, message);
    }
  }

  /// What to do when the transport establishes a connection.
  void _transportConnected(EventArgs e) {
    startTime();
  }

  /// What to do when the transport fails to connect.
  void _transportConnnectionFailed(EventArgs e) {
    localDisconnect(DisconnectReason.neverConnected);
  }

  /// What to do when the transport disconnects.
  void _transportDisconnected(event_args.DisconnectedEventArgs e) {
    if (_connection == e.connection) {
      localDisconnect(e.reason);
    }
  }

  /// Invokes the connected event.
  void _onConnected() {
    RiptideLogger.log2(LogType.info, logName, "Connected successfully!");
    connected.invoke(null);
  }

  /// Invokes the connectionFailed event.
  ///
  /// [reason] : The reason for the connection failure.
  /// [message] : Additional data related to the failed connection attempt.
  void _onConnectionFailed(RejectReason reason, {Message? message}) {
    String reasonString;

    switch (reason) {
      case RejectReason.noConnection:
        reasonString = CRNoConnection;
        break;
      case RejectReason.serverFull:
        reasonString = CRServerFull;
        break;
      case RejectReason.rejected:
        reasonString = CRRejected;
        break;
      case RejectReason.custom:
        reasonString = CRCustom;
        break;
      default:
        reasonString = "$UnknownReason '$reason'";
        break;
    }

    RiptideLogger.log2(LogType.info, logName, "Connection to server failed: $reasonString.");
    connectionFailed.invoke(ConnectionFailedEventArgs(message));
  }

  /// Invokes the messageReceived event and initiates handling of the received message.
  ///
  /// [message] : The received message.
  void _onMessageReceived(Message message) {
    int messageID = message.getUShort();
    messageReceived.invoke(MessageReceivedEventArgs(_connection!, messageID, message));

    if (useMessageHandlers) {
      if (_messageHandlers.containsKey(messageID)) {
        _messageHandlers[messageID]!.call(message);
      } else {
        RiptideLogger.log2(LogType.warning, logName, "No message handler method found for message ID $messageID!");
      }
    }
  }

  /// Invokes the disconnected event.
  ///
  /// [reason] : The reason for the disconnection.
  /// [message] : Additional data related to the disconnection.
  void _onDisconnected(DisconnectReason reason, Message? message) {
    String reasonString;
    switch (reason) {
      case DisconnectReason.neverConnected:
        reasonString = DCNeverConnected;
        break;
      case DisconnectReason.transportError:
        reasonString = DCTransportError;
        break;
      case DisconnectReason.timedOut:
        reasonString = DCTimedOut;
        break;
      case DisconnectReason.kicked:
        reasonString = DCKicked;
        break;
      case DisconnectReason.serverStopped:
        reasonString = DCServerStopped;
        break;
      case DisconnectReason.disconnected:
        reasonString = DCDisconnected;
        break;
      default:
        reasonString = "$UnknownReason '$reason'";
        break;
    }

    RiptideLogger.log2(LogType.info, logName, "Disconnected from server: $reasonString.");
    disconnected.invoke(DisconnectedEventArgs(reason, message));
  }

  /// Invokes the clientConnected event.
  ///
  /// [clientID] : The numeric ID of the client that connected.
  void _onClientConnected(int clientID) {
    RiptideLogger.log2(LogType.info, logName, "Client $clientID connected.");
    clientConnected.invoke(ClientConnectedEventArgs(clientID));
  }

  /// Invokes the clientDisconnected event.
  ///
  /// [clientID] : The numeric ID of the client that disconnected.
  void _onClientDisconnected(int clientID) {
    RiptideLogger.log2(LogType.info, logName, "Client $clientID disconnected.");
    clientDisconnected.invoke(ClientDisconnectedEventArgs(clientID));
  }
}
