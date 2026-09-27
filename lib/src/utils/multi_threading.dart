import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../client.dart' as client_ref;
import '../client.dart';
import '../connection.dart';
import '../event_args.dart';
import '../message.dart';
import '../message_relay_filter.dart';
import '../peer.dart';
import '../server.dart' as server_ref;
import '../server.dart';
import '../transports/iclient.dart';
import '../transports/iserver.dart';
import '../transports/tcp/tcp_client.dart';
import '../transports/tcp/tcp_server.dart';
import '../transports/udp/udp_client.dart';
import '../transports/udp/udp_server.dart';
import 'event_handler.dart';
import 'riptide_logger.dart';

// NOTE: This file has no C# counterpart. It runs a Server or Client in a separate isolate, so that sending and receiving
// data (including heartbeats, acks and resends) keeps working while the main isolate is busy, e.g. with rendering.
// Messages, events and commands are passed between the isolates (which copies them).

/// The transport type for multi threaded server and clients
enum MultiThreadedTransportType { tcp, udp }

/// Encapsulates a method that determines whether or not to accept a client's connection attempt on a
/// [MultiThreadedServer].
///
/// [attemptId] : Identifies the connection attempt. Pass it to [MultiThreadedServer.accept] or
/// [MultiThreadedServer.reject].
/// [endPoint] : The address and port the connection attempt came from.
/// [connectMessage] : A message containing any additional data the client included with the connection attempt.
typedef MultiThreadedConnectionAttemptHandler = void Function(int attemptId, String endPoint, Message connectMessage);

/// A server which runs in a separate isolate.
///
/// Received messages are handled and events are invoked on the isolate which created the server.
class MultiThreadedServer {
  /// Invoked when a client connects.
  Event<MultiThreadedServerConnectedEventArgs> clientConnected = Event<MultiThreadedServerConnectedEventArgs>();

  /// Invoked when a connection fails to be fully established.
  Event<MultiThreadedServerConnectionFailedEventArgs> connectionFailed =
      Event<MultiThreadedServerConnectionFailedEventArgs>();

  /// Invoked when a message is received.
  Event<MultiThreadedMessageReceivedEventArgs> messageReceived = Event<MultiThreadedMessageReceivedEventArgs>();

  /// Invoked when a client disconnects.
  Event<MultiThreadedServerDisconnectedEventArgs> clientDisconnected =
      Event<MultiThreadedServerDisconnectedEventArgs>();

  /// Invoked when a notify message is received.
  Event<MultiThreadedNotifyReceivedEventArgs> notifyReceived = Event<MultiThreadedNotifyReceivedEventArgs>();

  /// Invoked when a notify message is successfully delivered.
  Event<MultiThreadedNotifyEventArgs> notifyDelivered = Event<MultiThreadedNotifyEventArgs>();

  /// Invoked when a notify message is lost.
  Event<MultiThreadedNotifyEventArgs> notifyLost = Event<MultiThreadedNotifyEventArgs>();

  /// An optional method which determines whether or not to accept a client's connection attempt.
  ///
  /// If you set this, you should use it to call either [accept] or [reject]. Not doing so will result in the connection
  /// hanging until the client times out. Changes only take effect when the server is (re)started.
  MultiThreadedConnectionAttemptHandler? handleConnection;

  /// The name to use when logging messages via RiptideLogger.
  late String logName;

  /// The transport to use for sending and receiving data.
  late MultiThreadedTransportType _transportType;

  /// Methods used to handle messages, accessible by their corresponding message IDs.
  final Map<int, server_ref.MessageHandler> _messageHandlers = {};

  /// The isolate the server runs in.
  late final _NetworkIsolate _isolate = _NetworkIsolate(logName);

  /// The IDs of the currently connected clients.
  final Set<int> _clientIds = {};

  /// The local port that the server is running on.
  int? _port;
  int? get port => _port;

  /// Whether or not the server is currently running.
  bool get isRunning => _isolate.isRunning;

  /// The number of currently connected clients.
  int get clientCount => _clientIds.length;

  /// The IDs of the currently connected clients.
  List<int> get clientIds => _clientIds.toList();

  /// Handles initial setup.
  ///
  /// [transportType] : The [MultiThreadedTransportType] to use for sending and receiving data.
  /// [logName] : The name to use when logging messages via RiptideLogger.
  MultiThreadedServer({MultiThreadedTransportType? transportType, this.logName = "MULTI_THREADED_SERVER"}) {
    // NOTE: The transportType enum is used by design, as transports can't be passed to other isolates
    _transportType = transportType ?? MultiThreadedTransportType.udp;
  }

  /// Starts the multi threaded server, stopping it first if it's already running.
  ///
  /// [port] : The local port on which to start the server.
  /// [maxClientCount] : The maximum number of concurrent connections to allow.
  /// [loggingEnabled] : Whether or not the server's logs should be passed on to the RiptideLogger of this isolate.
  /// [updateInterval] : How often (in milliseconds) the server is updated.
  /// [heartbeatInterval] : The interval (in milliseconds) at which to send and expect heartbeats to be received.
  /// [timeoutTime] : The time (in milliseconds) after which to disconnect clients if no heartbeats are received.
  /// [relayFilter] : Stores which message IDs are relayed to all other clients instead of being handled by the server.
  ///
  /// Completes once the server is running, or with an error if it couldn't be started.
  Future<void> start(int port, int maxClientCount,
      {bool loggingEnabled = false,
      int updateInterval = 20,
      int heartbeatInterval = 1000,
      int timeoutTime = 5000,
      MessageRelayFilter? relayFilter}) async {
    await stop();

    await _isolate.spawn(
        _run,
        (SendPort events) => _ServerSettings(
            events,
            _transportType,
            port,
            maxClientCount,
            logName,
            _LogSettings.current(loggingEnabled),
            updateInterval,
            heartbeatInterval,
            timeoutTime,
            relayFilter,
            handleConnection != null),
        _handleEvent,
        () => _clientIds.clear());
    _port = port;
  }

  /// Stops the multi threaded server.
  ///
  /// Completes once the server's isolate has exited.
  Future<void> stop() async {
    if (_isolate.isRunning) {
      _isolate.send(const _Stop());
    }

    await _isolate.exited;
  }

  /// Sends a message to a given client.
  ///
  /// [message] : The message to send.
  /// [toClient] : The numeric ID of the client to send the message to.
  ///
  /// The message is returned to the pool after it is sent.
  void send(Message message, int toClient) {
    _isolate.send(_Send(message, toClient: toClient));
    message.release(); // The message was copied to the isolate
  }

  /// Sends a message to all connected clients.
  ///
  /// [message] : The message to send.
  ///
  /// The message is returned to the pool after it is sent.
  void sendToAll(Message message) {
    _isolate.send(_Send(message));
    message.release(); // The message was copied to the isolate
  }

  /// Sends a message to all connected clients except the given one.
  ///
  /// [message] : The message to send.
  /// [exceptToClientId] : The numeric ID of the client to not send the message to.
  ///
  /// The message is returned to the pool after it is sent.
  void sendToAllExcept(Message message, int exceptToClientId) {
    _isolate.send(_Send(message, exceptToClient: exceptToClientId));
    message.release(); // The message was copied to the isolate
  }

  /// Disconnects a specific client.
  ///
  /// [id] : The numeric ID of the client to disconnect.
  /// [message] : Data that should be sent to the client being disconnected. Use Message.create() to get an empty message
  /// instance. It is copied rather than sent directly, so it is not returned to the pool and can be reused.
  void disconnectClient(int id, [Message? message]) {
    _isolate.send(_DisconnectClient(id, message));
  }

  /// Accepts the given pending connection attempt.
  ///
  /// [attemptId] : The ID of the connection attempt which was passed to [handleConnection].
  void accept(int attemptId) {
    _isolate.send(_Accept(attemptId));
  }

  /// Rejects the given pending connection attempt.
  ///
  /// [attemptId] : The ID of the connection attempt which was passed to [handleConnection].
  /// [message] : Data that should be sent to the client being rejected. Use Message.create() to get an empty message
  /// instance. It is copied rather than sent directly, so it is not returned to the pool and can be reused.
  void reject(int attemptId, {Message? message}) {
    _isolate.send(_Reject(attemptId, message));
  }

  /// Registers a callback handler for a specifc [messageID] when messages with this particular id are received.
  void registerMessageHandler(int messageID, Function(int fromClientID, Message message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  /// Handles an event of the server's isolate.
  ///
  /// [event] : The event.
  void _handleEvent(Object event) {
    switch (event) {
      case _ClientConnected(:int id, :String endPoint):
        _clientIds.add(id);
        _invoke(
            logName, clientConnected, MultiThreadedServerConnectedEventArgs(id, endPoint: endPoint), 'clientConnected');
      case _ClientDisconnected(:int id, :DisconnectReason reason):
        _clientIds.remove(id);
        _invoke(
            logName, clientDisconnected, MultiThreadedServerDisconnectedEventArgs(id, reason), 'clientDisconnected');
      case _ConnectionAttempt(:int attemptId, :String endPoint, :Message message):
        _call(logName, 'handleConnection', () => handleConnection?.call(attemptId, endPoint, message));
      case _ConnectionFailed(:int? attemptId, :String endPoint):
        _invoke(logName, connectionFailed, MultiThreadedServerConnectionFailedEventArgs(attemptId, endPoint),
            'connectionFailed');
      case _MessageReceived(:int fromClientId, :int messageId, :Message message):
        _invoke(logName, messageReceived, MultiThreadedMessageReceivedEventArgs(fromClientId, messageId, message),
            'messageReceived');
        server_ref.MessageHandler? handler = _messageHandlers[messageId];
        if (handler != null) {
          _call(logName, 'message handler', () => handler(fromClientId, message));
        } else if (messageReceived.eventHandlers.isEmpty) {
          RiptideLogger.logWithLogName(
              LogType.warning, logName, "No message handler method found for message ID $messageId!");
        }
      case _NotifyReceived(:int clientId, :Message message):
        _invoke(logName, notifyReceived, MultiThreadedNotifyReceivedEventArgs(clientId, message), 'notifyReceived');
      case _NotifyStatus(:int clientId, :int sequenceId, :bool wasDelivered):
        _invoke(logName, wasDelivered ? notifyDelivered : notifyLost,
            MultiThreadedNotifyEventArgs(clientId, sequenceId), wasDelivered ? 'notifyDelivered' : 'notifyLost');
    }
  }

  /// The entry point of the server's isolate.
  ///
  /// NOTE: This is a static method so that it doesn't capture anything from the spawning isolate (like this instance's
  /// event subscribers), which would otherwise be copied into the new isolate.
  static Future<void> _run(_ServerSettings settings) async {
    SendPort events = settings.events;
    settings.log.apply(events);

    IServer transport = settings.transportType == MultiThreadedTransportType.udp ? UdpServer() : TcpServer();
    Server server = Server(transport: transport, logName: settings.logName);
    server.heartbeatInterval = settings.heartbeatInterval;
    server.timeoutTime = settings.timeoutTime;
    server.relayFilter = settings.relayFilter;

    // Connection attempts which were passed on to the other isolate, by their IDs
    Map<int, Connection> pendingAttempts = {};
    int nextAttemptId = 1;
    int? forgetAttempt(Connection connection) {
      for (MapEntry<int, Connection> attempt in pendingAttempts.entries) {
        if (identical(attempt.value, connection)) {
          pendingAttempts.remove(attempt.key);
          return attempt.key;
        }
      }
      return null;
    }

    if (settings.handlesConnections) {
      server.handleConnection = (Connection connection, Message connectMessage) {
        int attemptId = nextAttemptId++;
        pendingAttempts[attemptId] = connection;
        events.send(_ConnectionAttempt(attemptId, connection.toString(), connectMessage));
      };
    }

    server.clientConnected.subscribe((ServerConnectedEventArgs? args) {
      Connection client = args!.client;
      forgetAttempt(client);
      client.notifyReceived.subscribe((Message? message) => events.send(_NotifyReceived(client.id, message!)));
      client.notifyDelivered.subscribe((int? sequenceId) => events.send(_NotifyStatus(client.id, sequenceId!, true)));
      client.notifyLost.subscribe((int? sequenceId) => events.send(_NotifyStatus(client.id, sequenceId!, false)));
      events.send(_ClientConnected(client.id, client.toString()));
    });
    server.connectionFailed.subscribe((ServerConnectionFailedEventArgs? args) {
      events.send(_ConnectionFailed(forgetAttempt(args!.client), args.client.toString()));
    });
    server.clientDisconnected.subscribe((ServerDisconnectedEventArgs? args) {
      events.send(_ClientDisconnected(args!.client.id, args.reason));
    });
    server.messageReceived.subscribe((MessageReceivedEventArgs? args) {
      events.send(_MessageReceived(args!.fromConnection.id, args.messageID, args.message));
    });

    // Errors (like the port being in use) are reported to the other isolate by the isolate's error listener
    await server.start(settings.port, settings.maxClientCount, useMessageHandlers: false);
    Timer timer = Timer.periodic(Duration(milliseconds: settings.updateInterval), (Timer _) => server.update());

    ReceivePort commands = ReceivePort();
    commands.listen((Object? command) {
      switch (command) {
        case _Send(:Message message, :int? toClient, :int? exceptToClient):
          if (toClient != null) {
            server.send(message, toClient);
          } else if (exceptToClient != null) {
            server.sendToAllExcept(message, exceptToClient);
          } else {
            server.sendToAll(message);
          }
        case _DisconnectClient(:int id, :Message? message):
          server.disconnectClient(id, message);
        case _Accept(:int attemptId):
          Connection? connection = pendingAttempts.remove(attemptId);
          if (connection != null) {
            server.accept(connection);
          }
        case _Reject(:int attemptId, :Message? message):
          Connection? connection = pendingAttempts.remove(attemptId);
          if (connection != null) {
            server.reject(connection, message: message);
          }
        case _Stop():
          server.stop();
          // The isolate exits once everything (like data which is still being sent) is done
          timer.cancel();
          commands.close();
      }
    });

    events.send(_Ready(commands.sendPort, true));
  }
}

/// A client which runs in a separate isolate.
///
/// Received messages are handled and events are invoked on the isolate which created the client.
class MultiThreadedClient {
  /// Invoked when a connection to the server is established.
  // ignore: strict_raw_type
  Event connected = Event();

  /// Invoked when a connection to the server fails to be established.
  Event<ConnectionFailedEventArgs> connectionFailed = Event<ConnectionFailedEventArgs>();

  /// Invoked when a message is received.
  Event<MultiThreadedMessageReceivedEventArgs> messageReceived = Event<MultiThreadedMessageReceivedEventArgs>();

  /// Invoked when disconnected from the server.
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  /// Invoked when another non-local client connects.
  Event<ClientConnectedEventArgs> clientConnected = Event<ClientConnectedEventArgs>();

  /// Invoked when another non-local client disconnects.
  Event<ClientDisconnectedEventArgs> clientDisconnected = Event<ClientDisconnectedEventArgs>();

  /// Invoked when a notify message is received.
  Event<Message> notifyReceived = Event<Message>();

  /// Invoked when the notify message with the given sequence ID is successfully delivered.
  ///
  /// The connection numbers its notify messages consecutively, starting at 1 (and wrapping around after 65535).
  Event<int> notifyDelivered = Event<int>();

  /// Invoked when the notify message with the given sequence ID is lost.
  ///
  /// The connection numbers its notify messages consecutively, starting at 1 (and wrapping around after 65535).
  Event<int> notifyLost = Event<int>();

  /// The name to use when logging messages via RiptideLogger.
  late String logName;

  /// The transport to use for sending and receiving data.
  late MultiThreadedTransportType _transportType;

  /// Methods used to handle messages, accessible by their corresponding message IDs.
  final Map<int, client_ref.MessageHandler> _messageHandlers = {};

  /// The isolate the client runs in.
  late final _NetworkIsolate _isolate = _NetworkIsolate(logName);

  /// The state of the client's connection.
  ConnectionState _state = ConnectionState.notConnected;
  ConnectionState get state => _state;

  /// The client's numeric ID, once it's connected.
  int? _id;
  int? get id => _id;

  /// The round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  int _rtt = -1;
  int get rtt => _rtt;

  /// The smoothed round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  int _smoothRtt = -1;
  int get smoothRtt => _smoothRtt;

  /// Whether or not the client is currently not trying to connect, pending, nor actively connected.
  bool get isNotConnected => _state == ConnectionState.notConnected;

  /// Whether or not the client is currently in the process of connecting.
  bool get isConnecting => _state == ConnectionState.connecting;

  /// Whether or not the client is currently connected.
  bool get isConnected => _state == ConnectionState.connected;

  /// Handles initial setup.
  ///
  /// [transportType] : The [MultiThreadedTransportType] to use for sending and receiving data.
  /// [logName] : The name to use when logging messages via RiptideLogger.
  MultiThreadedClient({MultiThreadedTransportType? transportType, this.logName = "MULTI_THREADED_CLIENT"}) {
    // NOTE: The transportType enum is used by design, as transports can't be passed to other isolates
    _transportType = transportType ?? MultiThreadedTransportType.udp;
  }

  /// Attempts to connect to a server at the given host address, disconnecting first if the client is connected.
  ///
  /// [hostAddress] : The host address to connect to.
  /// [port] : The host port to connect to.
  /// [maxConnectionAttempts] : How many connection attempts to make before giving up.
  /// [message] : Data that should be sent to the server with the connection attempt. Use Message.create() to get an
  /// empty message instance. It is copied rather than sent directly, so it is not returned to the pool and can be reused.
  /// [loggingEnabled] : Whether or not the client's logs should be passed on to the RiptideLogger of this isolate.
  /// [updateInterval] : How often (in milliseconds) the client is updated.
  /// [heartbeatInterval] : The interval (in milliseconds) at which to send and expect heartbeats to be received.
  /// [timeoutTime] : The time (in milliseconds) after which to disconnect if no heartbeats are received.
  ///
  /// Returns true if a connection attempt will be made. False if an issue occurred and a connection attempt will not be
  /// made. The client's isolate stops once the client disconnects or fails to connect.
  Future<bool> connect(InternetAddress hostAddress, int port,
      {int maxConnectionAttempts = 5,
      Message? message,
      bool loggingEnabled = false,
      int updateInterval = 20,
      int heartbeatInterval = 1000,
      int timeoutTime = 5000}) async {
    await disconnect();

    _state = ConnectionState.connecting;
    _id = null;
    _rtt = -1;
    _smoothRtt = -1;

    try {
      _Ready ready = await _isolate.spawn(
          _run,
          (SendPort events) => _ClientSettings(events, _transportType, hostAddress, port, maxConnectionAttempts,
              message, logName, _LogSettings.current(loggingEnabled), updateInterval, heartbeatInterval, timeoutTime),
          _handleEvent,
          () => _state = ConnectionState.notConnected);
      if (!ready.isConnecting) {
        await _isolate.exited; // No connection attempt will be made, so the isolate stops right away
      }

      return ready.isConnecting;
    } catch (_) {
      _state = ConnectionState.notConnected;
      rethrow;
    }
  }

  /// Disconnects from the server.
  ///
  /// Completes once the client's isolate has exited.
  Future<void> disconnect() async {
    if (_isolate.isRunning) {
      _isolate.send(const _Stop());
    }

    await _isolate.exited;
  }

  /// Sends a message to the server.
  ///
  /// [message] : The message to send.
  ///
  /// The message is returned to the pool after it is sent.
  void send(Message message) {
    _isolate.send(_Send(message));
    message.release(); // The message was copied to the isolate
  }

  /// Registers a callback handler for a specifc [messageID] when messages with this particular id are received.
  void registerMessageHandler(int messageID, Function(Message message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  /// Handles an event of the client's isolate.
  ///
  /// [event] : The event.
  void _handleEvent(Object event) {
    switch (event) {
      case _Connected(:int id):
        _id = id;
        _state = ConnectionState.connected;
        _invoke(logName, connected, null, 'connected');
      case _ClientConnectionFailed(:RejectReason reason, :Message? message):
        _state = ConnectionState.notConnected;
        _invoke(logName, connectionFailed, ConnectionFailedEventArgs(reason, message), 'connectionFailed');
      case _Disconnected(:DisconnectReason reason, :Message? message):
        _state = ConnectionState.notConnected;
        _invoke(logName, disconnected, DisconnectedEventArgs(reason, message), 'disconnected');
      case _ClientConnected(:int id):
        _invoke(logName, clientConnected, ClientConnectedEventArgs(id), 'clientConnected');
      case _ClientDisconnected(:int id):
        _invoke(logName, clientDisconnected, ClientDisconnectedEventArgs(id), 'clientDisconnected');
      case _RttChanged(:int rtt, :int smoothRtt):
        _rtt = rtt;
        _smoothRtt = smoothRtt;
      case _MessageReceived(:int messageId, :Message message):
        _invoke(
            logName, messageReceived, MultiThreadedMessageReceivedEventArgs(0, messageId, message), 'messageReceived');
        client_ref.MessageHandler? handler = _messageHandlers[messageId];
        if (handler != null) {
          _call(logName, 'message handler', () => handler(message));
        } else if (messageReceived.eventHandlers.isEmpty) {
          RiptideLogger.logWithLogName(
              LogType.warning, logName, "No message handler method found for message ID $messageId!");
        }
      case _NotifyReceived(:Message message):
        _invoke(logName, notifyReceived, message, 'notifyReceived');
      case _NotifyStatus(:int sequenceId, :bool wasDelivered):
        _invoke(logName, wasDelivered ? notifyDelivered : notifyLost, sequenceId,
            wasDelivered ? 'notifyDelivered' : 'notifyLost');
    }
  }

  /// The entry point of the client's isolate.
  ///
  /// NOTE: This is a static method so that it doesn't capture anything from the spawning isolate (like this instance's
  /// event subscribers), which would otherwise be copied into the new isolate.
  static Future<void> _run(_ClientSettings settings) async {
    SendPort events = settings.events;
    settings.log.apply(events);

    IClient transport = settings.transportType == MultiThreadedTransportType.udp ? UdpClient() : TcpClient();
    Client client = Client(transport: transport, logName: settings.logName);
    client.heartbeatInterval = settings.heartbeatInterval;
    client.timeoutTime = settings.timeoutTime;

    ReceivePort commands = ReceivePort();
    Timer? timer;
    void shutDown() {
      // The isolate exits once everything (like data which is still being sent) is done
      timer?.cancel();
      commands.close();
    }

    client.connected.subscribe((Object? _) {
      Connection connection = client.connection!;
      connection.notifyReceived.subscribe((Message? message) => events.send(_NotifyReceived(0, message!)));
      connection.notifyDelivered.subscribe((int? sequenceId) => events.send(_NotifyStatus(0, sequenceId!, true)));
      connection.notifyLost.subscribe((int? sequenceId) => events.send(_NotifyStatus(0, sequenceId!, false)));
      events.send(_Connected(client.id));
    });
    client.connectionFailed.subscribe((ConnectionFailedEventArgs? args) {
      events.send(_ClientConnectionFailed(args!.reason, args.message));
      shutDown();
    });
    client.disconnected.subscribe((DisconnectedEventArgs? args) {
      events.send(_Disconnected(args!.reason, args.message));
      shutDown();
    });
    client.clientConnected.subscribe((ClientConnectedEventArgs? args) => events.send(_ClientConnected(args!.id, "")));
    client.clientDisconnected.subscribe((ClientDisconnectedEventArgs? args) =>
        events.send(_ClientDisconnected(args!.id, DisconnectReason.disconnected)));
    client.messageReceived.subscribe((MessageReceivedEventArgs? args) {
      events.send(_MessageReceived(0, args!.messageID, args.message));
    });

    commands.listen((Object? command) {
      switch (command) {
        case _Send(:Message message):
          if (client.isConnected || client.isConnecting || client.isPending) {
            client.send(message);
          }
        case _Stop():
          client.disconnect();
          shutDown();
      }
    });

    int rtt = -1;
    int smoothRtt = -1;
    timer = Timer.periodic(Duration(milliseconds: settings.updateInterval), (Timer _) {
      client.update();

      Connection? connection = client.connection;
      if (connection != null && (connection.rtt != rtt || connection.smoothRtt != smoothRtt)) {
        rtt = connection.rtt;
        smoothRtt = connection.smoothRtt;
        events.send(_RttChanged(rtt, smoothRtt));
      }
    });

    bool isConnecting = await client.connect(settings.hostAddress, settings.port,
        maxConnectionAttempts: settings.maxConnectionAttempts,
        message: settings.connectMessage,
        useMessageHandlers: false);
    events.send(_Ready(commands.sendPort, isConnecting));
    if (!isConnecting) {
      shutDown();
    }
  }
}

/// Invokes the given event, logging exceptions thrown by its subscribers like the Server and Client do.
void _invoke<T>(String logName, Event<T> event, T? args, String eventName) {
  try {
    event.invoke(args);
  } catch (e, stackTrace) {
    RiptideLogger.logEventException(logName, eventName, e, stackTrace);
  }
}

/// Calls the given user code, logging exceptions it throws, as they would otherwise be unhandled.
void _call(String logName, String name, void Function() callback) {
  try {
    callback();
  } catch (e, stackTrace) {
    RiptideLogger.logException(logName, "An exception was thrown by the $name!", e, stackTrace);
  }
}

/// Runs a Server or Client in a separate isolate and passes on its events.
class _NetworkIsolate {
  /// The name to use when logging messages via RiptideLogger.
  final String _logName;

  /// The port to send commands to the isolate through, while it's running.
  SendPort? _commands;

  /// Completes once the isolate has exited.
  Future<void> _exited = Future<void>.value();
  Future<void> get exited => _exited;

  /// Whether or not the isolate is currently running.
  bool get isRunning => _commands != null;

  _NetworkIsolate(this._logName);

  /// Spawns the isolate and waits until it's ready.
  ///
  /// [entryPoint] : The isolate's entry point.
  /// [createSettings] : Creates the settings to pass to [entryPoint], given the port to send events through.
  /// [onEvent] : Handles an event of the isolate.
  /// [onExit] : Called once the isolate has exited.
  Future<_Ready> spawn<T>(void Function(T settings) entryPoint, T Function(SendPort events) createSettings,
      void Function(Object event) onEvent, void Function() onExit) async {
    // NOTE: Errors and the exit notification are sent through the same port as the events, so that none of the events
    // which were sent before the isolate exited get lost
    ReceivePort events = ReceivePort();
    Completer<_Ready> ready = Completer<_Ready>();
    Completer<void> exited = Completer<void>();
    _exited = exited.future;

    events.listen((Object? event) {
      if (event == null) {
        // The isolate exited
        events.close();
        _commands = null;
        if (!ready.isCompleted) {
          ready.completeError(StateError("The network isolate exited before it was started!"));
        }

        onExit();
        exited.complete();
      } else if (event is List) {
        // The isolate encountered an uncaught error
        RemoteError error = RemoteError(event[0] as String, event[1] as String);
        if (!ready.isCompleted) {
          ready.completeError(error);
        } else {
          RiptideLogger.logException(_logName, "The network isolate encountered an error!", error, error.stackTrace);
        }
      } else if (event is _Ready) {
        _commands = event.commands;
        ready.complete(event);
      } else if (event is _Log) {
        // Logs are already formatted by the network isolate
        RiptideLogger.logMethods[event.type]?.call(event.log);
      } else {
        onEvent(event);
      }
    });

    try {
      await Isolate.spawn(entryPoint, createSettings(events.sendPort),
          onError: events.sendPort, onExit: events.sendPort);
    } catch (_) {
      events.close();
      exited.complete();
      rethrow;
    }

    return ready.future;
  }

  /// Sends a command to the isolate.
  ///
  /// [command] : The command.
  void send(Object command) {
    SendPort? commands = _commands;
    if (commands == null) {
      throw StateError("The network isolate isn't running! Start the server or connect the client first.");
    }

    commands.send(command);
  }
}

/// Settings for logging in a network isolate.
class _LogSettings {
  /// The log types to pass on.
  final Set<LogType> types;

  /// Whether or not to include timestamps.
  final bool includeTimestamps;

  /// The format to use for timestamps.
  final String timestampFormat;

  /// Takes the current settings of the RiptideLogger.
  ///
  /// [isEnabled] : Whether or not logs should be passed on at all.
  _LogSettings.current(bool isEnabled)
      : types = isEnabled ? RiptideLogger.logMethods.keys.toSet() : <LogType>{},
        includeTimestamps = RiptideLogger.includeTimestamps,
        timestampFormat = RiptideLogger.timestampFormat;

  /// Initializes the RiptideLogger of the network isolate to pass logs on through the given port.
  ///
  /// [events] : The port to pass the logs on through.
  void apply(SendPort events) {
    LogMethod<String>? method(LogType type) =>
        types.contains(type) ? (String log) => events.send(_Log(type, log)) : null;
    RiptideLogger.initializeExtended(
        method(LogType.debug), method(LogType.info), method(LogType.warning), method(LogType.error), includeTimestamps,
        timestampFormat: timestampFormat);
  }
}

/// Settings for a server's isolate.
class _ServerSettings {
  final SendPort events;
  final MultiThreadedTransportType transportType;
  final int port;
  final int maxClientCount;
  final String logName;
  final _LogSettings log;
  final int updateInterval;
  final int heartbeatInterval;
  final int timeoutTime;
  final MessageRelayFilter? relayFilter;
  final bool handlesConnections;

  _ServerSettings(this.events, this.transportType, this.port, this.maxClientCount, this.logName, this.log,
      this.updateInterval, this.heartbeatInterval, this.timeoutTime, this.relayFilter, this.handlesConnections);
}

/// Settings for a client's isolate.
class _ClientSettings {
  final SendPort events;
  final MultiThreadedTransportType transportType;
  final InternetAddress hostAddress;
  final int port;
  final int maxConnectionAttempts;
  final Message? connectMessage;
  final String logName;
  final _LogSettings log;
  final int updateInterval;
  final int heartbeatInterval;
  final int timeoutTime;

  _ClientSettings(this.events, this.transportType, this.hostAddress, this.port, this.maxConnectionAttempts,
      this.connectMessage, this.logName, this.log, this.updateInterval, this.heartbeatInterval, this.timeoutTime);
}

// ------------------------------------------------------------------------------------------------ Commands

/// Sends a message. To all clients if neither [toClient] nor [exceptToClient] is set.
class _Send {
  final Message message;
  final int? toClient;
  final int? exceptToClient;

  const _Send(this.message, {this.toClient, this.exceptToClient});
}

/// Disconnects a client from the server.
class _DisconnectClient {
  final int id;
  final Message? message;

  const _DisconnectClient(this.id, this.message);
}

/// Accepts a pending connection attempt.
class _Accept {
  final int attemptId;

  const _Accept(this.attemptId);
}

/// Rejects a pending connection attempt.
class _Reject {
  final int attemptId;
  final Message? message;

  const _Reject(this.attemptId, this.message);
}

/// Stops the server or disconnects the client.
class _Stop {
  const _Stop();
}

// ------------------------------------------------------------------------------------------------ Events

/// The network isolate is ready to receive commands.
class _Ready {
  final SendPort commands;

  /// For clients, whether or not a connection attempt will be made.
  final bool isConnecting;

  const _Ready(this.commands, this.isConnecting);
}

/// A log of the network isolate.
class _Log {
  final LogType type;
  final String log;

  const _Log(this.type, this.log);
}

/// A client connected (to the server, or to the server the client is connected to).
class _ClientConnected {
  final int id;
  final String endPoint;

  const _ClientConnected(this.id, this.endPoint);
}

/// A client disconnected (from the server, or from the server the client is connected to).
class _ClientDisconnected {
  final int id;
  final DisconnectReason reason;

  const _ClientDisconnected(this.id, this.reason);
}

/// A client attempts to connect to the server.
class _ConnectionAttempt {
  final int attemptId;
  final String endPoint;
  final Message message;

  const _ConnectionAttempt(this.attemptId, this.endPoint, this.message);
}

/// A connection to the server failed to be fully established.
class _ConnectionFailed {
  final int? attemptId;
  final String endPoint;

  const _ConnectionFailed(this.attemptId, this.endPoint);
}

/// A message was received.
class _MessageReceived {
  final int fromClientId;
  final int messageId;
  final Message message;

  const _MessageReceived(this.fromClientId, this.messageId, this.message);
}

/// A notify message was received.
class _NotifyReceived {
  final int clientId;
  final Message message;

  const _NotifyReceived(this.clientId, this.message);
}

/// A notify message was delivered or lost.
class _NotifyStatus {
  final int clientId;
  final int sequenceId;
  final bool wasDelivered;

  const _NotifyStatus(this.clientId, this.sequenceId, this.wasDelivered);
}

/// The client connected to the server.
class _Connected {
  final int id;

  const _Connected(this.id);
}

/// The client failed to connect to the server.
class _ClientConnectionFailed {
  final RejectReason reason;
  final Message? message;

  const _ClientConnectionFailed(this.reason, this.message);
}

/// The client disconnected from the server.
class _Disconnected {
  final DisconnectReason reason;
  final Message? message;

  const _Disconnected(this.reason, this.message);
}

/// The client's round trip time changed.
class _RttChanged {
  final int rtt;
  final int smoothRtt;

  const _RttChanged(this.rtt, this.smoothRtt);
}
