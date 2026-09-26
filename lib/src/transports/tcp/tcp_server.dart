import 'dart:core';
import 'dart:io';

import 'tcp_connection.dart';
import 'tcp_peer.dart';
import '../event_args.dart';
import '../socket_buffer_size.dart';
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
  ///
  /// NOTE: Dart has no equivalent of C#'s IPEndPoint, so endpoints are represented by records of the address and port.
  late Map<(InternetAddress, int), TcpConnection> _connections;

  /// Connections that have been closed and need to be removed from [_connections].
  final List<(InternetAddress, int)> _closedConnections = [];

  /// The IP address to bind the socket to.
  late InternetAddress _listenAddress;
  InternetAddress get listenAddress => _listenAddress;

  /// Server socket for listening for connections or for sending and receiving data.
  ServerSocket? serverSocket;

  /// Incremented whenever the server starts or stops listening, so that pending binds can detect that they're outdated.
  int _listenGeneration = 0;

  /// Initializes the transport, binding the socket to a specific IP address.
  ///
  /// [listenAddress] : The IP address to bind the socket to.
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  TcpServer({InternetAddress? listenAddress, super.socketBufferSize}) {
    _listenAddress = listenAddress ?? InternetAddress.anyIPv4;
  }

  @override
  Future<void> start(int port) async {
    this.port = port;
    _connections = {};

    await _startListening(port);
  }

  /// Starts listening for connections on the given port.
  ///
  /// [port] : The port to listen on.
  Future<void> _startListening(int port) async {
    if (_isRunning) {
      _stopListening();
    }

    int generation = ++_listenGeneration;
    ServerSocket socket = await ServerSocket.bind(_listenAddress, port);
    if (generation != _listenGeneration) {
      socket.close(); // The server was stopped or restarted while binding
      return;
    }

    serverSocket = socket;
    // NOTE: Dart accepts connections asynchronously instead of in poll()
    socket.listen(_accept, onError: (Object _) {}); // Failing to accept a connection doesn't affect other connections
    _isRunning = true;
  }

  /// Accepts a new connection.
  ///
  /// [acceptedSocket] : The socket of the new connection.
  void _accept(Socket acceptedSocket) {
    (InternetAddress, int) fromEndPoint;
    try {
      acceptedSocket.setOption(SocketOption.tcpNoDelay, true);
      setSocketBufferSizes(acceptedSocket.setRawOption, socketBufferSize);
      fromEndPoint = (acceptedSocket.remoteAddress, acceptedSocket.remotePort);
    } on SocketException {
      acceptedSocket.destroy(); // The connection was closed already
      return;
    }

    if (!_connections.containsKey(fromEndPoint)) {
      TcpConnection newConnection = TcpConnection(acceptedSocket, fromEndPoint.$1, this);
      _connections[fromEndPoint] = newConnection;
      onConnected(newConnection);
    } else {
      acceptedSocket.destroy();
    }
  }

  @override
  void poll() {
    if (!_isRunning) {
      return;
    }

    for (TcpConnection connection in _connections.values) {
      connection.receive();
    }

    for ((InternetAddress, int) endPoint in _closedConnections) {
      _connections.remove(endPoint);
    }

    _closedConnections.clear();
  }

  /// Stops listening for connections.
  void _stopListening() {
    _listenGeneration++; // Also cancels binds which are still in progress

    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    serverSocket?.close();
  }

  @override
  void close(Connection connection) {
    if (connection is TcpConnection) {
      _closedConnections.add((connection.remoteEndPoint, connection.remotePort));
      connection.close();
    }
  }

  @override
  void shutdown() {
    _stopListening();

    // NOTE: Unlike in C#, open sockets aren't cleaned up automatically (and would keep the process alive)
    for (TcpConnection connection in _connections.values) {
      connection.close();
    }

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
    if ((receiveBuffer[0] & Message.headerBitmask) == MessageHeader.connect.index) {
      if (fromConnection.didReceiveConnect) {
        return;
      }

      fromConnection.didReceiveConnect = true;
    }

    dataReceived.invoke(DataReceivedEventArgs(receiveBuffer, amount, fromConnection));
  }
}
