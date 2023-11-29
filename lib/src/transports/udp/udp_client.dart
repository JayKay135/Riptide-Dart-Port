import 'dart:io';
import 'dart:typed_data';

import '../../connection.dart';
import '../event_args.dart';
import 'udp_peer.dart';
import '../../utils/event_handler.dart';
import '../iclient.dart';
import 'udp_connection.dart';

/// A client which can connect to a UdpServer.
class UdpClient extends UdpPeer implements IClient {
  @override
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  @override
  Event connected = Event();

  @override
  Event connectionFailed = Event();

  @override
  Event<DataReceivedEventArgs> dataReceived = Event<DataReceivedEventArgs>();

  /// The connection to the server.
  late UdpConnection udpConnection;

  UdpClient({int socketBufferSize = UdpPeer.defaultSocketBufferSize}) : super(socketBufferSize: socketBufferSize);

  @override
  Future<(bool, Connection, String)> connect(InternetAddress hostAddress, int port) async {
    String connectError = "";

    await openSocket(listenAddress: InternetAddress.anyIPv4, port: port + 1);

    udpConnection = UdpConnection(hostAddress, port, this);

    // UDP is connectionless, so from the transport POV everything is immediately ready to send/receive data
    _onConnected();

    return (true, udpConnection, connectError);
  }

  @override
  void disconnect() {
    closeSocket();
  }

  /// Invokes the connected event.
  void _onConnected() {
    connected.invoke(null);
  }

  /// Invokes the connectionFailed event.
  void onConnectionFailed() {
    connectionFailed.invoke(null);
  }

  @override
  void onDataReceived(Uint8List data, int amount, InternetAddress fromEndPoint, int port) {
    if (udpConnection.remoteEndPoint == fromEndPoint && !udpConnection.isNotConnected) {
      dataReceived.invoke(DataReceivedEventArgs(data, amount, udpConnection));
    }
  }
}
