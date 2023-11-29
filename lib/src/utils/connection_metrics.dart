import 'rolling_stat.dart';
import '../connection.dart';

// NOTE: Checked

/// Tracks and manages various metrics of a [Connection].
class ConnectionMetrics {
  /// The total number of bytes received across all send modes since the last [reset] call, including those in duplicate and, in
  /// the case of notify messages, out-of-order packets. Does not include packet header bytes, which may vary by transport.
  int get bytesIn => unreliableBytesIn + notifyBytesIn + reliableBytesIn;

  /// The total number of bytes sent across all send modes since the last [reset] call, including those in automatic resends.
  /// Does not include packet header bytes, which may vary by transport.
  int get bytesOut => unreliableBytesOut + notifyBytesOut + reliableBytesOut;

  /// The total number of messages received across all send modes since the last [reset] call, including duplicate and out-of-order notify messages.
  int get messagesIn => unreliableIn + notifyIn + reliableIn;

  /// The total number of messages sent across all send modes since the last [reset] call, including automatic resends.
  int get messagesOut => unreliableOut + notifyOut + reliableOut;

  /// The total number of bytes received in unreliable messages since the last [reset] call. Does not include packet header bytes, which may vary by transport.
  late int unreliableBytesIn;

  /// The total number of bytes sent in unreliable messages since the last [reset] call. Does not include packet header bytes, which may vary by transport.
  late int unreliableBytesOut;

  /// The number of unreliable messages received since the last [reset] call.
  late int unreliableIn;

  /// The number of unreliable messages sent since the last [reset] call.
  late int unreliableOut;

  /// The total number of bytes received in notify messages since the last [reset] call, including those in duplicate and out-of-order packets.
  /// Does not include packet header bytes, which may vary by transport.
  late int notifyBytesIn;

  /// The total number of bytes sent in notify messages since the last [reset] call. Does not include packet header bytes, which may vary by transport.
  late int notifyBytesOut;

  /// The number of notify messages received since the last [reset] call, including duplicate and out-of-order ones.
  late int notifyIn;

  /// The number of notify messages sent since the last [reset] call.
  late int notifyOut;

  /// The number of duplicate or out-of-order notify messages which were received, but discarded (not handled) since the last [reset] call.
  late int notifyDiscarded;

  /// The number of notify messages lost since the last [reset] call.
  late int notifyLost;

  /// The number of notify messages delivered since the last [reset] call.
  late int notifyDelivered;

  /// The number of notify messages lost of the last 64 notify messages to be lost or delivered.
  late int rollingNotifyLost;

  /// The number of notify messages delivered of the last 64 notify messages to be lost or delivered.
  late int rollingNotifyDelivered;

  /// The loss rate (0-1) among the last 64 notify messages.
  double get rollingNotifyLossRate => rollingNotifyLost / 64.0;

  /// The total number of bytes received in reliable messages since the last [reset] call, including those in duplicate packets.
  /// Does not include packet header bytes, which may vary by transport.
  late int reliableBytesIn;

  /// The total number of bytes sent in reliable messages since the last [reset] call, including those in automatic resends.
  /// Does not include packet header bytes, which may vary by transport.
  late int reliableBytesOut;

  /// The number of reliable messages received since the last [reset] call, including duplicates.
  late int reliableIn;

  /// The number of reliable messages sent since the last [reset] call, including automatic resends (each resend adds to this value).
  late int reliableOut;

  /// The number of duplicate reliable messages which were received, but discarded (and not handled) since the last [reset] call.
  late int reliableDiscarded;

  /// The number of unique reliable messages sent since the last [reset] call.
  /// A message only counts towards this the first time it is sent—subsequent resends are not counted.
  late int reliableUniques;

  /// The number of send attempts that were required to deliver recent reliable messages.
  late RollingStat _rollingReliableSends;
  RollingStat get rollingReliableSends => _rollingReliableSends;

  /// The left-most bit of a [int] originally ulong in C#, used to store the oldest value in the [_notifyLossTracker].
  final int _uLongLeftBit = 1 << 63;

  /// Which recent notify messages were lost. Each bit corresponds to a message.
  late int _notifyLossTracker;

  /// How many of the [_notifyLossTracker]'s bits are in use.
  late int _notifyBufferCount;

  /// Initializes metrics.
  ConnectionMetrics() {
    reset();
    rollingNotifyDelivered = 0;
    rollingNotifyLost = 0;
    _notifyLossTracker = 0;
    _notifyBufferCount = 0;
    _rollingReliableSends = RollingStat(64);
  }

  /// Resets all non-rolling metrics to 0.
  void reset() {
    unreliableBytesIn = 0;
    unreliableBytesOut = 0;
    unreliableIn = 0;
    unreliableOut = 0;

    notifyBytesIn = 0;
    notifyBytesOut = 0;
    notifyIn = 0;
    notifyOut = 0;
    notifyDiscarded = 0;
    notifyLost = 0;
    notifyDelivered = 0;

    reliableBytesIn = 0;
    reliableBytesOut = 0;
    reliableIn = 0;
    reliableOut = 0;
    reliableDiscarded = 0;
    reliableUniques = 0;
  }

  /// Updates the metrics associated with receiving an unreliable message.
  ///
  /// [byteCount] : The number of bytes that were received.
  void receivedUnreliable(int byteCount) {
    unreliableBytesIn += byteCount;
    unreliableIn++;
  }

  /// Updates the metrics associated with sending an unreliable message.
  ///
  /// [byteCount] : The number of bytes that were sent.
  void sentUnreliable(int byteCount) {
    unreliableBytesOut += byteCount;
    unreliableOut++;
  }

  /// Updates the metrics associated with receiving a notify message.
  ///
  /// [byteCount] : The number of bytes that were received.
  void receivedNotify(int byteCount) {
    notifyBytesIn += byteCount;
    notifyIn++;
  }

  /// Updates the metrics associated with sending a notify message.
  ///
  /// [byteCount] : The number of bytes that were sent.
  void sentNotify(int byteCount) {
    notifyBytesOut += byteCount;
    notifyOut++;
  }

  /// Updates the metrics associated with delivering a notify message.
  void deliveredNotify() {
    notifyDelivered++;

    if (_notifyBufferCount < 64) {
      rollingNotifyDelivered++;
      _notifyBufferCount++;
    } else if ((_notifyLossTracker & _uLongLeftBit) == 0) {
      // The one being removed from the buffer was not delivered
      rollingNotifyDelivered++;
      rollingNotifyLost--;
    }

    _notifyLossTracker <<= 1;
    _notifyLossTracker |= 1;
  }

  /// Updates the metrics associated with losing a notify message.
  void lostNotify() {
    notifyLost++;

    if (_notifyBufferCount < 64) {
      rollingNotifyLost++;
      _notifyBufferCount++;
    } else if ((_notifyLossTracker & _uLongLeftBit) != 0) {
      // The one being removed from the buffer was delivered
      rollingNotifyDelivered--;
      rollingNotifyLost++;
    }

    _notifyLossTracker <<= 1;
  }

  /// Updates the metrics associated with receiving a reliable message.
  ///
  /// [byteCount] : The number of bytes that were received.
  void receivedReliable(int byteCount) {
    reliableBytesIn += byteCount;
    reliableIn++;
  }

  /// Updates the metrics associated with sending a reliable message.
  ///
  /// [byteCount] : The number of bytes that were sent.
  void sentReliable(int byteCount) {
    reliableBytesOut += byteCount;
    reliableOut++;
  }
}
