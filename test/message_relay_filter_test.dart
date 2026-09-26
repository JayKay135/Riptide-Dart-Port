import 'package:riptide/src/message_relay_filter.dart';
import 'package:test/test.dart';

enum MessageId {
  a,
  b,
  c,
  d,
  e,
  f,
  g,
  h,
  i,
  j,
  k,
  l,
  m,
  n,
  o,
  p,
  q,
  r,
  s,
  t,
  u,
  v,
  w,
  x,
  y,
  z,
  aa,
  ab,
  ac,
  ad,
  ae,
  af,
  ag
}

void main() {
  group('MessageRelayFilter', () {
    test('can be created from an enum', () {
      MessageRelayFilter<MessageId> filter =
          MessageRelayFilter.fromTypeAndIds(MessageId.values, [MessageId.b, MessageId.ag]);
      expect(filter.shouldRelay(MessageId.b.index), isTrue);
      expect(filter.shouldRelay(MessageId.ag.index), isTrue);
      expect(filter.shouldRelay(MessageId.a.index), isFalse);

      filter.disableRelayFromEnum(MessageId.ag);
      expect(filter.shouldRelay(MessageId.ag.index), isFalse);
      filter.enableRelayFromEnum(MessageId.c);
      expect(filter.shouldRelay(MessageId.c.index), isTrue);
    });

    test('can be created with a size', () {
      MessageRelayFilter filter = MessageRelayFilter.fromSize(40, [3, 39]);
      expect(filter.shouldRelay(3), isTrue);
      expect(filter.shouldRelay(39), isTrue);
      expect(filter.shouldRelay(4), isFalse);
    });
  });
}
