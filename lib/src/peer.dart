import 'dart:collection';

import 'package:collection/collection.dart';

import 'message.dart';
import 'connection.dart';
import 'transports/event_args.dart';
import 'transports/ipeer.dart';
import 'utils/converter.dart';
import 'utils/delayed_events.dart';
import 'server.dart';
import 'client.dart';
import 'utils/helper.dart';

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
  disconnected,

  /// The connection's loss and/or resend rates exceeded the maximum acceptable thresholds, or a reliably sent message could not be delivered.
  poorConnection
}

/// Provides base functionality for Server and Client
abstract class Peer {
  /// The name to use when logging messages via RiptideLogger.
  late String logName;

  /// Sets the relevant connections' [Connection.timeoutTime]s.
  late int timeoutTime;

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

  /// Whether or not the peer should use the subscription based message handler system.
  late bool useMessageHandlers;

  /// The default time (in milliseconds) after which to disconnect if no heartbeats are received.
  int defaultTimeout = 5000;

  /// A stopwatch used to track how much time has passed.
  final Stopwatch _time = Stopwatch();
  Stopwatch get time => _time;

  /// Received messages which need to be handled.
  final Queue<MessageToHandle> _messagesToHandle = Queue<MessageToHandle>();
  Queue<MessageToHandle> get messageToHandle => _messagesToHandle;

  /// A queue of events to execute, ordered by how soon they need to be executed.
  final PriorityQueue<(DelayedEvent, int)> _eventQueue = PriorityQueue<(DelayedEvent, int)>((a, b) => b.$2.compareTo(a.$2));
  PriorityQueue<(DelayedEvent, int)> get eventQueue => _eventQueue;

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

    while (eventQueue.isNotEmpty && eventQueue.first.$2 <= _currentTime) {
      DelayedEvent event = eventQueue.removeFirst().$1;
      event.invoke();
    }
  }

  /// Sets up a delayed event to be executed after the given time has passed
  ///
  /// [delay] : How long from now to execute the delayed event, in milliseconds.
  /// [event] : The delayed event to execute later
  void executeLater(int delay, DelayedEvent event) {
    eventQueue.add((event, _currentTime + delay));
  }

  /// Handles all queued messages
  void handleMessages() {
    while (_messagesToHandle.isNotEmpty) {
      MessageToHandle handleMsg = _messagesToHandle.removeFirst();
      handle(handleMsg.message, handleMsg.header, handleMsg.fromConnection);
    }
  }

  /// Handles data received by the transport
  void handleData(DataReceivedEventArgs e) {
    var (Message message, MessageHeader header) = Message.create().initWithByte(e.dataBuffer[0], e.amount);

    if (message.sendMode == MessageSendMode.notify) {
      if (e.amount < Message.minNotifyBytes) {
        return;
      }

      e.fromConnection.processNotify(e.dataBuffer, e.amount, message);
    } else if (message.sendMode == MessageSendMode.unreliable) {
      if (e.amount > Message.minUnreliableBytes) {
        Helper.blockCopy(e.dataBuffer, 1, message.data, 1, e.amount - 1);
      }

      _messagesToHandle.add(MessageToHandle(message, header, e.fromConnection));
      e.fromConnection.metrics.receivedUnreliable(e.amount);
    } else {
      if (e.amount < Message.minReliableBytes) {
        return;
      }

      e.fromConnection.metrics.receivedReliable(e.amount);
      if (e.fromConnection.shouldHandle(Converter.uShortFromByteBits(e.dataBuffer, Message.headerBits))) {
        Helper.blockCopy(e.dataBuffer, 1, message.data, 1, e.amount - 1);
        _messagesToHandle.add(MessageToHandle(message, header, e.fromConnection));
      } else {
        e.fromConnection.metrics.reliableDiscarded++;
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

  /// Disconnects the connection in question. Necessary for connections to be able to initiate disconnections (like in the case of poor connection quality).
  ///
  /// [connection] : The connection to disconnect.
  /// [reason] : The reason why the connection is being disconnected.
  void disconnectConnection(Connection connection, DisconnectReason reason) {
    // NOTE: Not implemented here
  }

  /// Increases [activeCount]. For use when a new [Server] or [Client] is started.
  void increaseActiveCount() {
    _activeCount++;
  }

  /// Decreases [activeCount]>. For use when a [Server] or [Client] is stopped.
  void decreaseActiveCount() {
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
