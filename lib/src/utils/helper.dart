import 'constants.dart';

/// Contains miscellaneous helper methods.
class Helper {
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
