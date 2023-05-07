import 'dart:typed_data';

class Converter {
  static const Endian endian = Endian.little;

  /// Converts a given int [value] representing a short to bytes and writes them to given [data].
  ///
  /// The [startIndex] marks the position in the [data] at which to write the bytes.
  /// As dart does not offer an equivalent short type like C# the lower 16 bit of the standard int type are used
  static void fromShort(int value, ByteData data, int startIndex) {
    // if (endian == Endian.big) {
    //   list[startIndex + 1] = value;
    //   list[startIndex] = (value >> 8);
    // } else {
    //   list[startIndex] = (value);
    //   list[startIndex + 1] = (value >> 8);
    // }
    data.setInt16(startIndex, value, endian);
  }

  /// Converst the 2 bytes in the list at [startIndex] to int representing a short
  static int toShort(ByteData data, int startIndex) {
    return data.getInt16(startIndex, endian);
  }

  /// Converts a given int [value] representing a short to bytes and writes them to given [data].
  ///
  /// The [startIndex] marks the position in the [data] at which to write the bytes.
  /// As dart does not offer an equivalent ushort type like C# the lower 16 bit of the standard int type are used
  static void fromUShort(int value, ByteData data, int startIndex) {
    data.setUint16(startIndex, value, endian);
  }

  /// Converts the 2 bytes in the list at [startIndex] to int representing a ushort
  static int toUShort(ByteData data, int startIndex) {
    return data.getUint16(startIndex, endian);
  }

  /// Converts a given int [value] to bytes and writes them to given [data].
  ///
  /// The [startIndex] marks the position in the [data] at which to write the bytes.
  static void fromInt(int value, ByteData data, int startIndex) {
    // if (endian == Endian.big) {
    //   list[startIndex + 3] = value;
    //   list[startIndex + 2] = (value >> 8);
    //   list[startIndex + 1] = (value >> 16);
    //   list[startIndex] = (value >> 24);
    // } else {
    //   list[startIndex] = value;
    //   list[startIndex + 1] = (value >> 8);
    //   list[startIndex + 2] = (value >> 16);
    //   list[startIndex + 3] = (value >> 24);
    // }
    data.setInt32(startIndex, value, endian);
  }

  /// Converts the 4 bytes in the list at [startIndex] to an int
  static int toInt(ByteData data, int startIndex) {
    // if (endian == Endian.big) {
    //   return list[startIndex + 3] |
    //       (list[startIndex + 2] << 8) |
    //       (list[startIndex + 1] << 16) |
    //       (list[startIndex] << 24);
    // } else {
    //   return list[startIndex] |
    //       (list[startIndex + 1] << 8) |
    //       (list[startIndex + 2] << 16) |
    //       (list[startIndex + 3] << 24);
    // }
    return data.getInt32(startIndex, endian);
  }

  /// Converts a given double [value] to bytes and writes them to given [data].
  ///
  /// The [startIndex] marks the position in the [data] at which to write the bytes.
  static void fromDouble(double value, ByteData data, int startIndex) {
    data.setFloat64(startIndex, value, endian);
  }

  /// Converts the 8 bytes in the list at [startIndex] to a double
  static double toDouble(ByteData data, int startIndex) {
    return data.getFloat64(startIndex, endian);
  }
}
