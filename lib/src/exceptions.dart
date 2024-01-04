import 'dart:core';

import 'message.dart';
import 'utils/helper.dart';

/// The exception that is thrown when a [Message] does not contain enough unread bytes to add a certain value.
class InsufficientCapacityException implements Exception {
  late String errorMessage;

  /// The message with insufficient remaining capacity.
  Message? _riptideMessage;
  Message? get riptideMessage => _riptideMessage;

  /// The name of the type which could not be added to the message.
  String? _typeName;
  String? get typeName => _typeName;

  /// The number of available bytes the type requires in order to be added successfully.
  int? _requiredBits;
  int? get requiredBits => _requiredBits;

  /// Initializes a new [InsufficientCapacityException] instance with a specified error message.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  InsufficientCapacityException(this.errorMessage);

  /// Initializes a new [InsufficientCapacityException] instance with a specified error message and a reference to the inner exception that is the cause of this exception.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  /// [inner] : The exception that is the cause of the current exception. If [inner] is not a null reference, the current exception is raised in a catch block that handles the inner exception.
  InsufficientCapacityException.withInner(this.errorMessage, Exception inner);

  /// Initializes a new [InsufficientCapacityException] instance and constructs an error message from the given information.
  ///
  /// [riptideMessage] : The message with insufficient remaining capacity.
  /// [reserveBits] : The number of bits which were attempted to be reserved.
  InsufficientCapacityException.withReservedBits(this._riptideMessage, int reserveBits) {
    errorMessage = _getErrorMessage(_riptideMessage!, reserveBits);
    _typeName = "reservation";
    _requiredBits = reserveBits;
  }

  /// Initializes a new [InsufficientCapacityException] instance and constructs an error message from the given information.
  ///
  /// [errorMessage] : The message with insufficient remaining capacity.
  /// [typeName] : The name of the type which could not be added to the message.
  /// [requiredBits] : The number of available bytes required for the type to be added successfully.
  InsufficientCapacityException.withDetails(this._riptideMessage, this._typeName, this._requiredBits) {
    errorMessage = _getErrorMessage2(_riptideMessage!, _typeName!, _requiredBits!);
  }

  /// Initializes a new [InsufficientCapacityException] instance and constructs an error message from the given information.
  ///
  /// [errorMessage] : The message with insufficient remaining capacity.
  /// [arrayLength] : The length of the array which could not be added to the message.
  /// [typeName] : The name of the array's type.
  /// [requiredBytes] : The number of available bytes required for a single element of the array to be added successfully.
  /// [totalRequiredBytes] : The number of available bytes required for the entire array to be added successfully. If left as -1, this will be set to [arrayLength] * [requiredBytes].
  InsufficientCapacityException.withArrayDetails(this._riptideMessage, int arrayLength, String typeName, int requiredBytes, [int totalRequiredBytes = -1]) {
    _requiredBits = totalRequiredBytes == -1 ? arrayLength * requiredBytes : totalRequiredBytes;
    _typeName = "${typeName}[]";

    errorMessage = _getErrorMessage3(_riptideMessage!, arrayLength, _typeName!, _requiredBits!, totalRequiredBytes);
  }

  /// Constructs the error message from the given information.
  ///
  /// Returns the error message.
  static String _getErrorMessage(Message message, int reserveBits) {
    return "Cannot reserve $reserveBits ${Helper.correctForm(reserveBits, "bit")} in a message with ${message.unwrittenBits} ${Helper.correctForm(message.unwrittenBits, "bit")} of remaining capacity!";
  }

  /// Constructs the error message from the given information.
  ///
  /// Return the error message.
  static String _getErrorMessage2(Message message, String typeName, int requiredBytes) {
    return "Cannot add a value of type '$typeName' (requires $requiredBytes ${Helper.correctForm(requiredBytes, "byte")}) to a message with ${message.unwrittenBits} ${Helper.correctForm(message.unwrittenBits, "bit")} of remaining capacity!";
  }

  /// Constructs the error message from the given information.
  ///
  /// Returns the error message.
  static String _getErrorMessage3(Message message, int arrayLength, String typeName, int requiredBytes, int totalRequiredBytes) {
    if (totalRequiredBytes == -1) {
      totalRequiredBytes = arrayLength * requiredBytes;
    }

    return "Cannot add an array of type '$typeName[]' with $arrayLength ${Helper.correctForm(arrayLength, "element")} (requires $totalRequiredBytes ${Helper.correctForm(totalRequiredBytes, "byte")}) to a message with ${message.unwrittenBits} ${Helper.correctForm(message.unwrittenBits, "bit")} of remaining capacity!";
  }

  @override
  String toString() {
    return errorMessage;
  }
}

class NonStaticHandlerException implements Exception {
  late String errorMessage;

  /// The type containing the handler method.
  Type? _declaringType;
  Type? get declaringType => _declaringType;

  /// The name of the handler method.
  String? _handlerMethodName;
  String? get handlerMethodName => _handlerMethodName;

  /// Initializes a new [NonStaticHandlerException] instance with a specified error message.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  NonStaticHandlerException(this.errorMessage);

  /// Initializes a new [NonStaticHandlerException] instance with a specified error message and a reference to the inner exception that is the cause of this exception.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  /// [inner] : The exception that is the cause of the current exception. If [inner] is not a null reference, the current exception is raised in a catch block that handles the inner exception.
  NonStaticHandlerException.withInner(this.errorMessage, Exception inner);

  /// Initializes a new [NonStaticHandlerException] instance and constructs an error message from the given information.
  ///
  /// [declaringType] : The type containing the handler method.
  /// [handlerMethodName] : The name of the handler method.
  NonStaticHandlerException.withDetails(this._declaringType, this._handlerMethodName) {
    errorMessage = _getErrorMessage(_declaringType!, _handlerMethodName!);
  }

  /// Constructs the error message from the given information.
  ///
  /// Returns the error message.
  static String _getErrorMessage(Type declaringType, String handlerMethodName) {
    return "'$declaringType.$handlerMethodName' is an instance method, but message handler methods must be static!";
  }

  @override
  String toString() {
    return errorMessage;
  }
}

/// The exception that is thrown when a method with a [MessageHandlerAttribute] does not have an acceptable message handler method signature (either [Server.MessageHandler] or [Client.MessageHandler]).
class InvalidHandlerSignatureException implements Exception {
  late String errorMessage;

  /// The type containing the handler method.
  Type? _declaringType;
  Type? get declaringType => _declaringType;

  /// The name of the handler method.
  String? _handlerMethodName;
  String? get handlerMethodName => _handlerMethodName;

  /// Initializes a new [InvalidHandlerSignatureException] instance with a specified error message.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  InvalidHandlerSignatureException(this.errorMessage);

  /// Initializes a new [InvalidHandlerSignatureException] instance with a specified error message and a reference to the inner exception that is the cause of this exception.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  /// [inner] : The exception that is the cause of the current exception. If [inner] is not a null reference, the current exception is raised in a catch block that handles the inner exception.
  InvalidHandlerSignatureException.withInner(this.errorMessage, Exception inner);

  /// Initializes a new [InvalidHandlerSignatureException] instance and constructs an error message from the given information.
  ///
  /// [declaringType] : The type containing the handler method.
  /// [handlerMethodName] : The name of the handler method.
  InvalidHandlerSignatureException.withDetails(this._declaringType, this._handlerMethodName) {
    errorMessage = _getErrorMessage(_declaringType!, _handlerMethodName!);
  }

  /// Constructs the error message from the given information.
  /// Returns the error message.
  static String _getErrorMessage(Type declaringType, String handlerMethodName) {
    return "'$declaringType.$handlerMethodName' doesn't match any acceptable message handler method signatures! Server message handler methods should have a 'ushort' and a 'Message' parameter, while client message handler methods should only have a 'Message' parameter.";
  }

  @override
  String toString() {
    return errorMessage;
  }
}

/// The exception that is thrown when multiple methods with [MessageHandlerAttribute]s are set to handle messages with the same ID <i>and</i> have the same method signature.
class DuplicateHandlerException implements Exception {
  late String errorMessage;

  /// The message ID with multiple handler methods.
  int? _id;
  int? get id => _id;

  /// The type containing the first handler method.
  Type? _declaringType1;
  Type? get declaringType1 => _declaringType1;

  /// The name of the first handler method.
  String? _handlerMethodName1;
  String? get handlerMethodeName1 => _handlerMethodName1;

  /// The type containing the second handler method.
  Type? _declaringType2;
  Type? get declaringType2 => _declaringType2;

  /// The name of the second handler method.
  String? _handlerMethodName2;
  String? get handlerMethodeName2 => _handlerMethodName2;

  /// Initializes a new [DuplicateHandlerException] instance with a specified error message.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  DuplicateHandlerException(this.errorMessage);

  /// Initializes a new [DuplicateHandlerException] instance with a specified error message and a reference to the inner exception that is the cause of this exception.
  ///
  /// [errorMessage] : The error message that explains the reason for the exception.
  /// [inner] : The exception that is the cause of the current exception. If [inner] is not a null reference, the current exception is raised in a catch block that handles the inner exception.
  DuplicateHandlerException.withInner(this.errorMessage, Exception inner);

  /// Initializes a new [DuplicateHandlerException] instance and constructs an error message from the given information.
  ///
  /// [id] : The message ID with multiple handler methods.
  DuplicateHandlerException.withDetails(this._id) {
    errorMessage = _getErrorMessage(_id!);
  }

  /// Constructs the error message from the given information.
  ///
  /// Returns the error message.
  static String _getErrorMessage(int id) {
    return "Message handler methods '{method1.DeclaringType.Name}.{method1.Name}' and '{method2.DeclaringType.Name}.{method2.Name}' are both set to handle messages with ID $id! Only one handler method is allowed per message ID!";
  }

  @override
  String toString() {
    return errorMessage;
  }
}
