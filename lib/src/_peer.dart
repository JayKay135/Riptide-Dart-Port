import 'dart:collection';

import 'package:collection/collection.dart';

import '_message.dart';
import 'transports/_connection.dart';
import 'transports/_eventArgs.dart';
import 'transports/_ipeer.dart';
import 'utils/_converter.dart';
import 'utils/_delayedEvents.dart';

/// The reason the connection attempt was rejected.
enum RejectReason {
  /// No response was received from the server (because the client has no internet connection, the server is offline, no server is listening on the target endpoint, etc.).
  noConnection,

  /// The client is already connected.
  alreadyConnected,

  /// The server is full.
  serverFull,

  /// The connection attempt was rejected.
  rejected,

  /// The connection attempt was rejected and custom data may have been included with the rejection message.
  custom
}

/// The reason for a disconnection.
enum DisconnectReason {
  /// No connection was ever established.
  neverConnected,

  /// The connection attempt was rejected by the server.
  connectionRejected,

  /// The active transport detected a problem with the connection.
  transportError,

  /// The connection timed out.
  ///
  /// This also acts as the fallback reason—if a client disconnects and the message containing the real reason is lost
  /// in transmission, it can't be resent as the connection will have already been closed. As a result, the other end will time
  /// out the connection after a short period of time and this will be used as the reason.
  timedOut,

  /// The client was forcibly disconnected by the server.
  kicked,

  /// The server shut down.
  serverStopped,

  /// The disconnection was initiated by the client.
  disconnected
}

/// Provides base functionality for Server and Client
abstract class Peer {
  /// The name to use when logging messages via RiptideLogger.
  late String logName;

  /// The interval (in milliseconds) at which to send and expect heartbeats to be received.
  ///
  /// Changes to this value will only take effect after the next heartbeat is executed.
  int heartbeatInterval = 1000;

  /// The number of currently active Server and Client instances.
  static int _activeCount = 0;
  static int get activeCount => _activeCount;

  /// The time (in milliseconds) for which to wait before giving up on a connection attempt.
  int connectTimeoutTime = 10000;

  /// The current time.
  int _currentTime = 0;
  int get currentTime => _currentTime;

  /// The text to log when disconnected due to DisconnectReason.NeverConnected.
  final String DCNeverConnected = "Never connected";

  /// The text to log when disconnected due to DisconnectReason.TransportError.
  String DCTransportError = "Transport error";

  /// The text to log when disconnected due to DisconnectReason.TimedOut.
  String DCTimedOut = "Timed out";

  /// The text to log when disconnected due to DisconnectReason.Kicked.
  String DCKicked = "Kicked";

  /// The text to log when disconnected due to DisconnectReason.ServerStopped.
  String DCServerStopped = "Server stopped";

  /// The text to log when disconnected due to DisconnectReason.Disconnected.
  String DCDisconnected = "Disconnected";

  /// The text to log when disconnected or rejected due to an unknown reason.
  String UnknownReason = "Unknown reason";

  /// The text to log when the connection failed due to RejectReason.NoConnection.
  String CRNoConnection = "No connection";

  /// The text to log when the connection failed due to RejectReason.AlreadyConnected.
  String CRAlreadyConnected = "This client is already connected";

  /// The text to log when the connection failed due to RejectReason.ServerFull.
  String CRServerFull = "Server is full";

  /// The text to log when the connection failed due to RejectReason.Rejected.
  String CRRejected = "Rejected";

  /// The text to log when the connection failed due to RejectReason.Custom.
  String CRCustom = "Rejected (with custom data)";

  /// Whether or not the peer should use the built-in message handler system.
  late bool useMessageHandlers;

  /// Received messages which need to be handled.
  Queue<MessageToHandle> messagesToHandle = Queue<MessageToHandle>();
  PriorityQueue<DelayedEventPriority> eventQueue = PriorityQueue<DelayedEventPriority>((a, b) => b.priority.compareTo(a.priority));

  /// A stopwatch used to track how much time has passed.
  final Stopwatch _time = Stopwatch();
  Stopwatch get time => _time;

  /// Initializes the peer.
  ///
  /// [logName] : The name to use when logging messages via RiptideLogger.
  Peer({this.logName = "PEER"});

  /// Starts tracking how much time has passed.
  void startTime() {
    _currentTime = 0;
    _time.reset();
    _time.start();
  }

  /// Stops tracking how much time has passed.
  void stopTime() {
    _currentTime = 0;
    _time.reset();
    eventQueue.clear();
  }

  /// Beats the heart
  void heartbeat() {
    // NOTE: Not implemented here
  }

  /// Handles any received messages and invokes any delayed events which need to be invoked.
  void update() {
    _currentTime = _time.elapsedMilliseconds;

    while (eventQueue.isNotEmpty && eventQueue.first.priority <= _currentTime) {
      DelayedEventPriority event = eventQueue.removeFirst();
      event.delayedEvent.invoke();
    }
  }

  /// Sets up a delayed event to be executed after the given time has passed
  ///
  /// [delay] : How long from now to execute the delayed event, in milliseconds.
  /// [event] : The delayed event to execute later
  void executeLater(int delay, DelayedEvent event) {
    eventQueue.add(DelayedEventPriority(_currentTime + delay, event));
  }

  /// Handles all queued messages
  void handleMessages() {
    while (messagesToHandle.isNotEmpty) {
      MessageToHandle handleMsg = messagesToHandle.removeFirst();
      handle(handleMsg.message, handleMsg.header, handleMsg.fromConnection);
    }
  }

  /// Handles data received by the transport
  void handleData(DataReceivedEventArgs e) {
    MessageHeader header = MessageHeaderExtension.fromMessageIndex(e.dataBuffer[0]);

    Message message = Message.createFromHeaderWithLength(header, e.amount);

    if (header == MessageHeader.notify) {
      if (e.amount < Message.notifyHeaderSize) {
        return;
      }

      e.fromConnection.processNotify(e.dataBuffer, e.amount, message);
    } else if (message.sendMode == MessageSendMode.unreliable) {
      // Only bother with the array copy if there is more than 1 byte in the packet (1 or less means no payload for a reliably sent packet)
      if (e.amount > Message.unreliableHeaderSize) {
        message.bytes.setRange(1, e.amount - 1, e.dataBuffer.getRange(1, e.dataBuffer.length - 1));
      }

      messagesToHandle.add(MessageToHandle(message, header, e.fromConnection));

      // if (e.fromConnection.reliableHandle(Converter.toUShort(e.dataBuffer.buffer.asByteData(), 1))) {
      //   // We've already established that the packet contains at least 3 bytes, and we always want to copy the sequence ID over
      //   message.bytes.setRange(1, e.amount - 1, e.dataBuffer.getRange(1, e.dataBuffer.length - 1));
      //   messagesToHandle.add(MessageToHandle(message, header, e.fromConnection));
      // }
    } else {
      if (e.amount < Message.reliableHeaderSize) {
        return;
      }

      if (e.fromConnection.shouldHandle(Converter.toUShort(e.dataBuffer.buffer.asByteData(), 1))) {
        message.bytes.setRange(1, e.amount - 1, e.dataBuffer.getRange(1, e.dataBuffer.length - 1));
        messagesToHandle.add(MessageToHandle(message, header, e.fromConnection));
      }
    }
  }

  /// Handles a message
  ///
  /// [message] : The message to handle
  /// [header] : The message's header type
  /// [connection] : The connection which the message was received on
  void handle(Message message, MessageHeader header, Connection connection) {
    // NOTE: Not implemented here
  }

  /// Increases [_activeCount]. For use when a new Server or Client is started.
  static void increaseActiveCount() {
    _activeCount++;
  }

  /// Decreases [_activeCount]. For use when a Server or Client is stopped.
  static void decreaseActiveCount() {
    _activeCount--;

    if (_activeCount < 0) {
      _activeCount = 0;
    }
  }
}

/// Stores information about a message that needs to be handled.
class MessageToHandle {
  /// The message that needs to be handled.
  late Message _message;
  Message get message => _message;

  /// The message's header type.
  late MessageHeader _header;
  MessageHeader get header => _header;

  /// The connection on which the message was received.
  late Connection _fromConnection;
  Connection get fromConnection => _fromConnection;

  /// Handles initialization.
  ///
  /// [message] : The message that needs to be handled.
  /// [header] : The message's header type.
  /// [fromConnection] : The connection on which the message was received.
  MessageToHandle(Message message, MessageHeader header, Connection fromConnection) {
    _message = message;
    _header = header;
    _fromConnection = fromConnection;
  }
}
