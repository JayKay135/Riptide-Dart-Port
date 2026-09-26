import 'dart:io';

import 'package:riptide/src/utils/extensions.dart';
import 'package:test/test.dart';

void main() {
  test('endpoints are formatted based on their IP format', () {
    expect(InternetAddress('127.0.0.1').toStringBasedOnIPFormat(7777), equals('127.0.0.1:7777'));
    expect(InternetAddress('::1').toStringBasedOnIPFormat(7777), equals('[::1]:7777'));
    expect(InternetAddress('::ffff:192.168.0.5').toStringBasedOnIPFormat(80), equals('192.168.0.5:80'));
  });
}
