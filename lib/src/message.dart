import 'dart:convert';
import 'dart:core';
import 'dart:typed_data';

import 'exceptions.dart';
import 'peer.dart';
import 'transports/ipeer.dart';
import 'utils/constants.dart';
import 'utils/converter.dart';
import 'utils/helper.dart';
import 'utils/riptide_logger.dart';

/// The send mode of a Message.
enum MessageSendMode {
  /// Unreliable send mode.
  unreliable,

  /// Reliable send mode.
  reliable,
}

extension MessageSendModeExtension on MessageSendMode {
  MessageHeader get messageHeader {
    return index == 0 ? MessageHeader.unreliable : MessageHeader.reliable;
  }
}

/// Provides functionality for converting data to bytes and vice versa.
class Message {
  final int poolSize = 10;

  /// The header size for unreliable messages. Does not count the 2 bytes used for the message ID.
  ///
  /// 1 byte - header
  static const int unreliableHeaderSize = 1;

  /// The header size for reliable messages. Does not count the 2 bytes used for the message ID.
  ///
  /// 1 byte - header, 2 bytes - sequence ID
  static const int reliableHeaderSize = 3;

  /// The header size for notify messages.
  ///
  /// 1 byte - header, 3 bytes - ack, 2 bytes - sequence ID
  static const int notifyHeaderSize = 6;

  /// The maximum number of bytes required for a message's header.
  ///
  /// 1 byte for the actual header, 2 bytes for the sequence ID (only for reliable messages), 2 bytes for the message ID. Messages sent unreliably will use 2 bytes less than this value for the header.
  static const int maxHeaderSize = notifyHeaderSize;

  /// The maximum number of bytes that a message can contain, including the MaxHeaderSize.
  static int _maxSize = maxHeaderSize + 1225;

  /// How many messages to add to the pool for each Server or Client instance that is started.
  ///
  /// Changes will not affect Server and Client instances which are already running until they are restarted.
  static int instancesPerPeer = 4;

  /// A pool of reusable message instances.
  static List<Message> _pool = [];

  /// The message's send mode.
  late MessageSendMode _sendMode;

  /// How many bytes have been retrieved from the message.
  int get readLength => _readPos;

  /// How many more bytes can be retrieved from the message.
  int get unreadLength => _writePos - _readPos;

  /// How many bytes have been added to the message.
  int get writtenLength => _writePos;

  /// How many more bytes can be added to the message.
  int get unwrittenLength => bytes.length - _writePos;

  /// The message's data.
  late Uint8List bytes;

  /// The position in the byte array that the next bytes will be written to.
  late int _writePos;

  /// The position in the byte array that the next bytes will be read from.
  late int _readPos;

  /// Initializes a reusable Message instance.
  ///
  /// [maxSize] : The maximum amount of bytes the message can contain.
  Message(int maxSize) {
    bytes = Uint8List(maxSize);
  }

  /// Returns the maximum message size allowed
  static int get maxSize => _maxSize;

  /// Returns the current pool of messages
  static List<Message> get pool => _pool;

  /// Returns the maximal payload size allowed for messages
  int get maxPayloadSize => _maxSize - maxHeaderSize;

  MessageSendMode get sendMode => _sendMode;

  /// Sets the maximum message payload size
  ///
  /// [value] : new maximal payload size
  set maxPayloadSize(int value) {
    if (Peer.activeCount > 0) {
      RiptideLogger.log(LogType.error, "Changing the max message size is not allowed while a Server or Client is running!");
    } else {
      if (value < 0) {
        RiptideLogger.log(LogType.error, "The max payload size cannot be negative! Setting it to 0 instead of the given value ($value).");
        _maxSize = maxHeaderSize;
      } else {
        _maxSize = maxHeaderSize + value;
      }

      trimPool(); // When ActiveSocketCount is 0, this clears the pool
    }
  }

  /// Trims the message pool to a more appropriate size for how many Server and Client instances are currently running.
  static void trimPool() {
    if (Peer.activeCount == 0) {
      // No Servers or Clients are running, empty the list and reset the capacity
      _pool.clear();
      _pool.length = instancesPerPeer * 2; // x2 so there's some buffer room for extra Message instances in the event that more are needed
    } else {
      // Reset the pool capacity and number of Message instances in the pool to what is appropriate for how many Servers & Clients are active
      int idealInstanceAmount = Peer.activeCount * instancesPerPeer;
      if (_pool.length > idealInstanceAmount) {
        _pool.removeRange(Peer.activeCount * instancesPerPeer, pool.length - idealInstanceAmount);
        _pool.length = idealInstanceAmount * 2;
      }
    }
  }

  /// Gets a completely empty message instance with no header.
  ///
  /// Returns an empty message instance.
  static Message create() {
    return _retrieveFromPool().prepareForUse();
  }

  /// Gets a message instance that can be used for sending.
  ///
  /// [sendMode] : The mode in which the message should be sent.
  /// [id] : The message ID.
  /// Returns a message instance ready to be sent.
  static Message createFromInt(MessageSendMode sendMode, int id) {
    return _retrieveFromPool().prepareForUse2(sendMode.messageHeader).addUShort(id);
  }

  /// Gets a message instance that can be used for sending.
  ///
  /// [sendMode] : The mode in which the message should be sent.
  /// [id] : The message ID as enum.
  /// NOTE: [id] will be cast to a ushort. You should ensure that its value never exceeds that of ushort maxvalue, otherwise you'll encounter unexpected behaviour when handling messages.
  static Message createFromEnum(MessageSendMode sendMode, Enum id) {
    return createFromInt(sendMode, id.index);
  }

  /// Gets a message instance that can be used for sending.
  ///
  /// [header] : The message's header type.
  /// Returns a message instance ready to be sent.
  static Message createFromHeader(MessageHeader header) {
    return _retrieveFromPool().prepareForUse2(header);
  }

  /// Gets a message instance that can be used for receiving/handling.
  ///
  /// [header] : The message's header type.
  /// [contentLength] : The number of bytes which this message will contain.
  /// Returns a message instance ready to be populated with received data.
  static Message createFromHeaderWithLength(MessageHeader header, int contentLength) {
    return _retrieveFromPool().prepareForUse3(header, contentLength);
  }

  /// Gets a notify message instance that can be used for sending.
  /// <returns>A notify message instance ready to be sent.</returns>
  static Message createNotify() {
    return _retrieveFromPool().prepareForUse2(MessageHeader.notify);
  }

  /// Retrieves a message instance from the pool. If none is available, a new instance is created.
  ///
  /// Returns a message instance ready to be used for sending or handling.
  static Message _retrieveFromPool() {
    Message message;
    if (pool.isNotEmpty) {
      message = pool.removeAt(0);
    } else {
      message = Message(_maxSize);
    }

    return message;
  }

  /// Returns the message instance to the internal pool so it can be reused.
  void release() {
    if (!pool.contains(this)) {
      // Only add it if it's not already in the list, otherwise this method being called twice in a row for whatever reason could cause *serious* issues
      pool.add(this);
    }
  }

  /// Prepares the message to be used.
  ///
  /// Returns the message, ready to be used.
  Message prepareForUse() {
    _readPos = 0;
    _writePos = 0;
    return this;
  }

  /// Prepares the message to be used for sending.
  ///
  /// [header] : The header of the message.
  /// Returns the message, ready to be used for sending.
  Message prepareForUse2(MessageHeader header) {
    setHeader(header);
    return this;
  }

  /// Prepares the message to be used for handling.
  ///
  /// [header] : The header of the message.
  /// [contentLength] : The number of bytes that this message will contain and which can be retrieved.
  /// Returns the message, ready to be used for handling.
  Message prepareForUse3(MessageHeader header, int contentLength) {
    setHeader(header);
    _writePos = contentLength;
    return this;
  }

  /// Sets the message's header byte to the given header and determines the appropriate MessageSendMode and read/write positions.
  ///
  /// [header] : The header to use for this message.
  void setHeader(MessageHeader header) {
    bytes[0] = header.messageIndex;

    if (header.index == MessageHeader.notify.index) {
      _readPos = notifyHeaderSize;
      _writePos = notifyHeaderSize;

      // Technically it's different but notify messages *are* still unreliable
      _sendMode = MessageSendMode.unreliable;
    } else if (header.index >= MessageHeader.reliable.index) {
      _readPos = reliableHeaderSize;
      _writePos = reliableHeaderSize;
      _sendMode = MessageSendMode.reliable;
    } else {
      _readPos = unreliableHeaderSize;
      _writePos = unreliableHeaderSize;
      _sendMode = MessageSendMode.unreliable;
    }
  }

  /// #region Add & Retrieve Data

  /// Adds a single byte to the message.
  ///
  /// [value] : The byte to add.
  /// Returns the message that the byte was added to.
  Message addByte(int value) {
    if (unwrittenLength < 1) {
      throw InsufficientCapacityError();
    }

    bytes[_writePos++] = value;
    return this;
  }

  /// Retrieves a single byte from the message.
  ///
  /// Returns the byte that was retrieved.
  int getByte() {
    if (unreadLength < 1) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(byteName));
      return 0;
    }

    return bytes[_readPos++];
  }

  /// Adds a byte array to the message.
  ///
  /// [data] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  /// Returns the message that the array was added to.
  Message addBytes(Uint8List data, {bool includeLength = true}) {
    if (includeLength) {
      _addArrayLength(data.length);
    }

    if (unwrittenLength < data.length) {
      throw InsufficientCapacityError();
    }

    bytes.setRange(_writePos, _writePos + data.length, data);
    _writePos += data.length;
    return this;
  }

  /// Populates a Uint8List with bytes retrieved from the message.
  ///
  /// [amount] : The amount of bytes to retrieve.
  /// [intoList] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  Uint8List getBytes(int? amount, {Uint8List? intoList, int startIndex = 0}) {
    if (amount == null) {
      return getBytes(_getArrayLength());
    }

    if (intoList == null) {
      Uint8List data = Uint8List(amount);
      _readBytes(amount, data, startIndex: startIndex);
      return data;
    } else {
      if (startIndex + amount > intoList.length) {
        throw ArgumentError();
      }

      _readBytes(amount, intoList, startIndex: startIndex);
      return intoList;
    }
  }

  /// Reads a number of bytes from the message and writes them into the given array.
  ///
  /// [amount] : The amount of bytes to read.
  /// [intoList] : The array to write the bytes into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readBytes(int amount, Uint8List intoList, {int startIndex = 0}) {
    if (unreadLength < amount) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError2(intoList.length, byteName));
      amount = unreadLength;
    }

    // Copy the bytes at readPos' position to the array that will be returned
    intoList.setRange(startIndex, startIndex + amount, bytes.getRange(_readPos, _readPos + amount));
    _readPos += amount;
  }

  /// Adds a bool to the message.
  ///
  /// [value] : The bool to add.
  /// Returns the message that the bool was added to.
  Message addBool(bool value) {
    if (unwrittenLength < Constants.boolBytes) {
      throw InsufficientCapacityError();
    }

    bytes[_writePos++] = value ? 1 : 0;
    return this;
  }

  /// Retrieves a bool from the message.
  ///
  /// Returns the bool that was retrieved.
  bool getBool() {
    if (unreadLength < Constants.boolBytes) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(boolName, defaultReturn: "false"));
      return false;
    }

    return bytes[_readPos++] == 1;
  }

  /// Adds a bool array to the message.
  ///
  /// [list] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  /// Returns the message that the array was added to.
  Message addBools(List<bool> list, {bool includeLength = true}) {
    if (includeLength) {
      _addArrayLength(list.length);
    }

    int byteLength = (list.length / 8).ceil() + (list.length % 8 == 0 ? 0 : 1);
    if (unwrittenLength < byteLength) {
      throw InsufficientCapacityError();
    }

    // Pack 8 bools into each byte
    bool isLengthMultipleOf8 = list.length % 8 == 0;
    for (int i = 0; i < byteLength; i++) {
      int nextByte = 0;
      int bitsToWrite = 8;
      if ((i + 1) == byteLength && !isLengthMultipleOf8) {
        bitsToWrite = list.length % 8;
      }

      for (int bit = 0; bit < bitsToWrite; bit++) {
        nextByte |= Helper.toByte((list[i * 8 + bit] ? 1 : 0) << bit);
      }

      bytes[_writePos + i] = nextByte;
    }

    _writePos += byteLength;
    return this;
  }

  /// Populates a bool array with bools retrieved from the message.
  ///
  /// [amount] : The amount of bools to retrieve.
  /// [intoList] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  List<bool> getBools(int? amount, {List<bool>? intoList, int startIndex = 0}) {
    if (amount == null) {
      return getBools(_getArrayLength());
    }

    int byteAmount = (amount / 8).ceil() + (amount % 8 == 0 ? 0 : 1);

    if (intoList == null) {
      List<bool> data = [];

      if (unreadLength < byteAmount) {
        RiptideLogger.log(LogType.error, NotEnoughBytesError().toString());
      }

      _readBools(byteAmount, data);
      return data;
    } else {
      if (startIndex + amount > intoList.length) {
        throw ArgumentError();
      }

      if (unreadLength < byteAmount) {
        RiptideLogger.log(LogType.error, NotEnoughBytesError().toString());
      }

      _readBools(byteAmount, intoList, startIndex: startIndex);
      return intoList;
    }
  }

  /// Reads a number of bools from the message and writes them into the given array.
  ///
  /// [byteAmount] : The number of bytes the bools are being stored in.
  /// [intoList] : The array to write the bools into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readBools(int byteAmount, List<bool> intoList, {int startIndex = 0}) {
    // Read 8 bools from each byte
    bool isLengthMultipleOf8 = intoList.length % 8 == 0;
    for (int i = 0; i < byteAmount; i++) {
      int bitsToRead = 8;
      if ((i + 1) == byteAmount && !isLengthMultipleOf8) {
        bitsToRead = intoList.length % 8;
      }

      for (int bit = 0; bit < bitsToRead; bit++) {
        intoList[startIndex + (i * 8 + bit)] = (bytes[_readPos + i] >> bit & 1) == 1;
      }
    }

    _readPos += byteAmount;
  }

  /// Adds a short to the message.
  ///
  /// [value] : The short to add.
  /// Returns the message that the short was added to.
  Message addShort(int value) {
    if (unwrittenLength < Constants.shortBytes) {
      throw InsufficientCapacityError();
    }

    Converter.fromShort(value, bytes.buffer.asByteData(), _writePos);
    _writePos += Constants.shortBytes;
    return this;
  }

  /// Retrieves a short from the message.
  ///
  /// Returns the short that was retrieved.
  int getShort() {
    if (unreadLength < Constants.shortBytes) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(shortName));
      return 0;
    }

    int value = Converter.toShort(bytes.buffer.asByteData(), _readPos);
    _readPos += Constants.shortBytes;
    return value;
  }

  /// Adds a ushort to the message.
  ///
  /// [value] : The ushort to add.
  /// Returns the message that the ushort was added to.
  Message addUShort(int value) {
    if (unwrittenLength < Constants.ushortBytes) {
      throw InsufficientCapacityError();
    }

    Converter.fromUShort(value, bytes.buffer.asByteData(), _writePos);
    _writePos += Constants.ushortBytes;
    return this;
  }

  /// Retrieves a ushort from the message.
  ///
  /// Returns the ushort that was retrieved.
  int getUShort() {
    if (unreadLength < Constants.ushortBytes) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(uShortName));
      return 0;
    }

    int value = Converter.toUShort(bytes.buffer.asByteData(), _readPos);
    _readPos += Constants.ushortBytes;
    return value;
  }

  /// Adds an int to the message.
  ///
  /// [value] : The int to add.
  /// Returns the message that the int was added to.
  Message addInt(int value) {
    if (unwrittenLength < Constants.intBytes) {
      throw InsufficientCapacityError();
    }

    Converter.fromInt(value, bytes.buffer.asByteData(), _writePos);
    _writePos += Constants.intBytes;
    return this;
  }

  /// Retrieves an int from the message.
  ///
  /// Returns the int that was retrieved.
  int getInt() {
    if (unreadLength < Constants.intBytes) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(intName));
      return 0;
    }

    int value = Converter.toInt(bytes.buffer.asByteData(), _readPos);
    _readPos += Constants.intBytes;
    return value;
  }

  /// Adds a double to the message.
  ///
  /// [value] : The double to add.
  /// Returns the message that the double was added to.
  Message addDouble(double value) {
    if (unwrittenLength < Constants.doubleBytes) {
      throw InsufficientCapacityError();
    }

    Converter.fromDouble(value, bytes.buffer.asByteData(), _writePos);
    _writePos += Constants.doubleBytes;
    return this;
  }

  /// Retrieves a double from the message.
  ///
  /// Returns the double that was retrieved.
  double getDouble() {
    if (unreadLength < Constants.doubleBytes) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(doubleName));
      return 0;
    }

    double value = Converter.toDouble(bytes.buffer.asByteData(), _readPos);
    _readPos += Constants.doubleBytes;
    return value;
  }

  /// Adds a string to the message.
  ///
  /// [value] : The string to add.
  /// Returns the message that the string was added to.
  Message addString(String value) {
    Uint8List stringBytes = Uint8List.fromList(utf8.encode(value));
    int requiredBytes = stringBytes.length + (stringBytes.length <= _oneByteLengthThreshold ? 1 : 2);
    if (unwrittenLength < requiredBytes) {
      throw InsufficientCapacityError();
    }

    addBytes(stringBytes);
    return this;
  }

  /// Retrieves a string from the message.
  ///
  /// Returns the string that was retrieved.
  String getString() {
    int length = _getArrayLength(); // Get the length of the string (in bytes, NOT characters)
    if (unreadLength < length) {
      RiptideLogger.log(LogType.error, NotEnoughBytesError().toString());
      length = unreadLength;
    }

    String value = utf8.decode(bytes.getRange(_readPos, _readPos + length).toList()); // Convert the bytes at readPos' position to a string
    _readPos += length;
    return value;
  }

  /// The maximum number of elements an array can contain where the length still fits into a single byte.
  final int _oneByteLengthThreshold = (Uint8List(1)..[0] = 0x7F).buffer.asInt8List().first; // 0b_0111_1111;

  /// The maximum number of elements an array can contain where the length still fits into two bytes.
  final int _twoByteLengthThreshold = (Uint16List(1)..[0] = 0x7FFFF).buffer.asInt16List().first; //0b_0111_1111_1111_1111;

  final int _oneByteComparison = (Uint8List(1)..[0] = 0x80).buffer.asInt8List().first; //0b_1000_0000;
  final int _twoByteComparison = (Uint16List(1)..[0] = 0x8000).buffer.asInt16List().first; //0b_1000_0000_0000_0000;

  /// Adds the length of an array to the message, using either 1 or 2 bytes depending on how large the array is. Does not support arrays with more than 32,767 elements.
  ///
  /// [length] : The length of the array.
  void _addArrayLength(int length) {
    if (unwrittenLength < 1) {
      throw InsufficientCapacityError();
    }

    if (length <= _oneByteLengthThreshold) {
      bytes[_writePos++] = length;
    } else {
      if (length > _twoByteLengthThreshold) {
        throw ArgumentOutOfRangeError();
      }

      if (unwrittenLength < 2) {
        throw InsufficientCapacityError();
      }

      length |= _twoByteComparison;

      // Add the byte with the big array flag bit first, using addUShort would add it second
      bytes[_writePos++] = length >> 8;
      bytes[_writePos++] = length;
    }
  }

  /// Retrieves the length of an array from the message, using either 1 or 2 bytes depending on how large the array is.
  ///
  /// Returns the length of the array.
  int _getArrayLength() {
    if (unreadLength < 1) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(arrayLengthName));
      return 0;
    }

    if ((bytes[_readPos] & _oneByteComparison) == 0) {
      return getByte();
    }

    if (unreadLength < 2) {
      RiptideLogger.log(LogType.error, _notEnoughBytesError(arrayLengthName));
      return 0;
    }

    // Read the byte with the big array flag bit first, using GetUShort would add it second
    return ((bytes[_readPos++] << 8) | bytes[_readPos++]) & _twoByteLengthThreshold;
  }

  /// The name of a byte value.
  final String byteName = "byte";

  /// The name of a sbyte value.
  final String sByteName = "sbyte";

  /// The name of a bool value.
  final String boolName = "bool";

  /// The name of a short value.
  final String shortName = "short";

  /// The name of a ushort value.
  final String uShortName = "ushort";

  /// The name of an int value.
  final String intName = "int";

  /// The name of a uint value.
  final String uIntName = "uint";

  /// The name of a long value.
  final String longName = "long";

  /// The name of a ulong value.
  final String uLongName = "ulong";

  /// The name of a float value.
  final String floatName = "float";

  /// The name of a double value.
  final String doubleName = "double";

  /// The name of a string value.
  final String stringName = "string";

  /// The name of an array length value.
  final String arrayLengthName = "array length";

  /// Constructs an error message for when a message contains insufficient unread bytes to retrieve a certain value.
  ///
  /// [valueName] : The name of the value type for which the retrieval attempt failed.
  /// [defaultReturn] : Text describing the value which will be returned.
  /// Returns the error message.
  String _notEnoughBytesError(String valueName, {String defaultReturn = "0"}) {
    return "Message only contains $unreadLength unread ${Helper.correctForm(unreadLength, "byte")}, which is not enough to retrieve a value of type '$valueName'! Returning $defaultReturn.";
  }

  /// Constructs an error message for when a message contains insufficient unread bytes to retrieve an array of values.
  ///
  /// [arrayLength] : The expected length of the array.
  /// [valueName] : The name of the value type for which the retrieval attempt failed.
  /// Returns the error message.
  String _notEnoughBytesError2(int arrayLength, String valueName) {
    return "Message only contains $unreadLength unread ${Helper.correctForm(unreadLength, "byte")}, which is not enough to retrieve $arrayLength ${Helper.correctForm(arrayLength, valueName)}! Returned array will contain default elements.";
  }

  /// Constructs an error message for when a number of retrieved values do not fit inside the bounds of the provided array.
  ///
  /// [amount] : The number of values being retrieved.
  /// [arrayLength] : The length of the provided array.
  /// [startIndex] : The position in the array at which to begin writing values.
  /// [valueName] : The name of the value type which is being retrieved.
  /// [pluralValueName] : The name of the value type in plural form. If left empty, this will be set to valueName with an 's' appended to it.
  /// Returns the error message.
  String _arrayNotLongEnoughError(int amount, int arrayLength, int startIndex, String valueName, {String pluralValueName = ""}) {
    if (pluralValueName == "") {
      pluralValueName = "${valueName}s";
    }

    return "The amount of $pluralValueName to retrieve ($amount) is greater than the number of elements from the start index ($startIndex) to the end of the given array (length: $arrayLength)!";
  }
}
