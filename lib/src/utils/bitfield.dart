import 'dart:core';
import 'dart:math';

import 'constants.dart';

// ignore: unused_import
import '../connection.dart'; // Referenced by the documentation

/// Provides functionality for managing and manipulating a collection of bits.
class Bitfield {
  /// The first 8 bits stored in the bitfield.
  int get first8 => segments[0] & 0xFF;

  /// The first 16 bits stored in the bitfield.
  int get first16 => segments[0] & 0xFFFF;

  /// The number of bits which fit into a single segment.
  final int _segmentSize = Constants.uintBytes * 8;

  /// The maximum number of segments a dynamic capacity bitfield may grow to.
  ///
  /// This determines how far back duplicates can be filtered out, so it must comfortably exceed the number of messages
  /// which may be sent in the time it takes a reliable message to be resent [Connection.maxSendAttempts] times.
  static const int _maxSegments = 32;

  /// A mask which only keeps the bits that fit into a single segment.
  ///
  /// NOTE: The segments are uints in C#, so values are truncated to 32 bits automatically, which Dart ints aren't.
  static const int _segmentMask = 0xFFFFFFFF;

  /// The segments of the bitfield.
  late List<int> segments;

  /// Whether or not the bitfield's capacity should dynamically adjust when shifting.
  late bool _isDynamicCapacity;

  /// The current number of bits being stored.
  int _count = 0;

  /// The current capacity.
  late int _capacity;

  /// Creates a bitfield.
  ///
  /// [isDynamicCapacity] : Whether or not the bitfield's capacity should dynamically adjust when shifting.
  Bitfield({bool isDynamicCapacity = true}) {
    segments = <int>[0];
    _capacity = segments.length * _segmentSize;
    _isDynamicCapacity = isDynamicCapacity;
  }

  /// Checks if the bitfield has capacity for the given number of bits.
  ///
  /// [amount] : The number of bits for which to check if there is capacity.
  ///
  /// Returns whether or not there is sufficient capacity and the number of bits which are currently in use and would be
  /// pushed out of the bitfield (the overflow).
  (bool hasCapacity, int overflow) hasCapacityFor(int amount) {
    int overflow = min(_count + amount - _capacity, _count);
    return (overflow < 0, overflow);
  }

  /// Shifts the bitfield by the given amount.
  ///
  /// [amount] : How much to shift by.
  ///
  /// Returns whether or not any untrimmed bits were discarded because the bitfield is at its maximum capacity.
  bool shiftBy(int amount) {
    bool discardedBits = false;
    int segmentShift = amount ~/ _segmentSize; // How many WHOLE segments we have to shift by
    int bitShift = amount % _segmentSize; // How many bits we have to shift by

    if (!_isDynamicCapacity) {
      _count = min(_count + amount, _segmentSize);
    } else if (!hasCapacityFor(amount).$1) {
      _trim();
      _count += amount;

      if (_count > _capacity) {
        int increaseBy = min(segmentShift + 1, _maxSegments - segments.length);
        for (int i = 0; i < increaseBy; i++) {
          segments.add(0);
        }

        _capacity = segments.length * _segmentSize;
        if (_count > _capacity) {
          // Trimming stops at the oldest bit which is still unset, so anything pushed out past the maximum
          // capacity includes at least one message that was never received
          _count = _capacity;
          discardedBits = true;
        }
      }
    } else {
      _count += amount;
    }

    // Work from the last segment backwards so that no segment is overwritten before its bits have been moved
    for (int s = segments.length - 1; s > -1; s--) {
      int source = s - segmentShift;
      int shiftedBits = source > -1 ? (segments[source] << bitShift) & _segmentMask : 0;
      if (bitShift > 0 && source > 0) {
        // Carry over the bits shifted out of the previous segment
        shiftedBits |= segments[source - 1] >>> (_segmentSize - bitShift);
      }

      segments[s] = shiftedBits;
    }

    return discardedBits;
  }

  /// Checks the last bit in the bitfield, and trims it if it is set to 1.
  ///
  /// Returns whether or not the checked bit was set and the checked bit's position in the bitfield.
  (bool isSet, int checkedPosition) checkAndTrimLast() {
    int checkedPosition = _count;
    int bit = _count - 1;
    int bitToCheck = (1 << (bit % _segmentSize));
    bool isSet = (segments[bit ~/ _segmentSize] & bitToCheck) != 0;
    _count--;
    return (isSet, checkedPosition);
  }

  /// Trims all bits from the end of the bitfield until an unset bit is encountered.
  void _trim() {
    while (_count > 0 && isSet(_count)) {
      _count--;
    }
  }

  /// Sets the given bit to 1.
  ///
  /// [bit] : The bit to set.
  ///
  /// Throws a [RangeError] if [bit] is less than 1.
  void set(int bit) {
    if (bit < 1) {
      throw RangeError("'$bit' must be greater than zero!");
    }

    bit--;
    int s = bit ~/ _segmentSize;
    int bitToSet = (1 << (bit % _segmentSize));
    if (s < segments.length) {
      segments[s] |= bitToSet;
    }
  }

  /// Checks if the given bit is set to 1.
  ///
  /// [bit] : The bit to check.
  ///
  /// Returns whether or not the bit is set.
  ///
  /// Throws a [RangeError] if [bit] is less than 1.
  bool isSet(int bit) {
    if (bit > _count) {
      return true;
    }

    if (bit < 1) {
      throw RangeError("'$bit' must be greater than zero!");
    }

    bit--;
    int s = bit ~/ _segmentSize;
    int bitToCheck = (1 << (bit % _segmentSize));
    if (s < segments.length) {
      return (segments[s] & bitToCheck) != 0;
    }

    return true;
  }

  /// Combines this bitfield with the given bits.
  ///
  /// [other] : The bits to OR into the bitfield.
  void combine(int other) {
    segments[0] |= other & 0xFFFF; // C# takes a ushort
  }
}
