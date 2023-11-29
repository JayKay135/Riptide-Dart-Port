import 'message.dart';

// NOTE: Checked

/// Represents a type that can be added to and retrieved from messages using the [Message.addSerializable] and [Message.getSerializable] methods.
abstract class IMessageSerializable {
  /// Adds the type to the message.
  ///
  /// [message] : The message to add the type to.
  void Serialize(Message message);

  /// Retrieves the type from the message.
  ///
  /// [message] : The message to retrieve the type from.
  void Deserialize(Message message);
}
