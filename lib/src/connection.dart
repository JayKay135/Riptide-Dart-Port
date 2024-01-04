import 'dart:core';
import 'dart:math';
import 'dart:typed_data';

import 'message.dart';
import 'peer.dart';
import 'pending_message.dart';
import 'utils/bitfield.dart';
import 'utils/connection_metrics.dart';
import 'utils/converter.dart';
import 'utils/event_handler.dart';
import 'utils/helper.dart';
import 'utils/riptide_logger.dart';
import 'transports/ipeer.dart';

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
}

/// Represents a connection to a Server or Client.
abstract class Connection {
  /// Invoked when the notify message with the given sequence ID is successfully delivered.
  Event<int>? notifyDelivered;

  /// Invoked when the notify message with the given sequence ID is lost.
  Event<int>? notifyLost;

  /// Invoked when a notify message is received.
  Event<Message>? notifyReceived;

  /// Invoked when the reliable message with the given sequence ID is successfully delivered.
  Event<int>? reliableDelivered;

  /// The connection's numeric ID.
  int id = 0;

  /// Whether or not the connection is currently <i>not</i> trying to connect, pending, nor actively connected.
  bool get isNotConnected => _state == ConnectionState.notConnected;

  /// Whether or not the connection is currently in the process of connecting.
  bool get isConnecting => _state == ConnectionState.connecting;

  /// Whether or not the connection is currently pending (waiting to be accepted/rejected by the server).
  bool get isPending => _state == ConnectionState.pending;

  /// Whether or not the connection is currently connected.
  bool get isConnected => _state == ConnectionState.connected;

  /// The round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  late int _rtt;

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
  late int _smoothRtt;

  /// Returns the smoothed round trip time (ping) of the connection, in milliseconds. -1 if not calculated yet.
  ///
  /// This value is slower to accurately represent lasting changes in latency than rtt, but it is less susceptible to
  /// changing drastically due to significant—but temporary—jumps in latency.
  int get smoothRtt => _smoothRtt;

  /// The time (in milliseconds) after which to disconnect if no heartbeats are received.
  late int timeoutTime;

  /// Whether or not the connection can time out.
  late bool _canTimeout;

  /// Returnns whether or not the connection can time out.
  bool get canTimeout => _canTimeout;

  /// Sets whether or not the connection can time out.
  set canTimeout(bool value) {
    if (value) {
      resetTimeout();
    }

    _canTimeout = value;
  }

  /// Whether or not the connection can disconnect due to poor connection quality.
  ///
  /// When this is set to false, [maxAvgSendAttempts], [maxSendAttempts],
  /// and [maxNotifyLoss] are ignored and exceeding their values will not trigger a disconnection.
  late bool canQualityDisconnect;

  /// The connection's metrics.
  late ConnectionMetrics _metrics;
  ConnectionMetrics get metrics => _metrics;

  /// The maximum acceptable average number of send attempts it takes to deliver a reliable message. The connection will be closed if this is exceeded more than [AvgSendAttemptsResilience] times in a row.
  late int maxAvgSendAttempts;

  /// How many consecutive times [maxAvgSendAttempts] can be exceeded before triggering a disconnect.
  late int avgSendAttemptsResilience;

  /// The absolute maximum number of times a reliable message may be sent. A single message reaching this threshold will cause a disconnection.
  late int maxSendAttempts;

  /// The maximum acceptable loss rate of notify messages. The connection will be closed if this is exceeded more than [notifyLossResilience] times in a row.
  late double maxNotifyLoss;

  /// How many consecutive times [maxNotifyLoss] can be exceeded before triggering a disconnect.
  late int notifyLossResilience;

  /// The local peer this connection is associated with.
  late Peer peer;

  /// Whether or not the connection has timed out.
  bool get hasTimedOut => _canTimeout && peer.currentTime - _lastHeartbeat > timeoutTime;

  /// Whether or not the connection attempt has timed out. Uses a multiple of timeoutTime and ignores the value of canTimeout.
  bool get hasConnectAttemptTimedOut => peer.currentTime - _lastHeartbeat > peer.connectTimeoutTime;

  /// The sequencer for notify messages.
  late NotifySequencer _notify;

  /// The sequencer for reliable messages.
  late ReliableSequencer _reliable;

  /// The currently pending reliably sent messages whose delivery has not been acknowledged yet. Stored by sequence ID.
  Map<int, PendingMessage> pendingMessages = {};

  /// Whether or not the connection is currently not trying to connect, pending, nor actively connected.
  late ConnectionState _state;

  /// The number of consecutive times that the [maxAvgSendAttempts] threshold was exceeded.
  int _sendAttemptsViolations = 0;

  ///The number of consecutive times that the [maxNotifyLoss] threshold was exceeded.
  int _lossRateViolations = 0;

  // late DateTime _lastHeartbeat;
  int _lastHeartbeat = 0;

  /// The ID of the last ping that was sent.
  late int _lastPingID = 0;

  /// The ID of the currently pending ping.
  late int _pendingPingID;

  /// The time at which the currently pending ping was sent.
  late int _pendingPingSendTime;

  /// Initializes the connection.
  Connection() {
    _metrics = ConnectionMetrics();
    _notify = NotifySequencer(this);
    _reliable = ReliableSequencer(this);
    _state = ConnectionState.connecting;
    _rtt = -1;
    _smoothRtt = -1;
    _canTimeout = true;
    canQualityDisconnect = true;
    maxAvgSendAttempts = 5;
    avgSendAttemptsResilience = 64;
    maxSendAttempts = 15;
    maxNotifyLoss = 0.05; // 5%
    notifyLossResilience = 64;
    pendingMessages = {};
  }

  /// Initializes connection data.
  ///
  /// [peer] : The [Peer] which this connection belongs to.
  /// [timeoutTime] : The timeout time.
  void initialize(Peer peer, int timeoutTime) {
    this.peer = peer;
    this.timeoutTime = timeoutTime;
  }

  /// Resets the connection's timeout time.
  void resetTimeout() {
    _lastHeartbeat = peer.currentTime;
  }

  /// Sends a message.
  ///
  /// [message] : The message to send.
  /// [shouldRelease] : Whether or not to return the message to the pool after it is sent.
  ///
  /// Returns for reliable and notify messages, the sequence ID that the message was sent with. 0 for unreliable messages.
  ///
  ///  If you intend to continue using the message instance after calling this method, you must set [shouldRelease] to false.
  /// [Message.release] can be used to manually return the message to the pool at a later time.
  int sendMessage(Message message, [bool shouldRelease = true]) {
    int sequenceID = 0;

    if (message.sendMode == MessageSendMode.notify) {
      sequenceID = _notify.insertHeader(message);
      int byteAmount = message.bytesInUse;
      Helper.blockCopyReversed(message.data, 0, Message.byteBuffer, 0, byteAmount);
      send(Message.byteBuffer.buffer.asUint8List(), byteAmount);
      _metrics.sentNotify(byteAmount);
    } else if (message.sendMode == MessageSendMode.unreliable) {
      int byteAmount = message.bytesInUse;
      Helper.blockCopyReversed(message.data, 0, Message.byteBuffer, 0, byteAmount);
      send(Message.byteBuffer.buffer.asUint8List(), byteAmount);
      _metrics.sentUnreliable(byteAmount);
    } else {
      sequenceID = _reliable.nextSequenceID;
      PendingMessage pendingMessage = PendingMessage.create(sequenceID, message, this);
      pendingMessages[sequenceID] = pendingMessage;
      pendingMessage.trySend();
      _metrics.reliableUniques++;
    }

    if (shouldRelease) {
      message.release();
    }

    return sequenceID;
  }

  /// Sends data.
  ///
  /// [dataBuffer] : The array containing the data.
  /// [amount] : The number of ints in the array which should be sent.
  void send(Uint8List dataBuffer, int amount);

  /// Processes a notify message.
  ///
  /// [dataBuffer] : The received data.
  /// [amount] : The number of bytes that were received.
  /// [message] : The message instance to use.
  void processNotify(Uint8List dataBuffer, int amount, Message message) {
    _notify.updateReceivedAcks(Converter.uShortFromByteBits(dataBuffer, Message.headerBits), Converter.byteFromByteBits(dataBuffer, Message.headerBits + 16));

    _metrics.receivedNotify(amount);
    if (_notify.shouldHandle(Converter.uShortFromByteBits(dataBuffer, Message.headerBits + 24))) {
      Helper.blockCopy(dataBuffer, 1, message.data, 1, amount - 1); // Copy payload
      notifyReceived?.invoke(message);
    } else {
      _metrics.notifyDiscarded++;
    }
  }

  /// Determines if the message with the given sequence ID should be handled.
  ///
  /// [sequenceID] : The message's sequence ID.
  /// Whether or not the message should be handled.
  bool shouldHandle(int sequenceID) {
    return _reliable.shouldHandle(sequenceID);
  }

  /// Cleans up the local side of the connection.
  ///
  /// [wasRejected] : Whether or not the connection was rejected.
  void localDisconnect({bool wasRejected = false}) {
    _state = ConnectionState.notConnected;

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
      _updateSendAttemptsViolations();
    }
  }

  /// Puts the connection in the pending state.
  void setPending() {
    if (isConnecting) {
      _state = ConnectionState.pending;
      resetTimeout();
    }
  }

  /// Checks the average send attempts (of reliable messages) and updates [_sendAttemptsViolations] accordingly.
  void _updateSendAttemptsViolations() {
    if (_metrics.rollingReliableSends.mean > maxAvgSendAttempts) {
      _sendAttemptsViolations++;
      if (_sendAttemptsViolations >= avgSendAttemptsResilience) {
        peer.disconnectConnection(this, DisconnectReason.poorConnection);
      }
    } else {
      _sendAttemptsViolations = 0;
    }
  }

  /// Checks the loss rate (of notify messages) and updates [_lossRateViolations] accordingly.
  void _updateLossViolations() {
    if (_metrics.rollingNotifyLossRate > maxNotifyLoss) {
      _lossRateViolations++;
      if (_lossRateViolations >= notifyLossResilience) {
        peer.disconnectConnection(this, DisconnectReason.poorConnection);
      }
    } else {
      _lossRateViolations = 0;
    }
  }

  /// Sends an ack message for the given sequence ID.
  ///
  /// [forSeqID] : The sequence ID to acknowledge.
  /// [lastReceivedSeqID] : The sequence ID of the latest message we've received.
  /// [receivedSeqIDs] : Sequence IDs of previous messages that we have (or have not received).
  void _sendAck(int forSeqID, int lastReceivedSeqID, Bitfield receivedSeqIDs) {
    Message message = Message.createFromHeader(MessageHeader.ack);
    message.addUShort(lastReceivedSeqID);
    message.addUShort(receivedSeqIDs.first16);

    if (forSeqID == lastReceivedSeqID) {
      message.addBool(false);
    } else {
      message.addBool(true);
    }

    message.addUShort(forSeqID);

    sendMessage(message);
  }

  /// Handles an ack message.
  ///
  /// [message] : The ack message to handle.
  void handleAck(Message message) {
    int remoteLastReceivedSeqID = message.getUShort();
    int remoteAcksBitField = message.getUShort();
    int ackedSeqID = message.getBool() ? message.getUShort() : remoteLastReceivedSeqID;

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
  bool handleWelcomeResponse(Message message) {
    if (!isPending) {
      return false;
    }

    int id = message.getUShort();
    if (this.id != id) {
      RiptideLogger.logWithLogName(LogType.error, peer.logName, "client has assumed ID $id instead of ${this.id}!");
    }

    _state = ConnectionState.connected;
    resetTimeout();
    return true;
  }

  /// Handles a heartbeat message.
  ///
  /// [message] : The heartbeat message to handle.
  void handleHeartbeat(Message message) {
    if (!isConnected) {
      return; // A client that is not yet fully connected should not be sending heartbeats
    }

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
    _pendingPingSendTime = peer.currentTime;

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
      rtt = max(1, peer.currentTime - _pendingPingSendTime);
    }

    resetTimeout();
  }

  /// Invokes the [notifyDelivered] event.
  ///
  /// [sequenceId] : The sequence ID of the delivered message.
  void onNotifyDelivered(int sequenceId) {
    _metrics.deliveredNotify();
    notifyDelivered?.invoke(sequenceId);
    _updateLossViolations();
  }

  /// Invokes the [notifyLost] event.
  ///
  /// [sequenceId] : The sequence ID of the lost message.
  void onNotifyLost(int sequenceId) {
    _metrics.lostNotify();
    notifyLost?.invoke(sequenceId);
    _updateLossViolations();
  }
}

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
  ///
  /// [connection] : The connection this sequencer belongs to.
  Sequencer(Connection connection) {
    _connection = connection;
  }

  /// Determines whether or not to handle a message with the given sequence ID.
  ///
  /// [sequenceID] : The sequence ID in question.
  ///
  /// Returns whether or not to handle the message.
  bool shouldHandle(int sequenceID);

  /// Updates which messages we've received acks for.
  ///
  /// [remoteLastReceivedSeqID] : The latest sequence ID that the other end has received.
  /// [remoteReceivedSeqIDs] : Sequence IDs which the other end has (or has not) received.
  void updateReceivedAcks(int remoteLastReceivedSeqID, int remoteReceivedSeqIDs);
}

/// Provides functionality for filtering out duplicate messages and determining delivery/loss status.
class NotifySequencer extends Sequencer {
  /// Initializes the sequencer.
  ///
  /// [connection] : The connection this sequencer belongs to.
  NotifySequencer(Connection connection) : super(connection);

  /// Inserts the notify header into the given message.
  ///
  /// [message] : The message to insert the header into.
  ///
  /// Returns the sequence ID of the message.
  int insertHeader(Message message) {
    int sequenceId = nextSequenceID;
    int notifyBits = lastReceivedSeqID | (receivedSeqIDs.first8 << (2 * Converter.bitsPerByte)) | (sequenceId << (3 * Converter.bitsPerByte));
    message.setBits(notifyBits, 5 * Converter.bitsPerByte, Message.headerBits);
    return sequenceId;
  }

  /// Duplicate and out of order messages are filtered out and not handled.
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
            _connection.onNotifyLost(lastAckedSeqID);
          } else {
            _connection.onNotifyDelivered(lastAckedSeqID);
          }
        }
      }

      lastAckedSeqID = remoteLastReceivedSeqID;
      _connection.onNotifyDelivered(lastAckedSeqID);
    }
  }
}

/// Provides functionality for filtering out duplicate messages and determining delivery/loss status.
class ReliableSequencer extends Sequencer {
  /// Initializes the sequencer.
  ///
  /// [connection] : The connection this sequencer belongs to.
  ReliableSequencer(Connection connection) : super(connection);

  /// Duplicate messages are filtered out while out of order messages are handled.
  @override
  bool shouldHandle(int sequenceID) {
    bool doHandle = false;
    int sequenceGap = Helper.getSequenceGap(sequenceID, lastReceivedSeqID);

    if (sequenceGap != 0) {
      // The received sequence ID is different from the previous one
      if (sequenceGap > 0) {
        // The received sequence ID is newer than the previous one
        if (sequenceGap > 64) {
          RiptideLogger.logWithLogName(LogType.warning, _connection.peer.logName, "The gap between received sequence IDs was very large ($sequenceGap)!");
        }

        receivedSeqIDs.shiftBy(sequenceGap);
        lastReceivedSeqID = sequenceID;
      } else {
        // The received sequence ID is older than the previous one (out of order message)
        sequenceGap = -sequenceGap;
      }

      doHandle = !receivedSeqIDs.isSet(sequenceGap);
      receivedSeqIDs.set(sequenceGap);
    }

    _connection._sendAck(sequenceID, lastReceivedSeqID, receivedSeqIDs);
    return doHandle;
  }

  /// Updates which messages we've received acks for.
  ///
  /// [remoteLastReceivedSeqID] : The latest sequence ID that the other end has received.
  /// [remoteReceivedSeqIDs] : Sequence IDs which the other end has (or has not) received.
  @override
  void updateReceivedAcks(int remoteLastReceivedSeqID, int remoteReceivedSeqIDs) {
    int sequenceGap = Helper.getSequenceGap(remoteLastReceivedSeqID, lastAckedSeqID);

    if (sequenceGap > 0) {
      // The latest sequence ID that the other end has received is newer than the previous one
      var (bool hasCapacity, int overflow) = ackedSeqIDs.hasCapacityFor(sequenceGap);
      if (!hasCapacity) {
        for (int i = 0; i < overflow; i++) {
          // Resend those messages which haven't been acked and whose sequence IDs are about to be pushed out of the bitfield
          var (bool isSet, int checkedPosition) = ackedSeqIDs.checkAndTrimLast();
          if (!isSet) {
            _connection._resendMessage(Helper.toUShort(lastAckedSeqID - checkedPosition));
          } else {
            _connection.clearMessage(Helper.toUShort(lastAckedSeqID - checkedPosition));
          }
        }
      }

      ackedSeqIDs.shiftBy(sequenceGap);
      lastAckedSeqID = remoteLastReceivedSeqID;

      for (int i = 0; i < 16; i++) {
        // Clear any messages that have been newly acknowledged
        if (!ackedSeqIDs.isSet(i + 1) && (remoteReceivedSeqIDs & (1 << i)) != 0) {
          _connection.clearMessage(Helper.toUShort(lastAckedSeqID - (i + 1)));
        }
      }

      ackedSeqIDs.combine(remoteReceivedSeqIDs);
      ackedSeqIDs.set(sequenceGap); // Ensure that the bit corresponding to the previous ack is set
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
