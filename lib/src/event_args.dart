import 'connection.dart';
import 'message.dart';
import 'peer.dart';
import 'utils/event_handler.dart';

// NOTE: Checked

/// Contains event data for when a client connects to the server.
class ServerConnectedEventArgs extends EventArgs {
  /// The newly connected client.
  late Connection _client;
  Connection get client => _client;

  /// Initializes event data.
  ///
  /// [client] : The newly connected client.
  ServerConnectedEventArgs(Connection client) {
    _client = client;
  }
}

/// Contains event data for when a client connects to the multi threaded server.
class MultiThreadedServerConnectedEventArgs extends EventArgs {
  // ID of the newly connected client
  int id;

  /// Initializes event data.
  ///
  /// [id] : The newly connected clients ID.
  MultiThreadedServerConnectedEventArgs(this.id);
}

/// Contains event data for when a connection fails to be fully established.
class ServerConnectionFailedEventArgs extends EventArgs {
  /// The connection that failed to be established.
  late Connection _client;
  Connection get client => _client;

  /// Initializes event data.
  ///
  /// [client] : The connection that failed to be established.
  ServerConnectionFailedEventArgs(Connection client) {
    _client = client;
  }
}

/// Contains event data for when a client disconnects from the server.
class ServerDisconnectedEventArgs extends EventArgs {
  /// The client that disconnected.
  late Connection _client;
  Connection get client => _client;

  /// The reason for the disconnection.
  late DisconnectReason _reason;
  DisconnectReason get reason => _reason;

  /// Initializes event data.
  ///
  /// [client] : The client that disconnected.
  /// [reason] : The reason for the disconnection.
  ServerDisconnectedEventArgs(Connection client, DisconnectReason reason) {
    _client = client;
    _reason = reason;
  }
}

/// Contains event data for when a client disconnects from the multi threaded server.
class MultiThreadedServerDisconnectedEventArgs extends EventArgs {
  // ID of the newly connected client
  int clientID;

  // Reason for the disconnect
  DisconnectReason disconnectReason;

  /// Initializes event data.
  ///
  /// [clientID] : The newly connected clients ID.
  MultiThreadedServerDisconnectedEventArgs(this.clientID, this.disconnectReason);
}

/// Contains event data for when a message is received.
class MessageReceivedEventArgs extends EventArgs {
  /// The connection from which the message was received.
  late Connection _fromConnection;
  Connection get fromConnection => _fromConnection;

  /// The ID of the message.
  late int _messageID;
  int get messageID => _messageID;

  /// The received message.
  late Message _message;
  Message get message => _message;

  /// Initializes event data.
  ///
  /// [fromConnection] : The connection from which the message was received.
  /// [messageID] : The ID of the message.
  /// [message] : The received message.
  MessageReceivedEventArgs(Connection fromConnection, int messageID, Message message) {
    _fromConnection = fromConnection;
    _messageID = messageID;
    _message = message;
  }
}

/// Contains event data for when a connection attempt to a server fails.
class ConnectionFailedEventArgs extends EventArgs {
  /// The reason for the connection failure.
  late RejectReason _reason;
  RejectReason get reason => _reason;

  /// Additional data related to the failed connection attempt (if any).
  late Message? _message;
  Message? get message => _message;

  /// Initializes event data.
  ///
  /// [message] : Additional data related to the failed connection attempt (if any).
  ConnectionFailedEventArgs(RejectReason reason, Message? message) {
    _reason = reason;
    _message = message;
  }
}

/// Contains event data for when the client disconnects from a server.
class DisconnectedEventArgs extends EventArgs {
  /// The reason for the disconnection.
  late DisconnectReason _reason;
  DisconnectReason get reason => _reason;

  /// Additional data related to the disconnection (if any).
  late Message? _message;
  Message? get message => _message;

  /// Initializes event data.
  ///
  /// [reason] : The reason for the disconnection.
  /// [message] : Additional data related to the disconnection (if any).
  DisconnectedEventArgs(DisconnectReason reason, Message? message) {
    _reason = reason;
    _message = message;
  }
}

/// Contains event data for when a non-local client connects to the server.
class ClientConnectedEventArgs extends EventArgs {
  /// The numeric ID of the client that connected.
  late int _id;
  int get id => _id;

  /// Initializes event data.
  ///
  /// [id] : The numeric ID of the client that connected.
  ClientConnectedEventArgs(int id) {
    _id = id;
  }
}

/// Contains event data for when a non-local client disconnects from the server.
class ClientDisconnectedEventArgs extends EventArgs {
  /// The numeric ID of the client that disconnected.
  late int _id;
  int get id => _id;

  /// Initializes event data.
  ///
  /// [id] : The numeric ID of the client that disconnected.
  ClientDisconnectedEventArgs(int id) {
    _id = id;
  }
}
