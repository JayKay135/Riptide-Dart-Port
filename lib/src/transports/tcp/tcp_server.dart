import 'dart:core';
import 'dart:io';

import '../../connection.dart';
import '../event_args.dart';
import '../../utils/event_handler.dart';
import '../ipeer.dart';
import '../iserver.dart';
import 'tcp_connection.dart';
import 'tcp_peer.dart';

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
  int _maxPendingConnections = 5;
  int get maxPendingConnections => _maxPendingConnections;

  /// Whether or not the server is running.
  bool _isRunning = false;

  /// The currently open connections, accessible by their endpoints.
  late Map<InternetAddress, TcpConnection> _connections;

  /// Connections that have been closed and need to be removed from <see cref="connections"/>.
  //List<InternetAddress> _closedConnections = [];

  /// The IP address to bind the socket to.
  late InternetAddress _listenAddress;
  InternetAddress get listenAddress => _listenAddress;

  /// Initializes the transport, binding the socket to a specific IP address.
  ///
  /// [listenAddress] : The IP address to bind the socket to.
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  TcpServer({InternetAddress? listenAddress, int socketBufferSize = TcpPeer.defaultSocketBufferSize}) : super(socketBufferSize: socketBufferSize) {
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

    // InternetAddress localEndPoint = new IPEndPoint(listenAddress, port);
    // socket = Socket(SocketType.Stream, ProtocolType.Tcp)
    // {
    //     SendBufferSize = socketBufferSize,
    //     ReceiveBufferSize = socketBufferSize,
    // };
    // socket.Bind(localEndPoint);
    // socket.Listen(MaxPendingConnections);

    serverSocket = await ServerSocket.bind(_listenAddress, port);
    serverSocket!.listen((Socket newSocket) {
      //newSocket.setRawOption(RawSocketOption.fromBool(RawSocketOption.levelSocket, 2, true));
      // bool optionSet = newSocket.setOption(SocketOption.tcpNoDelay, false);
      // print("option was successfully set: $optionSet");

      InternetAddress fromEndPoint = newSocket.remoteAddress;

      if (!_connections.containsKey(fromEndPoint)) {
        TcpConnection newConnection = TcpConnection(newSocket, fromEndPoint, this);
        _connections[fromEndPoint] = newConnection;
        onConnected(newConnection);
      } else {
        newSocket.close();
      }

      // // listen for send data
      // newSocket.listen((Uint8List data) {
      //   print("raw data: $data");

      //   // _connections[newSocket.address]?.receive(data);
      //   onDataReceived(data, data.length, _connections[fromEndPoint]!);
      // });
    });

    _isRunning = true;
  }

  @override
  void poll() {
    if (!_isRunning) {
      return;
    }

    //_accept();
    for (TcpConnection connection in _connections.values) {
      connection.receive();
    }

    // for (InternetAddress endPoint in _closedConnections) {
    //   _connections.remove(endPoint);
    // }

    // _closedConnections.clear();
  }

  // /// Accepts any pending connections.
  // void _accept() {
  //   if (socket.poll(0, SelectMode.SelectRead)) {
  //       Socket acceptedSocket = socket.accept();
  //       InternetAddress fromEndPoint = acceptedSocket.remoteAddress;
  //       if (!_connections.containsKey(fromEndPoint))
  //       {
  //           TcpConnection newConnection = TcpConnection(acceptedSocket, fromEndPoint, this);
  //           _connections[fromEndPoint] = newConnection;
  //           onConnected(newConnection);
  //       } else {
  //         acceptedSocket.close();
  //       }
  //   }
  // }

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
      //_closedConnections.add(connection.remoteEndPoint);
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

  // @override
  // void onDataReceived(int amount, TcpConnection fromConnection) {
  //   print("received data");
  //   if (receiveBuffer.getUint8(0) == MessageHeader.connect.index && !fromConnection.isConnecting()) {
  //     return;
  //   }

  //   print(receiveBuffer.buffer.asUint8List());

  //   dataReceived.invoke(DataReceivedEventArgs(receiveBuffer.buffer.asUint8List(), amount, fromConnection));
  // }

  @override
  void onDataReceived(int amount, TcpConnection fromConnection) {
    // if (MessageHeader.values[data[0]] == MessageHeader.connect && !fromConnection.isConnecting()) {
    //   return;
    // }

    if (MessageHeader.values[receiveBuffer.first] == MessageHeader.connect) {
      if (fromConnection.didReceiveConnect) {
        return;
      }

      fromConnection.didReceiveConnect = true;
    }

    //print("receiveBuffer: ${receiveBuffer.getRange(0, amount)}");

    dataReceived.invoke(DataReceivedEventArgs(receiveBuffer, amount, fromConnection));
  }
}
