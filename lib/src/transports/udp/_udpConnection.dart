import 'dart:io';
import 'dart:typed_data';

import '../_connection.dart';
import '_udpPeer.dart';

class UdpConnection extends Connection {
  late InternetAddress _remoteEndPoint;
  InternetAddress get remoteEndPoint => _remoteEndPoint;

  late int _port;
  int get port => _port;

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
