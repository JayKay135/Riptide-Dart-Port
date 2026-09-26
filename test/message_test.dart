import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:riptide/src/exceptions.dart';
import 'package:riptide/src/message.dart';
import 'package:riptide/src/transports/ipeer.dart';
import 'package:riptide/src/utils/helper.dart';
import 'package:test/test.dart';

/// Simulates sending [message] and receiving it on the other end, the same way Connection and Peer do.
Message transmit(Message message) {
  int amount = message.bytesInUse;
  Uint8List bytes = Uint8List(amount);
  Helper.blockCopyReversed(message.data, 0, bytes, 0, amount);

  var (Message received, _) = Message.create().initWithByte(bytes[0], amount);
  if (amount > 1) {
    Helper.blockCopy(bytes, 1, received.data, 1, amount - 1);
  }

  return received;
}

/// Creates an unreliable message and misaligns it by [offset] bits.
Message createMisaligned(int offset) {
  Message message = Message.createFromHeader(MessageHeader.unreliable);
  for (int i = 0; i < offset; i++) {
    message.addBool(i.isOdd);
  }

  return message;
}

/// Reads the bools added by [createMisaligned].
void skipMisalignment(Message message, int offset) {
  for (int i = 0; i < offset; i++) {
    expect(message.getBool(), equals(i.isOdd));
  }
}

/// Runs [write] and [read] for every bit offset within a byte (and some more).
void roundTrip(void Function(Message message) write, void Function(Message message) read) {
  for (int offset = 0; offset < 12; offset++) {
    Message message = createMisaligned(offset);
    write(message);
    message.addByte(0xA5); // Detects values reading or writing too many bits

    Message received = transmit(message);
    message.release();

    skipMisalignment(received, offset);
    read(received);
    expect(received.getByte(), equals(0xA5), reason: 'offset $offset');
    expect(received.unreadBits, lessThan(8), reason: 'offset $offset');
    received.release();
  }
}

void main() {
  group('Primitive round trips', () {
    test('bytes and sbytes', () {
      roundTrip((m) => m.addByte(0).addByte(255).addByte(256).addSByte(-128).addSByte(127).addSByte(-1), (m) {
        expect(m.getByte(), equals(0));
        expect(m.getByte(), equals(255));
        expect(m.getByte(), equals(0)); // Truncated like a C# cast
        expect(m.getSByte(), equals(-128));
        expect(m.getSByte(), equals(127));
        expect(m.getSByte(), equals(-1));
      });
    });

    test('bools', () {
      roundTrip((m) => m.addBool(true).addBool(false).addBool(false).addBool(true), (m) {
        expect(m.getBool(), isTrue);
        expect(m.getBool(), isFalse);
        expect(m.getBool(), isFalse);
        expect(m.getBool(), isTrue);
      });
    });

    test('shorts and ushorts', () {
      roundTrip((m) => m.addShort(-32768).addShort(32767).addShort(-1).addUShort(65535).addUShort(1).addUShort(-1),
          (m) {
        expect(m.getShort(), equals(-32768));
        expect(m.getShort(), equals(32767));
        expect(m.getShort(), equals(-1));
        expect(m.getUShort(), equals(65535));
        expect(m.getUShort(), equals(1));
        expect(m.getUShort(), equals(65535));
      });
    });

    test('ints and uints', () {
      roundTrip((m) => m.addInt(-2147483648).addInt(2147483647).addInt(-1).addUInt(4294967295).addUInt(7), (m) {
        expect(m.getInt(), equals(-2147483648));
        expect(m.getInt(), equals(2147483647));
        expect(m.getInt(), equals(-1));
        expect(m.getUInt(), equals(4294967295));
        expect(m.getUInt(), equals(7));
      });
    });

    test('longs and ulongs', () {
      roundTrip(
          (m) => m
              .addLong(-9223372036854775808)
              .addLong(9223372036854775807)
              .addLong(-1)
              .addULong(-1) // ulong.MaxValue
              .addULong(0x0123456789ABCDEF), (m) {
        expect(m.getLong(), equals(-9223372036854775808));
        expect(m.getLong(), equals(9223372036854775807));
        expect(m.getLong(), equals(-1));
        expect(m.getULong(), equals(-1));
        expect(m.getULong(), equals(0x0123456789ABCDEF));
      });
    });

    test('floats and doubles', () {
      roundTrip((m) => m.addFloat(3.5).addFloat(-0.15625).addDouble(3.1415).addDouble(-1e300).addDouble(0), (m) {
        expect(m.getFloat(), equals(3.5));
        expect(m.getFloat(), equals(-0.15625));
        expect(m.getDouble(), equals(3.1415));
        expect(m.getDouble(), equals(-1e300));
        expect(m.getDouble(), equals(0));
      });
    });

    test('var(u)longs', () {
      List<int> values = [0, 1, 127, 128, 300, 65535, 1 << 40, 9223372036854775807, -1, -9223372036854775808];
      roundTrip((m) {
        for (int value in values) {
          m.addVarLong(value);
        }
        m.addVarULong(0).addVarULong(127).addVarULong(128).addVarULong(-1);
      }, (m) {
        for (int value in values) {
          expect(m.getVarLong(), equals(value));
        }
        expect(m.getVarULong(), equals(0));
        expect(m.getVarULong(), equals(127));
        expect(m.getVarULong(), equals(128));
        expect(m.getVarULong(), equals(-1));
      });
    });

    test('strings', () {
      roundTrip((m) => m.addString('Hello World !').addString('').addString('äöü ✓ 🙂'), (m) {
        expect(m.getString(), equals('Hello World !'));
        expect(m.getString(), equals(''));
        expect(m.getString(), equals('äöü ✓ 🙂'));
      });
    });

    test('bits', () {
      roundTrip(
          (m) => m
              .addBitsByte(0x5, 3)
              .addBitsUshort(0x1234, 13)
              .addBitsUint(0xFFFFFFFF, 32)
              .addBitsUlong(-1, 64)
              .addBitsUlong(0x1F, 5)
              .addBitsByte(1, 0), (m) {
        expect(m.getBitsByte(3).$2, equals(0x5));
        expect(m.getBitsUshort(13).$2, equals(0x1234));
        expect(m.getBitsUint(32).$2, equals(0xFFFFFFFF));
        expect(m.getBitsUlong(64).$2, equals(-1));
        expect(m.getBitsUlong(5).$2, equals(0x1F));
      });
    });
  });

  group('Array round trips', () {
    test('byte arrays', () {
      Uint8List bytes = Uint8List.fromList(List.generate(40, (i) => i * 7));
      roundTrip((m) => m.addBytes(bytes).addBytesWithAmount(bytes, 5, 10).addSBytes(Int8List.fromList([-1, 5, -128])),
          (m) {
        expect(m.getBytes(), equals(bytes));
        expect(m.getBytes(), equals(bytes.sublist(5, 15)));
        expect(m.getSBytes(), equals([-1, 5, -128]));
      });
    });

    test('bool arrays', () {
      BoolList bools = BoolList.of([true, false, true, true, false]);
      roundTrip((m) => m.addBools(bools), (m) {
        expect(m.getBools(), equals(bools));
      });
    });

    test('short arrays', () {
      roundTrip(
          (m) => m.addShorts(Int16List.fromList([-32768, 0, 32767])).addUShorts(Uint16List.fromList([0, 65535, 3])),
          (m) {
        expect(m.getShorts(), equals([-32768, 0, 32767]));
        expect(m.getUShorts(), equals([0, 65535, 3]));
      });
    });

    test('int arrays', () {
      roundTrip(
          (m) => m
              .addInts(Int32List.fromList([-2147483648, -1, 2147483647]))
              .addUInts(Uint32List.fromList([0, 4294967295])), (m) {
        expect(m.getInts(), equals([-2147483648, -1, 2147483647]));
        expect(m.getUInts(), equals([0, 4294967295]));
      });
    });

    test('long arrays', () {
      roundTrip(
          (m) => m
              .addLongs(Int64List.fromList([-9223372036854775808, -1, 9223372036854775807]))
              .addULongs(Uint64List.fromList([0, -1])), (m) {
        expect(m.getLongs(), equals([-9223372036854775808, -1, 9223372036854775807]));
        expect(m.getULongs(), equals(Uint64List.fromList([0, -1])));
      });
    });

    test('float and double arrays', () {
      roundTrip(
          (m) => m.addFloats(Float32List.fromList([1.5, -2.25])).addDoubles(Float64List.fromList([3.1415, -1e-300])),
          (m) {
        expect(m.getFloats(), equals([1.5, -2.25]));
        expect(m.getDoubles(), equals([3.1415, -1e-300]));
      });
    });

    test('string arrays', () {
      roundTrip((m) => m.addStrings(['a', '', 'bcd']), (m) {
        expect(m.getStrings(), equals(['a', '', 'bcd']));
      });
    });
  });

  group('Headers and IDs', () {
    test('message IDs are added as varints', () {
      for (int id in [0, 1, 127, 128, 200, 300, 65535]) {
        Message message = Message.createFromInt(MessageSendMode.reliable, id);
        message.addString('payload');
        Message received = transmit(message);
        message.release();

        expect(received.sendMode, equals(MessageSendMode.reliable));
        expect(received.getVarULong(), equals(id));
        expect(received.getString(), equals('payload'));
        received.release();
      }
    });

    test('send modes use their corresponding headers', () {
      expect(MessageSendMode.notify.messageHeader, equals(MessageHeader.notify));
      expect(MessageSendMode.unreliable.messageHeader, equals(MessageHeader.unreliable));
      expect(MessageSendMode.reliable.messageHeader, equals(MessageHeader.reliable));

      for (MessageSendMode sendMode in MessageSendMode.values) {
        Message message = Message.createWithSendMode(sendMode);
        expect(message.sendMode, equals(sendMode));
        message.release();
      }
    });
  });

  group('Other', () {
    test('addMessage copies the unread bits of another message', () {
      for (int sourceOffset = 0; sourceOffset < 70; sourceOffset += 3) {
        for (int destOffset = 0; destOffset < 70; destOffset += 5) {
          Message source = Message.create();
          for (int i = 0; i < sourceOffset; i++) {
            source.addBool(true);
          }
          source.addULong(-1).addInt(-123456).addString('copied').addBool(true);
          for (int i = 0; i < sourceOffset; i++) {
            source.getBool();
          }

          Message dest = createMisaligned(destOffset);
          dest.addMessage(source);
          source.release();
          dest.addByte(0xA5);

          Message received = transmit(dest);
          dest.release();
          skipMisalignment(received, destOffset);
          expect(received.getULong(), equals(-1));
          expect(received.getInt(), equals(-123456));
          expect(received.getString(), equals('copied'));
          expect(received.getBool(), isTrue);
          expect(received.getByte(), equals(0xA5), reason: 'source $sourceOffset, dest $destOffset');
          received.release();
        }
      }
    });

    test('reused messages do not contain residual data', () {
      Message dirty = Message.create();
      for (int i = 0; i < 64; i++) {
        dirty.addULong(-1);
      }
      dirty.release();

      // The pool hands out the same instance again, now full of set bits
      Message message = Message.createFromHeader(MessageHeader.unreliable);
      message.addUInt(0).addUInt(0).addBool(false).addBool(false).addULong(0).addBool(false);
      Message received = transmit(message);
      message.release();

      expect(received.getUInt(), equals(0));
      expect(received.getUInt(), equals(0));
      expect(received.getBool(), isFalse);
      expect(received.getBool(), isFalse);
      expect(received.getULong(), equals(0));
      expect(received.getBool(), isFalse);
      received.release();
    });

    test('adding bits throws if there is insufficient capacity', () {
      Message message = Message.create();
      message.addBytes(Uint8List(Message.maxSize - 1), false).addBitsByte(0x7F, 7); // Leaves 1 bit
      expect(() => message.addBitsByte(0x3, 2), throwsA(isA<InsufficientCapacityException>()));
      expect(() => message.addBitsUshort(0x3, 2), throwsA(isA<InsufficientCapacityException>()));
      expect(() => message.addBitsUint(0x3, 2), throwsA(isA<InsufficientCapacityException>()));
      expect(() => message.addBitsUlong(0x3, 2), throwsA(isA<InsufficientCapacityException>()));
      message.addBitsByte(1, 1);
      expect(message.unwrittenBits, equals(0));
      message.release();
    });

    test('setBits and peekBits', () {
      Message message = Message.create();
      message.reserveBits(40).addInt(-5);
      message.setBits(0xABCDE12345, 40, 0);

      expect(message.peekBitsUlong(40, 0).$2, equals(0xABCDE12345));
      expect(message.peekBitsUint(32, 8).$2, equals(0xABCDE123));
      expect(message.peekBitsUshort(16, 4).$2, equals(0x1234));
      expect(message.peekBitsByte(4, 36).$2, equals(0xA));
      message.skipBits(40);
      expect(message.getInt(), equals(-5));
      message.release();
    });

    test('full messages can be received when the max size is a multiple of 8', () {
      int original = Message.maxPayloadSize;
      Message.maxPayloadSize = 1226; // Plus the 6 header bytes, this is a multiple of 8
      expect(Message.maxSize % 8, equals(0));

      // Fill the entire message (the unreliable header takes up 4 bits)
      Message message = Message.createFromHeader(MessageHeader.unreliable);
      message.addBytes(Uint8List(Message.maxSize - 1), false).addBitsByte(0xF, 4);
      expect(message.bytesInUse, equals(Message.maxSize));

      Message received = transmit(message);
      expect(received.getBytesWithAmount(Message.maxSize - 1), equals(Uint8List(Message.maxSize - 1)));
      expect(received.getBitsByte(4).$2, equals(0xF));

      message.release();
      received.release();
      Message.maxPayloadSize = original;
    });

    test('maxPayloadSize can be changed while no peers are running', () {
      int original = Message.maxPayloadSize;
      Message.maxPayloadSize = 100;
      expect(Message.maxPayloadSize, equals(100));
      Message message = Message.create();
      expect(() => message.addBytes(Uint8List(200)), throwsA(anything));
      Message.maxPayloadSize = original;
      expect(Message.maxPayloadSize, equals(original));
    });
  });
}
