import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'tcp_peer.dart';
import '../../connection.dart';
import '../../peer.dart';
import '../../utils/constants.dart';
import '../../utils/converter.dart';

/// Represents a connection to a TcpServer or TcpClient.
class TcpConnection extends Connection {
  /// The endpoint representing the other end of the connection.
  late final InternetAddress remoteEndPoint;

  /// The port of the other end of the connection.
  late final int remotePort;

  /// Whether or not the server has received a connection attempt from this connection.
  bool didReceiveConnect = false;

  /// The socket to use for sending and receiving.
  late final Socket _socket;

  /// The local peer this connection is associated with.
  late final TcpPeer _peer;

  /// An array to receive message size values into.
  final Uint8List _sizeBytes = Uint8List(Constants.intBytes);

  /// The size of the next message to be received.
  int _nextMessageSize = 0;

  /// Received chunks of data which haven't been processed yet.
  ///
  /// NOTE: Unlike C# sockets, Dart sockets don't let data be read on demand, but deliver it in chunks as it arrives.
  final ListQueue<Uint8List> _receivedChunks = ListQueue<Uint8List>();

  /// The position in the first of the [_receivedChunks] at which its unprocessed data starts.
  int _chunkOffset = 0;

  /// The number of received bytes which haven't been processed yet. The equivalent of C#'s Socket.Available.
  int _available = 0;

  /// Whether or not the connection has been closed locally.
  bool _isClosed = false;

  /// The reason for a disconnection detected by the socket, which still has to be reported to the peer.
  DisconnectReason? _detectedDisconnectReason;

  /// Initializes the connection.
  ///
  /// [socket] : The socket to use for sending and receiving.
  /// [remoteEndPoint] : The endpoint representing the other end of the connection.
  /// [peer] : The local peer this connection is associated with.
  TcpConnection(Socket socket, this.remoteEndPoint, TcpPeer peer) {
    _socket = socket;
    _peer = peer;
    remotePort = socket.remotePort;

    _socket.listen(
        (Uint8List data) {
          if (data.isNotEmpty) {
            _receivedChunks.add(data);
            _available += data.length;
          }
        },
        onError: (Object error) => _onSocketClosed(_getDisconnectReason(error)),
        onDone: () {
          _onSocketClosed(DisconnectReason.disconnected);
        },
        cancelOnError: true);

    // Errors while sending are reported here, and would be unhandled otherwise
    _socket.done.catchError((Object error) => _onSocketClosed(_getDisconnectReason(error)));
  }

  /// Polls the socket and checks if any data was received.
  void receive() {
    bool tryReceiveMore = true;
    bool receivedData = false;

    while (tryReceiveMore) {
      int byteCount = 0;

      if (_nextMessageSize > 0) {
        // We already have a size value
        (bool canReceiveMesssage, int receivedByteCount) data = _tryReceiveMessage();
        tryReceiveMore = data.$1;
        byteCount = data.$2;
      } else if (_available >= Constants.intBytes) {
        // We have enough bytes for a complete size value
        _read(_sizeBytes, Constants.intBytes);
        int messageSize = Converter.toInt(_sizeBytes.buffer.asByteData(), 0);

        if (messageSize < 1 || messageSize > _peer.receiveBuffer.length) {
          // A size value this far out of range means the stream is out of sync, and since
          // there's no way of knowing where the next message starts, it can't be recovered
          tryReceiveMore = false;
          _peer.onDisconnected(this, DisconnectReason.transportError);
        } else {
          _nextMessageSize = messageSize;
          (bool canReceiveMesssage, int receivedByteCount) data = _tryReceiveMessage();
          tryReceiveMore = data.$1;
          byteCount = data.$2;
        }
      } else {
        tryReceiveMore = false;
      }

      if (byteCount > 0) {
        receivedData = true;
        _peer.onDataReceived(byteCount, this);
      }
    }

    // NOTE: In C#, socket errors are detected while receiving. Here they're reported once all data which was received
    // before them has been handled (on the next poll), so that for example a disconnect message's reason isn't lost.
    if (_detectedDisconnectReason != null && !receivedData && !_isClosed) {
      DisconnectReason reason = _detectedDisconnectReason!;
      _detectedDisconnectReason = null;
      _peer.onDisconnected(this, reason);
    }
  }

  /// Receives a message, if all of its data is ready to be received.
  ///
  /// Returns whether or not all of the message's data was ready to be received and how many bytes were received
  (bool canReceiveMesssage, int receivedByteCount) _tryReceiveMessage() {
    if (_available >= _nextMessageSize) {
      // We have enough bytes to read the complete message
      int receivedByteCount = _nextMessageSize;
      _read(_peer.receiveBuffer, receivedByteCount);
      _nextMessageSize = 0;
      return (true, receivedByteCount);
    }

    return (false, 0);
  }

  /// Reads the given [amount] of received bytes into [buffer].
  ///
  /// [buffer] : The buffer to write the bytes into.
  /// [amount] : The number of bytes to read. Must not exceed [_available].
  void _read(Uint8List buffer, int amount) {
    int readBytes = 0;
    while (readBytes < amount) {
      Uint8List chunk = _receivedChunks.first;
      int count = min(amount - readBytes, chunk.length - _chunkOffset);
      buffer.setRange(readBytes, readBytes + count, chunk, _chunkOffset);
      readBytes += count;
      _chunkOffset += count;

      if (_chunkOffset == chunk.length) {
        _receivedChunks.removeFirst();
        _chunkOffset = 0;
      }
    }

    _available -= amount;
  }

  @override
  void send(Uint8List dataBuffer, int amount) {
    if (amount == 0) {
      throw RangeError("Sending 0 bytes is not allowed!");
    }

    if (_isClosed || _detectedDisconnectReason != null) {
      return; // C# only sends if the socket is connected
    }

    Converter.fromInt(amount, _peer.sendBuffer.buffer.asByteData(), 0);
    // TODO: consider sending length separately with an extra socket.Send call instead of copying the data an extra time
    _peer.sendBuffer.setRange(Constants.intBytes, Constants.intBytes + amount, dataBuffer);

    // NOTE: The data has to be copied, as the socket doesn't copy it and the send buffer is reused.
    // Errors which occur while sending are reported to the socket's done future.
    _socket.add(_peer.sendBuffer.sublist(0, amount + Constants.intBytes));
  }

  /// Closes the connection.
  void close() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _socket.close().catchError((Object _) => null); // Errors while closing are irrelevant
  }

  /// Handles the socket being closed by the other end or due to an error.
  ///
  /// [reason] : The reason for the disconnection.
  void _onSocketClosed(DisconnectReason reason) {
    if (!_isClosed) {
      _detectedDisconnectReason ??= reason;
    }
  }

  /// Determines the disconnect reason for the given socket [error], mirroring the socket error handling in C#.
  ///
  /// [error] : The error the socket encountered.
  static DisconnectReason _getDisconnectReason(Object error) {
    int? errorCode = error is SocketException ? error.osError?.errorCode : null;
    switch (errorCode) {
      case 10054: // WSAECONNRESET (Windows)
      case 104: // ECONNRESET (Linux, Android)
      case 54: // ECONNRESET (macOS, iOS)
        return DisconnectReason.disconnected;
      case 10060: // WSAETIMEDOUT (Windows)
      case 110: // ETIMEDOUT (Linux, Android)
      case 60: // ETIMEDOUT (macOS, iOS)
        return DisconnectReason.timedOut;
      default:
        return DisconnectReason.transportError;
    }
  }

  @override
  String toString() => remoteEndPoint.toString();
}
