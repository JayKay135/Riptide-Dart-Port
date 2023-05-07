import 'dart:typed_data';

import '../_peer.dart';
import '_connection.dart';

/// Contains event data for when a server's transport successfully establishes a connection to a client.
class ConnectedEventArgs {
  final Connection connection;

  /// Initializes event data.
  /// [connection] extends The newly established connection.
  ConnectedEventArgs(this.connection);
}

/// Contains event data for when a server's or client's transport receives data.
class DataReceivedEventArgs {
  /// An array containing the received data.
  late Uint8List _dataBuffer;
  Uint8List get dataBuffer => _dataBuffer;

  /// The number of bytes that were received.
  late int _amount;
  int get amount => _amount;

  /// The connection which the data was received from.
  final Connection fromConnection;

  /// Initializes event data.
  /// [dataBuffer] extends An array containing the received data.
  /// [amount] extends The number of bytes that were received.
  /// [fromConnection] extends The connection which the data was received from.
  DataReceivedEventArgs(Uint8List dataBuffer, int amount, this.fromConnection) {
    _dataBuffer = dataBuffer;
    _amount = amount;
  }
}

/// Contains event data for when a server's or client's transport initiates or detects a disconnection.
class DisconnectedEventArgs {
  /// The closed connection.
  final Connection connection;

  /// The reason for the disconnection.
  late DisconnectReason _reason;
  DisconnectReason get reason => _reason;

  /// Initializes event data.
  /// [connection] extends The closed connection.
  /// [reason] extends The reason for the disconnection.
  DisconnectedEventArgs(this.connection, DisconnectReason reason) {
    _reason = reason;
  }
}
