import 'dart:core';
import 'dart:math';

import 'constants.dart';

/// Provides functionality for managing and manipulating a collection of bits.
class Bitfield {
  /// The first 8 bits stored in the bitfield.
  int get first8 => segments[0];

  /// The first 16 bits stored in the bitfield.
  int get first16 => segments[0];

  /// The number of bits which fit into a single segment.
  final int _segmentSize = Constants.uintBytes * 8;

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
    segments = List<int>.filled(4, 0, growable: false); //new List<uint>(4) { 0 };
    _capacity = segments.length * _segmentSize;
    _isDynamicCapacity = isDynamicCapacity;
  }

  /// Checks if the bitfield has capacity for the given number of bits.
  ///
  /// [amount] : The number of bits for which to check if there is capacity.
  /// Whether or not there is sufficient capacity and the number of bits from [amount] which there is no capacity for.
  (bool hasCapacity, int overflow) hasCapacityFor(int amount) {
    int overflow = _count + amount - _capacity;
    return (overflow < 0, overflow);
  }

  /// Shifts the bitfield by the given amount.
  ///
  /// [amount] : How much to shift by.
  void shiftBy(int amount) {
    int segmentShift = (amount / _segmentSize).floor(); // How many WHOLE segments we have to shift by
    int bitShift = amount % _segmentSize; // How many bits we have to shift by

    if (!_isDynamicCapacity) {
      _count = min(_count + amount, _segmentSize);
    } else if (!hasCapacityFor(amount).$1) {
      _trim();
      _count += amount;

      if (_count > _capacity) {
        int increaseBy = segmentShift + 1;
        for (int i = 0; i < increaseBy; i++) segments.add(0);

        _capacity = segments.length * _segmentSize;
      }
    } else {
      _count += amount;
    }

    int s = segments.length - 1;
    segments[s] <<= bitShift;
    s -= 1 + segmentShift;
    while (s > -1) {
      // IMPORTANT: shiftedBits does originally is of type ulong => Which has a size of 64bits in C#
      // the int type in dart does also has a size of 64bits, but this does include the negative numbers too
      int shiftedBits = segments[s] << bitShift;
      segments[s] = shiftedBits;

      segments[s + 1 + segmentShift] |= (shiftedBits >> _segmentSize);
      s--;
    }
  }

  /// Checks the last bit in the bitfield, and trims it if it is set to 1.
  ///
  /// Returns whether or not the checked bit was set and the checked bit's position in the bitfield.
  (bool isSet, int checkedPosition) checkAndTrimLast() {
    int checkedPosition = _count;
    int bitToCheck = (1 << ((_count - 1) % _segmentSize));
    bool isSet = (segments[segments.length - 1] & bitToCheck) != 0;
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
  /// Throws RangeError if [bit] is less than 1.
  void set(int bit) {
    if (bit < 1) {
      throw RangeError("'${bit}' must be greater than zero!");
    }

    bit--;
    int s = (bit / _segmentSize).floor();
    int bitToSet = (1 << (bit % _segmentSize));
    if (s < segments.length) {
      segments[s] |= bitToSet;
    }
  }

  /// Checks if the given bit is set to 1.
  ///
  /// [bit] : The bit to check.
  /// Returns whether or not the bit is set.
  /// Throws RangeError if [bit] is less than 1.
  bool isSet(int bit) {
    if (bit > _count) {
      return true;
    }

    if (bit < 1) {
      throw RangeError("'${bit}' must be greater than zero!");
    }

    bit--;
    int s = (bit / _segmentSize).floor();
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
    segments[0] |= other;
  }
}
