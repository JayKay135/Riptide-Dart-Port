import '../peer.dart';
import '../pending_message.dart';
import '../transports/connection.dart';
import '../transports/iserver.dart';

/// Executes an action when invoked.
abstract class DelayedEvent {
  /// Executes the action.
  void invoke();
}

class DelayedEventPriority {
  int priority;
  DelayedEvent delayedEvent;

  DelayedEventPriority(this.priority, this.delayedEvent);
}

/// Resends a PendingMessage when invoked.
class PendingMessageResendEvent extends DelayedEvent {
  /// The message to resend.
  late PendingMessage _message;
  PendingMessage get message => _message;

  /// The time at which the resend event was queued.
  late int _initiatedAtTime;
  int get initiatedAtTime => _initiatedAtTime;

  /// Initializes the event.
  /// [message] : The message to resend.
  /// [initiatedAtTime] : The time at which the resend event was queued.
  PendingMessageResendEvent(PendingMessage message, int initiatedAtTime) {
    _message = message;
    _initiatedAtTime = initiatedAtTime;
  }

  @override
  void invoke() {
    // If this isn't the case then the message has been resent already
    if (_initiatedAtTime == message.lastSendTime) {
      message.retrySend();
    }
  }
}

/// Executes a heartbeat when invoked.
class HeartbeatEvent extends DelayedEvent {
  /// The peer whose heart to beat.
  late Peer _peer;
  Peer get peer => _peer;

  /// Initializes the event.
  /// [peer] : The peer whose heart to beat.
  HeartbeatEvent(Peer peer) {
    _peer = peer;
  }

  @override
  void invoke() {
    peer.heartbeat();
  }
}

/// Closes the given connection when invoked.
class CloseRejectedConnectionEvent extends DelayedEvent {
  /// The transport which the connection belongs to.
  late IServer _transport;
  IServer get transport => _transport;

  /// The connection to close.
  late Connection _connection;
  Connection get connection => _connection;

  /// Initializes the event.
  /// [transport] : The transport which the connection belongs to.
  /// [connection] : The connection to close.
  CloseRejectedConnectionEvent(IServer transport, Connection connection) {
    _transport = transport;
    _connection = connection;
  }

  @override
  void invoke() {
    transport.close(connection);
  }
}
