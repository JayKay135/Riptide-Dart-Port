import 'connection.dart';
// ignore: unused_import
import 'utils/multi_threading.dart'; // Referenced by the documentation
import 'message.dart';
import 'peer.dart';
import 'utils/event_handler.dart';

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
  /// The ID of the newly connected client.
  int id;

  /// The address and port of the newly connected client.
  String endPoint;

  /// Initializes event data.
  ///
  /// [id] : The newly connected clients ID.
  /// [endPoint] : The address and port of the newly connected client.
  MultiThreadedServerConnectedEventArgs(this.id, {this.endPoint = ""});
}

/// Contains event data for when a connection to the multi threaded server fails to be fully established.
class MultiThreadedServerConnectionFailedEventArgs extends EventArgs {
  /// The ID of the connection attempt, if it was passed to [MultiThreadedServer.handleConnection].
  int? attemptId;

  /// The address and port of the connection which failed to be established.
  String endPoint;

  /// Initializes event data.
  ///
  /// [attemptId] : The ID of the connection attempt, if it was passed to [MultiThreadedServer.handleConnection].
  /// [endPoint] : The address and port of the connection which failed to be established.
  MultiThreadedServerConnectionFailedEventArgs(this.attemptId, this.endPoint);
}

/// Contains event data for when a multi threaded server or client receives a message.
class MultiThreadedMessageReceivedEventArgs extends EventArgs {
  /// The ID of the client the message was received from. Always 0 for messages received by a client.
  int fromClientID;

  /// The ID of the message.
  int messageID;

  /// The received message.
  Message message;

  /// Initializes event data.
  ///
  /// [fromClientID] : The ID of the client the message was received from. Always 0 for messages received by a client.
  /// [messageID] : The ID of the message.
  /// [message] : The received message.
  MultiThreadedMessageReceivedEventArgs(this.fromClientID, this.messageID, this.message);
}

/// Contains event data for when a multi threaded server receives a notify message.
class MultiThreadedNotifyReceivedEventArgs extends EventArgs {
  /// The ID of the client the notify message was received from.
  int fromClientID;

  /// The received notify message.
  Message message;

  /// Initializes event data.
  ///
  /// [fromClientID] : The ID of the client the notify message was received from.
  /// [message] : The received notify message.
  MultiThreadedNotifyReceivedEventArgs(this.fromClientID, this.message);
}

/// Contains event data for when a notify message sent by a multi threaded server was delivered or lost.
class MultiThreadedNotifyEventArgs extends EventArgs {
  /// The ID of the client the notify message was sent to.
  int clientID;

  /// The sequence ID of the notify message.
  ///
  /// Each connection numbers its notify messages consecutively, starting at 1 (and wrapping around after 65535).
  int sequenceID;

  /// Initializes event data.
  ///
  /// [clientID] : The ID of the client the notify message was sent to.
  /// [sequenceID] : The sequence ID of the notify message.
  MultiThreadedNotifyEventArgs(this.clientID, this.sequenceID);
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
  /// The ID of the client that disconnected.
  int clientID;

  /// The reason for the disconnection.
  DisconnectReason disconnectReason;

  /// Initializes event data.
  ///
  /// [clientID] : The ID of the client that disconnected.
  /// [disconnectReason] : The reason for the disconnection.
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
