import 'dart:async';
import 'dart:io';

import 'tcp_connection.dart';
import 'tcp_peer.dart';
import 'tcp_server.dart';
import '../event_args.dart';
import '../socket_buffer_size.dart';
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
  Future<(bool connected, Connection? connection, String error)> connect(InternetAddress hostAddress, int port) async {
    // NOTE: Unlike in C#, connecting happens asynchronously, so a failed connection attempt can be reported right away
    // instead of letting Riptide detect that no connection was established
    try {
      socket = await Socket.connect(hostAddress, port);
      socket!.setOption(SocketOption.tcpNoDelay, true);
      setSocketBufferSizes(socket!.setRawOption, socketBufferSize);
    } on SocketException catch (e) {
      return (false, null, e.toString());
    }

    TcpConnection connection = tcpConnection = TcpConnection(socket!, socket!.remoteAddress, this);
    onConnected();

    return (true, connection, "");
  }

  @override
  void poll() {
    tcpConnection?.receive();
  }

  @override
  void disconnect() {
    tcpConnection?.close();
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
    dataReceived.invoke(DataReceivedEventArgs(receiveBuffer, amount, fromConnection));
  }
}
