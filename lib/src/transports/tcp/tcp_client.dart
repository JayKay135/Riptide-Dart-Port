import 'dart:async';
import 'dart:io';

import 'tcp_connection.dart';
import 'tcp_peer.dart';
import 'tcp_server.dart';
import '../event_args.dart';
import '../iclient.dart';
import '../../connection.dart';
import '../../utils/event_handler.dart';

/// A client which can connect to a [TcpServer].
class TcpClient extends TcpPeer implements IClient {
  @override
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  @override
  // ignore: strict_raw_type
  Event connected = Event();

  @override
  // ignore: strict_raw_type
  Event connectionFailed = Event();

  @override
  Event<DataReceivedEventArgs> dataReceived = Event<DataReceivedEventArgs>();

  /// The connection to the server.
  TcpConnection? tcpConnection;

  /// Client socket for sending and receiving data.
  Socket? socket;

  @override
  Future<(bool connected, Connection? connection, String error)> connect(
      InternetAddress hostAddress, int port) async {
    try {
      socket = await Socket.connect(hostAddress, port);
    } catch (e) {
      return (false, null, e.toString());
    }

    InternetAddress fromEndPoint = socket!.address;
    TcpConnection connection =
        tcpConnection = TcpConnection(socket!, fromEndPoint, this);
    onConnected();

    return (true, connection, "");
  }

  @override
  void poll() {
    tcpConnection?.receive();
  }

  @override
  void disconnect() {
    socket?.close();
    tcpConnection = null;
  }

  /// Invokes the [connected] event.
  void onConnected() {
    connected.invoke(this);
  }

  /// Invokes the [connectionFailed] event.
  void onConnectionFailed() {
    connectionFailed.invoke(
      this,
    );
  }

  @override
  void onDataReceived(int amount, TcpConnection fromConnection) {
    dataReceived
        .invoke(DataReceivedEventArgs(receiveBuffer, amount, fromConnection));
  }
}
