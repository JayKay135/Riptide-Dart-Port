import 'dart:io';
import 'dart:typed_data';

import 'package:tuple/tuple.dart';

import '../../transports/_connection.dart';
import '../../transports/_eventArgs.dart';
import '../../transports/udp/_udpPeer.dart';
import '../../utils/_eventHandler.dart';
import '../_iclient.dart';
import '_udpConnection.dart';

class UdpClient extends UdpPeer implements IClient {
  @override
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  @override
  Event connected = Event();

  @override
  Event connectionFailed = Event();

  @override
  Event<DataReceivedEventArgs> dataReceived = Event<DataReceivedEventArgs>();

  late UdpConnection udpConnection;

  UdpClient({int socketBufferSize = UdpPeer.defaultSocketBufferSize})
      : super(socketBufferSize: socketBufferSize);

  @override
  Future<Tuple3<bool, Connection, String>> connect(
      InternetAddress hostAddress, int port) async {
    String connectError = "";

    await openSocket(listenAddress: hostAddress, port: port + 1)
        .onError((error, stackTrace) => connectError = error.toString());

    udpConnection = UdpConnection(hostAddress, port, this);

    // UDP is connectionless, so from the transport POV everything is immediately ready to send/receive data
    _onConnected();

    return Tuple3(true, udpConnection, connectError);
  }

  @override
  void disconnect() {
    closeSocket();
  }

  void _onConnected() {
    connected.invoke(null);
  }

  void onConnectionFailed() {
    connectionFailed.invoke(null);
  }

  @override
  void onDataReceived(
      Uint8List data, int amount, InternetAddress fromEndPoint, int port) {
    if (udpConnection.remoteEndPoint == fromEndPoint &&
        !udpConnection.isNotConnected()) {
      dataReceived.invoke(DataReceivedEventArgs(data, amount, udpConnection));
    }
  }
}
