import '../peer.dart';
import '../pending_message.dart';

/// Executes an action when invoked.
abstract class DelayedEvent {
  /// Executes the action.
  void invoke();
}

/// Resends a PendingMessage when invoked.
class ResendEvent extends DelayedEvent {
  /// The message to resend.
  late PendingMessage _message;
  PendingMessage get message => _message;

  /// The time at which the resend event was queued.
  late int _initiatedAtTime;
  int get initiatedAtTime => _initiatedAtTime;

  /// Initializes the event.
  ///
  /// [message] : The message to resend.
  /// [initiatedAtTime] : The time at which the resend event was queued.
  ResendEvent(PendingMessage message, int initiatedAtTime) {
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
  ///
  /// [peer] : The peer whose heart to beat.
  HeartbeatEvent(Peer peer) {
    _peer = peer;
  }

  @override
  void invoke() {
    peer.heartbeat();
  }
}
