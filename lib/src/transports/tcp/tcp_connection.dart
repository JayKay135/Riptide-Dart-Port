import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'tcp_peer.dart';
import '../../connection.dart';
import '../../utils/constants.dart';
import '../../utils/converter.dart';

class TcpConnection extends Connection {
  /// The endpoint representing the other end of the connection.
  late final InternetAddress remoteEndPoint;

  /// Whether or not the server has received a connection attempt from this connection.
  bool didReceiveConnect = false;

  /// The socket to use for sending and receiving.
  late final Socket _socket;

  /// The local peer this connection is associated with.
  late final TcpPeer _peer;

  /// An array to receive message size values into.
  Uint8List _sizeBytes = Uint8List(Constants.intBytes);

  Queue<int> queue = Queue<int>();

  /// The size of the next message to be received.
  late int _nextMessageSize = 0;

  /// Initializes the connection.
  ///
  /// [socket] : The socket to use for sending and receiving.
  /// [remoteEndPoint] : The endpoint representing the other end of the connection.
  /// [peer] : The local peer this connection is associated with.
  TcpConnection(Socket socket, InternetAddress remoteEndPoint, TcpPeer peer) {
    this.remoteEndPoint = remoteEndPoint;
    _socket = socket;
    _peer = peer;

    _socket.listen((Uint8List data) {
      if (data.isNotEmpty) {
        queue.addAll(data);
      }
    });
  }

  /// Polls the socket and checks if any data was received.
  void receive() {
    bool tryReceiveMore = true;

    while (tryReceiveMore) {
      int byteCount = 0;

      if (_nextMessageSize > 0) {
        // We already have a size value for the message size
        (bool canReceiveMesssage, int receivedByteCount) data = _tryReceiveMessage();
        tryReceiveMore = data.$1;
        byteCount = data.$2;
      } else if (queue.length >= Constants.intBytes) {
        // We have enough bytes for a complete size value
        _sizeBytes.setAll(0, queue.take(Constants.intBytes));

        for (int i = 0; i < Constants.intBytes; i++) {
          queue.removeFirst();
        }

        _nextMessageSize = Converter.toInt(_sizeBytes.buffer.asByteData(), 0);

        if (_nextMessageSize > 0) {
          (bool canReceiveMesssage, int receivedByteCount) data = _tryReceiveMessage();
          tryReceiveMore = data.$1;
          byteCount = data.$2;
        }
      } else {
        tryReceiveMore = false;
      }

      if (byteCount > 0) {
        _peer.onDataReceived(byteCount, this);
      }
    }
  }

  /// Receives a message, if all of its data is ready to be received.
  ///
  /// Returns whether or not all of the message's data was ready to be received and how many bytes were received
  (bool canReceiveMesssage, int receivedByteCount) _tryReceiveMessage() {
    int receivedByteCount = 0;

    if (queue.length >= _nextMessageSize) {
      // We have enough bytes to read the complete message
      receivedByteCount = _nextMessageSize;
      _nextMessageSize = 0;

      List<int> data = queue.take(receivedByteCount).toList();
      for (int i = 0; i < receivedByteCount; i++) {
        queue.removeFirst();
      }

      _peer.receiveBuffer.setAll(0, data);

      return (true, receivedByteCount);
    }

    return (false, receivedByteCount);
  }

  @override
  void send(Uint8List dataBuffer, int amount) {
    if (amount == 0) {
      throw RangeError("Sending 0 bytes is not allowed!");
    }

    try {
      Converter.fromInt(amount, _peer.sendBuffer.buffer.asByteData(), 0);

      // TODO: consider sending length separately with an extra socket.Send call instead of copying the data an extra time
      _peer.sendBuffer.setRange(Constants.intBytes, Constants.intBytes + amount, dataBuffer);

      List<int> sendingData = _peer.sendBuffer.getRange(0, amount + Constants.intBytes).toList();

      _socket.add(sendingData);
    } on SocketException {
      // May want to consider triggering a disconnect here (perhaps depending on the type
      // of SocketException)? Timeout should catch disconnections, but disconnecting
      // explicitly might be better...
    }
  }

  /// Closes the connection.
  void close() {
    _socket.close();
  }

  @override
  String toString() => remoteEndPoint.toString();
}
