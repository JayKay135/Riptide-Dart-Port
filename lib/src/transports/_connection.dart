import 'dart:core';
import 'dart:math';
import 'dart:typed_data';

import '../_message.dart';
import '../_peer.dart';
import '../_pendingMessage.dart';
import '../utils/_helper.dart';
import '../utils/_riptideLogger.dart';
import '_ipeer.dart';

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

/// Represents a connection to a <see cref="Server"/> or <see cref="Client"/>.
abstract class Connection {
  /// The connection's numeric ID.
  int id = 0;

  /// Whether or not the connection is currently <i>not</i> trying to connect, pending, nor actively connected.
  ConnectionState _state = ConnectionState.connecting;

  /// The round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  int _rtt = -1;

  /// The smoothed round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  /// This value is slower to accurately represent lasting changes in latency than rtt, but it is less susceptible to changing drastically due to significant—but temporary—jumps in latency.
  int _smoothRtt = 0;

  // /// Whether or not the connection can time out.
  bool _canTimeout = true;

  /// The local peer this connection is associated with.
  Peer? peer;

  /// Whether or not the connection has timed out.
  bool get hasTimedOut =>
      _canTimeout &&
      (DateTime.now().difference(_lastHeartbeat).inMilliseconds) >
          peer!.timeoutTime;

  /// Whether or not the connection attempt has timed out. Uses a multiple of timeoutTime and ignores the value of canTimeout.
  bool get hasConnectAttemptTimedOut =>
      (DateTime.now().difference(_lastHeartbeat).inMilliseconds) >
      peer!.connectTimeoutTime;

  /// The currently pending reliably sent messages whose delivery has not been acknowledged yet. Stored by sequence ID.
  Map<int, PendingMessage> pendingMessages = {};

  /// The sequence ID of the latest message that we want to acknowledge.
  int _lastReceivedSeqID = 0;

  /// Messages that we have received and want to acknowledge.
  int _acksBitfield = 0;

  /// Messages that we have received whose sequence IDs no longer fall into acksBitfield's range. Used to improve duplicate message filtering capabilities.
  int _duplicateFilterBitfield = 0;

  /// The sequence ID of the latest message that we've received an ack for.
  int _lastAckedSeqID = 0;

  /// Messages that we sent which have been acknoweledged.
  int _ackedMessagesBitfield = 0;

  /// A <see cref="ushort"/> with the left-most bit set to 1.
  final int leftBit = (Uint16List(1)..[0] = 0x8000)
      .buffer
      .asInt8List()
      .first; // 0b_1000_0000_0000_0000;

  /// The next sequence ID to use.
  int get nextSequenceID =>
      (++_lastSequenceID) & 0xffff; // Ushort + simulated overflow

  int _lastSequenceID = 0;

  late DateTime _lastHeartbeat;

  /// The ID of the last ping that was sent.
  late int _lastPingID = 0;

  /// The ID of the currently pending ping.
  late int _pendingPingID;

  /// The stopwatch that tracks the time since the currently pending ping was sent.
  Stopwatch _pendingPingStopwatch = Stopwatch();
  Stopwatch get pendingPingStopwatch => _pendingPingStopwatch;

  // #region Connection State

  /// Returns `true` if the connection is currently not connected nor trying to connect.
  bool isNotConnected() {
    return _state == ConnectionState.notConnected;
  }

  /// Returns `true` if the client is currently in the process of connecting
  bool isConnecting() {
    return _state == ConnectionState.connecting;
  }

  /// Returns `true` if the client's connection is currently pending
  ///
  /// Will only be True when a server doesn't immediately accept the connection request
  bool isPending() {
    return _state == ConnectionState.pending;
  }

  /// Returns `true` if the client is currently connected.
  bool isConnected() {
    return _state == ConnectionState.connected;
  }

  // #endregion

  // #region RTT

  /// Gets the round trip time (ping) of the connection, in milliseconds.
  ///
  /// -1 if not calculated yet.
  int get rtt => _rtt;

  /// Sets the round trip time (ping) of the connection, in milliseconds.
  ///
  /// -1 if not calculated yet.
  set rtt(int value) {
    _smoothRtt =
        _rtt < 0 ? value : max(1, (_smoothRtt * .7 + value * .3).toInt());
    _rtt = value;
  }

  /// Returns the smoothed round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  ///
  /// This value is slower to accurately represent lasting changes in latency than rtt, but it is less susceptible to
  /// changing drastically due to significant—but temporary—jumps in latency.
  int get smoothRtt => _smoothRtt;

  // #endregion

  // #region Timeout

  /// Gets if the connection can time out.
  bool get canTimeout => _canTimeout;

  /// Sets if the connection can time out.
  set canTimeout(bool value) {
    if (value) {
      resetTimeout();
    }

    _canTimeout = value;
  }

  /// Returns true if the connection attempt has timed out. Uses a multiple of Peer.timeoutTime
  /// and ignores the value of CanTimeout
  bool get hasConnecntingAttemptTimedOut {
    return DateTime.now().difference(_lastHeartbeat).inMilliseconds * 1000 >
        peer!.timeoutTime * 2;
  }

  /// Initializes the connection.
  Connection() {
    _state = ConnectionState.connecting;
    _canTimeout = true;
  }

  /// Resets the connection's timeout time.
  void resetTimeout() {
    _lastHeartbeat = DateTime.now();
  }

  /// Sends a message.
  void sendMessage(Message message, {bool shouldRelease = true}) {
    if (message.sendMode == MessageSendMode.unreliable) {
      send(message.bytes, message.writtenLength);
    } else {
      int seqID = nextSequenceID;
      PendingMessage.createAndSend(seqID, message, this);
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

  /// Updates acks and determines whether the message is a duplicate.
  ///
  /// [sequenceId] : The message's sequence ID.
  /// Returns whether or not the message should be handled.
  bool reliableHandle(int sequenceId) {
    bool doHandle = true;
    // Update acks
    int sequenceGap = Helper.getSequenceGap(sequenceId, _lastReceivedSeqID);
    if (sequenceGap > 0) {
      // The received sequence ID is newer than the previous one
      if (sequenceGap > 64) {
        RiptideLogger.log2(LogType.warning, peer!.logName,
            "The gap between received sequence IDs was very large ($sequenceGap)! If the connection's packet loss, latency, or your send rate of reliable messages increases much further, sequence IDs may begin falling outside the bounds of the duplicate filter.");
      }

      _duplicateFilterBitfield <<= sequenceGap;
      if (sequenceGap <= 16) {
        int shiftedBits = _acksBitfield << sequenceGap;
        _acksBitfield = Helper.toUShort(
            shiftedBits); // Give the acks bitfield the first 2 ints of the shifted bits
        _duplicateFilterBitfield |= shiftedBits >>
            16; // OR the last 6 ints worth of the shifted bits into the duplicate filter bitfield

        doHandle = _updateAcksBitfield(sequenceGap);
        _lastReceivedSeqID = sequenceId;
      } else if (sequenceGap <= 80) {
        int shiftedBits = _acksBitfield << (sequenceGap - 16);
        _acksBitfield =
            0; // Reset the acks bitfield as all its bits are being moved to the duplicate filter bitfield
        _duplicateFilterBitfield |=
            shiftedBits; // OR the shifted bits into the duplicate filter bitfield

        doHandle = _updateDuplicateFilterBitfield(sequenceGap);
      }
    } else if (sequenceGap < 0) {
      // The received sequence ID is older than the previous one (out of order message)
      sequenceGap = -sequenceGap; // Make sequenceGap positive
      if (sequenceGap <= 16) {
        // If the message's sequence ID still falls within the ack bitfield's value range
        doHandle = _updateAcksBitfield(sequenceGap);
      } else if (sequenceGap <= 80) {
        // If it's an "old" message and its sequence ID doesn't fall within the ack bitfield's value range anymore (but it falls in the range of the duplicate filter)
        doHandle = _updateDuplicateFilterBitfield(sequenceGap);
      }
    } else {
      // The received sequence ID is the same as the previous one (duplicate message)
      doHandle = false;
    }

    _sendAck(sequenceId);
    return doHandle;
  }

  /// Cleans up the local side of the connection.
  ///
  /// [wasRejected] : Whether or not the connection was rejected.
  void localDisconnect({bool wasRejected = false}) {
    _state =
        wasRejected ? ConnectionState.rejected : ConnectionState.notConnected;

    for (PendingMessage pendingMessage in pendingMessages.values) {
      pendingMessage.clear(shouldRemoveFromDictionary: false);
    }

    pendingMessages.clear();
  }

  /// Updates the acks bitfield and determines whether or not to handle the message.
  ///
  /// [sequenceGap] : The gap between the newly received sequence ID and the previously last received sequence ID.
  /// Returns whether or not the message should be handled, based on whether or not it's a duplicate.
  bool _updateAcksBitfield(int sequenceGap) {
    int seqIdBit = 1 <<
        Helper.toUShort(sequenceGap -
            1); // Calculate which bit corresponds to the sequence ID and set it to 1
    if ((_acksBitfield & seqIdBit) == 0) {
      // If we haven't received this message before
      _acksBitfield |=
          seqIdBit; // Set the bit corresponding to the sequence ID to 1 because we received that ID
      return true; // Message was "new", handle it
    } else {
      // If we have received this message before
      return false; // Message was a duplicate, don't handle it
    }
  }

  /// Updates the duplicate filter bitfield and determines whether or not to handle the message.
  ///
  /// [sequenceGap] : The gap between the newly received sequence ID and the previously last received sequence ID.
  /// Returns whether or not the message should be handled, based on whether or not it's a duplicate.
  bool _updateDuplicateFilterBitfield(int sequenceGap) {
    int seqIdBit = 1 <<
        (sequenceGap -
            1 -
            16); // Calculate which bit corresponds to the sequence ID and set it to 1
    if ((_duplicateFilterBitfield & seqIdBit) == 0) {
      // If we haven't received this message before
      _duplicateFilterBitfield |=
          seqIdBit; // Set the bit corresponding to the sequence ID to 1 because we received that ID
      return true; // Message was "new", handle it
    } else {
      // If we have received this message before
      return false; // Message was a duplicate, don't handle it
    }
  }

  /// Updates which messages we've received acks for.
  ///
  /// [remoteLastReceivedSeqID] : The latest sequence ID that the other end has received.
  /// [remoteAcksBitField] : A redundant list of sequence IDs that the other end has (or has not) received.
  void updateReceivedAcks(int remoteLastReceivedSeqID, int remoteAcksBitField) {
    int sequenceGap =
        Helper.getSequenceGap(remoteLastReceivedSeqID, _lastAckedSeqID);
    if (sequenceGap > 0) {
      // The latest sequence ID that the other end has received is newer than the previous one
      for (int i = 1; i < sequenceGap; i++) {
        // NOTE: loop starts at 1, meaning it only runs if the gap in sequence IDs is greater than 1
        _ackedMessagesBitfield <<=
            1; // Shift the bits left to make room for a previous ack
        checkMessageAckStatus(Helper.toUShort(_lastAckedSeqID - 16 + i),
            leftBit); // Check the ack status of the oldest sequence ID in the bitfield (before it's removed)
      }
      _ackedMessagesBitfield <<=
          1; // Shift the bits left to make room for the latest ack
      _ackedMessagesBitfield |= Helper.toUShort(remoteAcksBitField |
          (1 <<
              sequenceGap -
                  1)); // Combine the bit fields and ensure that the bit corresponding to the ack is set to 1
      _lastAckedSeqID = remoteLastReceivedSeqID;

      checkMessageAckStatus(Helper.toUShort(_lastAckedSeqID - 16),
          leftBit); // Check the ack status of the oldest sequence ID in the bitfield
    } else if (sequenceGap < 0) {
      // TODO: remove? I don't think this case ever executes
      // The latest sequence ID that the other end has received is older than the previous one (out of order ack)
      sequenceGap =
          Helper.toUShort(-sequenceGap - 1); // Because bit shifting is 0-based
      int ackedBit = Helper.toUShort(1 <<
          sequenceGap); // Calculate which bit corresponds to the sequence ID and set it to 1
      _ackedMessagesBitfield |=
          ackedBit; // Set the bit corresponding to the sequence ID

      if (pendingMessages.containsKey(remoteLastReceivedSeqID)) {
        // Message was successfully delivered, remove it from the pending messages.
        pendingMessages[remoteLastReceivedSeqID]!.clear();
      }
    } else {
      // The latest sequence ID that the other end has received is the same as the previous one (duplicate ack)
      _ackedMessagesBitfield |= remoteAcksBitField; // Combine the bit fields
      checkMessageAckStatus(Helper.toUShort(_lastAckedSeqID - 16),
          leftBit); // Check the ack status of the oldest sequence ID in the bitfield
    }
  }

  /// Check the ack status of the given sequence ID.
  ///
  /// [sequenceID] : The sequence ID whose ack status to check.
  /// [bit] : The bit corresponding to the sequence ID's position in the bit field.
  void checkMessageAckStatus(int sequenceID, int bit) {
    if ((_ackedMessagesBitfield & bit) == 0) {
      // Message was lost
      if (pendingMessages.containsKey(sequenceID)) {
        pendingMessages[sequenceID]!.retrySend();
      }
    } else {
      // Message was successfully delivered
      if (pendingMessages.containsKey(sequenceID)) {
        pendingMessages[sequenceID]!.clear();
      }
    }
  }

  /// Immediately marks the <see cref="PendingMessage"/> of a given sequence ID as delivered.
  ///
  /// [seqID] : The sequence ID that was acknowledged.
  ackMessage(int seqID) {
    if (pendingMessages.containsKey(seqID)) {
      pendingMessages[seqID]!.clear();
    }
  }

  /// Puts the connection in the pending state.
  void setPending() {
    if (isConnecting()) {
      _state = ConnectionState.pending;
      resetTimeout();
    }
  }

  // #region Messages

  /// Sends an ack message for the given sequence ID.
  ///
  /// [forSeqID] : The sequence ID to acknowledge.
  void _sendAck(int forSeqID) {
    Message message = Message.createFromHeader(forSeqID == _lastReceivedSeqID
        ? MessageHeader.ack
        : MessageHeader.ackExtra);
    message.addUShort(_lastReceivedSeqID); // Last remote sequence ID
    message.addUShort(_acksBitfield); // Acks

    if (forSeqID != _lastReceivedSeqID) {
      message.addUShort(forSeqID);
    }

    sendMessage(message);
  }

  /// Handles an ack message.
  ///
  /// [message] : The ack message to handle.
  void handleAck(Message message) {
    int remoteLastReceivedSeqID = message.getUShort();
    int remoteAcksBitField = message.getUShort();

    ackMessage(
        remoteLastReceivedSeqID); // Immediately mark it as delivered so no resends are triggered while waiting for the sequence ID's bit to reach the end of the bit field
    updateReceivedAcks(remoteLastReceivedSeqID, remoteAcksBitField);
  }

  /// Handles an ack message for a sequence ID other than the last received one.
  ///
  /// [message] : The ack message to handle.
  void handleAckExtra(Message message) {
    int remoteLastReceivedSeqId = message.getUShort();
    int remoteAcksBitField = message.getUShort();
    int ackedSeqId = message.getUShort();

    ackMessage(
        ackedSeqId); // Immediately mark it as delivered so no resends are triggered while waiting for the sequence ID's bit to reach the end of the bit field
    updateReceivedAcks(remoteLastReceivedSeqId, remoteAcksBitField);
  }

  // #region Server

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
      RiptideLogger.log2(LogType.error, peer!.logName,
          "Client has assumed ID $id instead of ${this.id}!");
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
  void respondHeartbeat(int pingId) {
    Message message = Message.createFromHeader(MessageHeader.heartbeat);
    message.addByte(pingId);

    sendMessage(message);
  }
  // #endregion

  // #region Client

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
    int pingId = message.getByte();

    if (_pendingPingID == pingId) {
      rtt = max(1, pendingPingStopwatch.elapsedMilliseconds);
    }

    resetTimeout();
  }
  // #endregion
  // #endregion
}
