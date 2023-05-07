import 'dart:io';
import 'dart:typed_data';

import '../_connection.dart';
import '_udpPeer.dart';

/// Represents a connection to a UdpServer or UdpClient.
class UdpConnection extends Connection {
  /// The endpoint representing the other end of the connection.
  late InternetAddress _remoteEndPoint;
  InternetAddress get remoteEndPoint => _remoteEndPoint;

  /// The port of the endpoints connection
  late int _port;
  int get port => _port;

  /// The local peer this connection is associated with.
  late UdpPeer _peer;
  @override
  UdpPeer get peer => _peer;

  UdpConnection(InternetAddress remoteEndPoint, int port, UdpPeer udpPeer) {
    _remoteEndPoint = remoteEndPoint;
    _port = port;
    _peer = udpPeer;
  }

  @override
  void send(Uint8List dataBuffer, int amount) {
    _peer.send(dataBuffer, amount, _remoteEndPoint, _port);
  }
}
