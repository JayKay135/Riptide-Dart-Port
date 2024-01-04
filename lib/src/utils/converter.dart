import 'dart:math';
import 'dart:typed_data';

import 'constants.dart';
import 'helper.dart';
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
  /// [value] : The 32 bit signed value to encode.
  /// Returns the zig zag-encoded value.
  ///
  /// Zig zag encoding allows small negative numbers to be represented as small positive numbers. All positive numbers are doubled and become even numbers,
  /// while all negative numbers become positive odd numbers. In contrast, simply casting a negative value to its unsigned counterpart would result in a large positive
  /// number which uses the high bit, rendering compression via [Message.addVarULong] and [Message.getVarULong] ineffective.
  static int zigZagEncodeInt(int value) {
    return (value >> 31) ^ (value << 1);
  }

  /// Zig zag encodes [value].
  ///
  /// [value] : The 64 bit signed value to encode.
  /// Returns the zig zag-encoded value.
  ///
  /// Zig zag encoding allows small negative numbers to be represented as small positive numbers. All positive numbers are doubled and become even numbers,
  /// while all negative numbers become positive odd numbers. In contrast, simply casting a negative value to its unsigned counterpart would result in a large positive
  /// number which uses the high bit, rendering compression via [Message.addVarULong] and [Message.getVarULong] ineffective.
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
  /// number which uses the high bit, rendering compression via [Message.addVarULong] and [Message.getVarULong] ineffective.
  static int zigZagDecode(int value) {
    return (value >> 1) ^ -(value & 1);
  }

  /// Takes [amount] bits from [bitfield] and writes them into [array], starting at [startBit].
  ///
  /// [bitfield] : The bitfield from which to write the bits into the array.
  /// [amount] : The number of bits to write.
  /// [array] : The array to write the bits into.
  /// [startBit] : The bit position in the array at which to start writing.
  static void setBitsFromByte(int bitfield, int amount, Uint8List array, int startBit) {
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
    // int startByte = startBit ~/ 8;
    // int offset = startBit % 8;
    // int mask = ((1 << amount) - 1) << offset;
    // int value = (bitfield & ((1 << amount) - 1)) << offset;
    // array[startByte] = (array[startByte] & ~mask) | value;
  }

  /// Takes [amount] bits from [bitfield] and writes them into [array], starting at [startBit].
  ///
  /// [bitfield] : The bitfield from which to write the bits into the array.
  /// [amount] : The number of bits to write.
  /// [array] : The array to write the bits into.
  /// [startBit] : The bit position in the array at which to start writing.
  static void setBitsFromUshort(int bitfield, int amount, Uint8List array, int startBit) {
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
    // int startByte = startBit ~/ 8;
    // int offset = startBit % 8;
    // int mask = ((1 << amount) - 1) << offset;
    // int value = (bitfield & ((1 << amount) - 1)) << offset;

    // // Write the first byte
    // array[startByte] = (array[startByte] & ~mask) | (value & 0xFF);

    // // If the bits span more than one byte, write the remaining bytes
    // if (offset + amount > 8) {
    //   array[startByte + 1] = (array[startByte + 1] & ~(mask >> 8)) | (value >> 8);
    // }
  }

  /// Takes [amount] bits from [bitfield] and writes them into [array], starting at [startBit].
  ///
  /// [bitfield] : The bitfield from which to write the bits into the array.
  /// [amount] : The number of bits to write.
  /// [array] : The array to write the bits into.
  /// [startBit] : The bit position in the array at which to start writing.
  static void setBitsFromUint(int bitfield, int amount, Uint8List array, int startBit) {
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
    // int startByte = startBit ~/ 8;
    // int offset = startBit % 8;
    // int mask = ((1 << amount) - 1) << offset;
    // int value = (bitfield & ((1 << amount) - 1)) << offset;

    // // Write the first byte
    // array[startByte] = (array[startByte] & ~mask) | (value & 0xFF);

    // // If the bits span more than one byte, write the remaining bytes
    // if (offset + amount > 8) {
    //   for (int i = 1; i * 8 < offset + amount; i++) {
    //     array[startByte + i] = (array[startByte + i] & ~(mask >> (8 * i))) | (value >> (8 * i));
    //   }
    // }
  }

  /// Takes [amount] bits from [bitfield] and writes them into [array], starting at [startBit].
  ///
  /// [bitfield] : The bitfield from which to write the bits into the array.
  /// [amount] : The number of bits to write.
  /// [array] : The array to write the bits into.
  /// [startBit] : The bit position in the array at which to start writing.
  static void setBitsFromUlongWithByteList(int bitfield, int amount, Uint8List array, int startBit) {
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
    // int startByte = startBit ~/ 8;
    // int offset = startBit % 8;
    // int mask = ((1 << amount) - 1) << offset;
    // int value = (bitfield & ((1 << amount) - 1)) << offset;

    // // Write the first byte
    // array[startByte] = (array[startByte] & ~mask) | (value & 0xFF);

    // // If the bits span more than one byte, write the remaining bytes
    // if (offset + amount > 8) {
    //   for (int i = 1; i * 8 < offset + amount; i++) {
    //     array[startByte + i] = (array[startByte + i] & ~(mask >> (8 * i))) | (value >> (8 * i));
    //   }
    // }
  }

  /// Takes [amount] bits from [bitfield] and writes them into [array], starting at [startBit].
  ///
  /// [bitfield] : The bitfield from which to write the bits into the array.
  /// [amount] : The number of bits to write.
  /// [array] : The array to write the bits into.
  /// [startBit] : The bit position in the array at which to start writing.
  static void setBitsFromUlongWithUlongList(int bitfield, int amount, Uint64List array, int startBit) {
    int mask = (1 << (amount - 1) << 1) - 1; // Perform 2 shifts, doing it in 1 doesn't cause the value to wrap properly
    bitfield &= mask; // Discard any bits that are set beyond the ones we're setting
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;

    if (bit == 0) {
      array[pos] = bitfield | array[pos] & ~mask;
    } else {
      array[pos] = (bitfield << bit) | (array[pos] & ~(mask << bit));
      if (bit + amount >= bitsPerULong) {
        array[pos + 1] = (bitfield >> (64 - bit)) | (array[pos + 1] & ~(mask >> (64 - bit)));
      }
    }
    // int mask = ((1 << amount) - 1); // Mask to get the relevant bits from bitfield
    // int pos = startBit ~/ bitsPerULong; // Position in the array
    // int bit = startBit % bitsPerULong; // Bit position within the ulong at array[pos]

    // // Clear the relevant bits in the array and set them to the relevant bits from bitfield
    // array[pos] = (array[pos] & ~(mask << bit)) | ((bitfield & mask) << bit);

    // // If the bits span more than one ulong, set the remaining bits in the next ulong
    // if (bit + amount > bitsPerULong) {
    //   array[pos + 1] = (array[pos + 1] & ~(mask >> (bitsPerULong - bit))) | ((bitfield & mask) >> (bitsPerULong - bit));
    // }
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsForByte(int amount, Uint8List array, int startBit) {
    int bitfield = byteFromByteBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsForUshort(int amount, Uint8List array, int startBit) {
    int bitfield = uShortFromByteBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsForUint(int amount, Uint8List array, int startBit) {
    int bitfield = uIntFromByteBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsForUlong(int amount, Uint8List array, int startBit) {
    int bitfield = uLongFromByteBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsFromUlongforByte(int amount, Uint64List array, int startBit) {
    int bitfield = byteFromUlongBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsFromUlongForUshort(int amount, Uint64List array, int startBit) {
    int bitfield = byteFromUlongBits(array, startBit);
    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsFromUlongForUint(int amount, Uint64List array, int startBit) {
    int bitfield = byteFromUlongBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Starting at [startBit], reads [amount] bits from [array] and returns it.
  ///
  /// [amount] : The number of bits to read.
  /// [array] : The array to read the bits from.
  /// [startBit] : The bit position in the array at which to start reading.
  static int getBitsFromUlongForUlong(int amount, Uint64List array, int startBit) {
    int bitfield = byteFromUlongBits(array, startBit);
    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're reading
    return bitfield;
  }

  /// Converts [value] to 8 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The sbyte to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void sByteToBitsFromBytes(int value, Uint8List array, int startBit) => byteToBitsFromBytes(value, array, startBit);

  /// Converts [value] to 8 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The sbyte to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void sByteToBitsFromUlongs(int value, Uint64List array, int startBit) => byteToBitsFromUlongs(value, array, startBit);

  /// Converts [value] to 8 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The byte to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void byteToBitsFromBytes(int value, Uint8List array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    if (bit == 0)
      array[pos] = value;
    else {
      array[pos] |= value << bit;
      array[pos + 1] = value >> (8 - bit);
    }
  }

  /// Converts [value] to 8 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The byte to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void byteToBitsFromUlongs(int value, Uint64List array, int startBit) => toBits(value, bitsPerByte, array, startBit);

  /// Converts the 8 bits at [startBit] in [array] to an [sbyte].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [sbyte].
  static int sByteFromByteBits(Uint8List array, int startBit) => byteFromByteBits(array, startBit);

  /// <inheritdoc cref="SByteFromBits(byte[], int)"/>
  static int sByteFromUlongBits(Uint64List array, int startBit) => byteFromUlongBits(array, startBit);

  /// Converts the 8 bits at [startBit] in [array] to a [byte].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [byte].
  static int byteFromByteBits(Uint8List array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    int value = array[pos];
    if (bit == 0) return value;

    value >>= bit;
    return value | (array[pos + 1] << (8 - bit));
  }

  /// <inheritdoc cref="ByteFromBits(byte[], int)"/>
  static int byteFromUlongBits(Uint64List array, int startBit) => fromBits(bitsPerByte, array, startBit);

  /// Converts [value] to a bit and writes it into [array] at [startBit].
  ///
  /// [value] : The [bool] to convert.
  /// [array] : The array to write the bit into.
  /// [startBit] : The position in the array at which to write the bit.
  static void boolToBitFromBytes(bool value, Uint8List array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;

    if (bit == 0) {
      array[pos] = 0;
    }

    if (value) {
      array[pos] |= 1 << bit;
    }
  }

  /// <inheritdoc cref="BoolToBit(bool, byte[], int)"/>
  static void boolToBitFromUlongs(bool value, Uint64List array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
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
  static bool boolFromByteWithBytes(Uint8List array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    return (array[pos] & (1 << bit)) != 0;
  }

  /// <inheritdoc cref="BoolFromBit(byte[], int)"/>
  static bool boolFromBitWithUlongs(Uint64List array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
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

  /// Converts a given int [value] representing a short to bytes and writes them to given [data].
  ///
  /// The [startIndex] marks the position in the [data] at which to write the bytes.
  /// As dart does not offer an equivalent ushort type like C# the lower 16 bit of the standard int type are used
  static void fromUShort(int value, ByteData data, int startIndex) {
    data.setUint16(startIndex, value, endian);
  }

  /// Converst the 2 bytes in the list at [startIndex] to [int] representing a short
  static int toShort(ByteData data, int startIndex) {
    return data.getInt16(startIndex, endian);
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
  static void shortToBitsFromBytes(int value, Uint8List array, int startBit) => uShortToBitsFromBytes(value, array, startBit);

  /// <inheritdoc cref="ShortToBits(short, byte[], int)"/>
  static void shortToBitsFromUlongs(int value, Uint64List array, int startBit) => uShortToBitsFromUlongs(value, array, startBit);

  /// Converts [value] to 16 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [ushort] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void uShortToBitsFromBytes(int value, Uint8List array, int startBit) {
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

  /// <inheritdoc cref="UShortToBits(ushort, byte[], int)"/>
  static void uShortToBitsFromUlongs(int value, Uint64List array, int startBit) => toBits(value, Constants.ushortBytes * bitsPerByte, array, startBit);

  /// Converts the 16 bits at [startBit] in [array] to a [short].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [short].
  static int shortFromByteBits(Uint8List array, int startBit) => Helper.toUShort(uShortFromByteBits(array, startBit));

  /// <inheritdoc cref="ShortFromBits(byte[], int)"/>
  static int shortFromUlongBits(Uint64List array, int startBit) => Helper.toUShort(uShortFromUlongBits(array, startBit));

  /// Converts the 16 bits at [startBit] in [array] to a [ushort].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [ushort].
  static int uShortFromByteBits(Uint8List array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    int value = array[pos] | (array[pos + 1] << 8);
    if (bit == 0) return value;

    value >>= bit;
    return (value | (array[pos + 2] << (16 - bit))) % (pow(2, 8 * Constants.ushortBytes)).toInt();
  }

  /// <inheritdoc cref="UShortFromBits(byte[], int)"/>
  static int uShortFromUlongBits(Uint64List array, int startBit) => Helper.toUShort(fromBits(Constants.ushortBytes * bitsPerByte, array, startBit));

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
  static void intToBitsFromBytes(int value, Uint8List array, int startBit) => uIntToByteBits(value, array, startBit);

  /// <inheritdoc cref="IntToBits(int, byte[], int)"/>
  static void intToBitsFromUlong(int value, Uint64List array, int startBit) => uIntToUlongBits(value, array, startBit);

  /// Converts [value] to 32 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [uint] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void uIntToByteBits(int value, Uint8List array, int startBit) {
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

  /// <inheritdoc cref="UIntToBits(uint, byte[], int)"/>
  static void uIntToUlongBits(int value, Uint64List array, int startBit) => toBits(value, Constants.uintBytes * bitsPerByte, array, startBit);

  /// Converts the 32 bits at [startBit] in [array] to an [int].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [int].
  static int intFromByteBits(Uint8List array, int startBit) => uIntFromByteBits(array, startBit);

  /// <inheritdoc cref="IntFromBits(byte[], int)"/>
  static int intFromUlongBits(Uint64List array, int startBit) => uIntFromUlongBits(array, startBit);

  /// Converts the 32 bits at [startBit] in [array] to a [uint].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [uint].
  static int uIntFromByteBits(Uint8List array, int startBit) {
    int pos = startBit ~/ bitsPerByte;
    int bit = startBit % bitsPerByte;
    int value = array[pos] | (array[pos + 1] << 8) | (array[pos + 2] << 16) | (array[pos + 3] << 24);
    if (bit == 0) return value;

    value >>= bit;
    return value | array[pos + 4] << (32 - bit);
  }

  /// <inheritdoc cref="UIntFromBits(byte[], int)"/>
  static int uIntFromUlongBits(Uint64List array, int startBit) => fromBits(Constants.uintBytes * bitsPerByte, array, startBit);

  /// Converts a given [long] to bytes and writes them into the given array.
  ///
  /// [value] : The [long] to convert.
  /// [array] : The array to write the bytes into.
  /// [startIndex] : The position in the array at which to write the bytes.
  static void FromLong(int value, Uint8List array, int startIndex) => fromULong(value, array, startIndex);

  /// Converts a given [ulong] to bytes and writes them into the given array.
  ///
  /// [value] : The [ulong] to convert.
  /// [array] : The array to write the bytes into.
  /// [startIndex] : The position in the array at which to write the bytes.
  static void fromULong(int value, Uint8List array, int startIndex) {
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
  static int toLong(Uint8List array, int startIndex) {
    var buffer = Uint8List.fromList(array.sublist(startIndex, startIndex + 8)).buffer;
    return Int64List.view(buffer)[0];
  }

  /// Converts the 8 bytes in the array at [startIndex] to a [ulong].
  ///
  /// [array] : The array to read the bytes from.
  /// [startIndex] : The position in the array at which to read the bytes.
  /// Returns the converted [ulong].
  static int toULong(Uint8List array, int startIndex) {
    var buffer = Uint8List.fromList(array.sublist(startIndex, startIndex + 8)).buffer;
    return Uint64List.view(buffer)[0];
  }

  /// Converts [value] to 64 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [long] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void longToByteBits(int value, Uint8List array, int startBit) => uLongToByteBits(value, array, startBit);

  /// <inheritdoc cref="LongToBits(long, byte[], int)"/>
  static void longToUlongBits(int value, Uint64List array, int startBit) => uLongToUlongBits(value, array, startBit);

  /// Converts [value] to 64 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [ulong] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  ///
  /// IMPORTANT: Originally takes a ulong [value] aka unsigned 64 bits as parameter. Dart only has int aka 64 signed bits. This might cause problems
  static void uLongToByteBits(int value, Uint8List array, int startBit) {
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

  /// <inheritdoc cref="ULongToBits(ulong, byte[], int)"/>
  ///
  /// IMPORTANT: Originally takes a ulong [value] aka unsigned 64 bits as parameter. Dart only has int aka 64 signed bits. This might cause problems
  static void uLongToUlongBits(int value, Uint64List array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
    if (bit == 0)
      array[pos] = value;
    else {
      array[pos] |= value << bit;
      array[pos + 1] = value >> (bitsPerULong - bit);
    }
  }

  /// Converts the 64 bits at [startBit] in [array] to a [long].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [long].
  static int longFromByteBits(Uint8List array, int startBit) => uLongFromByteBits(array, startBit);

  /// <inheritdoc cref="LongFromBits(byte[], int)"/>
  static int LongFromUlongBits(Uint64List array, int startBit) => uLongFromUlongBits(array, startBit);

  /// Converts the 64 bits at [startBit] in [array] to a [ulong].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [ulong].
  /// IMPORTANT: Originally returns a ulong [value] aka unsigned 64 bits. Dart only has int aka 64 signed bits. This might cause problems
  static int uLongFromByteBits(Uint8List array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
    int value = array[pos];
    if (bit == 0) return value;

    value >>= bit;
    return value | (array[pos + 1] << (bitsPerULong - bit));
  }

  /// <inheritdoc cref="ULongFromBits(byte[], int)"/>
  /// IMPORTANT: Originally returns a ulong [value] aka unsigned 64 bits. Dart only has int aka 64 signed bits. This might cause problems
  static int uLongFromUlongBits(Uint64List array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
    int value = array[pos];
    if (bit == 0) return value;

    value >>= bit;
    return value | (array[pos + 1] << (bitsPerULong - bit));
  }

  /// Converts [value] to [valueSize] bits and writes them into [array] at [startBit].
  ///
  /// Meant for values which fit into a [ulong], not for [ulong]s themselves.
  /// [value] : The value to convert.
  /// [valueSize] : The size in bits of the value being converted.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void toBits(int value, int valueSize, Uint64List array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;

    if (bit == 0) {
      array[pos] = value;
    } else if (bit + valueSize < bitsPerULong) {
      array[pos] |= value << bit;
    } else {
      array[pos] |= value << bit;
      array[pos + 1] = value >> (bitsPerULong - bit);
    }
  }

  /// Converts the [valueSize] bits at [startBit] in [array] to a [ulong].
  ///
  /// Meant for values which fit into a [ulong], not for [ulong]s themselves.
  /// [valueSize] : The size in bits of the value being converted.
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  ///
  /// Returns the converted [ulong].
  static int fromBits(int valueSize, Uint64List array, int startBit) {
    int pos = startBit ~/ bitsPerULong;
    int bit = startBit % bitsPerULong;
    int value = array[pos];
    if (bit == 0) {
      return value;
    }

    value >>= bit;
    if (bit + valueSize < bitsPerULong) {
      return value;
    }

    return value | (array[pos + 1] << (bitsPerULong - bit));
    // if (pos + 1 < array.length) {
    //   return value | (array[pos + 1] << (bitsPerULong - bit));
    // } else {
    //   return value;
    // }

    // int pos = startBit ~/ bitsPerULong;
    // int bit = startBit % bitsPerULong;
    // int value = array[pos].toUnsigned(64);
    // if (bit == 0) {
    //   return value;
    // }

    // value = (value >> bit).toUnsigned(64);
    // if (bit + valueSize <= bitsPerULong) {
    //   return value & ((1 << valueSize) - 1);
    // }

    // if (pos + 1 < array.length) {
    //   int nextValue = (array[pos + 1] << (bitsPerULong - bit)).toUnsigned(64);
    //   return (value | (nextValue >> (bit + valueSize - bitsPerULong))).toUnsigned(64);
    // } else {
    //   return value;
    // }
  }

  /// Converts a given [float] to bytes and writes them into the given array.
  ///
  /// [value] : The [float] to convert.
  /// [array] : The array to write the bytes into.
  /// [startIndex] : The position in the array at which to write the bytes.
  static void fromFloat(double value, Uint8List array, int startIndex) {
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
  static double toFloat(Uint8List array, int startIndex) {
    var buffer = Uint8List.fromList(array.sublist(startIndex, startIndex + 4)).buffer;
    return ByteData.view(buffer).getFloat32(0, endian);
  }

  /// Converts [value] to 32 bits and writes them into [array] at [startBit].
  ///
  /// [value] : The [float] to convert.
  /// [array] : The array to write the bits into.
  /// [startBit] : The position in the array at which to write the bits.
  static void floatToByteBits(double value, Uint8List array, int startBit) {
    var buffer = Float32List(1);
    buffer[0] = value;
    var intValue = ByteData.view(buffer.buffer).getUint32(0, Endian.little);
    uIntToByteBits(intValue, array, startBit);
  }

  /// <inheritdoc cref="FloatToBits(float, byte[], int)"/>
  static void floatToUlongBits(double value, Uint64List array, int startBit) {
    var floatList = Float32List(1);
    floatList[0] = value;
    var intList = floatList.buffer.asUint32List();
    uIntToUlongBits(intList[0], array, startBit);
  }

  /// Converts the 32 bits at [startBit] in [array] to a [float].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [float].
  static double floatFromByteBits(Uint8List array, int startBit) {
    return array.buffer.asByteData().getFloat32(startBit, endian);
  }

  /// <inheritdoc cref="FloatFromBits(byte[], int)"/>
  static double floatFromUlongBits(Uint64List array, int startBit) {
    return array.buffer.asByteData().getFloat32(startBit, endian);
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
  static void doubleToByteBits(double value, Uint8List array, int startBit) {
    // var buffer = Float64List(1);
    // buffer[0] = value;
    // var ulongValue = Uint64List.view(buffer.buffer)[0];
    // uLongToByteBits(ulongValue, array, startBit);

    array.buffer.asByteData().setFloat64(startBit, value, endian);
  }

  /// <inheritdoc cref="DoubleToBits(double, byte[], int)"/>
  static void doubleToUlongBits(double value, Uint64List array, int startBit) {
    // var doubleList = Float64List(1);
    // doubleList[0] = value;
    // var longList = doubleList.buffer.asUint64List();
    // uLongToUlongBits(longList[0], array, startBit);

    array.buffer.asByteData().setFloat64(startBit, value, endian);
  }

  /// Converts the 64 bits at [startBit] in [array] to a [double].
  ///
  /// [array] : The array to convert the bits from.
  /// [startBit] : The position in the array from which to read the bits.
  /// Returns the converted [double].
  static double doubleFromByteBits(Uint8List array, int startBit) {
    // var ulongValue = uLongFromByteBits(array, startBit);
    // var buffer = Uint64List(1);
    // buffer[0] = ulongValue;
    // return Float64List.view(buffer.buffer)[0];

    return array.buffer.asByteData().getFloat64(startBit, endian);
  }

  /// <inheritdoc cref="DoubleFromBits(byte[], int)"/>
  static double doubleFromUlongBits(Uint64List array, int startBit) {
    return array.buffer.asByteData().getFloat64(startBit, endian);
  }
}
