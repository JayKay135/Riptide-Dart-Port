import '../_peer.dart';
import '../_pendingMessage.dart';
import '../transports/_connection.dart';
import '../transports/_iserver.dart';

abstract class DelayedEvent {
  void invoke();
}

class DelayedEventPriority {
  int priority;
  DelayedEvent delayedEvent;

  DelayedEventPriority(this.priority, this.delayedEvent);
}

class PendingMessageResendEvent extends DelayedEvent {
  late PendingMessage _message;
  PendingMessage get message => _message;

  late int _initiatedAtTime;
  int get initiatedAtTime => _initiatedAtTime;

  PendingMessageResendEvent(PendingMessage message, int initiatedAtTime) {
    _message = message;
    _initiatedAtTime = initiatedAtTime;
  }

  @override
  void invoke() {
    if (_initiatedAtTime == message.lastSendTime) {
      message.retrySend();
    }
  }
}

class HeartbeatEvent extends DelayedEvent {
  late Peer _peer;
  Peer get peer => _peer;

  HeartbeatEvent(Peer peer) {
    _peer = peer;
  }

  @override
  void invoke() {
    peer.heartbeat();
  }
}

class CloseRejectedConnectionEvent extends DelayedEvent {
  late IServer _transport;
  IServer get transport => _transport;

  late Connection _connection;
  Connection get connection => _connection;

  CloseRejectedConnectionEvent(IServer transport, Connection connection) {
    _transport = transport;
    _connection = connection;
  }

  @override
  void invoke() {
    transport.close(connection);
  }
}
