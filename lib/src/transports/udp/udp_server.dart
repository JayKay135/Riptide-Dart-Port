import 'dart:io';
import 'dart:typed_data';

import 'udp_connection.dart';
import 'udp_peer.dart';
import '../event_args.dart';
import '../ipeer.dart';
import '../iserver.dart';
import '../../connection.dart';
import '../../message.dart';
import '../../utils/event_handler.dart';

/// A server which can accept connections from UdpClients
class UdpServer extends UdpPeer implements IServer {
  @override
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  @override
  Event<ConnectedEventArgs> connected = Event<ConnectedEventArgs>();

  @override
  Event<DataReceivedEventArgs> dataReceived = Event<DataReceivedEventArgs>();

  @override
  late int port;

  /// The currently open connections, accessible by their endpoints.
  ///
  /// NOTE: Dart has no equivalent of C#'s IPEndPoint, so endpoints are represented by records of the address and port.
  late Map<(InternetAddress, int), Connection> _connections;

  /// The IP address to bind the socket to, if any.
  late InternetAddress _listenAddress;
  InternetAddress get listenAddress => _listenAddress;

  /// Initializes the transport, binding the socket to a specific IP address.
  ///
  /// [listenAddress] : The IP address to bind the socket to.
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  UdpServer({InternetAddress? listenAddress, super.socketBufferSize}) {
    _listenAddress = listenAddress ?? InternetAddress.anyIPv4;
  }

  @override
  Future<void> start(int port) async {
    this.port = port;
    _connections = {};

    await openSocket(listenAddress: listenAddress, port: port);
  }

  /// Decides what to do with a connection attempt.
  ///
  /// [fromEndPoint] : The endpoint the connection attempt is coming from.
  ///
  /// Returns whether or not the connection attempt was from a new connection.
  bool _handleConnectionAttempt(InternetAddress fromEndPoint, int port) {
    if (_connections.containsKey((fromEndPoint, port))) {
      return false;
    }

    UdpConnection connection = UdpConnection(fromEndPoint, port, this);
    _connections[(fromEndPoint, port)] = connection;
    onConnected(connection);
    return true;
  }

  @override
  void close(Connection connection) {
    if (connection is UdpConnection) {
      _connections.remove((connection.remoteEndPoint, connection.port));
    }
  }

  @override
  void shutdown() {
    closeSocket();
    _connections.clear();
  }

  /// Invokes the connected event.
  ///
  /// [connection] : The successfully established connection.
  void onConnected(Connection connection) {
    connected.invoke(ConnectedEventArgs(connection));
  }

  @override
  void onDataReceived(Uint8List data, int amount, InternetAddress fromEndPoint, int port) {
    if ((data[0] & Message.headerBitmask) == MessageHeader.connect.index &&
        !_handleConnectionAttempt(fromEndPoint, port)) {
      return;
    }

    Connection? connection = _connections[(fromEndPoint, port)];
    if (connection != null && !connection.isNotConnected) {
      dataReceived.invoke(DataReceivedEventArgs(data, amount, connection));
    }
  }
}
