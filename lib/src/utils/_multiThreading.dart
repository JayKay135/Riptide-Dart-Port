import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../_eventArgs.dart';
import '../_message.dart';
import '../_server.dart';
import '../_client.dart';
import '../_server.dart' as server_ref;
import '../_client.dart' as client_ref;
import '_riptideLogger.dart';

class MultiThreadedServer {
  late SendPort _sendPort;

  /// Methods used to handle messages, accessible by their corresponding message IDs.
  Map<int, server_ref.MessageHandler> _messageHandlers = {};

  final String _logName = "MULTI_THREADED_SERVER";

  /// Starts the multi threaded server.
  ///
  /// [port] : The local port on which to start the server.
  /// [maxClientCount] : The maximum number of concurrent connections to allow.
  /// [loggingEnabled] : If true the Riptider logger is initialized on the isolate.
  Future<void> start(int port, int maxClientCount, {bool loggingEnabled = false}) async {
    _sendPort = await _multiThreadedServer(port, maxClientCount, loggingEnabled);
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
  void registerMessageHandler(int messageID, Function(int, Message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  /// Internal function to start the riptide server isolate in a different thread.
  Future<SendPort> _multiThreadedServer(int port, int maxClientCount, bool loggingEnabled) async {
    Completer<SendPort> completer = Completer<SendPort>();
    ReceivePort receivePort = ReceivePort();

    Isolate.spawn((Map<String, dynamic> map) {
      ReceivePort receiver = ReceivePort();

      final SendPort sendPort = map['sendPort'];
      sendPort.send(receiver.sendPort);

      if (map['loggingEnabled']) {
        RiptideLogger.initialize2(print, print, print, print, true);
      }

      // actual riptide code
      Server server = Server();
      server.start(map['port'], map['maxClientCount'], useMessageHandlers: false);

      // received command or message data
      receiver.listen((data) {
        // NOTE: Isolates only allow for a few data types to be passed through ports.
        // The nicest way is to use maps to send multiple objects at once.
        // Downside is that the whole api infrastructure from the Server class has to be encoded and decoded through maps.
        Map<String, dynamic> map = data;

        bool? stop = map['stop'];
        int? id = map['id'];
        Message? message = map['message'];

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

      server.messageReceived.subscribe((MessageReceivedEventArgs? args) {
        sendPort.send({'messageId': args!.messageID, 'connectionId': args.fromConnection.id, 'message': args.message});
      });

      Timer.periodic(const Duration(milliseconds: 20), (timer) {
        server.update();
      });
    }, {
      'sendPort': receivePort.sendPort,
      'port': port,
      'maxClientCount': maxClientCount,
      'loggingEnabled': loggingEnabled,
    });

    // send received socket data
    receivePort.listen((data) {
      if (data is SendPort) {
        completer.complete(data);
      } else {
        // received message data
        int messageId = data['messageId'];
        int connectionId = data['connectionId'];
        Message message = data['message'];

        if (_messageHandlers.containsKey(messageId)) {
          _messageHandlers[messageId]!(connectionId, message);
        } else {
          RiptideLogger.log2(LogType.warning, _logName, "No message handler method found for message ID $messageId!");
        }
      }
    });

    return completer.future;
  }
}

class MultiThreadedClient {
  late SendPort _sendPort;

  /// Methods used to handle messages, accessible by their corresponding message IDs.
  Map<int, client_ref.MessageHandler> _messageHandlers = {};

  final String _logName = "MULTI_THREADED_CLIENT";

  /// Attempts to connect to a server at the given host address.
  ///
  /// [hostAddress] : The host address to connect to.
  /// [port] : The host port to connect to.
  /// [maxConnectionAttempts] : How many connection attempts to make before giving up.
  /// [loggingEnabled] : If true the Riptider logger is initialized on the isolate.
  ///
  /// Returns true if a connection attempt will be made. False if an issue occurred and a connection attempt will not be made.
  Future<void> connect(InternetAddress hostAddress, int port, {int maxConnectionAttempts = 5, loggingEnabled = false}) async {
    _sendPort = await _multiThreadedClient(hostAddress, port, maxConnectionAttempts, loggingEnabled);
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
  void registerMessageHandler(int messageID, Function(Message) callback) {
    _messageHandlers[messageID] = callback;
  }

  /// Removes the callback handler for a certain [messageID].
  void removeMessageHandler(int messageID) {
    _messageHandlers.remove(messageID);
  }

  /// Internal function to start the riptide client isolate in a different thread.
  Future<SendPort> _multiThreadedClient(InternetAddress hostAddress, int port, int maxConnectionAttempts, bool loggingEnabled) async {
    Completer<SendPort> completer = Completer<SendPort>();
    ReceivePort receivePort = ReceivePort();

    Isolate.spawn((Map<String, dynamic> map) {
      ReceivePort receiver = ReceivePort();

      final SendPort sendPort = map['sendPort'];
      sendPort.send(receiver.sendPort);

      if (map['loggingEnabled']) {
        RiptideLogger.initialize2(print, print, print, print, true);
      }

      // actual riptide code
      Client client = Client();
      client.connect(map['hostAddress'], map['port'], maxConnectionAttempts: map['maxConnectionAttempts'], useMessageHandlers: false);

      // received command or message data
      receiver.listen((data) {
        // NOTE: Isolates only allow for a few data types to be passed through ports.
        // The nicest way is to use maps to send multiple objects at once.
        // Downside is that the whole api infrastructure from the Server class has to be encoded and decoded through maps.
        Map<String, dynamic> map = data;

        bool? disconnect = map['disconnect'];
        Message? message = map['message'];

        // execute different server function based on given map content

        if (disconnect != null && disconnect) {
          client.disconnect();

          return Isolate.current.kill();
        }

        client.send(message!);
      });

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
      'loggingEnabled': loggingEnabled
    });

    // send received socket data
    receivePort.listen((data) {
      if (data is SendPort) {
        completer.complete(data);
      } else {
        // received message data
        int messageId = data['messageId'];
        Message message = data['message'];

        if (_messageHandlers.containsKey(messageId)) {
          _messageHandlers[messageId]!(message);
        } else {
          RiptideLogger.log2(LogType.warning, _logName, "No message handler method found for message ID $messageId!");
        }
      }
    });

    return completer.future;
  }
}
