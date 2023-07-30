import '../utils/_eventHandler.dart';
import '_eventArgs.dart';

enum MessageHeader {
  /// An unreliable user message.
  unreliable,

  /// An internal unreliable ack message.
  ack,

  /// An internal unreliable connect message.
  connect,

  /// An internal unreliable connection rejection message.
  reject,

  /// An internal unreliable heartbeat message.
  heartbeat,

  /// An internal unreliable disconnect message.
  disconnect,

  /// A notify message.
  notify,

  /// A reliable user message.
  reliable,

  /// An internal reliable welcome message.
  welcome,

  /// An internal reliable client connected message.
  clientConnected,

  /// An internal reliable client disconnected message.
  clientDisconnected,
}

extension MessageHeaderExtension on MessageHeader {
  int get messageIndex {
    return index;
  }

  static MessageHeader fromMessageIndex(int messageIndex) {
    return MessageHeader.values[messageIndex];
  }
}

/// Defines methods, properties, and events which every transport's server and client must implement.
abstract class IPeer {
  /// Invoked when data is received by the transport.
  abstract Event<DataReceivedEventArgs> dataReceived;

  /// Invoked when a disconnection is initiated or detected by the transport.
  abstract Event<DisconnectedEventArgs> disconnected;

  /// Initiates handling of any received messages.
  void poll();
}
