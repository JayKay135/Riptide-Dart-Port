import 'dart:math';
import 'dart:typed_data';

import 'peer.dart';
import 'connection.dart';
import 'transports/ipeer.dart';
import 'message.dart';
import 'utils/constants.dart';
import 'utils/converter.dart';
import 'utils/delayed_events.dart';
import 'utils/helper.dart';
import 'utils/riptide_logger.dart';

/// Represents a currently pending reliably sent message whose delivery has not been acknowledged yet.
class PendingMessage {
  /// The time of the latest send attempt.
  late int _lastSendTime;
  int get lastSendTime => _lastSendTime;

  /// The multiplier used to determine how long to wait before resending a pending message.
  final double _retryTimeMultiplier = 1.2;

  /// A pool of reusable PendingMessage instances.
  static final List<PendingMessage> _pool = [];
  List<PendingMessage> get pool => _pool;

  /// The [Connection] to use to send (and resend) the pending message.
  late Connection _connection;

  /// The contents of the message.
  late Uint8List _data;
  Uint8List get data => _data;

  /// The length in bytes of the message.
  int _size = 0;

  /// How many send attempts have been made so far.
  late int _sendAttempts;

  /// Whether the pending message has been cleared or not.
  late bool _wasCleared;

  /// Handles initial setup.
  PendingMessage() {
    _data = Uint8List(Message.maxSize);
  }

  /// Retrieves a PendingMessage instance and initializes it.
  ///
  /// [sequenceID] : The sequence ID of the message.
  /// [message] : The message that is being sent reliably.
  /// [connection] : The Connection to use to send (and resend) the pending message.
  static PendingMessage create(int sequenceID, Message message, Connection connection) {
    PendingMessage pendingMessage = _retrieveFromPool();
    pendingMessage._connection = connection;

    message.setBits(sequenceID, Constants.ushortBytes * Converter.bitsPerByte, Message.headerBits);
    pendingMessage._size = message.bytesInUse;
    Helper.blockCopyReversed(message.data, 0, pendingMessage.data, 0, pendingMessage._size);

    pendingMessage._sendAttempts = 0;
    pendingMessage._wasCleared = false;

    return pendingMessage;
  }

  /// Retrieves a PendingMessage instance from the pool. If none is available, a new instance is created.
  ///
  /// Returns a PendingMessage instance.
  static PendingMessage _retrieveFromPool() {
    PendingMessage message;
    if (_pool.isNotEmpty) {
      message = _pool[0];
      _pool.removeAt(0);
    } else {
      message = PendingMessage();
    }

    return message;
  }

  /// Empties the pool. Does not affect [PendingMessage] instances which are actively pending and therefore not in the pool.
  static void clearPool() {
    _pool.clear();
  }

  /// Returns the PendingMessage instance to the pool so it can be reused.
  void _release() {
    if (!pool.contains(this)) {
      // Only add it if it's not already in the list, otherwise this method being called twice in a row for whatever reason could cause *serious* issues
      pool.add(this);
    }

    // TODO: consider doing something to decrease pool capacity if there are far more
    // available instance than are needed, which could occur if a large burst of
    // messages has to be sent for some reason
  }

  /// Resends the message.
  void retrySend() {
    if (!_wasCleared) {
      int time = _connection.peer.currentTime;
      if (lastSendTime + (_connection.smoothRtt < 0 ? 25 : _connection.smoothRtt / 2) <= time) {
        // Avoid triggering a resend if the latest resend was less than half a RTT ago
        trySend();
      } else {
        _connection.peer
            .executeLater(_connection.smoothRtt < 0 ? 50 : max(10, (_connection.smoothRtt * _retryTimeMultiplier).toInt()), ResendEvent(this, time));
      }
    }
  }

  /// Attempts to send the message.
  void trySend() {
    if (_sendAttempts >= _connection.maxSendAttempts && _connection.canQualityDisconnect) {
      RiptideLogger.logWithLogName(LogType.info, _connection.peer.logName,
          "Could not guarantee delivery of a ${MessageHeader.values[data[0]]} message after $_sendAttempts attempts! Disconnecting...");
      _connection.peer.disconnectConnection(_connection, DisconnectReason.poorConnection);
      return;
    }

    _connection.send(data, _size);
    _connection.metrics.sentReliable(_size);

    _lastSendTime = _connection.peer.currentTime;
    _sendAttempts++;

    _connection.peer.executeLater(
        _connection.smoothRtt < 0 ? 50 : max(10, (_connection.smoothRtt * _retryTimeMultiplier).toInt()), ResendEvent(this, _connection.peer.currentTime));
  }

  /// Clears the message.
  void clear() {
    _connection.metrics.rollingReliableSends.add(_sendAttempts.toDouble());
    _wasCleared = true;
    _release();
  }
}
