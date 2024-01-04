import 'dart:core';
import 'dart:io';

import 'tcp_connection.dart';
import 'tcp_peer.dart';
import '../event_args.dart';
import '../ipeer.dart';
import '../iserver.dart';
import '../../connection.dart';
import '../../message.dart';
import '../../utils/event_handler.dart';

/// A server which can accept connections from TcpClients.
class TcpServer extends TcpPeer implements IServer {
  @override
  Event<DisconnectedEventArgs> disconnected = Event<DisconnectedEventArgs>();

  @override
  Event<ConnectedEventArgs> connected = Event<ConnectedEventArgs>();

  @override
  Event<DataReceivedEventArgs> dataReceived = Event<DataReceivedEventArgs>();

  @override
  late int port;

  /// The maximum number of pending connections to allow at any given time.
  final int _maxPendingConnections = 5;
  int get maxPendingConnections => _maxPendingConnections;

  /// Whether or not the server is running.
  bool _isRunning = false;

  /// The currently open connections, accessible by their endpoints.
  late Map<InternetAddress, TcpConnection> _connections;

  /// Connections that have been closed and need to be removed from <see cref="connections"/>.
  final List<InternetAddress> _closedConnections = [];

  /// The IP address to bind the socket to.
  late InternetAddress _listenAddress;
  InternetAddress get listenAddress => _listenAddress;

  /// Initializes the transport, binding the socket to a specific IP address.
  ///
  /// [listenAddress] : The IP address to bind the socket to.
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  TcpServer({InternetAddress? listenAddress, super.socketBufferSize}) {
    _listenAddress = listenAddress ?? InternetAddress.anyIPv4;
  }

  @override
  void start(int port) {
    port = port;
    _connections = {};

    _startListening(port);
  }

  /// Starts listening for connections on the given port.
  ///
  /// [port] : The port to listen on.
  void _startListening(int port) async {
    if (_isRunning) {
      _stopListening();
    }

    serverSocket = await ServerSocket.bind(_listenAddress, port);

    serverSocket!.listen((Socket newSocket) {
      InternetAddress fromEndPoint = newSocket.remoteAddress;

      if (!_connections.containsKey(fromEndPoint)) {
        TcpConnection newConnection =
            TcpConnection(newSocket, fromEndPoint, this);
        _connections[fromEndPoint] = newConnection;
        onConnected(newConnection);
      } else {
        newSocket.close();
      }
    });

    _isRunning = true;
  }

  @override
  void poll() {
    if (!_isRunning) {
      return;
    }

    for (TcpConnection connection in _connections.values) {
      connection.receive();
    }

    for (InternetAddress endPoint in _closedConnections) {
      _connections.remove(endPoint);
    }

    _closedConnections.clear();
  }

  /// Stops listening for connections.
  void _stopListening() {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    serverSocket?.close();
    socket?.close();
  }

  @override
  void close(Connection connection) {
    if (connection is TcpConnection) {
      _closedConnections.add(connection.remoteEndPoint);
      connection.close();
    }
  }

  @override
  void shutdown() {
    _stopListening();
    _connections.clear();
  }

  /// Invokes the connected event.
  ///
  /// [connection] : The successfully established connection.
  void onConnected(Connection connection) {
    connected.invoke(ConnectedEventArgs(connection));
  }

  @override
  void onDataReceived(int amount, TcpConnection fromConnection) {
    if (MessageHeader.values[receiveBuffer.first & Message.headerBitmask] ==
        MessageHeader.connect) {
      if (fromConnection.didReceiveConnect) {
        return;
      }

      fromConnection.didReceiveConnect = true;
    }

    dataReceived
        .invoke(DataReceivedEventArgs(receiveBuffer, amount, fromConnection));
  }
}
