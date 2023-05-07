import 'dart:math';
import 'dart:typed_data';

import 'transports/_connection.dart';
import 'transports/_ipeer.dart';
import '_message.dart';
import 'utils/_converter.dart';
import 'utils/_delayedEvents.dart';
import 'utils/_helper.dart';
import 'utils/_riptideLogger.dart';

/// Represents a currently pending reliably sent message whose delivery has not been acknowledged yet.
class PendingMessage {
  /// The time of the latest send attempt.
  late int _lastSendTime;
  int get lastSendTime => _lastSendTime;

  /// The multiplier used to determine how long to wait before resending a pending message.
  double _retryTimeMultiplier = 1.2;

  /// How often to try sending the message before giving up.
  final int _maxSendAttempts = 15; // TODO: get rid of this

  /// A pool of reusable PendingMessage instances.
  static List<PendingMessage> _pool = [];
  List<PendingMessage> get pool => _pool;

  /// The Connection to use to send (and resend) the pending message.
  late Connection _connection;

  /// The sequence ID of the message.
  late int _sequenceId;

  /// The contents of the message.
  late Uint8List _data;
  Uint8List get data => _data;

  /// The length in bytes of the data that has been written to the message.
  late int _writtenLength;

  /// How many send attempts have been made so far.
  late int _sendAttempts;

  /// Whether the pending message has been cleared or not.
  late bool _wasCleared;

  /// Handles initial setup.
  PendingMessage() {
    _data = Uint8List(Message.maxSize);
  }

  // #region Pooling

  /// Retrieves a PendingMessage instance, initializes it and then sends it.
  ///
  /// [sequenceID] : The sequence ID of the message.
  /// [message] : The message that is being sent reliably.
  /// [connection] : The Connection to use to send (and resend) the pending message.
  static void createAndSend(
      int sequenceID, Message message, Connection connection) {
    PendingMessage pendingMessage = _retrieveFromPool();
    pendingMessage._connection = connection;
    pendingMessage._sequenceId = sequenceID;

    pendingMessage.data[0] = message.bytes[0]; // Copy message header
    Converter.fromUShort(sequenceID, pendingMessage.data.buffer.asByteData(),
        1); // Insert sequence ID

    // Array.Copy(message.bytes, 3, pendingMessage.data, 3,
    //     message.writtenLength - 3); // Copy the rest of the message

    pendingMessage.data.setRange(3, message.writtenLength,
        message.bytes.getRange(3, message.writtenLength));

    pendingMessage._writtenLength = message.writtenLength;

    pendingMessage._sendAttempts = 0;
    pendingMessage._wasCleared = false;

    connection.pendingMessages[sequenceID] = pendingMessage;
    pendingMessage.trySend();
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

  /// Returns the PendingMessage instance to the pool so it can be reused.
  void _release() {
    if (!pool.contains(this)) {
      pool.add(
          this); // Only add it if it's not already in the list, otherwise this method being called twice in a row for whatever reason could cause *serious* issues
    }

    // TODO: consider doing something to decrease pool capacity if there are far more
    // available instance than are needed, which could occur if a large burst of
    // messages has to be sent for some reason
  }
  // #endregion

  /// Resends the message.
  void retrySend() {
    if (!_wasCleared) {
      int time = _connection.peer!.currentTime;
      if (lastSendTime +
              (_connection.smoothRtt < 0 ? 25 : _connection.smoothRtt / 2) <=
          time) {
        // Avoid triggering a resend if the latest resend was less than half a RTT ago
        trySend();
      } else {
        _connection.peer!.executeLater(
            _connection.smoothRtt < 0
                ? 50
                : max(
                    10, (_connection.smoothRtt * _retryTimeMultiplier).toInt()),
            PendingMessageResendEvent(this, time));
      }
    }
  }

  /// Attempts to send the message.
  void trySend() {
    if (_sendAttempts >= _maxSendAttempts) {
      // Send attempts exceeds max send attempts, so give up
      if (RiptideLogger.isWarningLoggingEnabled) {
        MessageHeader header = MessageHeader.values[data[0]];
        if (header == MessageHeader.reliable) {
          RiptideLogger.log2(LogType.warning, _connection.peer!.logName,
              "No ack received for $header message (ID: ${Converter.toUShort(data.buffer.asByteData(), 3)}) after $_sendAttempts ${Helper.correctForm(_sendAttempts, "attempt")}, delivery may have failed!");
        } else {
          RiptideLogger.log2(LogType.warning, _connection.peer!.logName,
              "No ack received for internal $header message after $_sendAttempts ${Helper.correctForm(_sendAttempts, "attempt")}, delivery may have failed!");
        }
      }

      clear();
      return;
    }

    _connection.send(data, _writtenLength);

    _lastSendTime = _connection.peer!.currentTime;
    _sendAttempts++;

    _connection.peer!.executeLater(
        _connection.smoothRtt < 0
            ? 50
            : max(10, (_connection.smoothRtt * _retryTimeMultiplier).toInt()),
        PendingMessageResendEvent(this, _connection.peer!.currentTime));
  }

  /// Clears the message.
  ///
  /// [shouldRemoveFromDictionary] : Whether or not to remove the message from Connection.PendingMessages.
  void clear({bool shouldRemoveFromDictionary = true}) {
    if (shouldRemoveFromDictionary) {
      _connection.pendingMessages.remove(_sequenceId);
    }

    _wasCleared = true;
    _release();
  }
}
