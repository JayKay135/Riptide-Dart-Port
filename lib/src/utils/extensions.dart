import 'dart:io';

/// Contains extension methods for various classes.
extension InternetAddressExtensions on InternetAddress {
  /// Takes the address' format into account when converting it to a string together with the given [port].
  ///
  /// [port] : The port of the endpoint.
  ///
  /// Returns a string representing the endpoint. IPv4 addresses (including IPv4 addresses mapped to IPv6) are
  /// formatted as `address:port`, IPv6 addresses as `[address]:port`.
  ///
  /// NOTE: C# extends IPEndPoint, which Dart has no equivalent of.
  String toStringBasedOnIPFormat(int port) {
    if (_isIPv4MappedToIPv6) {
      return "${rawAddress.sublist(12).join('.')}:$port";
    }

    return type == InternetAddressType.IPv6 ? "[$address]:$port" : "$address:$port";
  }

  /// Whether or not the address is an IPv4 address mapped to IPv6 (::ffff:a.b.c.d).
  bool get _isIPv4MappedToIPv6 {
    if (type != InternetAddressType.IPv6) {
      return false;
    }

    List<int> bytes = rawAddress;
    for (int i = 0; i < 10; i++) {
      if (bytes[i] != 0) {
        return false;
      }
    }

    return bytes[10] == 0xFF && bytes[11] == 0xFF;
  }
}
