import 'dart:io';
import 'dart:typed_data';

import '../event_args.dart';
import '../../connection.dart';
import '../../peer.dart';
import '../../utils/event_handler.dart';

/// Provides base send &#38; receive functionality for TcpServer and TcpClient.
abstract class UdpPeer extends Peer {
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
  late RawDatagramSocket socket;

  bool _isRunning = false;

  late InternetAddress _remoteEndPoint;

  /// Initializes the transport.
  ///
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  UdpPeer({int socketBufferSize = defaultSocketBufferSize}) {
    if (socketBufferSize < minSocketBufferSize) {
      throw RangeError("The minimum socket buffer size is $minSocketBufferSize!");
    }

    _socketBufferSize = socketBufferSize;

    _remoteEndPoint = InternetAddress.anyIPv4;
  }

  void poll() {
    // NOTE: Not required for the underlying dart socket library
  }

  /// Opens the socket and starts the transport.
  ///
  /// [listenAddress] : The IP address to bind the socket to, if any.
  /// [port] : The port to bind the socket to.
  Future<void> openSocket({InternetAddress? listenAddress, required int port, bool ipv6 = true}) async {
    if (_isRunning) {
      closeSocket();
    }

    _remoteEndPoint = listenAddress ?? (ipv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4);

    socket = await RawDatagramSocket.bind(_remoteEndPoint, port);
    socket.listen(_receive);

    _isRunning = true;
  }

  /// Closes the socket and stops the transport.
  void closeSocket() {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    socket.close();
  }

  /// Sends data to a given endpoint.
  ///
  /// [data] : The array containing the data.
  /// [numBytes] : The number of bytes in the array which should be sent.
  /// [toEndPoint] : The endpoint to send the data to.
  void send(Uint8List data, int numBytes, InternetAddress toEndPoint, int port) {
    try {
      if (_isRunning) {
        socket.send(data.sublist(0, numBytes), toEndPoint, port);
      }
    } on SocketException {
      // May want to consider triggering a disconnect here (perhaps depending on the type
      // of SocketException)? Timeout should catch disconnections, but disconnecting
      // explicitly might be better...
    }
  }

  /// Handles received data from the socket
  void _receive(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      Datagram? dg = socket.receive();
      int byteCount = 0;

      if (dg != null) {
        byteCount = dg.data.length;

        onDataReceived(dg.data, byteCount, dg.address, dg.port);
      }
    } else if (event == RawSocketEvent.closed) {
      _isRunning = false;
    }
  }

  /// Handles received data.
  ///
  /// [data] : A Uint8List containing the received data.
  /// [amount] : The number of bytes that were received.
  /// [fromEndPoint] : The connection from which the data was received.
  void onDataReceived(Uint8List data, int amount, InternetAddress fromEndPoint, int port);

  /// Invokes the disconnected event.
  ///
  /// [connection] : The closed connection.
  /// [reason] : The reason for the disconnection.
  void onDisconnected(Connection connection, DisconnectReason reason) {
    disconnected.invoke(DisconnectedEventArgs(connection, reason));
  }
}
