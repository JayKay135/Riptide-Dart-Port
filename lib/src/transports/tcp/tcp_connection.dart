import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/constants.dart';
import '../../utils/converter.dart';
import '../../connection.dart';
import 'tcp_peer.dart';

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
  Uint8List _sizeBytes = Uint8List(Constants.ushortBytes);

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

    // Makes sure, that bytes are not buffered internally
    //_socket.setOption(SocketOption.tcpNoDelay, true);

    _socket.listen((Uint8List data) {
      if (data.isNotEmpty) {
        // builder.add(data);
        queue.addAll(data);
        // _peer.onDataReceived(data, data.length, this);
      }
    });

    // var fromByte = StreamTransformer<Uint8List, List<int>>.fromHandlers(handleData: (data, sink) {
    //   sink.add(data.buffer.asInt64List());
    // });

    // _socket.transform(fromByte).listen((e) => e.forEach(print));
  }

  void receive() {
    bool tryReceiveMore = true;

    while (tryReceiveMore) {
      int byteCount = 0;

      if (_nextMessageSize > 0) {
        // We already have a size value for the message size
        (bool canReceiveMesssage, int receivedByteCount) data = _tryReceiveMessage();
        tryReceiveMore = data.$1;
        byteCount = data.$2;
      } else if (queue.length >= Constants.ushortBytes) {
        // We have enough bytes for a complete size value
        _sizeBytes.setAll(0, queue.take(Constants.ushortBytes));

        for (int i = 0; i < Constants.ushortBytes; i++) {
          queue.removeFirst();
        }

        _nextMessageSize = Converter.toUShort(_sizeBytes.buffer.asByteData(), 0);

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
      Converter.fromUShort(amount, _peer.sendBuffer.buffer.asByteData(), 0);

      // TODO: consider sending length separately with an extra socket.Send call instead of copying the data an extra time
      _peer.sendBuffer.setRange(Constants.ushortBytes, Constants.ushortBytes + amount, dataBuffer);

      _socket.add(_peer.sendBuffer.getRange(0, amount + Constants.ushortBytes).toList());
    } on SocketException {
      // May want to consider triggering a disconnect here (perhaps depending on the type
      // of SocketException)? Timeout should catch disconnections, but disconnecting
      // explicitly might be better...
      print("SOCKET ERROR");
    }
  }

  // /// Polls the socket and checks if any data was received.
  // Future<void> receive(Uint8List data) async {
  //   bool tryReceiveMore = true;

  //   while (tryReceiveMore) {
  //     int byteCount = 0;

  //     try {
  //       if (_nextMessageSize > 0) {
  //         // We already have a size value
  //         (bool receivedData, int receivedByteCount) data2 = await _tryReceiveMessage();
  //         tryReceiveMore = data2.$1;
  //         byteCount = data2.$2;
  //       } else if (data.length >= Constants.intBytes) {
  //         // We have enough bytes for a complete size value
  //         _sizeBytes = data;
  //         _nextMessageSize = Converter.toInt(_sizeBytes.buffer.asByteData(), 0);

  //         if (_nextMessageSize > 0) {
  //           (bool receivedData, int receivedByteCount) data2 = await _tryReceiveMessage();
  //           tryReceiveMore = data2.$1;
  //         }
  //       } else {
  //         tryReceiveMore = false;
  //       }
  //     } on SocketException catch (a, ex) {
  //       tryReceiveMore = false;
  //       switch (a.osError) {
  //         // case SocketError.Interrupted:
  //         // case SocketError.NotSocket:
  //         //     peer.OnDisconnected(this, DisconnectReason.transportError);
  //         //     break;
  //         // case SocketError.ConnectionReset:
  //         //     peer.OnDisconnected(this, DisconnectReason.disconnected);
  //         //     break;
  //         // case SocketError.TimedOut:
  //         //     peer.OnDisconnected(this, DisconnectReason.timedOut);
  //         //     break;
  //         // case SocketError.MessageSize:
  //         //     break;
  //         // default:
  //         //     break;
  //       }
  //     }
  //     // catch (ObjectDisposedException)
  //     // {
  //     //     tryReceiveMore = false;
  //     //     peer.OnDisconnected(this, DisconnectReason.TransportError);
  //     // }
  //     // catch (NullReferenceException)
  //     // {
  //     //     tryReceiveMore = false;
  //     //     peer.OnDisconnected(this, DisconnectReason.TransportError);
  //     // }

  //     if (byteCount > 0) {
  //       _peer.onDataReceived(byteCount, this);
  //     }
  //   }
  // }

  // /// Receives a message, if all of its data is ready to be received.
  // ///
  // /// Returns whether or not all of the message's data was ready to be received and how many bytes were received.
  // Future<(bool receivedData, int receivedByteCount)> _tryReceiveMessage() async {
  //   if (await _socket.length >= _nextMessageSize) {
  //     // We have enough bytes to read the complete message
  //     Uint8List data = await _socket.single;
  //     _nextMessageSize = 0;

  //     return (true, data.length);
  //   }

  //   return (false, 0);
  // }

  /// Closes the connection.
  void close() {
    _socket.close();
  }

  // @override
  // String toString() => remoteEndPoint.toString();
}
