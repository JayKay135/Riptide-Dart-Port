import 'dart:core';
import 'dart:math';
import 'dart:typed_data';

import '../message.dart';
import '../peer.dart';
import '../pending_message.dart';
import '../utils/bitfield.dart';
import '../utils/converter.dart';
import '../utils/event_handler.dart';
import '../utils/helper.dart';
import '../utils/riptide_logger.dart';
import 'ipeer.dart';

/// The state of a connection
enum ConnectionState {
  /// Not connected. No connection has been established or the connection has been closed.
  notConnected,

  /// Connecting. Still trying to establish a connection.
  connecting,

  /// Connection is pending. The server is still determining whether or not the connection should be allowed.
  pending,

  /// Connected. A connection has been established successfully.
  connected,

  /// Not connected. A connection attempt was made but was rejected.
  rejected,
}

/// Represents a connection to a Server or Client.
abstract class Connection {
  /// Invoked when the notify message with the given sequence ID is successfully delivered.
  Event<int>? notifyDelivered;

  /// Invoked when the notify message with the given sequence ID is lost.
  Event<int>? notifyLost;

  /// Invoked when a notify message is received.
  Event<Message>? notifyReceived;

  /// Returns `true` if the connection is currently not connected nor trying to connect.
  bool get isNotConnected => _state == ConnectionState.notConnected;

  /// Returns `true` if the client is currently in the process of connecting
  bool get isConnecting => _state == ConnectionState.connecting;

  /// Returns `true` if the client's connection is currently pending
  ///
  /// Will only be True when a server doesn't immediately accept the connection request
  bool get isPending => _state == ConnectionState.pending;

  /// Returns `true` if the client is currently connected.
  bool get isConnected => _state == ConnectionState.connected;

  /// The connection's numeric ID.
  int id = 0;

  /// The round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  int _rtt = -1;

  /// Gets the round trip time (ping) of the connection, in milliseconds.
  ///
  /// -1 if not calculated yet.
  int get rtt => _rtt;

  /// Sets the round trip time (ping) of the connection, in milliseconds.
  ///
  /// -1 if not calculated yet.
  set rtt(int value) {
    _smoothRtt = _rtt < 0 ? value : max(1, (_smoothRtt * .7 + value * .3).toInt());
    _rtt = value;
  }

  /// The smoothed round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  /// This value is slower to accurately represent lasting changes in latency than rtt, but it is less susceptible to changing drastically due to significant—but temporary—jumps in latency.
  int _smoothRtt = -1;

  /// Returns the smoothed round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  ///
  /// This value is slower to accurately represent lasting changes in latency than rtt, but it is less susceptible to
  /// changing drastically due to significant—but temporary—jumps in latency.
  int get smoothRtt => _smoothRtt;

  /// The time (in milliseconds) after which to disconnect if no heartbeats are received.
  int timeoutTime = 5000;

  // /// Whether or not the connection can time out.
  bool _canTimeout = true;

  /// The local peer this connection is associated with.
  Peer? peer;

  /// Whether or not the connection has timed out.
  bool get hasTimedOut => _canTimeout && peer!.currentTime - _lastHeartbeat > timeoutTime;

  /// Whether or not the connection attempt has timed out. Uses a multiple of timeoutTime and ignores the value of canTimeout.
  bool get hasConnectAttemptTimedOut => peer!.currentTime - _lastHeartbeat > peer!.connectTimeoutTime;

  /// The sequencer for notify messages.
  late NotifySequencer _notify;

  /// The sequencer for reliable messages.
  late ReliableSequencer _reliable;

  /// The currently pending reliably sent messages whose delivery has not been acknowledged yet. Stored by sequence ID.
  Map<int, PendingMessage> pendingMessages = {};

  /// Whether or not the connection is currently not trying to connect, pending, nor actively connected.
  ConnectionState _state = ConnectionState.connecting;

  // late DateTime _lastHeartbeat;
  int _lastHeartbeat = 0;

  /// The ID of the last ping that was sent.
  late int _lastPingID = 0;

  /// The ID of the currently pending ping.
  late int _pendingPingID;

  /// The stopwatch that tracks the time since the currently pending ping was sent.
  Stopwatch _pendingPingStopwatch = Stopwatch();
  Stopwatch get pendingPingStopwatch => _pendingPingStopwatch;

  /// Initializes the connection.
  Connection() {
    _notify = NotifySequencer(this);
    _reliable = ReliableSequencer(this);

    _state = ConnectionState.connecting;
    _canTimeout = true;
  }

  /// Resets the connection's timeout time.
  void resetTimeout() {
    _lastHeartbeat = peer!.currentTime;
  }

  /// Sends a message.
  void sendMessage(Message message, {bool shouldRelease = true}) {
    if (message.sendMode == MessageSendMode.unreliable) {
      send(message.bytes, message.writtenLength);
    } else {
      int sequenceID = _reliable.nextSequenceID;
      PendingMessage pendingMessage = PendingMessage.create(sequenceID, message, this);
      pendingMessages[sequenceID] = pendingMessage;
      pendingMessage.trySend();
    }

    if (shouldRelease) {
      message.release();
    }
  }

  /// Sends data.
  ///
  /// [dataBuffer] : The array containing the data.
  /// [amount] : The number of ints in the array which should be sent.
  void send(Uint8List dataBuffer, int amount);

  /// <summary>Sends a notify message.</summary>
  ///
  /// <param name="message">The message to send.</param>
  /// <param name="shouldRelease">Whether or not to return the message to the pool after it is sent.</param>
  /// <returns>The sequence ID of the sent message.</returns>
  int sendNotify(Message message, {bool shouldRelease = true}) {
    int sequenceID = _notify.insertHeader(message);
    send(message.bytes, message.writtenLength);

    if (shouldRelease) {
      message.release();
    }

    return sequenceID;
  }

  /// Processes a notify message.
  ///
  /// [dataBuffer] : The received data.
  /// [amount] : The number of bytes that were received.
  /// [message] : The message instance to use.
  void processNotify(Uint8List dataBuffer, int amount, Message message) {
    _notify.updateReceivedAcks(Converter.toUShort(dataBuffer.buffer.asByteData(), 1), dataBuffer[3]);

    if (_notify.shouldHandle(Converter.toUShort(dataBuffer.buffer.asByteData(), 4))) {
      // Copy payload
      message.bytes.setRange(1, amount - 1, dataBuffer.getRange(1, dataBuffer.length - 1));

      notifyReceived?.invoke(message);
    }
  }

  /// Determines if the message with the given sequence ID should be handled.
  ///
  /// [sequenceID] : The message's sequence ID.
  /// Whether or not the message should be handled.
  bool shouldHandle(int sequenceID) {
    return _reliable.shouldHandle(sequenceID);
  }

  // /// Updates acks and determines whether the message is a duplicate.
  // ///
  // /// [sequenceID] : The message's sequence ID.
  // /// Returns whether or not the message should be handled.
  // bool reliableHandle(int sequenceID) {
  //   bool doHandle = true;
  //   // Update acks
  //   int sequenceGap = Helper.getSequenceGap(sequenceID, _lastReceivedSeqID);
  //   if (sequenceGap > 0) {
  //     // The received sequence ID is newer than the previous one
  //     if (sequenceGap > 64) {
  //       RiptideLogger.log2(LogType.warning, peer!.logName,
  //           "The gap between received sequence IDs was very large ($sequenceGap)! If the connection's packet loss, latency, or your send rate of reliable messages increases much further, sequence IDs may begin falling outside the bounds of the duplicate filter.");
  //     }

  //     _duplicateFilterBitfield <<= sequenceGap;
  //     if (sequenceGap <= 16) {
  //       int shiftedBits = _acksBitfield << sequenceGap;
  //       _acksBitfield = Helper.toUShort(shiftedBits); // Give the acks bitfield the first 2 ints of the shifted bits
  //       _duplicateFilterBitfield |= shiftedBits >> 16; // OR the last 6 ints worth of the shifted bits into the duplicate filter bitfield

  //       doHandle = _updateAcksBitfield(sequenceGap);
  //       _lastReceivedSeqID = sequenceID;
  //     } else if (sequenceGap <= 80) {
  //       int shiftedBits = _acksBitfield << (sequenceGap - 16);
  //       _acksBitfield = 0; // Reset the acks bitfield as all its bits are being moved to the duplicate filter bitfield
  //       _duplicateFilterBitfield |= shiftedBits; // OR the shifted bits into the duplicate filter bitfield

  //       doHandle = _updateDuplicateFilterBitfield(sequenceGap);
  //     }
  //   } else if (sequenceGap < 0) {
  //     // The received sequence ID is older than the previous one (out of order message)
  //     sequenceGap = -sequenceGap; // Make sequenceGap positive
  //     if (sequenceGap <= 16) {
  //       // If the message's sequence ID still falls within the ack bitfield's value range
  //       doHandle = _updateAcksBitfield(sequenceGap);
  //     } else if (sequenceGap <= 80) {
  //       // If it's an "old" message and its sequence ID doesn't fall within the ack bitfield's value range anymore (but it falls in the range of the duplicate filter)
  //       doHandle = _updateDuplicateFilterBitfield(sequenceGap);
  //     }
  //   } else {
  //     // The received sequence ID is the same as the previous one (duplicate message)
  //     doHandle = false;
  //   }

  //   _sendAck(sequenceID);
  //   return doHandle;
  // }

  /// Cleans up the local side of the connection.
  ///
  /// [wasRejected] : Whether or not the connection was rejected.
  void localDisconnect({bool wasRejected = false}) {
    _state = wasRejected ? ConnectionState.rejected : ConnectionState.notConnected;

    for (PendingMessage pendingMessage in pendingMessages.values) {
      pendingMessage.clear();
    }

    pendingMessages.clear();
  }

  /// Resends the PendingMessage with the given sequence ID.
  ///
  /// [sequenceID] : The sequence ID of the message to resend.
  void _resendMessage(int sequenceID) {
    if (pendingMessages.containsKey(sequenceID)) {
      pendingMessages[sequenceID]!.retrySend();
    }
  }

  /// Clears the PendingMessage with the given sequence ID.
  ///
  /// [sequenceID] : The sequence ID that was acknowledged.
  void clearMessage(int sequenceID) {
    if (pendingMessages.containsKey(sequenceID)) {
      pendingMessages[sequenceID]!.clear();
      pendingMessages.remove(sequenceID);
    }
  }

  /// <summary>Puts the connection in the pending state.</summary>
  void setPending() {
    if (isConnecting) {
      _state = ConnectionState.pending;
      resetTimeout();
    }
  }

  /// <summary>Sends an ack message for the given sequence ID.</summary>
  /// <param name="forSeqId">The sequence ID to acknowledge.</param>
  /// <param name="lastReceivedSeqId">The sequence ID of the latest message we've received.</param>
  /// <param name="receivedSeqIds">Sequence IDs of previous messages that we have (or have not received).</param>
  void _sendAck(int forSeqId, int lastReceivedSeqID, Bitfield receivedSeqIDs) {
    Message message = Message.createFromHeader(MessageHeader.ack);
    message.addUShort(lastReceivedSeqID);
    message.addUShort(receivedSeqIDs.first16);

    if (forSeqId != lastReceivedSeqID) {
      message.addUShort(forSeqId);
    }

    sendMessage(message);
  }

  /// <summary>Handles an ack message.</summary>
  /// <param name="message">The ack message to handle.</param>
  void handleAck(Message message) {
    int remoteLastReceivedSeqID = message.getUShort();
    int remoteAcksBitField = message.getUShort();
    int ackedSeqID = message.unreadLength > 0 ? message.getUShort() : remoteLastReceivedSeqID;

    clearMessage(ackedSeqID);
    _reliable.updateReceivedAcks(remoteLastReceivedSeqID, remoteAcksBitField);
  }

  /// Sends a welcome message.
  void sendWelcome() {
    Message message = Message.createFromHeader(MessageHeader.welcome);
    message.addUShort(id);

    sendMessage(message);
  }

  /// Handles a welcome message on the server.
  ///
  /// [message] : The welcome message to handle.
  void handleWelcomeResponse(Message message) {
    int id = message.getUShort();
    if (this.id != id) {
      RiptideLogger.log2(LogType.error, peer!.logName, "Client has assumed ID $id instead of ${this.id}!");
    }

    _state = ConnectionState.connected;
    resetTimeout();
  }

  /// Handles a heartbeat message.
  ///
  /// [message] : The heartbeat message to handle.
  void handleHeartbeat(Message message) {
    respondHeartbeat(message.getByte());
    rtt = message.getShort();

    resetTimeout();
  }

  /// Sends a heartbeat message.
  void respondHeartbeat(int pingID) {
    Message message = Message.createFromHeader(MessageHeader.heartbeat);
    message.addByte(pingID);

    sendMessage(message);
  }

  /// Handles a welcome message on the client.
  ///
  /// [message] : The welcome message to handle.
  void handleWelcome(Message message) {
    id = message.getUShort();
    _state = ConnectionState.connected;
    resetTimeout();

    respondWelcome();
  }

  /// Sends a welcome response message.
  void respondWelcome() {
    Message message = Message.createFromHeader(MessageHeader.welcome);
    message.addUShort(id);

    sendMessage(message);
  }

  /// Sends a heartbeat message.
  void sendHeartbeat() {
    _pendingPingID = _lastPingID++;
    pendingPingStopwatch.reset();
    pendingPingStopwatch.start();

    Message message = Message.createFromHeader(MessageHeader.heartbeat);
    message.addByte(_pendingPingID);
    message.addShort(rtt);

    sendMessage(message);
  }

  /// Handles a heartbeat message.
  /// [message] : The heartbeat message to handle.
  void handleHeartbeatResponse(Message message) {
    int pingID = message.getByte();

    if (_pendingPingID == pingID) {
      rtt = max(1, pendingPingStopwatch.elapsedMilliseconds);
    }

    resetTimeout();
  }

  // /// Updates the acks bitfield and determines whether or not to handle the message.
  // ///
  // /// [sequenceGap] : The gap between the newly received sequence ID and the previously last received sequence ID.
  // /// Returns whether or not the message should be handled, based on whether or not it's a duplicate.
  // bool _updateAcksBitfield(int sequenceGap) {
  //   int seqIDBit = 1 << Helper.toUShort(sequenceGap - 1); // Calculate which bit corresponds to the sequence ID and set it to 1
  //   if ((_acksBitfield & seqIDBit) == 0) {
  //     // If we haven't received this message before
  //     _acksBitfield |= seqIDBit; // Set the bit corresponding to the sequence ID to 1 because we received that ID
  //     return true; // Message was "new", handle it
  //   } else {
  //     // If we have received this message before
  //     return false; // Message was a duplicate, don't handle it
  //   }
  // }

  // /// Updates the duplicate filter bitfield and determines whether or not to handle the message.
  // ///
  // /// [sequenceGap] : The gap between the newly received sequence ID and the previously last received sequence ID.
  // /// Returns whether or not the message should be handled, based on whether or not it's a duplicate.
  // bool _updateDuplicateFilterBitfield(int sequenceGap) {
  //   int seqIDBit = 1 << (sequenceGap - 1 - 16); // Calculate which bit corresponds to the sequence ID and set it to 1
  //   if ((_duplicateFilterBitfield & seqIDBit) == 0) {
  //     // If we haven't received this message before
  //     _duplicateFilterBitfield |= seqIDBit; // Set the bit corresponding to the sequence ID to 1 because we received that ID
  //     return true; // Message was "new", handle it
  //   } else {
  //     // If we have received this message before
  //     return false; // Message was a duplicate, don't handle it
  //   }
  // }

  // /// Updates which messages we've received acks for.
  // ///
  // /// [remoteLastReceivedSeqID] : The latest sequence ID that the other end has received.
  // /// [remoteAcksBitField] : A redundant list of sequence IDs that the other end has (or has not) received.
  // void updateReceivedAcks(int remoteLastReceivedSeqID, int remoteAcksBitField) {
  //   int sequenceGap = Helper.getSequenceGap(remoteLastReceivedSeqID, _lastAckedSeqID);
  //   if (sequenceGap > 0) {
  //     // The latest sequence ID that the other end has received is newer than the previous one
  //     for (int i = 1; i < sequenceGap; i++) {
  //       // NOTE: loop starts at 1, meaning it only runs if the gap in sequence IDs is greater than 1
  //       _ackedMessagesBitfield <<= 1; // Shift the bits left to make room for a previous ack
  //       checkMessageAckStatus(
  //           Helper.toUShort(_lastAckedSeqID - 16 + i), leftBit); // Check the ack status of the oldest sequence ID in the bitfield (before it's removed)
  //     }
  //     _ackedMessagesBitfield <<= 1; // Shift the bits left to make room for the latest ack
  //     _ackedMessagesBitfield |=
  //         Helper.toUShort(remoteAcksBitField | (1 << sequenceGap - 1)); // Combine the bit fields and ensure that the bit corresponding to the ack is set to 1
  //     _lastAckedSeqID = remoteLastReceivedSeqID;

  //     checkMessageAckStatus(Helper.toUShort(_lastAckedSeqID - 16), leftBit); // Check the ack status of the oldest sequence ID in the bitfield
  //   } else if (sequenceGap < 0) {
  //     // TODO: remove? I don't think this case ever executes
  //     // The latest sequence ID that the other end has received is older than the previous one (out of order ack)
  //     sequenceGap = Helper.toUShort(-sequenceGap - 1); // Because bit shifting is 0-based
  //     int ackedBit = Helper.toUShort(1 << sequenceGap); // Calculate which bit corresponds to the sequence ID and set it to 1
  //     _ackedMessagesBitfield |= ackedBit; // Set the bit corresponding to the sequence ID

  //     if (pendingMessages.containsKey(remoteLastReceivedSeqID)) {
  //       // Message was successfully delivered, remove it from the pending messages.
  //       pendingMessages[remoteLastReceivedSeqID]!.clear();
  //     }
  //   } else {
  //     // The latest sequence ID that the other end has received is the same as the previous one (duplicate ack)
  //     _ackedMessagesBitfield |= remoteAcksBitField; // Combine the bit fields
  //     checkMessageAckStatus(Helper.toUShort(_lastAckedSeqID - 16), leftBit); // Check the ack status of the oldest sequence ID in the bitfield
  //   }
  // }

  // /// Check the ack status of the given sequence ID.
  // ///
  // /// [sequenceID] : The sequence ID whose ack status to check.
  // /// [bit] : The bit corresponding to the sequence ID's position in the bit field.
  // void checkMessageAckStatus(int sequenceID, int bit) {
  //   if ((_ackedMessagesBitfield & bit) == 0) {
  //     // Message was lost
  //     if (pendingMessages.containsKey(sequenceID)) {
  //       pendingMessages[sequenceID]!.retrySend();
  //     }
  //   } else {
  //     // Message was successfully delivered
  //     if (pendingMessages.containsKey(sequenceID)) {
  //       pendingMessages[sequenceID]!.clear();
  //     }
  //   }
  // }

  // /// Immediately marks the PendingMessage of a given sequence ID as delivered.
  // ///
  // /// [seqID] : The sequence ID that was acknowledged.
  // ackMessage(int seqID) {
  //   if (pendingMessages.containsKey(seqID)) {
  //     pendingMessages[seqID]!.clear();
  //   }
  // }

  // /// Handles an ack message for a sequence ID other than the last received one.
  // ///
  // /// [message] : The ack message to handle.
  // void handleAckExtra(Message message) {
  //   int remoteLastReceivedSeqID = message.getUShort();
  //   int remoteAcksBitField = message.getUShort();
  //   int ackedSeqID = message.getUShort();

  //   ackMessage(
  //       ackedSeqID); // Immediately mark it as delivered so no resends are triggered while waiting for the sequence ID's bit to reach the end of the bit field
  //   updateReceivedAcks(remoteLastReceivedSeqID, remoteAcksBitField);
  // }
}

// #region Message Sequencing
/// Provides functionality for filtering out duplicate messages and determining delivery/loss status.
abstract class Sequencer {
  /// The next sequence ID to use.
  int _nextSequenceID = 1;
  int get nextSequenceID => _nextSequenceID++;

  /// The connection this sequencer belongs to.
  late Connection _connection;

  /// The sequence ID of the latest message that we want to acknowledge.
  int lastReceivedSeqID = 0;

  /// Sequence IDs of messages which we have (or have not) received and want to acknowledge.
  Bitfield receivedSeqIDs = Bitfield();

  /// The sequence ID of the latest message that we've received an ack for.
  int lastAckedSeqID = 0;

  /// Sequence IDs of messages we sent and which we have (or have not) received acks for.
  Bitfield ackedSeqIDs = Bitfield(isDynamicCapacity: false);

  /// Initializes the sequencer.
  /// [connection] : The connection this sequencer belongs to.
  Sequencer(Connection connection) {
    _connection = connection;
  }

  /// Determines whether or not to handle a message with the given sequence ID.
  /// [sequenceID] : The sequence ID in question.
  /// <returns>Whether or not to handle the message.</returns>
  bool shouldHandle(int sequenceID);

  /// Updates which messages we've received acks for.
  /// [remoteLastReceivedSeqID] : The latest sequence ID that the other end has received.
  /// [remoteReceivedSeqIDs] : Sequence IDs which the other end has (or has not) received.
  void updateReceivedAcks(int remoteLastReceivedSeqID, int remoteReceivedSeqIDs);
}

/// <inheritdoc/>
class NotifySequencer extends Sequencer {
  /// <inheritdoc/>
  NotifySequencer(Connection connection) : super(connection) {}

  /// Inserts the notify header into the given message.
  /// [message] : The message to insert the header into.
  /// <returns>The sequence ID of the message.</returns>
  int insertHeader(Message message) {
    int sequenceID = _nextSequenceID;
    Converter.fromUShort(lastReceivedSeqID, message.bytes.buffer.asByteData(), 1); // Ack sequence ID
    message.bytes[3] = receivedSeqIDs.first8; // Acks bitfield
    Converter.fromUShort(sequenceID, message.bytes.buffer.asByteData(), 4); // Insert sequence ID
    return sequenceID;
  }

  /// <remarks>Duplicate and out of order messages are filtered out and not handled.</remarks>
  @override
  bool shouldHandle(int sequenceID) {
    int sequenceGap = Helper.getSequenceGap(sequenceID, lastReceivedSeqID);

    if (sequenceGap > 0) {
      // The received sequence ID is newer than the previous one
      receivedSeqIDs.shiftBy(sequenceGap);
      lastReceivedSeqID = sequenceID;

      if (receivedSeqIDs.isSet(sequenceGap)) return false;

      receivedSeqIDs.set(sequenceGap);
      return true;
    } else {
      // The received sequence ID is older than or the same as the previous one (out of order or duplicate message)
      return false;
    }
  }

  @override
  void updateReceivedAcks(int remoteLastReceivedSeqID, int remoteReceivedSeqIDs) {
    int sequenceGap = Helper.getSequenceGap(remoteLastReceivedSeqID, lastAckedSeqID);

    if (sequenceGap > 0) {
      if (sequenceGap > 1) {
        // Deal with messages in the gap
        while (
            sequenceGap > 9) // 9 because a gap of 1 means sequence IDs are consecutive, and notify uses 8 bits for the bitfield. 9 means all 8 bits are in use
        {
          lastAckedSeqID++;
          sequenceGap--;
          _connection.notifyLost?.invoke(lastAckedSeqID);
        }

        int bitCount = sequenceGap - 1;
        int bit = 1 << bitCount;
        for (int i = 0; i < bitCount; i++) {
          lastAckedSeqID++;
          bit >>= 1;
          if ((remoteReceivedSeqIDs & bit) == 0) {
            _connection.notifyLost?.invoke(lastAckedSeqID);
          } else {
            _connection.notifyDelivered?.invoke(lastAckedSeqID);
          }
        }
      }

      lastAckedSeqID = remoteLastReceivedSeqID;
      _connection.notifyDelivered?.invoke(lastAckedSeqID);
    }
  }
}

/// <inheritdoc/>
class ReliableSequencer extends Sequencer {
  /// <inheritdoc/>
  ReliableSequencer(Connection connection) : super(connection) {}

  /// <remarks>Duplicate messages are filtered out while out of order messages are handled.</remarks>
  @override
  bool shouldHandle(int sequenceID) {
    bool doHandle = false;
    int sequenceGap = Helper.getSequenceGap(sequenceID, lastReceivedSeqID);

    if (sequenceGap != 0) {
      // The received sequence ID is different from the previous one
      if (sequenceGap > 0) {
        // The received sequence ID is newer than the previous one
        if (sequenceGap > 64)
          RiptideLogger.log2(LogType.warning, _connection.peer!.logName, "The gap between received sequence IDs was very large ($sequenceGap)!");

        receivedSeqIDs.shiftBy(sequenceGap);
        lastReceivedSeqID = sequenceID;
      } else // The received sequence ID is older than the previous one (out of order message)
        sequenceGap = -sequenceGap;

      doHandle = !receivedSeqIDs.isSet(sequenceGap);
      receivedSeqIDs.set(sequenceGap);
    }

    _connection._sendAck(sequenceID, lastReceivedSeqID, receivedSeqIDs);
    return doHandle;
  }

  /// Updates which messages we've received acks for.
  /// [remoteLastReceivedSeqID] : The latest sequence ID that the other end has received.
  /// [remoteReceivedSeqIDs] : Sequence IDs which the other end has (or has not) received.
  @override
  void updateReceivedAcks(int remoteLastReceivedSeqID, int remoteReceivedSeqIDs) {
    int sequenceGap = Helper.getSequenceGap(remoteLastReceivedSeqID, lastAckedSeqID);

    if (sequenceGap > 0) {
      // The latest sequence ID that the other end has received is newer than the previous one
      for (int i = 0; i < 16; i++) {
        // Clear any messages that have been newly acknowledged
        if (!ackedSeqIDs.isSet(i + 1) && (remoteReceivedSeqIDs & (1 << (sequenceGap + i))) != 0) {
          _connection.clearMessage((lastAckedSeqID - (i + 1)));
        }
      }

      (bool hasCapacity, int overflow) capacity = ackedSeqIDs.hasCapacityFor(sequenceGap);
      if (!capacity.$1) {
        for (int i = 0; i < capacity.$2; i++) {
          // Resend those messages which haven't been acked and whose sequence IDs are about to be pushed out of the bitfield
          (bool isSet, int checkedPosition) set = ackedSeqIDs.checkAndTrimLast();
          if (!set.$1) {
            _connection._resendMessage((lastAckedSeqID - set.$2));
          } else {
            _connection.clearMessage((lastAckedSeqID - set.$2));
          }
        }
      }

      ackedSeqIDs.shiftBy(sequenceGap);
      ackedSeqIDs.combine(remoteReceivedSeqIDs);
      ackedSeqIDs.set(sequenceGap); // Ensure that the bit corresponding to the previous ack is set
      lastAckedSeqID = remoteLastReceivedSeqID;
      _connection.clearMessage(remoteLastReceivedSeqID);
    } else if (sequenceGap < 0) {
      // The latest sequence ID that the other end has received is older than the previous one (out of order ack)
      ackedSeqIDs.set(-sequenceGap);
    } else {
      // The latest sequence ID that the other end has received is the same as the previous one (duplicate ack)
      ackedSeqIDs.combine(remoteReceivedSeqIDs);
    }
  }
}
// #endregion
