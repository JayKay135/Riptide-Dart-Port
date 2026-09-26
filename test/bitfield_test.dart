import 'package:riptide/src/utils/bitfield.dart';
import 'package:test/test.dart';

void main() {
  group('Bitfield', () {
    test('starts out with a single segment', () {
      Bitfield bitfield = Bitfield();
      expect(bitfield.segments.length, equals(1));
      expect(bitfield.hasCapacityFor(31).$1, isTrue);
      expect(bitfield.hasCapacityFor(32).$1, isFalse);
    });

    test('bits beyond the current count count as set', () {
      Bitfield bitfield = Bitfield();
      bitfield.shiftBy(3);
      expect(bitfield.isSet(1), isFalse);
      expect(bitfield.isSet(3), isFalse);
      expect(bitfield.isSet(4), isTrue);
      expect(() => bitfield.isSet(0), throwsRangeError);
      expect(() => bitfield.set(0), throwsRangeError);
    });

    test('shifting moves set bits', () {
      Bitfield bitfield = Bitfield();
      bitfield.shiftBy(1);
      bitfield.set(1);
      bitfield.shiftBy(5);
      expect(bitfield.isSet(6), isTrue);
      for (int bit = 1; bit < 6; bit++) {
        expect(bitfield.isSet(bit), isFalse, reason: 'bit $bit');
      }
    });

    test('segments stay within 32 bits and first8/first16 only contain their bits', () {
      Bitfield bitfield = Bitfield(isDynamicCapacity: false);
      bitfield.shiftBy(32);
      for (int bit = 1; bit <= 32; bit++) {
        bitfield.set(bit);
      }

      bitfield.shiftBy(4);
      expect(bitfield.segments[0], equals(0xFFFFFFF0));
      expect(bitfield.first8, equals(0xF0));
      expect(bitfield.first16, equals(0xFFF0));
    });

    test('combine only uses the lower 16 bits', () {
      Bitfield bitfield = Bitfield();
      bitfield.combine(0x3FFFF);
      expect(bitfield.segments[0], equals(0xFFFF));
    });

    test('checkAndTrimLast checks and removes the last bit', () {
      Bitfield bitfield = Bitfield(isDynamicCapacity: false);
      bitfield.shiftBy(2);
      bitfield.set(2);

      var (bool isSet, int checkedPosition) = bitfield.checkAndTrimLast();
      expect(isSet, isTrue);
      expect(checkedPosition, equals(2));

      (isSet, checkedPosition) = bitfield.checkAndTrimLast();
      expect(isSet, isFalse);
      expect(checkedPosition, equals(1));
    });
  });
}
