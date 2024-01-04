import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riptide/src/utils/converter.dart';

void converterTests() {
  group('zigZagEncodeInt', () {
    test('Test positive number', () {
      expect(Converter.zigZagEncodeInt(5), equals(10));
    });

    test('Test negative number', () {
      expect(Converter.zigZagEncodeInt(-5), equals(9));
    });

    test('Test zero', () {
      expect(Converter.zigZagEncodeInt(0), equals(0));
    });

    test('Test large positive number', () {
      expect(Converter.zigZagEncodeInt(1234567890), equals(2469135780));
    });

    test('Test large negative number', () {
      expect(Converter.zigZagEncodeInt(-1234567890), equals(2469135779));
    });
  });

  group('zigZagEncodeLong', () {
    test('Test positive number', () {
      expect(Converter.zigZagEncodeLong(5), equals(10));
    });

    test('Test negative number', () {
      expect(Converter.zigZagEncodeLong(-5), equals(9));
    });

    test('Test zero', () {
      expect(Converter.zigZagEncodeLong(0), equals(0));
    });

    test('Test large positive number', () {
      expect(Converter.zigZagEncodeLong(1234567890123456789),
          equals(2469135780246913578));
    });

    test('Test large negative number', () {
      expect(Converter.zigZagEncodeLong(-1234567890123456789),
          equals(2469135780246913577));
    });
  });

  group('zigZagDecode', () {
    test('Test positive even number', () {
      expect(Converter.zigZagDecode(10), equals(5));
    });

    test('Test positive odd number', () {
      expect(Converter.zigZagDecode(9), equals(-5));
    });

    test('Test zero', () {
      expect(Converter.zigZagDecode(0), equals(0));
    });

    test('Test large positive even number', () {
      expect(Converter.zigZagDecode(2469135780), equals(1234567890));
    });

    test('Test large positive odd number', () {
      expect(Converter.zigZagDecode(2469135779), equals(-1234567890));
    });
  });

  group('setBitsFromByte', () {
    test('Test with 8 bits', () {
      Uint8List array = Uint8List(1);
      Converter.setBitsFromByte(255, 8, array, 0);
      expect(array[0], equals(255));
    });

    test('Test with 4 bits', () {
      Uint8List array = Uint8List(1);
      Converter.setBitsFromByte(15, 4, array, 0);
      expect(array[0], equals(15));
    });

    test('Test with 0 bits', () {
      Uint8List array = Uint8List(1);
      Converter.setBitsFromByte(255, 0, array, 0);
      expect(array[0], equals(0));
    });

    test('Test with startBit at 4', () {
      Uint8List array = Uint8List(1);
      Converter.setBitsFromByte(15, 4, array, 4);
      expect(array[0], equals(240));
    });

    test('Test with more complex value', () {
      Uint8List array = Uint8List(1);
      Converter.setBitsFromByte(109, 7, array, 1);
      expect(array[0], equals(218));
    });
  });

  group('setBitsFromUshort', () {
    test('Test with 16 bits', () {
      Uint8List array = Uint8List(2);
      Converter.setBitsFromUshort(65535, 16, array, 0);
      expect(array[0], equals(255));
      expect(array[1], equals(255));
    });

    test('Test with 8 bits', () {
      Uint8List array = Uint8List(2);
      Converter.setBitsFromUshort(255, 8, array, 0);
      expect(array[0], equals(255));
      expect(array[1], equals(0));
    });

    test('Test with 0 bits', () {
      Uint8List array = Uint8List(2);
      Converter.setBitsFromUshort(65535, 0, array, 0);
      expect(array[0], equals(0));
      expect(array[1], equals(0));
    });

    test('Test with startBit at 8', () {
      Uint8List array = Uint8List(2);
      Converter.setBitsFromUshort(255, 8, array, 8);
      expect(array[0], equals(0));
      expect(array[1], equals(255));
    });

    test('Test with more complex value', () {
      Uint8List array = Uint8List(1);
      Converter.setBitsFromUshort(109, 7, array, 1);
      expect(array[0], equals(218));
    });
  });

  group('setBitsFromUint', () {
    test('Test with 32 bits', () {
      Uint8List array = Uint8List(4);
      Converter.setBitsFromUint(4294967295, 32, array, 0);
      expect(array[0], equals(255));
      expect(array[1], equals(255));
      expect(array[2], equals(255));
      expect(array[3], equals(255));
    });

    test('Test with 16 bits', () {
      Uint8List array = Uint8List(4);
      Converter.setBitsFromUint(65535, 16, array, 0);
      expect(array[0], equals(255));
      expect(array[1], equals(255));
      expect(array[2], equals(0));
      expect(array[3], equals(0));
    });

    test('Test with 0 bits', () {
      Uint8List array = Uint8List(4);
      Converter.setBitsFromUint(4294967295, 0, array, 0);
      expect(array[0], equals(0));
      expect(array[1], equals(0));
      expect(array[2], equals(0));
      expect(array[3], equals(0));
    });

    test('Test with startBit at 16', () {
      Uint8List array = Uint8List(4);
      Converter.setBitsFromUint(65535, 16, array, 16);
      expect(array[0], equals(0));
      expect(array[1], equals(0));
      expect(array[2], equals(255));
      expect(array[3], equals(255));
    });
  });

  group('setBitsFromUlongWithByteList', () {
    test('Test with 64 bits', () {
      Uint8List array = Uint8List(8);
      Converter.setBitsFromUlongWithByteList(9223372036854775807, 64, array, 0);
      expect(array[0], equals(255));
      expect(array[1], equals(255));
      expect(array[2], equals(255));
      expect(array[3], equals(255));
      expect(array[4], equals(255));
      expect(array[5], equals(255));
      expect(array[6], equals(255));
      expect(array[7], equals(127));
    });

    test('Test with 32 bits', () {
      Uint8List array = Uint8List(8);
      Converter.setBitsFromUlongWithByteList(4294967295, 32, array, 0);
      expect(array[0], equals(255));
      expect(array[1], equals(255));
      expect(array[2], equals(255));
      expect(array[3], equals(255));
      expect(array[4], equals(0));
      expect(array[5], equals(0));
      expect(array[6], equals(0));
      expect(array[7], equals(0));
    });

    test('Test with 0 bits', () {
      Uint8List array = Uint8List(8);
      Converter.setBitsFromUlongWithByteList(9223372036854775807, 0, array, 0);
      expect(array[0], equals(0));
      expect(array[1], equals(0));
      expect(array[2], equals(0));
      expect(array[3], equals(0));
      expect(array[4], equals(0));
      expect(array[5], equals(0));
      expect(array[6], equals(0));
      expect(array[7], equals(0));
    });

    test('Test with startBit at 32', () {
      Uint8List array = Uint8List(8);
      Converter.setBitsFromUlongWithByteList(4294967295, 32, array, 32);
      expect(array[0], equals(0));
      expect(array[1], equals(0));
      expect(array[2], equals(0));
      expect(array[3], equals(0));
      expect(array[4], equals(255));
      expect(array[5], equals(255));
      expect(array[6], equals(255));
      expect(array[7], equals(255));
    });
  });

  group('setBitsFromUlongWithUlongList', () {
    test('Test with 64 bits', () {
      Uint64List array = Uint64List(1);
      Converter.setBitsFromUlongWithUlongList(
          9223372036854775807, 64, array, 0);
      expect(array[0], equals(9223372036854775807));
    });

    test('Test with 32 bits', () {
      Uint64List array = Uint64List(2); // 2 * 64 bits = 128 bits
      Converter.setBitsFromUlongWithUlongList(4294967295, 32, array, 0);
      expect(array[0], equals(4294967295));
      expect(array[1], equals(0));
    });

    test('Test with 0 bits', () {
      Uint64List array = Uint64List(1);
      Converter.setBitsFromUlongWithUlongList(9223372036854775807, 0, array, 0);
      expect(array[0], equals(0));
    });

    test('Test with startBit at 32', () {
      Uint64List array = Uint64List(1);
      Converter.setBitsFromUlongWithUlongList(2147483647, 32, array, 32);
      expect(array[0], equals(9223372030412324864)); // 2147483647 << 32
    });
  });

  group('getBitsForByte', () {
    test('Test with 4 bits', () {
      Uint8List array = Uint8List.fromList([255, 0]);
      int result = Converter.getBitsForByte(4, array, 0);
      expect(result, equals(15));
    });

    test('Test with 8 bits', () {
      Uint8List array = Uint8List.fromList([255, 0]);
      int result = Converter.getBitsForByte(8, array, 0);
      expect(result, equals(255));
    });
  });

  group('getBitsForUshort', () {
    test('Test with 8 bits', () {
      Uint8List array = Uint8List.fromList([255, 255, 0, 0]);
      int result = Converter.getBitsForUshort(8, array, 0);
      expect(result, equals(255));
    });

    test('Test with 16 bits', () {
      Uint8List array = Uint8List.fromList([255, 255, 0, 0]);
      int result = Converter.getBitsForUshort(16, array, 0);
      expect(result, equals(65535));
    });
  });

  group('getBitsForUint', () {
    test('Test with 16 bits', () {
      Uint8List array = Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 0]);
      int result = Converter.getBitsForUint(16, array, 0);
      expect(result, equals(65535));
    });

    test('Test with 32 bits', () {
      Uint8List array = Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 0]);
      int result = Converter.getBitsForUint(32, array, 0);
      expect(result, equals(4294967295));
    });
  });

  group('getBitsForUlong', () {
    test('Test with 32 bits', () {
      Uint8List array = Uint8List.fromList(
          [255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0]);
      int result = Converter.getBitsForUlong(32, array, 0);
      expect(result, equals(4294967295));
    });

    test('Test with 64 bits', () {
      Uint8List array = Uint8List.fromList(
          [255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0]);
      int result = Converter.getBitsForUlong(64, array, 0);
      expect(result, equals(9223372036854775807));
    });
  });

  group('getBitsFromUlongforByte', () {
    test('Test with 4 bits', () {
      Uint64List array = Uint64List.fromList([15, 0]);
      int result = Converter.getBitsFromUlongforByte(4, array, 0);
      expect(result, equals(15));
    });

    test('Test with 8 bits', () {
      Uint64List array = Uint64List.fromList([255, 0]);
      int result = Converter.getBitsFromUlongforByte(8, array, 0);
      expect(result, equals(255));
    });
  });

  group('getBitsFromUlongForUshort', () {
    test('Test with 8 bits', () {
      Uint64List array = Uint64List.fromList([255, 0]);
      int result = Converter.getBitsFromUlongForUshort(8, array, 0);
      expect(result, equals(255));
    });

    test('Test with 16 bits', () {
      Uint64List array = Uint64List.fromList([65535, 0]);
      int result = Converter.getBitsFromUlongForUshort(16, array, 0);
      expect(result, equals(65535));
    });
  });

  group('getBitsFromUlongForUint', () {
    test('Test with 16 bits', () {
      Uint64List array = Uint64List.fromList([65535, 0]);
      int result = Converter.getBitsFromUlongForUint(16, array, 0);
      expect(result, equals(65535));
    });

    test('Test with 32 bits', () {
      Uint64List array = Uint64List.fromList([4294967295, 0]);
      int result = Converter.getBitsFromUlongForUint(32, array, 0);
      expect(result, equals(4294967295));
    });
  });

  group('getBitsFromUlongForUlong', () {
    test('Test with 32 bits', () {
      Uint64List array = Uint64List.fromList([4294967295, 0]);
      int result = Converter.getBitsFromUlongForUlong(32, array, 0);
      expect(result, equals(4294967295));
    });

    test('Test with 64 bits', () {
      Uint64List array = Uint64List.fromList([9223372036854775807, 0]);
      int result = Converter.getBitsFromUlongForUlong(64, array, 0);
      expect(result, equals(9223372036854775807));
    });
  });

  group('sByteToBitsFromBytes', () {
    test('Test with startBit at 0', () {
      Uint8List array = Uint8List(1);
      Converter.sByteToBitsFromBytes(127, array, 0);
      expect(array[0], equals(127));
    });

    test('Test with startBit not at 0', () {
      Uint8List array = Uint8List(2);
      Converter.sByteToBitsFromBytes(127, array, 4);
      expect(array[0], equals(127 << 4));
      expect(array[1], equals(127 >> 4));
    });
  });

  group('sByteToBitsFromUlongs', () {
    test('Test with startBit at 0', () {
      Uint64List array = Uint64List(1);
      Converter.sByteToBitsFromUlongs(127, array, 0);
      expect(array[0], equals(127));
    });

    test('Test with startBit not at 0', () {
      Uint64List array = Uint64List(2);
      Converter.sByteToBitsFromUlongs(127, array, 4);
      expect(array[0], equals(127 << 4));
      expect(array[1], equals(127 >> 4));
    });
  });

  group('byteToBitsFromBytes', () {
    test('Test with startBit at 0', () {
      Uint8List array = Uint8List(1);
      Converter.byteToBitsFromBytes(255, array, 0);
      expect(array[0], equals(255));
    });

    test('Test with startBit not at 0', () {
      Uint8List array = Uint8List(2);
      Converter.byteToBitsFromBytes(255, array, 4);
      expect(array[0], equals(255 << 4));
      expect(array[1], equals(255 >> 4));
    });
  });

  group('byteToBitsFromUlongs', () {
    test('Test with startBit at 0', () {
      Uint64List array = Uint64List(1);
      Converter.byteToBitsFromUlongs(255, array, 0);
      expect(array[0], equals(255));
    });

    test('Test with startBit not at 0', () {
      Uint64List array = Uint64List(2);
      Converter.byteToBitsFromUlongs(255, array, 4);
      expect(array[0], equals(255 << 4));
      expect(array[1], equals(255 >> 4));
    });
  });

  group('fromBits', () {
    test('Test with 64 bits', () {
      var array = Uint64List.fromList([0xFFFFFFFFFFFFFFFF]);
      var result = Converter.fromBits(64, array, 0);
      expect(result, equals(0xFFFFFFFFFFFFFFFF));
    });

    test('Test with 32 bits', () {
      var array = Uint64List.fromList([0xFFFFFFFF]);
      var result = Converter.fromBits(32, array, 0);
      expect(result, equals(0xFFFFFFFF));
    });

    test('Test with startBit at 32', () {
      var array = Uint64List.fromList([0xFFFFFFFF00000000]);
      var result = Converter.fromBits(32, array, 32);
      expect(result, equals(0xFFFFFFFF));
    });

    test('Test with 0 bits', () {
      var array = Uint64List.fromList([0]);
      var result = Converter.fromBits(0, array, 0);
      expect(result, equals(0));
    });

    test('Test with welcome values', () {
      var array = Uint64List(154);
      array[0] = 0x18;
      array[2] = 0x40;
      var result = Converter.fromBits(16, array, 20);
      expect(result, equals(1));
    });
  });

  group('toBits', () {
    test('Test with bit 0', () {
      var array = Uint64List(2);
      Converter.toBits(10, 64, array, 0);
      expect(array[0], equals(10));
    });

    test('Test with valueSize less than BitsPerULong', () {
      var array = Uint64List(2);
      Converter.toBits(10, 32, array, 16);
      expect(array[0], equals(10 << 16));
    });

    test('Test with valueSize greater than BitsPerULong', () {
      var array = Uint64List(2);
      Converter.toBits(0xFFFFFFFFFFFFFFFF, 64, array, 32);
      expect(array[0], equals(0xFFFFFFFF << 32));
      expect(array[1], equals(0xFFFFFFFF));
    });

    test('Test with valueSize equal to BitsPerULong', () {
      var array = Uint64List(2);
      Converter.toBits(0xFFFFFFFFFFFFFFFF, 64, array, 0);
      expect(array[0], equals(0xFFFFFFFFFFFFFFFF));
    });
  });
}
