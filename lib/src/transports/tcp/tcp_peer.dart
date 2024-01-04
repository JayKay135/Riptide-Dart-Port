import 'dart:io';
import 'dart:typed_data';

import 'tcp_connection.dart';
import '../event_args.dart';
import '../../connection.dart';
import '../../message.dart';
import '../../peer.dart';
import '../../utils/constants.dart';
import '../../utils/event_handler.dart';

/// Provides base send &#38; receive functionality for <see cref="TcpServer"/> and <see cref="TcpClient"/>.
abstract class TcpPeer extends Peer {
  abstract Event<DisconnectedEventArgs> disconnected;

  /// An array that incoming data is received into.
  late final Uint8List receiveBuffer;

  /// An array that outgoing data is sent out of.
  late final Uint8List sendBuffer;

  /// The default size used for the socket's send and receive buffers.
  static const int defaultSocketBufferSize = 1024 * 1024; // 1MB

  /// The size to use for the socket's send and receive buffers.
  late int _socketBufferSize;
  int get socketBufferSize => _socketBufferSize;

  /// Server socket for listening for connections or for sending and receiving data.
  ServerSocket? serverSocket;

  /// The minimum size that may be used for the socket's send and receive buffers.
  static const int minSocketBufferSize = 256 * 1024;

  /// Initializes the transport.
  ///
  /// [socketBufferSize] : How big the socket's send and receive buffers should be.
  TcpPeer({int socketBufferSize = defaultSocketBufferSize}) {
    if (socketBufferSize < minSocketBufferSize) {
      throw RangeError(
          "The minimum socket buffer size is $minSocketBufferSize!");
    }

    _socketBufferSize = socketBufferSize;

    Message.initialize();

    // Need room for the entire message plus the message length (since this is TCP)
    receiveBuffer = Uint8List(Message.maxSize + Constants.ushortBytes);
    sendBuffer = Uint8List(Message.maxSize + Constants.ushortBytes);
  }

  /// Handles received data.
  ///
  /// [amount] : The number of bytes that were received.
  /// [fromConnection] : The connection from which the data was received.
  void onDataReceived(int amount, TcpConnection fromConnection);

  /// Invokes the disconnected event.
  ///
  /// [connection] : The closed connection.
  /// [reason] : The reason for the disconnection.
  void onDisconnected(Connection connection, DisconnectReason reason) {
    disconnected.invoke(DisconnectedEventArgs(connection, reason));
  }
}
