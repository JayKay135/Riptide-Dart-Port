import 'dart:io';

import '../utils/event_handler.dart';
import '../connection.dart';
import 'ipeer.dart';

// NOTE: Checked

/// Defines methods, properties, and events which every transport's client must implement.
abstract class IClient extends IPeer {
  /// Invoked when a connection is established at the transport level.
  abstract Event connected;

  /// Invoked when a connection attempt fails at the transport level.
  abstract Event connectionFailed;

  /// Starts the transport and attempts to connect to the given host address.
  ///
  /// [hostAddress] :The host address to connect to.
  /// [port] : The hosts port to connect to
  ///
  /// Returns true if a connection attempt will be made and false if an issue occurred. It will also contain the connection and error message if an error occured
  Future<(bool, Connection, String)> connect(InternetAddress hostAddress, int port);

  /// Closes the connection to the server.
  void disconnect();
}
