import 'dart:io';
import 'dart:typed_data';

import '../event_args.dart';
import '../socket_buffer_size.dart';
import '../../connection.dart';
import '../../message.dart';
import '../../peer.dart';
import '../../utils/event_handler.dart';
import '../../utils/riptide_logger.dart';

/// Provides base send &#38; receive functionality for UdpServer and UdpClient.
abstract class UdpPeer {
  abstract Event<DisconnectedEventArgs> disconnected;

  /// The default size used for the socket's send and receive buffers.
  static const int defaultSocketBufferSize = 1024 * 1024; // 1MB

  /// The minimum size that may be used for the socket's send and receive buffers.
  static const int minSocketBufferSize = 256 * 1024;

  /// How long to wait for a packet, in microseconds.
  final int receivePollingTime = 500000; // 0.5 seconds

  /// The size to use for the socket's send and receive buffers.
  late int _socketBufferSize;
  int get socketBufferSize => _socketBufferSize;

  /// The main socket, either used for listening for connections or for sending and receiving data.
  RawDatagramSocket? _socket;
  RawDatagramSocket? get socket => _socket;

  /// Whether or not the transport is running.
  bool _isRunning = false;

  /// Whether or not the socket should be reopened once it's closed, which is the case if it was closed due to an error.
  bool _reopenOnClose = false;

  /// Incremented whenever the socket is intentionally opened or closed, so that pending (re)binds can detect that
  /// they're outdated.
  int _socketGeneration = 0;

  /// The address the socket is bound to.
  late InternetAddress _listenAddress;

  /// The port the socket is bound to.
  int _port = 0;

  /// Initializes the transport.
  ///
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  UdpPeer({int socketBufferSize = defaultSocketBufferSize}) {
    if (socketBufferSize < minSocketBufferSize) {
      throw RangeError("The minimum socket buffer size is $minSocketBufferSize!");
    }

    _socketBufferSize = socketBufferSize;
    _listenAddress = InternetAddress.anyIPv4;
    Message.initialize();
  }

  void poll() {
    // NOTE: Not required, as dart:io notifies the socket's listener as soon as data is available
  }

  /// Opens the socket and starts the transport.
  ///
  /// [listenAddress] : The IP address to bind the socket to, if any.
  /// [port] : The port to bind the socket to.
  /// [ipv6] : Whether to bind to the IPv6 or IPv4 wildcard address if no [listenAddress] is given.
  Future<void> openSocket({InternetAddress? listenAddress, int port = 0, bool ipv6 = true}) async {
    if (_isRunning) {
      closeSocket();
    }

    _listenAddress = listenAddress ?? (ipv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4);
    int generation = ++_socketGeneration;
    RawDatagramSocket socket = await RawDatagramSocket.bind(_listenAddress, port);
    if (generation != _socketGeneration) {
      socket.close(); // The socket was closed or reopened while binding
      return;
    }

    _port = socket.port; // The actual port, in case an ephemeral one was requested
    _isRunning = true;
    _listen(socket);
  }

  /// Makes the given socket the transport's socket and starts listening to it.
  ///
  /// [socket] : The socket to use.
  void _listen(RawDatagramSocket socket) {
    _socket = socket;
    setSocketBufferSizes(socket.setRawOption, _socketBufferSize);
    socket.listen((RawSocketEvent event) => _receive(socket, event),
        onError: (Object error) => _onSocketError(socket, error));
  }

  /// Closes the socket and stops the transport.
  void closeSocket() {
    _socketGeneration++; // Also cancels binds which are still in progress

    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    _reopenOnClose = false;
    _socket?.close();
  }

  /// Sends data to a given endpoint.
  ///
  /// [data] : The array containing the data.
  /// [numBytes] : The number of bytes in the array which should be sent.
  /// [toEndPoint] : The endpoint to send the data to.
  /// [port] : The port to send the data to.
  void send(Uint8List data, int numBytes, InternetAddress toEndPoint, int port) {
    // NOTE: dart:io doesn't throw when sending fails, but reports the error to the socket's listener instead
    if (_isRunning) {
      _socket!.send(Uint8List.sublistView(data, 0, numBytes), toEndPoint, port);
    }
  }

  /// Handles events of the given socket.
  ///
  /// [socket] : The socket which emitted the event.
  /// [event] : The event.
  void _receive(RawDatagramSocket socket, RawSocketEvent event) {
    if (!identical(socket, _socket)) {
      return; // The event belongs to a socket which has been replaced already
    }

    if (event == RawSocketEvent.read) {
      Datagram? datagram;
      while (_isRunning && (datagram = socket.receive()) != null) {
        int byteCount = datagram!.data.length;

        // Like in C#, empty datagrams are ignored and those which don't fit into a message are discarded
        if (byteCount > 0 && byteCount <= Message.maxSize) {
          onDataReceived(datagram.data, byteCount, datagram.address, datagram.port);
        }
      }
    } else if (event == RawSocketEvent.closed) {
      if (_reopenOnClose) {
        _reopenOnClose = false;
        _reopen();
      } else {
        _isRunning = false;
      }
    }
  }

  /// Handles errors of the given socket.
  ///
  /// [socket] : The socket which encountered the error.
  /// [error] : The error.
  ///
  /// NOTE: Unlike C#, dart:io closes the socket after any error, so it has to be reopened to keep receiving data.
  void _onSocketError(RawDatagramSocket socket, Object error) {
    if (!identical(socket, _socket) || !_isRunning) {
      return;
    }

    RiptideLogger.log(LogType.warning, "UDP socket error, reopening the socket: $error");
    _reopenOnClose = true;
  }

  /// Reopens the socket on the endpoint it was previously bound to.
  Future<void> _reopen() async {
    int generation = _socketGeneration;
    try {
      RawDatagramSocket socket = await RawDatagramSocket.bind(_listenAddress, _port);
      if (generation != _socketGeneration || !_isRunning) {
        socket.close(); // The socket was closed or reopened in the meantime
        return;
      }

      _listen(socket);
    } on SocketException catch (e) {
      if (generation == _socketGeneration) {
        _isRunning = false;
        RiptideLogger.log(LogType.error, "Failed to reopen the UDP socket: $e");
      }
    }
  }

  /// Handles received data.
  ///
  /// [data] : A Uint8List containing the received data.
  /// [amount] : The number of bytes that were received.
  /// [fromEndPoint] : The connection from which the data was received.
  /// [port] : The port from which the data was received.
  void onDataReceived(Uint8List data, int amount, InternetAddress fromEndPoint, int port);

  /// Invokes the disconnected event.
  ///
  /// [connection] : The closed connection.
  /// [reason] : The reason for the disconnection.
  void onDisconnected(Connection connection, DisconnectReason reason) {
    disconnected.invoke(DisconnectedEventArgs(connection, reason));
  }
}
