import '../peer.dart';
import 'constants.dart';

// NOTE: Checked

/// Contains miscellaneous helper methods.
class Helper {
  /// The text to log when disconnected due to [DisconnectReason.neverConnected].
  static const String _dcNeverConnected = "Never connected";

  /// The text to log when disconnected due to [DisconnectReason.transportError].
  static const String _dcTransportError = "Transport error";

  /// The text to log when disconnected due to [DisconnectReason.timedOut].
  static const String _dcTimedOut = "Timed out";

  /// The text to log when disconnected due to [DisconnectReason.kicked].
  static const String _dcKicked = "Kicked";

  /// The text to log when disconnected due to [DisconnectReason.serverStopped].
  static const String _dcServerStopped = "Server stopped";

  /// The text to log when disconnected due to [DisconnectReason.disconnected].
  static const String _dcDisconnected = "Disconnected";

  /// The text to log when disconnected due to [DisconnectReason.poorConnection].
  static const String _dcPoorConnection = "Poor connection";

  /// The text to log when disconnected or rejected due to an unknown reason.
  static const String _unknownReason = "Unknown reason";

  /// The text to log when the connection failed due to [RejectReason.noConnection].
  static const String _crNoConnection = "No connection";

  /// The text to log when the connection failed due to [RejectReason.alreadyConnected].
  static const String _crAlreadyConnected = "This client is already connected";

  /// The text to log when the connection failed due to [RejectReason.serverFull].
  static const String _crServerFull = "Server is full";

  /// The text to log when the connection failed due to [RejectReason.rejected].
  static const String _crRejected = "Rejected";

  /// The text to log when the connection failed due to [RejectReason.custom].
  static const String _crCustom = "Rejected (with custom data)";

  /// Determines whether [singular] or [plural] form should be used based on the [amount].
  ///
  /// [amount] : The amount that [singular] and [plural] refer to.
  /// [singular] : The singular form.
  /// [plural] : The plural form.
  /// Returns [singular] if [amount] is 1; otherwise [plural].
  static String correctForm(int amount, String singular, {String? plural = ""}) {
    if (plural == null || plural == "") {
      plural = "${singular}s";
    }

    return amount == 1 ? singular : plural;
  }

  /// Calculates the signed gap between sequence IDs, accounting for wrapping.
  ///
  /// [seqId1] : The new sequence ID.
  /// [seqId2] : The previous sequence ID.
  /// Returns the signed gap between the two given sequence IDs.
  /// A positive gap means [seqId1] is newer than [seqId2].
  /// A negative gap means [seqId1] is older than [seqId2].
  static int getSequenceGap(int seqId1, int seqId2) {
    int gap = seqId1 - seqId2;
    if (gap.abs() <= 32768) {
      // Difference is small, meaning sequence IDs are close together
      return gap;
    } else {
      // Difference is big, meaning sequence IDs are far apart
      return (seqId1 <= 32768 ? Constants.ushortMaxVal + 1 + seqId1 : seqId1) - (seqId2 <= 32768 ? Constants.ushortMaxVal + 1 + seqId2 : seqId2);
    }
  }

  /// Retrieves the appropriate reason string for the given [DisconnectReason].
  ///
  /// [forReason] : The [DisconnectReason] to retrieve the string for.
  /// Returns the appropriate reason string.
  static String getDisconnectReasonString(DisconnectReason forReason) {
    switch (forReason) {
      case DisconnectReason.neverConnected:
        return _dcNeverConnected;
      case DisconnectReason.transportError:
        return _dcTransportError;
      case DisconnectReason.timedOut:
        return _dcTimedOut;
      case DisconnectReason.kicked:
        return _dcKicked;
      case DisconnectReason.serverStopped:
        return _dcServerStopped;
      case DisconnectReason.disconnected:
        return _dcDisconnected;
      case DisconnectReason.poorConnection:
        return _dcPoorConnection;
      default:
        return "$_unknownReason '$forReason'";
    }
  }

  /// Retrieves the appropriate reason string for the given [RejectReason].
  ///
  /// [forReason] : The [RejectReason] to retrieve the string for.
  /// Returns the appropriate reason string.
  static String getRejectReasonString(RejectReason forReason) {
    switch (forReason) {
      case RejectReason.noConnection:
        return _crNoConnection;
      case RejectReason.alreadyConnected:
        return _crAlreadyConnected;
      case RejectReason.serverFull:
        return _crServerFull;
      case RejectReason.rejected:
        return _crRejected;
      case RejectReason.custom:
        return _crCustom;
      default:
        return "$_unknownReason '$forReason'";
    }
  }

  /// Converts an integer (also negatives) to the range of a two byte ushort
  ///
  /// [value] : Int value with possible range greater than 2 bytes
  static int toUShort(int value) {
    return value & 0xffff;
  }

  /// Converts an integer (also negatives) to the range of a byte
  ///
  /// [value] : Int value with possible range greater than 1 byte
  static int toByte(int value) {
    return value & 0xff;
  }
}
