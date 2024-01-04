import 'dart:typed_data';

import '../connection.dart';
import '../peer.dart';

/// Contains event data for when a server's transport successfully establishes a connection to a client.
class ConnectedEventArgs {
  late Connection _connection;

  /// The newly established connection.
  Connection get connection => _connection;

  /// Initializes event data.
  ///
  /// [connection] : The newly established connection.
  ConnectedEventArgs(this._connection);
}

/// Contains event data for when a server's or client's transport receives data.
class DataReceivedEventArgs {
  late Uint8List _dataBuffer;

  /// An array containing the received data.
  Uint8List get dataBuffer => _dataBuffer;

  late int _amount;

  /// The number of bytes that were received.
  int get amount => _amount;

  late Connection _fromConnection;

  /// The connection which the data was received from.
  Connection get fromConnection => _fromConnection;

  /// Initializes event data.
  ///
  /// [dataBuffer] : An array containing the received data.
  /// [amount] : The number of bytes that were received.
  /// [fromConnection] : The connection which the data was received from.
  DataReceivedEventArgs(this._dataBuffer, this._amount, this._fromConnection);
}

/// Contains event data for when a server's or client's transport initiates or detects a disconnection.
class DisconnectedEventArgs {
  final Connection _connection;

  /// The closed connection.
  Connection get connection => _connection;

  late DisconnectReason _reason;

  /// The reason for the disconnection.
  DisconnectReason get reason => _reason;

  /// Initializes event data.
  ///
  /// [connection] : The closed connection.
  /// [reason] : The reason for the disconnection.
  DisconnectedEventArgs(this._connection, this._reason);
}
