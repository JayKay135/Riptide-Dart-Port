import 'dart:io';
import 'dart:typed_data';

import '../../utils/event_handler.dart';
import '../connection.dart';
import '../event_args.dart';
import '../ipeer.dart';
import '../iserver.dart';
import 'udp_connection.dart';
import 'udp_peer.dart';

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
  late Map<InternetAddress, Connection> _connections;

  /// The IP address to bind the socket to, if any.
  late InternetAddress _listenAddress;
  InternetAddress get listenAddress => _listenAddress;

  /// Initializes the transport, binding the socket to a specific IP address.
  ///
  /// [listenAddress] : The IP address to bind the socket to.
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  UdpServer({InternetAddress? listenAddress, int socketBufferSize = UdpPeer.defaultSocketBufferSize}) : super(socketBufferSize: socketBufferSize) {
    _listenAddress = listenAddress ?? InternetAddress.anyIPv4;
  }

  @override
  void start(int port) {
    port = port;
    _connections = {};

    openSocket(listenAddress: listenAddress, port: port);
  }

  /// Decides what to do with a connection attempt.
  ///
  /// [fromEndPoint] : The endpoint the connection attempt is coming from.
  /// Returns whether or not the connection attempt was from a new connection.
  bool _handleConnectionAttempt(InternetAddress fromEndPoint, int port) {
    if (_connections.containsKey(fromEndPoint)) {
      return false;
    }

    UdpConnection connection = UdpConnection(fromEndPoint, port, this);
    _connections[fromEndPoint] = connection;
    onConnected(connection);
    return true;
  }

  @override
  void close(Connection connection) {
    if (connection is UdpConnection) {
      _connections.remove(connection.remoteEndPoint);
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
    if (MessageHeader.values[data.first] == MessageHeader.connect && !_handleConnectionAttempt(fromEndPoint, port)) {
      return;
    }

    if (_connections.containsKey(fromEndPoint)) {
      Connection connection = _connections[fromEndPoint]!;

      if (!connection.isNotConnected) {
        dataReceived.invoke(DataReceivedEventArgs(data, amount, connection));
      }
    }
  }
}
