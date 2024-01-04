import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../riptide.dart';
import 'event_handler.dart';
import 'riptide_logger.dart';
import '../server.dart';
import '../client.dart';
import '../server.dart' as server_ref;
import '../client.dart' as client_ref;

enum MultiThreadedTransportType { tcp, udp }

/// Intended multi threaded copy of the Server class
class MultiThreadedServer {
  late SendPort _sendPort;

  /// Methods used to handle messages, accessible by their corresponding message IDs.
  final Map<int, server_ref.MessageHandler> _messageHandlers = {};

  /// Invoked when a client connects.
  Event<MultiThreadedServerConnectedEventArgs> clientConnected =
      Event<MultiThreadedServerConnectedEventArgs>();

  /// Invoked when a client disconnects.
  Event<MultiThreadedServerDisconnectedEventArgs> clientDisconnected =
      Event<MultiThreadedServerDisconnectedEventArgs>();

  /// The underlying transport's server that is used for sending and receiving data.
  late MultiThreadedTransportType _transportType;

  /// The name to use when logging messages via RiptideLogger.
  late String logName;

  /// Handles initial setup.
  ///
  /// [transportType] : The [MultiThreadedTransportType] to use for sending and receiving data.
  /// [logName] : The name to use when logging messages via RiptideLogger.
  MultiThreadedServer(
      {MultiThreadedTransportType? transportType,
      this.logName = "MULTI_THREADED_SERVER"}) {
    // NOTE: The transportType enum is used by design, as later on it has to be parsed to a string and passed to the isolate.
    // Using the IServer class wouldn't allow for easy String parsing.
    _transportType = transportType ?? MultiThreadedTransportType.udp;
  }

  /// Starts the multi threaded server.
  ///
  /// [port] : The local port on which to start the server.
  /// [maxClientCount] : The maximum number of concurrent connections to allow.
  /// [loggingEnabled] : If true the Riptider logger is initialized on the isolate.
  Future<void> start(int port, int maxClientCount,
      {bool loggingEnabled = false}) async {
    _sendPort = await _multiThreadedServer(
        _transportType, port, maxClientCount, loggingEnabled);
  }

  /// Stops the multi threaded server.
  void stop() {
    _sendPort.send({'stop': true});
  }

  /// Sends a message to a given client.
  ///
  /// [message] : The message to send.
  /// [toClient] : The numeric ID of the client to send the message to.
  void send(Message message, int toClient) {
    _sendPort.send({'id': toClient, 'message': message});
  }

  /// Sends a message to all connected clients.
  ///
  /// [message] : The message to send.
  void sendToAll(Message message) {
    _sendPort.send({'message': message});
  }

  /// Registers a callback handler for a specifc [messageID] when messages with this particular id are received.
  void registerMessageHandler(
      int messageID, Function(int messageID, Message message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  /// Internal function to start the riptide server isolate in a different thread.
  Future<SendPort> _multiThreadedServer(
      MultiThreadedTransportType transportType,
      int port,
      int maxClientCount,
      bool loggingEnabled) async {
    Completer<SendPort> completer = Completer<SendPort>();
    ReceivePort receivePort = ReceivePort();

    Isolate.spawn((Map<String, dynamic> map) {
      ReceivePort receiver = ReceivePort();

      final SendPort sendPort = map['sendPort'] as SendPort;
      sendPort.send(receiver.sendPort);

      if (map['loggingEnabled'] as bool) {
        RiptideLogger.initializeExtended(
          (debugMessage) => sendPort.send({'debug': debugMessage}),
          (infoMessage) => sendPort.send({'info': infoMessage}),
          (warningMessage) => sendPort.send({'warning': warningMessage}),
          (errorMessage) => sendPort.send({'error': errorMessage}),
          true,
        );
      }

      MultiThreadedTransportType transportType =
          MultiThreadedTransportType.values[map['transportType'] as int];

      // actual riptide code
      IServer transport = transportType == MultiThreadedTransportType.udp
          ? UdpServer()
          : TcpServer();
      Server server = Server(transport: transport);
      server.start(map['port'] as int, map['maxClientCount'] as int,
          useMessageHandlers: false);

      // received command or message data
      receiver.listen((data) {
        // NOTE: Isolates only allow for a few data types to be passed through ports.
        // The nicest way is to use maps to send multiple objects at once.
        // Downside is that the whole api infrastructure from the Server class has to be encoded and decoded through maps.
        Map<String, dynamic> map = data as Map<String, dynamic>;

        bool? stop = map['stop'] as bool?;
        int? id = map['id'] as int?;
        Message? message = map['message'] as Message?;

        // execute different server function based on given map content

        if (stop != null && stop) {
          server.stop();

          return Isolate.current.kill();
        }

        if (id != null) {
          server.send(message!, id);
        } else {
          server.sendToAll(message!);
        }
      });

      server.clientConnected.subscribe((ServerConnectedEventArgs? args) {
        sendPort.send({'clientConnected': args!.client.id});
      });

      server.clientDisconnected.subscribe((ServerDisconnectedEventArgs? args) {
        sendPort.send(
            {'clientDisconnected': args!.client.id, 'reason': args.reason});
      });

      // listen for received messages and forward them through the sendPort
      server.messageReceived.subscribe((MessageReceivedEventArgs? args) {
        sendPort.send({
          'messageId': args!.messageID,
          'connectionId': args.fromConnection.id,
          'message': args.message
        });
      });

      Timer.periodic(const Duration(milliseconds: 20), (timer) {
        server.update();
      });
    }, {
      'sendPort': receivePort.sendPort,
      'port': port,
      'maxClientCount': maxClientCount,
      'loggingEnabled': loggingEnabled,
      'transportType': transportType.index,
    });

    // send received socket data
    receivePort.listen((data) {
      if (data is SendPort) {
        completer.complete(data);
      } else {
        Map<String, dynamic> map = data as Map<String, dynamic>;

        // distinguish between certain events from the isolate
        if (map.containsKey('clientConnected')) {
          return clientConnected.invoke(MultiThreadedServerConnectedEventArgs(
              map['clientConnected'] as int));
        }
        if (map.containsKey('clientDisconnected')) {
          return clientDisconnected.invoke(
              MultiThreadedServerDisconnectedEventArgs(
                  map['clientDisconnected'] as int,
                  map['reason'] as DisconnectReason));
        }

        if (map.containsKey('debug')) {
          return RiptideLogger.logWithLogName(
              LogType.debug, logName, map['debug'] as String);
        }
        if (map.containsKey('info')) {
          return RiptideLogger.logWithLogName(
              LogType.info, logName, map['info'] as String);
        }
        if (map.containsKey('warning')) {
          return RiptideLogger.logWithLogName(
              LogType.warning, logName, map['warning'] as String);
        }
        if (map.containsKey('error')) {
          return RiptideLogger.logWithLogName(
              LogType.error, logName, map['error'] as String);
        }

        // received message data
        int messageId = map['messageId'] as int;
        int connectionId = map['connectionId'] as int;
        Message message = map['message'] as Message;

        if (_messageHandlers.containsKey(messageId)) {
          _messageHandlers[messageId]!(connectionId, message);
        } else {
          RiptideLogger.logWithLogName(LogType.warning, logName,
              "No message handler method found for message ID $messageId!");
        }
      }
    });

    return completer.future;
  }
}

/// Intended multi threaded copy of the Client class
class MultiThreadedClient {
  late SendPort _sendPort;

  /// Methods used to handle messages, accessible by their corresponding message IDs.
  final Map<int, client_ref.MessageHandler> _messageHandlers = {};

  /// Invoked when a connection to the server is established.
  // ignore: strict_raw_type
  Event connected = Event();

  /// Invoked when a connection to the server fails to be established.
  // ignore: strict_raw_type
  Event connectionFailed = Event();

  /// Invoked when disconnected from the server.
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  /// Invoked when another non-localclient connects.
  Event<ClientConnectedEventArgs> clientConnected =
      Event<ClientConnectedEventArgs>();

  /// Invoked when another non-local client disconnects.
  Event<ClientDisconnectedEventArgs> clientDisconnected =
      Event<ClientDisconnectedEventArgs>();

  /// The underlying transport's client that is used for sending and receiving data.
  late MultiThreadedTransportType _transportType;

  /// The name to use when logging messages via RiptideLogger.
  late String logName;

  /// Handles initial setup.
  ///
  /// [transportType] : The [MultiThreadedTransportType] to use for sending and receiving data.
  /// [logName] : The name to use when logging messages via RiptideLogger.
  MultiThreadedClient(
      {MultiThreadedTransportType? transportType,
      this.logName = "MULTI_THREADED_CLIENT"}) {
    // NOTE: The transportType enum is used by design, as later on it has to be parsed to a string and passed to the isolate.
    // Using the IClient class wouldn't allow for easy String parsing.
    _transportType = transportType ?? MultiThreadedTransportType.udp;
  }

  /// Attempts to connect to a server at the given host address.
  ///
  /// [hostAddress] : The host address to connect to.
  /// [port] : The host port to connect to.
  /// [maxConnectionAttempts] : How many connection attempts to make before giving up.
  /// [loggingEnabled] : If true the Riptider logger is initialized on the isolate.
  ///
  /// Returns true if a connection attempt will be made. False if an issue occurred and a connection attempt will not be made.
  Future<void> connect(InternetAddress hostAddress, int port,
      {int maxConnectionAttempts = 5, bool loggingEnabled = false}) async {
    _sendPort = await _multiThreadedClient(_transportType, hostAddress, port,
        maxConnectionAttempts, loggingEnabled);
  }

  /// Disconnects from the client from the server and directly closes the isolate.
  void disconnect() {
    _sendPort.send({'disconnect': true});
  }

  /// Sends a message to the server.
  ///
  /// [message] : The message to send.
  void send(Message message) {
    _sendPort.send({'message': message});
  }

  /// Registers a callback handler for a specifc [messageID] when messages with this particular id are received.
  void registerMessageHandler(
      int messageID, Function(Message message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  /// Internal function to start the riptide client isolate in a different thread.
  Future<SendPort> _multiThreadedClient(
      MultiThreadedTransportType transportType,
      InternetAddress hostAddress,
      int port,
      int maxConnectionAttempts,
      bool loggingEnabled) async {
    Completer<SendPort> completer = Completer<SendPort>();
    ReceivePort receivePort = ReceivePort();

    Isolate.spawn((Map<String, dynamic> map) {
      ReceivePort receiver = ReceivePort();

      final SendPort sendPort = map['sendPort'] as SendPort;
      sendPort.send(receiver.sendPort);

      if (map['loggingEnabled'] as bool) {
        RiptideLogger.initializeExtended(
          (debugMessage) => sendPort.send({'debug': debugMessage}),
          (infoMessage) => sendPort.send({'info': infoMessage}),
          (warningMessage) => sendPort.send({'warning': warningMessage}),
          (errorMessage) => sendPort.send({'error': errorMessage}),
          true,
        );
      }

      MultiThreadedTransportType transportType =
          MultiThreadedTransportType.values[map['transportType'] as int];

      // actual riptide code
      IClient transport = transportType == MultiThreadedTransportType.udp
          ? UdpClient()
          : TcpClient();
      Client client = Client(transport: transport);
      client.connect(map['hostAddress'] as InternetAddress, map['port'] as int,
          maxConnectionAttempts: map['maxConnectionAttempts'] as int,
          useMessageHandlers: false);

      // received command or message data
      receiver.listen((data) {
        // NOTE: Isolates only allow for a few data types to be passed through ports.
        // The nicest way is to use maps to send multiple objects at once.
        // Downside is that the whole api infrastructure from the Client class has to be encoded and decoded through maps.
        Map<String, dynamic> map = data as Map<String, dynamic>;

        bool? disconnect = map['disconnect'] as bool?;
        Message? message = map['message'] as Message?;

        // execute different server function based on given map content

        if (disconnect != null && disconnect) {
          client.disconnect();

          return Isolate.current.kill();
        }

        client.send(message!);
      });

      client.connected.subscribe((_) => sendPort.send({'connected': null}));

      client.connectionFailed
          .subscribe((_) => sendPort.send({'connectionFailed': null}));

      client.disconnected.subscribe((DisconnectedEventArgs? args) {
        sendPort.send({'disconnected': args!.message, 'reason': args.reason});
      });

      client.clientConnected.subscribe((ClientConnectedEventArgs? args) {
        sendPort.send({'clientConnected': args!.id});
      });

      client.clientDisconnected.subscribe((ClientDisconnectedEventArgs? args) {
        sendPort.send({'clientDisconnected': args!.id});
      });

      // listen for received messages and forward them through the sendPort
      client.messageReceived.subscribe((MessageReceivedEventArgs? args) {
        sendPort.send({'messageId': args!.messageID, 'message': args.message});
      });

      Timer.periodic(const Duration(milliseconds: 20), (timer) {
        client.update();
      });
    }, {
      'sendPort': receivePort.sendPort,
      'hostAddress': hostAddress,
      'port': port,
      'maxConnectionAttempts': maxConnectionAttempts,
      'loggingEnabled': loggingEnabled,
      'transportType': transportType.index,
    });

    // send received socket data
    receivePort.listen((data) {
      if (data is SendPort) {
        completer.complete(data);
      } else {
        Map<String, dynamic> map = data as Map<String, dynamic>;

        // distinguish between certain events from the isolate
        if (map.containsKey('connected')) {
          return connected.invoke(null);
        }
        if (map.containsKey('connectionFailed')) {
          return connectionFailed.invoke(null);
        }
        if (map.containsKey('disconnected')) {
          return disconnected.invoke(DisconnectedEventArgs(
              map['reason'] as DisconnectReason,
              map['disconnected'] as Message?));
        }
        if (map.containsKey('clientConnected')) {
          return clientConnected
              .invoke(ClientConnectedEventArgs(map['clientConnected'] as int));
        }
        if (map.containsKey('clientDisconnected')) {
          return clientDisconnected.invoke(
              ClientDisconnectedEventArgs(map['clientDisconnected'] as int));
        }

        if (map.containsKey('debug')) {
          return RiptideLogger.logWithLogName(
              LogType.debug, logName, map['debug'] as String);
        }
        if (map.containsKey('info')) {
          return RiptideLogger.logWithLogName(
              LogType.info, logName, map['info'] as String);
        }
        if (map.containsKey('warning')) {
          return RiptideLogger.logWithLogName(
              LogType.warning, logName, map['warning'] as String);
        }
        if (map.containsKey('error')) {
          return RiptideLogger.logWithLogName(
              LogType.error, logName, map['error'] as String);
        }

        // received message data
        int messageId = map['messageId'] as int;
        Message message = map['message'] as Message;

        if (_messageHandlers.containsKey(messageId)) {
          _messageHandlers[messageId]!(message);
        } else {
          RiptideLogger.logWithLogName(LogType.warning, logName,
              "No message handler method found for message ID $messageId!");
        }
      }
    });

    return completer.future;
  }
}
