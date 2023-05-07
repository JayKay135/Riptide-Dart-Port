import 'utils/_constants.dart';

/// Provides functionality for enabling/disabling automatic message relaying by message type.
class MessageRelayFilter<T extends Enum> {
  /// The number of bits an int consists of.
  int get _bitsPerInt => Constants.intBytes * 8;

  /// A list storing all the bits which represent whether messages of a given ID should be relayed or not.
  late List<int> _filter;

  /// Creates a filter of a given size.
  /// [size] : How big to make the filter.
  ///
  /// [size] should be set to the value of the largest message ID, plus 1. For example, if a server will
  /// handle messages with IDs 1, 2, 3, 7, and 8, [size] should be set to 9 (8 is the largest possible value,
  /// and 8 + 1 = 9) despite the fact that there are only 5 unique message IDs the server will ever handle.
  MessageRelayFilter(int size) {
    _set(size);
  }

  /// Creates a filter based on an enum of message IDs.
  ///
  /// [idEnum] : The enum type.
  MessageRelayFilter.fromType(Type idEnum) {
    _set(_getSizeFromEnum(idEnum));
  }

  /// Creates a filter of a given size and enables relaying for the given message IDs.
  ///
  /// [size] : How big to make the filter.
  /// [idsToEnable] : Message IDs to enable auto relaying for.
  /// [size] should be set to the value of the largest message ID, plus 1. For example, if a server will
  /// handle messages with IDs 1, 2, 3, 7, and 8, [size] should be set to 9 (8 is the largest possible value,
  /// and 8 + 1 = 9) despite the fact that there are only 5 unique message IDs the server will ever handle.
  MessageRelayFilter.fromSize(int size, List<int> idsToEnable) {
    _set(size);
    enableIds(idsToEnable);
  }

  /// Creates a filter based on an enum of message IDs and enables relaying for the given message IDs.
  ///
  /// [idEnum] : The enum type.
  /// [idsToEnable] : Message IDs to enable relaying for.
  MessageRelayFilter.fromType2(Type idEnum, List<T> idsToEnable) {
    _set(_getSizeFromEnum(idEnum));
    enableIds(idsToEnable.map((e) => e.index).toList());
  }

  /// Enables auto relaying for the given message IDs.
  ///
  /// [idsToEnable] : Message IDs to enable relaying for.
  void enableIds(List<int> idsToEnable) {
    for (int i = 0; i < idsToEnable.length; i++) {
      enableRelay(idsToEnable[i]);
    }
  }

  /// Calculate the filter size necessary to manage all message IDs in the given enum.
  ///
  /// [idEnum] : The enum type.
  /// Returns the appropriate filter size.
  int _getSizeFromEnum<T>(Type idEnum) {
    if (idEnum is! Enum) {
      throw ArgumentError("Parameter '($idEnum)' must be an enum type!");
    }

    return ((idEnum as Enum) as List).length;
  }

  /// Sets the filter size.
  ///
  /// [size] : How big to make the filter.
  void _set(int size) {
    _filter = List<int>.filled((size / _bitsPerInt + (size % _bitsPerInt > 0 ? 1 : 0)).toInt(), 0);
  }

  /// Enables auto relaying for the given message ID.
  ///
  /// [forMessageID] : The message ID to enable relaying for.
  void enableRelay(int forMessageID) {
    _filter[forMessageID ~/ _bitsPerInt] |= 1 << (forMessageID % _bitsPerInt);
  }

  void enableRelay2(Enum forMessageID) => enableRelay(forMessageID.index);

  /// Disables auto relaying for the given message ID.
  ///
  /// [forMessageID] : The message ID to enable relaying for.
  void disableRelay(int forMessageID) {
    _filter[forMessageID ~/ _bitsPerInt] &= ~(1 << (forMessageID % _bitsPerInt));
  }

  void disableRelay2(Enum forMessageID) => disableRelay(forMessageID.index);

  /// Checks whether or not messages with the given ID should be relayed.
  ///
  /// [forMessageID] : The message ID to check.
  /// Returns whether or not messages with the given ID should be relayed.
  bool shouldRelay(int forMessageID) {
    return (_filter[forMessageID ~/ _bitsPerInt] & (1 << (forMessageID % _bitsPerInt))) != 0;
  }
}
