import 'dart:typed_data';

import 'constants.dart';
import '../message.dart';

/// Provides functionality for converting bits and bytes to various value types and vice versa.
class Converter {
  static const Endian endian = Endian.little;

  /// The number of bits in a byte.
  static const int bitsPerByte = 8;

  /// The number of bits in a ulong.
  static const int bitsPerULong = Constants.ulongBytes * bitsPerByte;

  /// Zig zag encodes [value].
  ///
  /// [value] : The value to encode.
  /// Returns the zig zag-encoded value.
  ///
  /// Zig zag encoding allows small negative numbers to be represented as small positive numbers. All positive numbers are doubled and become even numbers,
  /// while all negative numbers become positive odd numbers. In contrast, simply casting a negative value to its unsigned counterpart would result in a large positive
  /// number which uses the high bit, rendering compression via [Message.AddVarULong(ulong)] and [Message.getVarULong] ineffective.
  static int zigZagEncodeInt(int value) {
    return (value >> 31) ^ (value << 1);
  }

  static int zigZagEncodeLong(int value) {
    return (value >> 63) ^ (value << 1);
  }

  /// Zig zag decodes [value].
  ///
  /// [value] : The value to decode.
  /// Returns the zig zag-decoded value.
  ///
  /// Zig zag encoding allows small negative numbers to be represented as small positive numbers. All positive numbers are doubled and become even numbers,
  /// while all negative numbers become positive odd numbers. In contrast, simply casting a negative value to its unsigned counterpart would result in a large positive
  /// number which uses the high bit, rendering compression via [Message.AddVarULong(ulong)] and [Message.getVarULong] ineffective.
  static int zigZagDecode(int value) {
    return (value >> 1) ^ -(value & 1);
  }

  /// Takes [amount] bits from [bitfield] and writes them into [array], starting at [startBit].
  ///
  /// [bitfield] : The bitfield from which to write the bits into the array.
  /// [amount] : The number of bits to write.
  /// [array] : The array to write the bits into.
  /// [startBit] : The bit position in the array at which to start writing.
  static void setBitsFromByte(int bitfield, int amount, List<int> array, int startBit) {
    int mask = ((1 << amount) - 1);
    bitfield &= mask; // Discard any bits that are set beyond the ones we're setting
    int inverseMask = ~mask;
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0) {
      array[pos] = bitfield | (array[pos] & inverseMask);
    } else {
      array[pos] = (bitfield << bit) | (array[pos] & ~(mask << bit));
      array[pos + 1] = (bitfield >> (8 - bit)) | (array[pos + 1] & (inverseMask >> (8 - bit)));
    }
  }

  /// <inheritdoc cref="SetBits(byte, int, byte[], int)]
  static void setBitsFromUshort(int bitfield, int amount, List<int> array, int startBit) {
    int mask = ((1 << amount) - 1);
    bitfield &= mask; // Discard any bits that are set beyond the ones we're setting
    int inverseMask = ~mask;
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0) {
      array[pos] = bitfield | (array[pos] & inverseMask);
      array[pos + 1] = (bitfield >> 8) | (array[pos + 1] & (inverseMask >> 8));
    } else {
      array[pos] = (bitfield << bit) | (array[pos] & ~(mask << bit));
      bitfield >>= 8 - bit;
      inverseMask >>= 8 - bit;
      array[pos + 1] = bitfield | (array[pos + 1] & inverseMask);
      array[pos + 2] = (bitfield >> 8) | (array[pos + 2] & (inverseMask >> 8));
    }
  }

  /// <inheritdoc cref="SetBits(byte, int, byte[], int)]
  static void setBitsFromUint(int bitfield, int amount, List<int> array, int startBit) {
    int mask = (1 << (amount - 1) << 1) - 1; // Perform 2 shifts, doing it in 1 doesn't cause the value to wrap properly
    bitfield &= mask; // Discard any bits that are set beyond the ones we're setting
    int inverseMask = ~mask;
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0) {
      array[pos] = bitfield | (array[pos] & inverseMask);
      array[pos + 1] = (bitfield >> 8) | (array[pos + 1] & (inverseMask >> 8));
      array[pos + 2] = (bitfield >> 16) | (array[pos + 2] & (inverseMask >> 16));
      array[pos + 3] = (bitfield >> 24) | (array[pos + 3] & (inverseMask >> 24));
    } else {
      array[pos] = (bitfield << bit) | (array[pos] & ~(mask << bit));
      bitfield >>= 8 - bit;
      inverseMask >>= 8 - bit;
      array[pos + 1] = bitfield | (array[pos + 1] & inverseMask);
      array[pos + 2] = (bitfield >> 8) | (array[pos + 2] & (inverseMask >> 8));
      array[pos + 3] = (bitfield >> 16) | (array[pos + 3] & (inverseMask >> 16));
      array[pos + 4] =
          (bitfield >> 24) | (array[pos + 4] & ~(mask >> (32 - bit))); // This one can't use inverseMask because it would have incorrectly zeroed bits
    }
  }

  /// <inheritdoc cref="SetBits(byte, int, byte[], int)]
  static void setBitsFromUlongWithByteList(int bitfield, int amount, List<int> array, int startBit) {
    int mask = (1 << (amount - 1) << 1) - 1; // Perform 2 shifts, doing it in 1 doesn't cause the value to wrap properly
    bitfield &= mask; // Discard any bits that are set beyond the ones we're setting
    int inverseMask = ~mask;
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0) {
      array[pos] = bitfield | (array[pos] & inverseMask);
      array[pos + 1] = (bitfield >> 8) | (array[pos + 1] & (inverseMask >> 8));
      array[pos + 2] = (bitfield >> 16) | (array[pos + 2] & (inverseMask >> 16));
      array[pos + 3] = (bitfield >> 24) | (array[pos + 3] & (inverseMask >> 24));
      array[pos + 4] = (bitfield >> 32) | (array[pos + 4] & (inverseMask >> 32));
      array[pos + 5] = (bitfield >> 40) | (array[pos + 5] & (inverseMask >> 40));
      array[pos + 6] = (bitfield >> 48) | (array[pos + 6] & (inverseMask >> 48));
      array[pos + 7] = (bitfield >> 56) | (array[pos + 7] & (inverseMask >> 56));
    } else {
      array[pos] = (bitfield << bit) | (array[pos] & ~(mask << bit));
      bitfield >>= 8 - bit;
      inverseMask >>= 8 - bit;
      array[pos + 1] = bitfield | (array[pos + 1] & inverseMask);
      array[pos + 2] = (bitfield >> 8) | (array[pos + 2] & (inverseMask >> 8));
      array[pos + 3] = (bitfield >> 16) | (array[pos + 3] & (inverseMask >> 16));
      array[pos + 4] = (bitfield >> 24) | (array[pos + 4] & (inverseMask >> 24));
      array[pos + 5] = (bitfield >> 32) | (array[pos + 5] & (inverseMask >> 32));
      array[pos + 6] = (bitfield >> 40) | (array[pos + 6] & (inverseMask >> 40));
      array[pos + 7] = (bitfield >> 48) | (array[pos + 7] & (inverseMask >> 48));
      array[pos + 8] =
          (bitfield >> 56) | (array[pos + 8] & ~(mask >> (64 - bit))); // This one can't use inverseMask because it would have incorrectly zeroed bits
    }
  }

  /// <inheritdoc cref="SetBits(byte, int, byte[], int)]
  static void setBitsFromUlongWithUlongList(int bitfield, int amount, List<int> array, int startBit) {
    int mask = (1 << (amount - 1) << 1) - 1; // Perform 2 shifts, doing it in 1 doesn't cause the value to wrap properly
    bitfield &= mask; // Discard any bits that are set beyond the ones we're setting
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
    if (bit == 0)
      array[pos] = bitfield | array[pos] & ~mask;
    else if (bit + amount < bitsPerULong)
      array[pos] |= bitfield << bit;
    else {
      array[pos] = (bitfield << bit) | (array[pos] & ~(mask << bit));
      array[pos + 1] = (bitfield >> (64 - bit)) | (array[pos + 1] & ~(mask >> (64 - bit)));
    }
  }

  /// Starting at [startBit], reads [amount] bits from [array] into [bitfield].
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  /// [bitfield] : The bitfield into which to write the bits from the array.
  static int getBitsForByte(int amount, List<int> array, int startBit) {
    int bitfield = byteFromBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// <inheritdoc cref="GetBits(int, List<int>, int, out byte)]
  static int getBitsForUshort(int amount, List<int> array, int startBit) {
    int bitfield = uShortFromBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// <inheritdoc cref="GetBits(int, List<int>, int, out byte)]
  static int getBitsForUint(int amount, List<int> array, int startBit) {
    int bitfield = uIntFromBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// <inheritdoc cref="getBits(int, List<int>, int, out byte)]
  static int getBitsForUlong(int amount, List<int> array, int startBit) {
    int bitfield = uLongFromBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// <inheritdoc cref="GetBits(int, List<int>, int, out byte)]
  static int getBitsFromUlongforByte(int amount, List<int> array, int startBit) {
    int bitfield = byteFromBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// <inheritdoc cref="GetBits(int, List<int>, int, out byte)]
  static int getBitsFromUlongForUshort(int amount, List<int> array, int startBit) {
    int bitfield = uShortFromBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// <inheritdoc cref="GetBits(int, List<int>, int, out byte)]
  static int getBitsFromUlongForUint(int amount, List<int> array, int startBit) {
    int bitfield = uIntFromBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// <inheritdoc cref="GetBits(int, List<int>, int, out byte)]
  static int getBitsFromUlongForUlong(int amount, List<int> array, int startBit) {
    int bitfield = uLongFromBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Converts [value] to 8 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [sbyte] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void sByteToBits(int value, List<int> array, int startBit) => byteToBits(value, array, startBit);

  /// Converts [value] to 8 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [byte] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void byteToBits(int value, List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0)
      array[pos] = value;
    else {
      array[pos] |= value << bit;
      array[pos + 1] = value >> (8 - bit);
    }
  }

  /// Converts the 8 bits at [startBit] in [array] to an [sbyte].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [sbyte].
  static int sByteFromBits(List<int> array, int startBit) => byteFromBits(array, startBit);

  /// Converts the 8 bits at [startBit] in [array] to a [byte].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [byte].
  static int byteFromBits(List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    int value = array[pos];
    if (bit == 0) return value;

    value >>= bit;
    return value | (array[pos + 1] << (8 - bit));
  }

  /// Converts [value] to a bit and writes it into [array] at [startBit].
  ///
  /// [value] : The [bool] to convert.
  /// [array] : The array to write the bit into.
  /// [startBit] : The position in the array at which to write the bit.
  static void boolToBit(bool value, List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;

    if (bit == 0) {
      array[pos] = 0;
    }

    if (value) {
      array[pos] |= 1 << bit;
    }
  }

  /// Converts the bit at [startBit] in [array] to a [bool].
  ///
  /// [array] : The array to convert the bit from.
  /// [startBit] : The position in the array from which to read the bit.
  /// Returns the converted [bool].
  static bool boolFromBit(List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    return (array[pos] & (1 << bit)) != 0;
  }

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

  /// Converst the 2 bytes in the list at [startIndex] to [int] representing a short
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

  /// Converts the 2 bytes in the list at [startIndex] to [int] representing a ushort
  static int toUShort(ByteData data, int startIndex) {
    return data.getUint16(startIndex, endian);
  }

  /// Converts [value] to 16 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [short] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void shortToBits(int value, List<int> array, int startBit) => uShortToBits(value, array, startBit);

  /// Converts [value] to 16 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [ushort] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void uShortToBits(int value, List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0) {
      array[pos] = value;
      array[pos + 1] = value >> 8;
    } else {
      array[pos] |= value << bit;
      value >>= 8 - bit;
      array[pos + 1] = value;
      array[pos + 2] = value >> 8;
    }
  }

  /// Converts the 16 bits at [startBit] in [array] to a [short].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [short].
  static int shortFromBits(List<int> array, int startBit) => uShortFromBits(array, startBit);

  /// Converts the 16 bits at [startBit] in [array] to a [ushort].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [ushort].
  static int uShortFromBits(List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    int value = array[pos] | (array[pos + 1] << 8);
    if (bit == 0) return value;

    value >>= bit;
    return value | (array[pos + 2] << (16 - bit));
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

  /// Converts a given uint [value] to bytes and writes them to given [data].
  ///
  /// The [startIndex] marks the position in the [data] at which to write the bytes.
  static void fromUint(int value, ByteData data, int startIndex) {
    data.setUint32(startIndex, value, endian);
  }

  /// Converts the 4 bytes in the list at [startIndex] to an [int]
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

  /// Converts the 4 bytes in the list at [startIndex] to an u[int]
  static int toUint(ByteData data, int startIndex) {
    return data.getUint32(startIndex, endian);
  }

  /// Converts [value] to 32 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [int] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void intToBits(int value, List<int> array, int startBit) => uIntToBits(value, array, startBit);

  /// Converts [value] to 32 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [uint] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void uIntToBits(int value, List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0) {
      array[pos] = value;
      array[pos + 1] = value >> 8;
      array[pos + 2] = value >> 16;
      array[pos + 3] = value >> 24;
    } else {
      array[pos] |= value << bit;
      value >>= 8 - bit;
      array[pos + 1] = value;
      array[pos + 2] = value >> 8;
      array[pos + 3] = value >> 16;
      array[pos + 4] = value >> 24;
    }
  }

  /// Converts the 32 bits at [startBit] in [array] to an [int].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [int].
  static int intFromBits(List<int> array, int startBit) => uIntFromBits(array, startBit);

  /// Converts the 32 bits at [startBit] in [array] to a [uint].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [uint].
  static int uIntFromBits(List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    int value = array[pos] | (array[pos + 1] << 8) | (array[pos + 2] << 16) | (array[pos + 3] << 24);
    if (bit == 0) return value;

    value >>= bit;
    return value | array[pos + 4] << (32 - bit);
  }

  /// Converts a given [long] to bytes and writes them into the given array.
  ///
  /// [value] : The [long] to convert.
  /// [array] : The array to write the bytes into.
  /// [startIndex] : The position in the array at which to write the bytes.
  static void FromLong(int value, List<int> array, int startIndex) => fromULong(value, array, startIndex);

  /// Converts a given [ulong] to bytes and writes them into the given array.
  ///
  /// [value] : The [ulong] to convert.
  /// [array] : The array to write the bytes into.
  /// [startIndex] : The position in the array at which to write the bytes.
  static void fromULong(int value, List<int> array, int startIndex) {
    if (endian == Endian.big) {
      array[startIndex + 7] = value;
      array[startIndex + 6] = (value >> 8);
      array[startIndex + 5] = (value >> 16);
      array[startIndex + 4] = (value >> 24);
      array[startIndex + 3] = (value >> 32);
      array[startIndex + 2] = (value >> 40);
      array[startIndex + 1] = (value >> 48);
      array[startIndex] = (value >> 56);
    } else {
      array[startIndex] = value;
      array[startIndex + 1] = (value >> 8);
      array[startIndex + 2] = (value >> 16);
      array[startIndex + 3] = (value >> 24);
      array[startIndex + 4] = (value >> 32);
      array[startIndex + 5] = (value >> 40);
      array[startIndex + 6] = (value >> 48);
      array[startIndex + 7] = (value >> 56);
    }
  }

  /// Converts the 8 bytes in the array at [startIndex] to a [long].
  ///
  /// [array] : The array to read the bytes from.
  /// [startIndex] : The position in the array at which to read the bytes.
  /// Returns the converted [long].
  static int toLong(List<int> array, int startIndex) {
    var buffer = Uint8List.fromList(array.sublist(startIndex, startIndex + 8)).buffer;
    return Int64List.view(buffer)[0];
  }

  /// Converts the 8 bytes in the array at [startIndex] to a [ulong].
  ///
  /// [array] : The array to read the bytes from.
  /// [startIndex] : The position in the array at which to read the bytes.
  /// Returns the converted [ulong].
  static int toULong(List<int> array, int startIndex) {
    var buffer = Uint8List.fromList(array.sublist(startIndex, startIndex + 8)).buffer;
    return Uint64List.view(buffer)[0];
  }

  /// Converts [value] to 64 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [long] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void longToBits(int value, List<int> array, int startBit) => uLongToBits(value, array, startBit);

  /// Converts [value] to 64 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [ulong] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void uLongToBits(int value, List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0) {
      array[pos] = value;
      array[pos + 1] = value >> 8;
      array[pos + 2] = value >> 16;
      array[pos + 3] = value >> 24;
      array[pos + 4] = value >> 32;
      array[pos + 5] = value >> 40;
      array[pos + 6] = value >> 48;
      array[pos + 7] = value >> 56;
    } else {
      array[pos] |= value << bit;
      value >>= 8 - bit;
      array[pos + 1] = value;
      array[pos + 2] = value >> 8;
      array[pos + 3] = value >> 16;
      array[pos + 4] = value >> 24;
      array[pos + 5] = value >> 32;
      array[pos + 6] = value >> 40;
      array[pos + 7] = value >> 48;
      array[pos + 8] = value >> 56;
    }
  }

  /// Converts the 64 bits at [startBit] in [array] to a [long].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [long].
  static int longFromBits(List<int> array, int startBit) => uLongFromBits(array, startBit);

  /// Converts the 64 bits at [startBit] in [array] to a [ulong].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [ulong].
  static int uLongFromBits(List<int> array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
    int value = array[pos];
    if (bit == 0) return value;

    value >>= bit;
    return value | (array[pos + 1] << (bitsPerULong - bit));
  }

  // /// Converts [value] to [valueSize] bits and writes them into [array] at [startBit].
  // ///
  // /// Meant for values which fit into a [ulong], not for [ulong]s themselves.
  // /// [value] : The value to convert.
  // /// [valueSize] : The size in bits of the value being converted.
  // /// [array] : The array to write the bits into.
  // /// [startBit] : The position in the array at which to write the bits.
  // static void _toBits(int value, int valueSize, List<int> array, int startBit) {
  //   int pos = startBit ~/ bitsPerULong;
  //   int bit = startBit % bitsPerULong;
  //   if (bit == 0)
  //     array[pos] = value;
  //   else if (bit + valueSize < bitsPerULong)
  //     array[pos] |= value << bit;
  //   else {
  //     array[pos] |= value << bit;
  //     array[pos + 1] = value >> (bitsPerULong - bit);
  //   }
  // }

  // /// Converts the [valueSize] bits at [startBit] in [array] to a [ulong].
  // ///
  // /// Meant for values which fit into a [ulong], not for [ulong]s themselves.
  // /// [valueSize] : The size in bits of the value being converted.
  // /// [array] : The array to convert the bits from.
  // /// [startBit] : The position in the array from which to read the bits.
  // /// Returns the converted [ulong].
  // static int _fromBits(int valueSize, List<int> array, int startBit) {
  //   int pos = startBit ~/ bitsPerULong;
  //   int bit = startBit % bitsPerULong;
  //   int value = array[pos];
  //   if (bit == 0) return value;

  //   value >>= bit;
  //   if (bit + valueSize < bitsPerULong) return value;

  //   return value | (array[pos + 1] << (bitsPerULong - bit));
  // }

  /// Converts a given [float] to bytes and writes them into the given array.
  ///
  /// [value] : The [float] to convert.
  /// [array] : The array to write the bytes into.
  /// [startIndex] : The position in the array at which to write the bytes.
  static void fromFloat(double value, List<int> array, int startIndex) {
    var buffer = Float32List(1);
    buffer[0] = value;
    var byteData = ByteData.view(buffer.buffer);
    if (endian == Endian.little) {
      array[startIndex] = byteData.getUint8(0);
      array[startIndex + 1] = byteData.getUint8(1);
      array[startIndex + 2] = byteData.getUint8(2);
      array[startIndex + 3] = byteData.getUint8(3);
    } else {
      array[startIndex] = byteData.getUint8(3);
      array[startIndex + 1] = byteData.getUint8(2);
      array[startIndex + 2] = byteData.getUint8(1);
      array[startIndex + 3] = byteData.getUint8(0);
    }
  }

  /// Converts the 4 bytes in the array at [startIndex] to a [float].
  ///
  /// [array] : The array to read the bytes from.
  /// [startIndex] : The position in the array at which to read the bytes.
  /// Returns the converted [float].
  static double toFloat(List<int> array, int startIndex) {
    var buffer = Uint8List.fromList(array.sublist(startIndex, startIndex + 4)).buffer;
    return ByteData.view(buffer).getFloat32(0, endian);
  }

  /// Converts [value] to 32 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [float] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void floatToBits(double value, List<int> array, int startBit) {
    var buffer = Float32List(1);
    buffer[0] = value;
    var intValue = ByteData.view(buffer.buffer).getUint32(0, Endian.little);
    uIntToBits(intValue, array, startBit);
  }

  /// Converts the 32 bits at [startBit] in [array] to a [float].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [float].
  static double floatFromBits(List<int> array, int startBit) {
    var intValue = uIntFromBits(array, startBit);
    var buffer = Uint32List(1).buffer;
    ByteData.view(buffer).setUint32(0, intValue, Endian.little);
    return Float32List.view(buffer)[0];
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

  /// Converts [value] to 64 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [double] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void doubleToBits(double value, List<int> array, int startBit) {
    var buffer = Float64List(1);
    buffer[0] = value;
    var ulongValue = Uint64List.view(buffer.buffer)[0];
    uLongToBits(ulongValue, array, startBit);
  }

  /// Converts the 64 bits at [startBit] in [array] to a [double].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [double].
  static double doubleFromBits(List<int> array, int startBit) {
    var ulongValue = uLongFromBits(array, startBit);
    var buffer = Uint64List(1);
    buffer[0] = ulongValue;
    return Float64List.view(buffer.buffer)[0];
  }
}
