import 'package:test/test.dart';
import 'converter_test.dart';

void main() {
  group('riptide tests', () {
    converterTests();
  });

  // Message tests
  // test('test byte message creation', () {
  //   Message message = Message();

  //   message.addByte(0);
  //   message.addByte(255);
  //   message.addByte(256);
  //   expect(message.getByte(), 0);
  //   expect(message.getByte(), 255);
  //   expect(message.getByte(), 0);
  // });

  // test('test bool message creation', () {
  //   Message message = Message();

  //   message.addBool(true);
  //   message.addBool(false);
  //   expect(message.getBool(), true);
  //   expect(message.getBool(), false);
  // });

  // test('test short message creation', () {
  //   Message message = Message();

  //   message.addShort(1);
  //   message.addShort(32768);
  //   message.addShort(32767);
  //   message.addShort(-32768);
  //   message.addShort(-32769);
  //   expect(message.getShort(), 1);
  //   expect(message.getShort(), -32768);
  //   expect(message.getShort(), 32767);
  //   expect(message.getShort(), -32768);
  //   expect(message.getShort(), 32767);
  // });

  // test('test ushort message creation', () {
  //   Message message = Message();

  //   message.addUShort(1);
  //   message.addUShort(65535);
  //   message.addUShort(65536);
  //   message.addUShort(-1);
  //   expect(message.getUShort(), 1);
  //   expect(message.getUShort(), 65535);
  //   expect(message.getUShort(), 0);
  //   expect(message.getUShort(), 65535);
  // });

  // test('test int message creation', () {
  //   Message message = Message();

  //   message.addInt(1);
  //   message.addInt(2147483648);
  //   expect(message.getInt(), 1);
  //   expect(message.getInt(), -2147483648);
  // });

  // test('test double message creation', () {
  //   Message message = Message();

  //   message.addDouble(3.1415);
  //   message.addDouble(0);
  //   expect(message.getDouble(), 3.1415);
  //   expect(message.getDouble(), 0);
  // });

  // test('test string message creation', () {
  //   Message message = Message();

  //   message.addString("Hello World !");
  //   expect(message.getString(), "Hello World !");
  // });
}
