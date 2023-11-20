import '../utils/event_handler.dart';
import 'connection.dart';
import 'ipeer.dart';

/// Defines methods, properties, and events which every transport's server must implement.
abstract class IServer implements IPeer {
  /// Invoked when a connection is established at the transport level.
  abstract Event connected;

  late int port;

  /// Starts the transport and begins listening for incoming connections.
  ///
  /// [port] : The local port on which to listen for connections.
  void start(int port);

  /// Closes an active connection.
  ///
  /// [connection] : The connection to close.
  void close(Connection connection);

  /// Closes all existing connections and stops listening for new connections.
  void shutdown();
}
