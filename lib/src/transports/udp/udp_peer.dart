import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../event_args.dart';
import '../socket_buffer_size.dart';
import '../../connection.dart';
import '../../message.dart';
import '../../utils/converter.dart';
import '../ipeer.dart';
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

  /// The maximum number of datagrams which may be waiting to be sent.
  static const int _maxQueuedDatagrams = 4096;

  /// Datagrams which couldn't be sent right away because the socket's send buffer was full.
  ///
  /// NOTE: C# sockets block until data can be sent, whereas Dart's datagram sockets return without sending it, so the
  /// datagrams are queued and sent once the socket is writable again.
  final ListQueue<(Uint8List data, InternetAddress toEndPoint, int port)> _sendQueue = ListQueue();

  /// The endpoints and sequence IDs of the reliable messages in [_sendQueue].
  ///
  /// Resending a reliable message while it's still waiting to be sent is pointless (the receiver discards duplicates),
  /// but it happens when sending many messages at once, as the send queue then takes longer to be sent than it takes
  /// for the messages to be resent. Skipping such resends prevents the queue from growing faster than it's sent.
  final Set<(InternetAddress toEndPoint, int port, int sequenceId)> _queuedReliableMessages = {};

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
    // NOTE: Dart allows binding ports which are already in use by default, whereas C# doesn't
    RawDatagramSocket socket = await RawDatagramSocket.bind(_listenAddress, port, reuseAddress: false);
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
    _sendQueue.clear();
    _queuedReliableMessages.clear();
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
    if (!_isRunning) {
      return;
    }

    RawDatagramSocket socket = _socket!;
    if (_sendQueue.isEmpty && socket.send(Uint8List.sublistView(data, 0, numBytes), toEndPoint, port) > 0) {
      return;
    }

    // The data couldn't be sent right away (or older data is still waiting to be sent), so queue a copy of it, as the
    // given buffer is reused
    if (_sendQueue.length < _maxQueuedDatagrams) {
      (InternetAddress, int, int)? reliableMessage = _getReliableMessage(data, numBytes, toEndPoint, port);
      if (reliableMessage == null || _queuedReliableMessages.add(reliableMessage)) {
        _sendQueue.add((Uint8List.fromList(Uint8List.sublistView(data, 0, numBytes)), toEndPoint, port));
      }
    }

    socket.writeEventsEnabled = true;
  }

  /// Identifies the reliable message contained in the given data, if it contains one.
  ///
  /// [data] : The data to check.
  /// [numBytes] : The number of bytes in the data.
  /// [toEndPoint] : The endpoint the data is sent to.
  /// [port] : The port the data is sent to.
  ///
  /// Returns the endpoint and sequence ID of the reliable message, or null if the data doesn't contain one.
  (InternetAddress, int, int)? _getReliableMessage(Uint8List data, int numBytes, InternetAddress toEndPoint, int port) {
    int header = data[0] & Message.headerBitmask;
    if (numBytes < Message.minReliableBytes ||
        header < MessageHeader.reliable.index ||
        header >= MessageHeader.values.length) {
      return null;
    }

    return (toEndPoint, port, Converter.uShortFromByteBits(data, Message.headerBits));
  }

  /// Sends the queued datagrams, as far as the given socket's send buffer allows it.
  ///
  /// [socket] : The socket to send the datagrams with.
  void _sendQueued(RawDatagramSocket socket) {
    while (_sendQueue.isNotEmpty) {
      var (Uint8List data, InternetAddress toEndPoint, int port) = _sendQueue.first;
      if (socket.send(data, toEndPoint, port) == 0) {
        socket.writeEventsEnabled = true; // Try again once the socket is writable
        return;
      }

      _sendQueue.removeFirst();
      (InternetAddress, int, int)? reliableMessage = _getReliableMessage(data, data.length, toEndPoint, port);
      if (reliableMessage != null) {
        _queuedReliableMessages.remove(reliableMessage);
      }
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
    } else if (event == RawSocketEvent.write) {
      _sendQueued(socket);
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
    _sendQueue.clear(); // One of the queued datagrams may have caused the error
    _queuedReliableMessages.clear();
  }

  /// Reopens the socket on the endpoint it was previously bound to.
  Future<void> _reopen() async {
    int generation = _socketGeneration;
    try {
      RawDatagramSocket socket = await RawDatagramSocket.bind(_listenAddress, _port, reuseAddress: false);
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
