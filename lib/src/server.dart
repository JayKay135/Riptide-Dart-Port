import 'dart:collection';
import 'dart:typed_data';

import 'message.dart';
import 'connection.dart';
import 'transports/event_args.dart' as event_args;
import 'transports/ipeer.dart';
import 'transports/iserver.dart';
import 'transports/udp/udp_server.dart';
import 'utils/constants.dart';
import 'utils/delayed_events.dart';
import 'utils/event_handler.dart';
import 'utils/helper.dart';
import 'utils/riptide_logger.dart';
import 'event_args.dart';
import 'message_relay_filter.dart';
import 'peer.dart';

/// Encapsulates a method that handles a message from a client.
///
/// [fromClientID] : The numeric ID of the client from whom the message was received.
/// [message] : The message that was received.
typedef MessageHandler = void Function(int fromClientID, Message message);

/// Encapsulates a method that determines whether or not to accept a client's connection attempt.
typedef ConnectionAttemptHandler = void Function(Connection pendingConnection, Message connectMessage);

/// A server that can accept connections from Clients.
class Server extends Peer {
  /// Invoked when a client connects.
  Event<ServerConnectedEventArgs> clientConnected = Event<ServerConnectedEventArgs>();

  /// Invoked when a connection fails to be fully established.
  Event<ServerConnectionFailedEventArgs> connectionFailed = Event<ServerConnectionFailedEventArgs>();

  /// Invoked when a message is received.
  Event<MessageReceivedEventArgs> messageReceived = Event<MessageReceivedEventArgs>();

  /// Invoked when a client disconnects.
  Event<ServerDisconnectedEventArgs> clientDisconnected = Event<ServerDisconnectedEventArgs>();

  /// Whether or not the server is currently running.
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// The local port that the server is running on.
  int get port => _transport.port;

  @override
  int get timeoutTime => defaultTimeout;

  /// Sets the default timeout time for future connections and updates the [Connection.timeoutTime] of all connected clients.
  @override
  set timeoutTime(int value) {
    defaultTimeout = value;
    for (var connection in _clients.values) {
      connection.timeoutTime = defaultTimeout;
    }
  }

  /// The maximum number of concurrent connections.
  late int _maxClientCount;
  int get maxClientCount => _maxClientCount;

  /// The number of currently connected clients.
  int get clientCount => _clients.length;

  /// An array of all the currently connected clients.
  ///
  /// The position of each Connection instance in the array does not correspond to that client's numeric ID (except by coincidence).
  List<Connection> get clients => _clients.values.toList();

  /// An optional method which determines whether or not to accept a client's connection attempt.
  ///
  /// The Connection parameter is the pending connection and the Message parameter is a message containing any additional data the client included with the connection attempt.
  /// If you choose to subscribe a method to this delegate, you should use it to call either [accept] or [reject].
  /// Not doing so will result in the connection hanging until the client times out.
  ConnectionAttemptHandler? handleConnection;

  /// Stores which message IDs have auto relaying enabled. Relaying is disabled entirely when this is null.
  MessageRelayFilter? relayFilter;

  /// Currently pending connections which are waiting to be accepted or rejected.
  late final List<Connection> _pendingConnections;

  /// Currently connected clients.
  late final Map<int, Connection> _clients;

  /// Clients that have timed out and need to be removed from clients.
  late final List<Connection> _timedOutClients;

  /// Methods used to handle messages, accessible by their corresponding message IDs.
  Map<int, MessageHandler> _messageHandlers = {};

  /// The underlying transport's server that is used for sending and receiving data.
  late IServer _transport;

  /// All currently unused client IDs.
  late Queue<int> _availableClientIds;

  /// Handles initial setup.
  ///
  /// [transport] : The transport to use for sending and receiving data.
  /// [logName] : The name to use when logging messages via RiptideLogger.
  Server({IServer? transport, String logName = "SERVER"}) : super(logName: logName) {
    _transport = transport ?? UdpServer();
    _pendingConnections = [];
    _clients = {};
    _timedOutClients = [];
  }

  /// Stops the server if it's running and swaps out the transport it's using.
  ///
  /// [newTransport] : The new underlying transport server to use for sending and receiving data.
  ///
  /// This method does not automatically restart the server. To continue accepting connections, [start] must be called again.
  void changeTransport(IServer newTransport) {
    stop();
    _transport = newTransport;
  }

  /// Starts the server.
  ///
  /// [port] : The local port on which to start the server.
  /// [maxClientCount] : The maximum number of concurrent connections to allow.
  /// [messageHandlerGroupId] : The ID of the group of message handler methods to use when building [_messageHandlers].
  /// [useMessageHandlers] : Whether or not the server should use the built-in message handler system.
  ///
  /// Setting [useMessageHandlers] to false will disable the message specific subscription system, which is beneficial if you prefer to handle messages via the [messageReceived] event.
  void start(
    int port,
    int maxClientCount, {
    int messageHandlerGroupId = 0,
    bool useMessageHandlers = true,
  }) {
    stop();

    increaseActiveCount();
    this.useMessageHandlers = useMessageHandlers;

    _maxClientCount = maxClientCount;
    _clients.clear();
    _initializeClientIds();

    _subToTransportEvents();
    _transport.start(port);

    startTime();
    heartbeat();
    _isRunning = true;
    RiptideLogger.logWithLogName(LogType.info, logName, "Started on port $port.");
  }

  /// Subscribes appropriate methods to the transport's events.
  void _subToTransportEvents() {
    _transport.connected.subscribe((args) => _handleConnectionAttempt(args!));
    _transport.dataReceived.subscribe((args) => handleData(args!));
    _transport.disconnected.subscribe((args) => _transportDisconnected(args!));
  }

  /// Unsubscribes methods from all of the transport's events.
  void _unsubFromTransportEvents() {
    _transport.connected.unsubscribe((args) => _handleConnectionAttempt(args!));
    _transport.dataReceived.unsubscribe((args) => handleData(args!));
    _transport.disconnected.unsubscribe((args) => _transportDisconnected(args!));
  }

  /// Registers a callback handler for a specifc [messageID] when messages with this particular id are received.
  void registerMessageHandler(int messageID, Function(int fromClientID, Message message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  /// Handles an incoming connection attempt.
  void _handleConnectionAttempt(event_args.ConnectedEventArgs e) {
    // e.connection.peer = _transport as Peer;
    e.connection.initialize(this, defaultTimeout);
  }

  /// Handles a connect message.
  ///
  /// [connection] : The client that sent the connect message.
  /// [connectMessage] : The connect message.
  void _handleConnect(Connection connection, Message connectMessage) {
    connection.setPending();

    if (handleConnection == null) {
      _acceptConnection(connection);
    } else if (clientCount < _maxClientCount) {
      if (!_clients.containsValue(connection) && !_pendingConnections.contains(connection)) {
        _pendingConnections.add(connection);
        sendWithConnection(Message.createFromHeader(MessageHeader.connect), connection); // Inform the client we've received the connection attempt
        handleConnection!(connection, connectMessage); // Externally determines whether to accept
      } else {
        _reject(connection, RejectReason.alreadyConnected);
      }
    } else {
      _reject(connection, RejectReason.serverFull);
    }
  }

  /// Accepts the given pending connection.
  ///
  /// [connection] : The connection to accept.
  void accept(Connection connection) {
    if (_pendingConnections.remove(connection)) {
      _acceptConnection(connection);
    } else {
      RiptideLogger.logWithLogName(LogType.warning, logName, "Couldn't accept connection from $connection because no such connection was pending!");
    }
  }

  /// Rejects the given pending connection.
  ///
  /// [connection] : The connection to reject.
  /// [message] : Data that should be sent to the client being rejected. Use [Message.create] to get an empty message instance.
  void reject(Connection connection, {Message? message}) {
    if (message != null && message.readBits != 0)
      RiptideLogger.logWithLogName(LogType.error, logName, "Use the parameterless 'Message.create()' function when setting rejection data!");

    if (_pendingConnections.remove(connection))
      _reject(connection, message == null ? RejectReason.rejected : RejectReason.custom, message);
    else
      RiptideLogger.logWithLogName(LogType.warning, logName, "Couldn't reject connection from $connection because no such connection was pending!");
  }

  /// Accepts the given pending connection.
  ///
  /// [connection] : The connection to accept.
  void _acceptConnection(Connection connection) {
    if (clientCount < _maxClientCount) {
      if (!_clients.containsValue(connection)) {
        int clientId = _getAvailableClientId();
        connection.id = clientId;
        _clients[clientId] = connection;
        connection.resetTimeout();
        connection.sendWelcome();
        return;
      } else {
        _reject(connection, RejectReason.alreadyConnected);
      }
    } else {
      _reject(connection, RejectReason.serverFull);
    }
  }

  /// Rejects the given pending connection.
  ///
  /// [connection] : The connection to reject.
  /// [reason] : The reason why the connection is being rejected.
  /// [rejectMessage] : Data that should be sent to the client being rejected.
  void _reject(Connection connection, RejectReason reason, [Message? rejectMessage]) {
    if (reason != RejectReason.alreadyConnected) {
      // Sending a reject message about the client already being connected could theoretically be exploited to obtain information
      // on other connected clients, although in practice that seems very unlikely. However, under normal circumstances, clients
      // should never actually encounter a scenario where they are "already connected".

      Message message = Message.createFromHeader(MessageHeader.reject);
      message.addByte(reason.index);

      if (reason == RejectReason.custom) {
        message.addMessage(rejectMessage!);
      }

      for (int i = 0; i < 3; i++) {
        // Send the rejection message a few times to increase the odds of it arriving
        connection.sendMessage(message, false);
      }

      message.release();
    }

    connection.resetTimeout(); // Keep the connection alive for a moment so the same client can't immediately attempt to connect again
    connection.localDisconnect(wasRejected: true);

    RiptideLogger.logWithLogName(LogType.info, logName, "Rejected connection from $connection: ${Helper.getRejectReasonString(reason)}.");
  }

  /// Checks if clients have timed out.
  @override
  void heartbeat() {
    for (Connection connection in _clients.values) {
      if (connection.hasTimedOut) {
        _timedOutClients.add(connection);
      }
    }

    for (Connection connection in _pendingConnections) {
      if (connection.hasConnectAttemptTimedOut) {
        _timedOutClients.add(connection);
      }
    }

    for (Connection connection in _timedOutClients) {
      _localDisconnect(connection, DisconnectReason.timedOut);
    }

    _timedOutClients.clear();

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
        onMessageReceived(message, connection);
        break;

      // Internal messages
      case MessageHeader.ack:
        connection.handleAck(message);
        break;
      case MessageHeader.connect:
        _handleConnect(connection, message);
        break;
      case MessageHeader.heartbeat:
        connection.handleHeartbeat(message);
        break;
      case MessageHeader.disconnect:
        _localDisconnect(connection, DisconnectReason.disconnected);
        break;
      case MessageHeader.welcome:
        if (connection.handleWelcomeResponse(message)) {
          onClientConnected(connection);
        }
        break;
      default:
        RiptideLogger.logWithLogName(
            LogType.warning, logName, "Unexpected message header '$header'! Discarding ${message.bytesInUse} bytes received from $connection.");
        break;
    }

    message.release();
  }

  /// Sends a message to a given client.
  ///
  /// [message] : The message to send.
  /// [toClient] : The numeric ID of the client to send the message to.
  /// [shouldRelease] : Whether or not to return the message to the pool after it is sent.
  void send(Message message, int toClient, [bool shouldRelease = true]) {
    if (_clients.containsKey(toClient)) {
      Connection connection = _clients[toClient]!;
      sendWithConnection(message, connection, shouldRelease);
    }
  }

  /// Sends a message to a given client.
  ///
  /// [message] : The message to send.
  /// [toClient] : The client to send the message to.
  /// [shouldRelease] : Whether or not to return the message to the pool after it is sent.
  void sendWithConnection(Message message, Connection toClient, [bool shouldRelease = true]) {
    toClient.sendMessage(message, shouldRelease);
  }

  /// Sends a message to all connected clients.
  ///
  /// [message] : The message to send.
  /// [shouldRelease] : Whether or not to return the message to the pool after it is sent.
  void sendToAll(Message message, [bool shouldRelease = true]) {
    for (Connection client in _clients.values) {
      client.sendMessage(message, false);
    }

    if (shouldRelease) {
      message.release();
    }
  }

  /// Sends a message to all connected clients except the given one.
  ///
  /// [message] : The message to send.
  /// [exceptToClientId] : The numeric ID of the client to not send the message to.
  /// [shouldRelease] : Whether or not to return the message to the pool after it is sent.
  void sendToAllExcept(Message message, int exceptToClientId, [bool shouldRelease = true]) {
    for (Connection client in _clients.values) {
      if (client.id != exceptToClientId) {
        client.sendMessage(message, false);
      }
    }

    if (shouldRelease) {
      message.release();
    }
  }

  /// Retrieves the client with the given ID, if a client with that ID is currently connected.
  ///
  /// [id] : The ID of the client to retrieve.
  ///
  /// Returns true if a client with the given ID was connected; otherwise false
  (bool connected, Connection? client) tryGetClient(int id) {
    Connection? client = _clients[id];

    return (client != null, client);
  }

  /// Disconnects a specific client.
  ///
  /// [id] : The numeric ID of the client to disconnect.
  /// [message] : Data that should be sent to the client being disconnected. Use Message.create() to get an empty message instance.
  void disconnectClient(int id, [Message? message]) {
    if (message != null && message.readBits != 0) {
      RiptideLogger.logWithLogName(LogType.error, logName, "Use the parameterless 'Message.create()' function when setting disconnection data!");
    }

    if (_clients.containsKey(id)) {
      Connection client = _clients[id]!;

      _sendDisconnect(client, DisconnectReason.kicked, message);
      _localDisconnect(client, DisconnectReason.kicked);
    } else {
      RiptideLogger.logWithLogName(LogType.warning, logName, "Couldn't disconnect client $id because it wasn't connected!");
    }
  }

  /// Disconnects the given client.
  ///
  /// [client] : The client to disconnect.
  /// [message] : Data that should be sent to the client being disconnected. Use Message.create() to get an empty message instance.
  void disconnectClientWithConnection(Connection client, [Message? message]) {
    if (message != null && message.readBits != 0) {
      RiptideLogger.logWithLogName(LogType.error, logName, "Use the parameterless 'Message.create()' function when setting disconnection data!");
    }

    if (_clients.containsKey(client.id)) {
      _sendDisconnect(client, DisconnectReason.kicked, message);
      _localDisconnect(client, DisconnectReason.kicked);
    } else {
      RiptideLogger.logWithLogName(LogType.warning, logName, "Couldn't disconnect client ${client.id} because it wasn't connected!");
    }
  }

  @override
  void disconnectConnection(Connection connection, DisconnectReason reason) {
    if (connection.isConnected && connection.canQualityDisconnect) {
      _localDisconnect(connection, reason);
    }
  }

  /// Cleans up the local side of the given connection.
  ///
  /// [client] : The client to disconnect.
  /// [reason] : The reason why the client is being disconnected.
  void _localDisconnect(Connection client, DisconnectReason reason) {
    // NOTE: The original C# implementation uses a simple check (client.peer != this).
    // But for some reason, does the dynamic binding for the dart port work not as expected.
    // The containsValue check should definetely work aswell, but is also more expensive.
    if (!_clients.containsValue(client)) {
      RiptideLogger.logWithLogName(LogType.warning, logName, "Attempted to disconnect client from server $this, but client belongs to server ${client.peer}");
      return; // Client does not belong to this Server instance
    }

    _transport.close(client);

    if (_clients.containsKey(client.id)) {
      _clients.remove(client.id);
      _availableClientIds.add(client.id);
    }

    if (client.isConnected) {
      onClientDisconnected(client, reason); // Only run if the client was ever actually connected
    } else if (client.isPending) {
      onConnectionFailed(client);
    }

    client.localDisconnect();
  }

  /// What to do when the transport disconnects a client.
  void _transportDisconnected(event_args.DisconnectedEventArgs e) {
    _localDisconnect(e.connection, e.reason);
  }

  /// Stops the server.
  void stop() {
    if (!_isRunning) {
      return;
    }

    _pendingConnections.clear();
    Uint8List disconnectBytes = Uint8List.fromList([MessageHeader.disconnect.index, DisconnectReason.serverStopped.index]);
    for (Connection client in _clients.values) {
      client.send(disconnectBytes, disconnectBytes.length);
    }
    _clients.clear();

    _transport.shutdown();
    _unsubFromTransportEvents();

    decreaseActiveCount();

    stopTime();
    _isRunning = false;
    RiptideLogger.logWithLogName(LogType.info, logName, "Server stopped.");
  }

  /// Initializes available client IDs.
  void _initializeClientIds() {
    if (maxClientCount > Constants.ushortMaxVal - 1) {
      throw Exception("A server's max client count may not exceed ${Constants.ushortMaxVal - 1}!");
    }

    _availableClientIds = ListQueue<int>(maxClientCount);
    for (int i = 1; i <= _maxClientCount; i++) {
      _availableClientIds.add(i);
    }
  }

  /// Retrieves an available client ID.
  ///
  /// Returns the client ID. 0 if none were available.
  int _getAvailableClientId() {
    if (_availableClientIds.isNotEmpty) {
      return _availableClientIds.removeFirst();
    }

    RiptideLogger.logWithLogName(LogType.error, logName, "No available client IDs, assigned 0!");
    return 0;
  }

  // #region Messages

  /// Sends a disconnect message.
  ///
  /// [client] : The client to send the disconnect message to.
  /// [reason] : Why the client is being disconnected.
  /// [disconnectMessage] : Optional custom data that should be sent to the client being disconnected.
  void _sendDisconnect(Connection client, DisconnectReason reason, Message? disconnectMessage) {
    Message message = Message.createFromHeader(MessageHeader.disconnect);
    message.addByte(reason.index);

    if (reason == DisconnectReason.kicked && disconnectMessage != null) {
      message.addMessage(disconnectMessage);
    }

    sendWithConnection(message, client);
  }

  /// Sends a client connected message.
  ///
  /// [newClient] : The newly connected client.
  void _sendClientConnected(Connection newClient) {
    Message message = Message.createFromHeader(MessageHeader.clientConnected);
    message.addUShort(newClient.id);

    sendToAllExcept(message, newClient.id);
  }

  /// Sends a client disconnected message.
  ///
  /// [id] : The numeric ID of the client that disconnected.
  void _sendClientDisconnected(int id) {
    Message message = Message.createFromHeader(MessageHeader.clientDisconnected);
    message.addUShort(id);

    sendToAll(message);
  }

  /// Invokes the ClientConnected event.
  ///
  /// [client] : The newly connected client.
  void onClientConnected(Connection client) {
    RiptideLogger.logWithLogName(LogType.info, logName, "Client ${client.id} ($client) connected successfully!");
    _sendClientConnected(client);
    clientConnected.invoke(ServerConnectedEventArgs(client));
  }

  /// Invokes the [connectionFailed] event.
  ///
  /// [connection] : The connection that failed to be fully established.
  void onConnectionFailed(Connection connection) {
    RiptideLogger.logWithLogName(LogType.info, logName, "Client $connection stopped responding before the connection was fully established!");
    connectionFailed.invoke(ServerConnectionFailedEventArgs(connection));
  }

  /// Invokes the MessageReceived event and initiates handling of the received message.
  ///
  /// [message] : The received message.
  /// [fromConnection] : The client from which the message was received.
  void onMessageReceived(Message message, Connection fromConnection) {
    int messageId = message.getVarULong();
    if (relayFilter != null && relayFilter!.shouldRelay(messageId)) {
      // The message should be automatically relayed to clients instead of being handled on the server
      sendToAllExcept(message, fromConnection.id);
      return;
    }

    messageReceived.invoke(MessageReceivedEventArgs(fromConnection, messageId, message));

    if (useMessageHandlers) {
      if (_messageHandlers.containsKey(messageId)) {
        _messageHandlers[messageId]!(fromConnection.id, message);
      } else {
        RiptideLogger.logWithLogName(LogType.warning, logName, "No message handler method found for message ID $messageId!");
      }
    }
  }

  /// Invokes the ClientDisconnected event.
  ///
  /// [connection] : The client that disconnected.
  /// [reason] : The reason for the disconnection.
  void onClientDisconnected(Connection connection, DisconnectReason reason) {
    RiptideLogger.logWithLogName(LogType.info, logName, "Client ${connection.id} ($connection) disconnected: ${Helper.getDisconnectReasonString(reason)}.");
    _sendClientDisconnected(connection.id);
    clientDisconnected.invoke(ServerDisconnectedEventArgs(connection, reason));
  }
}
