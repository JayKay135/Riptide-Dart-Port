import 'dart:convert';
import 'dart:core';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'exceptions.dart';
import 'peer.dart';
import 'pending_message.dart';
import 'transports/ipeer.dart';
import 'utils/constants.dart';
import 'utils/converter.dart';
import 'utils/helper.dart';
import 'utils/riptide_logger.dart';
import 'connection.dart';

/// The send mode of a Message.
enum MessageSendMode {
  /// Guarantees order but not delivery. Notifies the sender of what happened via the [Connection.notifyDelivered] and [Connection.notifyLost] events.
  /// The receiver must handle notify messages via the [Connection.notifyReceived] event, which is different from the other two send modes.
  notify,

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
  static bool _initialized = false;

  /// The maximum number of bits required for a message's header.
  static const int maxHeaderSize = notifyHeaderBits;

  /// The number of bits used by the [MessageHeader].
  static const int headerBits = 4;

  /// A bitmask that, when applied, only keeps the bits corresponding to the [MessageHeader] value.
  static const int headerBitmask = (1 << headerBits) - 1;

  /// The header size for unreliable messages. Does not count the 2 bytes used for the message ID.
  ///
  /// 4 bits - header.
  static const int unreliableHeaderBits = headerBits;

  /// The header size for reliable messages. Does not count the 2 bytes used for the message ID.
  ///
  /// 4 bits - header, 16 bits - sequence ID.
  static const int reliableHeaderBits = headerBits + 2 * _bitsPerByte;

  /// The header size for notify messages.
  ///
  /// 4 bits - header, 24 bits - ack, 16 bits - sequence ID.
  static const int notifyHeaderBits = headerBits + 5 * _bitsPerByte;

  /// The minimum number of bytes contained in an unreliable message.
  static const int minUnreliableBytes = unreliableHeaderBits ~/ _bitsPerByte + (unreliableHeaderBits % _bitsPerByte == 0 ? 0 : 1);

  /// The minimum number of bytes contained in a reliable message.
  static const int minReliableBytes = reliableHeaderBits ~/ _bitsPerByte + (reliableHeaderBits % _bitsPerByte == 0 ? 0 : 1);

  /// The minimum number of bytes contained in a notify message.
  static const int minNotifyBytes = notifyHeaderBits ~/ _bitsPerByte + (notifyHeaderBits % _bitsPerByte == 0 ? 0 : 1);

  /// The number of bits in a byte.
  static const int _bitsPerByte = Converter.bitsPerByte;

  /// The number of bits in each data segment.
  static const int _bitsPerSegment = Converter.bitsPerULong;

  /// The maximum number of bytes that a message can contain, including the MaxHeaderSize.
  static late int _maxSize;

  /// Returns the maximum message size allowed
  static int get maxSize => _maxSize;

  /// Returns the maximal payload size allowed for messages
  int get maxPayloadSize => _maxSize - (maxHeaderSize ~/ _bitsPerByte + (maxHeaderSize % _bitsPerByte == 0 ? 0 : 1));

  /// Sets the maximum message payload size
  ///
  /// [value] : new maximal payload size
  set maxPayloadSize(int value) {
    if (Peer.activeCount > 0) {
      throw Exception("Changing the 'maxPayloadSize' is not allowed while a Server or Client is running!");
    }

    if (value < 0) {
      throw RangeError("'maxPayloadSize' cannot be negative!");
    }

    _maxSize = maxHeaderSize ~/ _bitsPerByte + (maxHeaderSize % _bitsPerByte == 0 ? 0 : 1) + value;
    _maxBitCount = _maxSize * _bitsPerByte;
    _maxArraySize = _maxSize ~/ Constants.ulongBytes + (_maxSize % Constants.ulongBytes == 0 ? 0 : 1);
    byteBuffer = Uint8List(_maxSize);
    trimPool(); // When ActiveSocketCount is 0, this clears the pool
    PendingMessage.clearPool();
  }

  /// An intermediary buffer to help convert [data] to a byte array when sending.
  static late Uint8List byteBuffer;

  /// The maximum number of bits a message can contain.
  static late int _maxBitCount;

  /// The maximum size of the [data] array.
  static late int _maxArraySize;

  /// How many messages to add to the pool for each Server or Client instance that is started.
  ///
  /// Changes will not affect Server and Client instances which are already running until they are restarted.
  static int instancesPerPeer = 4;

  /// A pool of reusable message instances.
  static List<Message> _pool = List.generate(instancesPerPeer * 2, (index) => Message(), growable: false);

  static void initialize() {
    _maxSize = maxHeaderSize ~/ _bitsPerByte + (maxHeaderSize % _bitsPerByte == 0 ? 0 : 1) + 1225;
    _maxBitCount = _maxSize * _bitsPerByte;
    _maxArraySize = _maxSize ~/ Constants.ulongBytes + (_maxSize % Constants.ulongBytes == 0 ? 0 : 1);
    byteBuffer = Uint8List(_maxSize);
  }

  /// The message's send mode.
  late MessageSendMode _sendMode;
  MessageSendMode get sendMode => _sendMode;

  /// How many bits have been retrieved from the message.
  int get readBits => _readBit;

  /// How many unretrieved bits remain in the message.
  int get unreadBits => _writeBit - _readBit;

  /// How many bits have been added to the message.
  int get writtenBits => _writeBit;

  /// How many more bits can be added to the message.
  int get unwrittenBits => _maxBitCount - _writeBit;

  /// How many of this message's bytes are in use. Rounds up to the next byte because only whole bytes can be sent.
  int get bytesInUse => _writeBit ~/ _bitsPerByte + (_writeBit % _bitsPerByte == 0 ? 0 : 1);

  /// The message's data.
  late Uint8List _data;
  Uint8List get data => _data;

  /// The next bit to be read.
  late int _readBit;

  /// The next bit to be written.
  late int _writeBit;

  /// Initializes a reusable Message instance.
  Message() {
    if (!_initialized) {
      initialize();
    }

    _data = Uint8List(_maxArraySize);
  }

  /// Gets a completely empty message instance with no header.
  ///
  /// Returns an empty message instance.
  static Message create() {
    if (!_initialized) {
      initialize();
    }

    Message message = _retrieveFromPool();
    message._readBit = 0;
    message._writeBit = 0;

    return message;
  }

  /// Gets a message instance that can be used for sending.
  ///
  /// [sendMode] : The mode in which the message should be sent.
  ///
  /// Returns a message instance ready to be sent.
  ///
  /// This method is primarily intended for use with [MessageSendMode.notify] as notify messages don't have a built-in message ID, and unlike
  /// [createFromInt] and [createFromEnum], this create function does not add a message ID to the message.
  static Message createWithSendMode(MessageSendMode sendMode) {
    return _retrieveFromPool()._initWithHeader(sendMode.messageHeader);
  }

  /// Gets a message instance that can be used for sending.
  ///
  /// [sendMode] : The mode in which the message should be sent.
  /// [id] : The message ID.
  ///
  /// Returns a message instance ready to be sent.
  static Message createFromInt(MessageSendMode sendMode, int id) {
    return _retrieveFromPool()._initWithHeader(sendMode.messageHeader).addUShort(id);
  }

  /// Gets a message instance that can be used for sending.
  ///
  /// [sendMode] : The mode in which the message should be sent.
  /// [id] : The message ID as enum.
  ///
  /// NOTE: [id] will be cast to the size of a ushort aka 16 bit. You should ensure that its value never exceeds that of ushort maxvalue, otherwise you'll encounter unexpected behaviour when handling messages.
  static Message createFromEnum(MessageSendMode sendMode, Enum id) {
    return createFromInt(sendMode, id.index);
  }

  /// Gets a message instance that can be used for sending.
  ///
  /// [header] : The message's header type.
  ///
  /// Returns a message instance ready to be sent.
  static Message createFromHeader(MessageHeader header) {
    return _retrieveFromPool()._initWithHeader(header);
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
        _pool.removeRange(Peer.activeCount * instancesPerPeer, _pool.length - idealInstanceAmount);
        _pool.length = idealInstanceAmount * 2;
      }
    }
  }

  /// Retrieves a message instance from the pool. If none is available, a new instance is created.
  ///
  /// Returns a message instance ready to be used for sending or handling.
  static Message _retrieveFromPool() {
    Message message;
    if (_pool.isNotEmpty) {
      message = _pool.removeAt(0);
    } else {
      message = Message();
    }

    return message;
  }

  /// Returns the message instance to the internal pool so it can be reused.
  void release() {
    if (!_pool.contains(this)) {
      // Only add it if it's not already in the list, otherwise this method being called twice in a row for whatever reason could cause *serious* issues
      _pool.add(this);
    }
  }

  /// Initializes the message so that it can be used for sending.
  ///
  /// [header] : The message's header type.
  ///
  /// Returns the message, ready to be used for sending.
  Message _initWithHeader(MessageHeader header) {
    data[0] = header.messageIndex;
    setHeader(header);
    return this;
  }

  /// Initializes the message so that it can be used for receiving/handling.
  ///
  /// [firstByte] : The first byte of the received data.
  /// [contentLength] : The number of bytes which this message will contain.
  ///
  /// Returns the message, ready to be used for handling and the message's header type.
  (Message message, MessageHeader header) initWithByte(int firstByte, int contentLength) {
    data[0] = firstByte;
    MessageHeader header = MessageHeader.values[firstByte & headerBitmask];
    setHeader(header);
    _writeBit = contentLength * _bitsPerByte;
    return (this, header);
  }

  /// Sets the message's header byte to the given header and determines the appropriate MessageSendMode and read/write positions.
  ///
  /// [header] : The header to use for this message.
  void setHeader(MessageHeader header) {
    if (header.messageIndex == MessageHeader.notify.index) {
      _readBit = notifyHeaderBits;
      _writeBit = notifyHeaderBits;
      _sendMode = MessageSendMode.notify;
    } else if (header.messageIndex >= MessageHeader.reliable.index) {
      _readBit = reliableHeaderBits;
      _writeBit = reliableHeaderBits;
      _sendMode = MessageSendMode.reliable;
    } else {
      _readBit = unreliableHeaderBits;
      _writeBit = unreliableHeaderBits;
      _sendMode = MessageSendMode.unreliable;
    }
  }

  /// Adds [message]'s unread bits to the message.
  ///
  /// [message] : The message whose unread bits to add.
  /// Returns the message that the bits were added to.
  ///
  /// This method does not move [message]'s internal read position!
  Message addMessage(Message message) => addMessageWithBit(message, message.unreadBits, message._readBit);

  /// Adds a range of bits from [message] to the message.
  ///
  /// [message] : The message whose bits to add.
  /// [amount] : The number of bits to add.
  /// [startBit] : The position in [message] from which to add the bits.
  /// Returns the message that the bits were added to.
  ///
  /// This method does not move [message]'s internal read position!
  Message addMessageWithBit(Message message, int amount, int startBit) {
    if (unwrittenBits < amount) {
      throw new InsufficientCapacityException.withDetails(this, message.runtimeType.toString(), amount);
    }

    int sourcePos = startBit ~/ _bitsPerSegment;
    int sourceBit = startBit % _bitsPerSegment;
    int destPos = _writeBit ~/ _bitsPerSegment;
    int destBit = _writeBit % _bitsPerSegment;
    int bitOffset = destBit - sourceBit;
    int destSegments = (_writeBit + amount) ~/ _bitsPerSegment - destPos + 1;

    if (bitOffset == 0) {
      // Source doesn't need to be shifted, source and dest bits span the same number of segments
      int firstSegment = message.data[sourcePos];
      if (destBit == 0)
        data[destPos] = firstSegment;
      else
        data[destPos] |= firstSegment & ~((1 << sourceBit) - 1);

      for (int i = 1; i < destSegments; i++) data[destPos + i] = message.data[sourcePos + i];
    } else if (bitOffset > 0) {
      // Source needs to be shifted left, dest bits may span more segments than source bits
      int firstSegment = message.data[sourcePos] & ~((1 << sourceBit) - 1);
      firstSegment <<= bitOffset;
      if (destBit == 0)
        data[destPos] = firstSegment;
      else
        data[destPos] |= firstSegment;

      for (int i = 1; i < destSegments; i++)
        data[destPos + i] = (message.data[sourcePos + i - 1] >> (_bitsPerSegment - bitOffset)) | (message.data[sourcePos + i] << bitOffset);
    } else {
      // Source needs to be shifted right, source bits may span more segments than dest bits
      bitOffset = -bitOffset;
      int firstSegment = message.data[sourcePos] & ~((1 << sourceBit) - 1);
      firstSegment >>= bitOffset;
      if (destBit == 0)
        data[destPos] = firstSegment;
      else
        data[destPos] |= firstSegment;

      int sourceSegments = (startBit + amount) ~/ _bitsPerSegment - sourcePos + 1;
      for (int i = 1; i < sourceSegments; i++) {
        data[destPos + i - 1] |= message.data[sourcePos + i] << (_bitsPerSegment - bitOffset);
        data[destPos + i] = message.data[sourcePos + i] >> bitOffset;
      }
    }

    _writeBit += amount;
    data[destPos + destSegments - 1] &= (1 << (_writeBit % _bitsPerSegment)) - 1;
    return this;
  }

  /// Moves the message's internal write position by the given [amount] of bits, reserving them so they can be set at a later time.
  ///
  /// [amount] : The number of bits to reserve.
  ///
  /// Returns the message instance.
  Message reserveBits(int amount) {
    if (unwrittenBits < amount) {
      throw new InsufficientCapacityException.withReservedBits(this, amount);
    }

    int bit = _writeBit % _bitsPerSegment;
    _writeBit += amount;

    // Reset the last segment that the reserved range touches, unless it's also the first one, in which case it may already contain data which we don't want to overwrite
    if (bit + amount >= _bitsPerSegment) {
      data[_writeBit ~/ _bitsPerSegment] = 0;
    }

    return this;
  }

  /// Moves the message's internal read position by the given [amount] of bits, skipping over them.
  ///
  /// [amount] : The number of bits to skip.
  ///
  /// Returns the message instance.
  Message skipBits(int amount) {
    if (unreadBits < amount) {
      RiptideLogger.log(
          LogType.error, "Message only contains $unreadBits unread ${Helper.correctForm(unreadBits, "bit")}, which is not enough to skip $amount!");
    }

    _readBit += amount;
    return this;
  }

  /// Sets up to 64 bits at the specified position in the message.
  ///
  /// [bitfield] : The bits to write into the message.
  /// [amount] : The number of bits to set.
  /// [startBit] : The bit position in the message at which to start writing.
  ///
  /// Returns the message instance.
  ///
  /// This method can be used to directly set a range of bits anywhere in the message without moving its internal write position. Data which was previously added to
  /// the message and which falls within the range of bits being set will be <i>overwritten</i>, meaning that improper use of this method will likely corrupt the message!
  ///
  /// IMPORTANT: Originally takes a ulong [bitfield] aka unsigned 64 bits as parameter. Dart only has int aka 64 signed bits. This might cause problems
  Message setBits(int bitfield, int amount, int startBit) {
    if (amount > Constants.ulongBytes * _bitsPerByte) {
      throw RangeError("Cannot set more than ${Constants.ulongBytes * _bitsPerByte} bits at a time!");
    }

    Converter.setBitsFromUlongWithUlongList(bitfield, amount, data, startBit);
    return this;
  }

  /// Retrieves up to 8 bits from the specified position in the message.
  ///
  /// [amount] : The number of bits to peek.
  /// [startBit] : The bit position in the message at which to start peeking.
  ///
  /// Returns the message instance and the bits that were retrieved.
  ///
  /// This method can be used to retrieve a range of bits from anywhere in the message without moving its internal read position.
  (Message message, int bitfield) peekBitsByte(int amount, int startBit) {
    if (amount > _bitsPerByte) {
      throw RangeError("PeekBitsByte cannot be used to peek more than $_bitsPerByte bits at a time!");
    }

    int bitfield = Converter.getBitsForByte(amount, data, startBit);
    return (this, bitfield);
  }

  /// Retrieves up to 16 bits from the specified position in the message.
  ///
  /// <inheritdoc cref="PeekBits(int, int, out byte)]
  (Message message, int bitfield) peekBitsUshort(int amount, int startBit) {
    if (amount > Constants.ushortBytes * _bitsPerByte) {
      throw RangeError("PeekBitsUshort cannot be used to peek more than ${Constants.ushortBytes * _bitsPerByte} bits at a time!");
    }

    int bitfield = Converter.getBitsForUshort(amount, data, startBit);
    return (this, bitfield);
  }

  /// Retrieves up to 32 bits from the specified position in the message.
  ///
  /// <inheritdoc cref="PeekBits(int, int, out byte)]
  (Message message, int bitfield) peekBitsUint(int amount, int startBit) {
    if (amount > Constants.uintBytes * _bitsPerByte) {
      throw RangeError("PeekBitsUint overload cannot be used to peek more than ${Constants.uintBytes * _bitsPerByte} bits at a time!");
    }

    int bitfield = Converter.getBitsForUint(amount, data, startBit);
    return (this, bitfield);
  }

  /// Retrieves up to 64 bits from the specified position in the message.
  ///
  /// <inheritdoc cref="PeekBits(int, int, out byte)]
  /// IMPORTANT: Originally returns a ulong [bitfield] aka unsigned 64 bits. Dart only has int aka 64 signed bits. This might cause problems
  (Message message, int bitfield) peekBitsUlong(int amount, int startBit) {
    if (amount > Constants.ulongBytes * _bitsPerByte) {
      throw RangeError("PeekBitsUlong cannot be used to peek more than ${Constants.ulongBytes * _bitsPerByte} bits at a time!");
    }

    int bitfield = Converter.getBitsForUlong(amount, data, startBit);
    return (this, bitfield);
  }

  /// Adds up to 8 of the given bits to the message.
  ///
  /// [bitfield] : The bits to add.
  /// [amount] : The number of bits to add.
  ///
  /// Returns the message that the bits were added to.
  Message addBitsByte(int bitfield, int amount) {
    if (amount > _bitsPerByte) {
      throw RangeError("AddBitsByte cannot be used to add more than $_bitsPerByte bits at a time!");
    }

    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're setting
    Converter.byteToBits(bitfield, data, _writeBit);
    _writeBit += amount;
    return this;
  }

  /// Adds up to 16 of the given bits to the message.
  ///
  /// [bitfield] : The bits to add.
  /// [amount] : The number of bits to add.
  ///
  /// Returns the message that the bits were added to.
  Message addBitsUshort(int bitfield, int amount) {
    if (amount > Constants.ushortBytes * _bitsPerByte) {
      throw RangeError("AddBitsUshort cannot be used to add more than ${Constants.ushortBytes * _bitsPerByte} bits at a time!");
    }

    bitfield &= (1 << amount) - 1; // Discard any bits that are set beyond the ones we're adding
    Converter.uShortToBits(bitfield, data, _writeBit);
    _writeBit += amount;
    return this;
  }

  /// Adds up to 32 of the given bits to the message.
  ///
  /// [bitfield] : The bits to add.
  /// [amount] : The number of bits to add.
  ///
  /// Returns the message that the bits were added to.
  Message addBitsUint(int bitfield, int amount) {
    if (amount > Constants.uintBytes * _bitsPerByte) {
      throw RangeError("AddBitsUint cannot be used to add more than ${Constants.uintBytes * _bitsPerByte} bits at a time!");
    }

    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're adding
    Converter.uIntToBits(bitfield, data, _writeBit);
    _writeBit += amount;
    return this;
  }

  /// Adds up to 64 of the given bits to the message.
  ///
  /// [bitfield] : The bits to add.
  /// [amount] : The number of bits to add.
  ///
  /// Returns the message that the bits were added to.
  ///
  /// IMPORTANT: Originally takes a ulong [bitfield] aka unsigned 64 bits as parameter. Dart only has int aka 64 signed bits. This might cause problems
  Message addBitsUlong(int bitfield, int amount) {
    if (amount > Constants.ulongBytes * _bitsPerByte) {
      throw RangeError("AddBitsUlong cannot be used to add more than ${Constants.ulongBytes * _bitsPerByte} bits at a time!");
    }

    bitfield &= (1 << (amount - 1) << 1) - 1; // Discard any bits that are set beyond the ones we're adding
    Converter.uLongToBits(bitfield, data, _writeBit);
    _writeBit += amount;
    return this;
  }

  /// Retrieves the next [amount] bits (up to 8) from the message.
  ///
  /// [amount] : The number of bits to retrieve.
  ///
  /// Returns the messages that the bits were retrieved from and the bits that were retrieved.
  (Message message, int bitfield) getBitsByte(int amount) {
    (Message, int) data = peekBitsByte(amount, _readBit);
    _readBit += amount;
    return (this, data.$2);
  }

  /// Retrieves the next [amount] bits (up to 16) from the message.
  ///
  /// [amount] : The number of bits to retrieve.
  ///
  /// Returns the messages that the bits were retrieved from and the bits that were retrieved.
  (Message message, int bitfield) getBitsUshort(int amount) {
    (Message, int) data = peekBitsUshort(amount, _readBit);
    _readBit += amount;
    return (this, data.$2);
  }

  /// Retrieves the next [amount] bits (up to 32) from the message.
  ///
  /// [amount] : The number of bits to retrieve.
  ///
  /// Returns the messages that the bits were retrieved from and the bits that were retrieved.
  (Message message, int bitfield) getBitsUint(int amount) {
    (Message, int) data = peekBitsUint(amount, _readBit);
    _readBit += amount;
    return (this, data.$2);
  }

  /// Retrieves the next [amount] bits (up to 64) from the message.
  ///
  /// [amount] : The number of bits to retrieve.
  ///
  /// Returns the messages that the bits were retrieved from and the bits that were retrieved.
  ///
  /// IMPORTANT: Originally returns a ulong [bitfield] aka unsigned 64 bits. Dart only has int aka 64 signed bits. This might cause problems
  (Message message, int bitfield) getBitsUlong(int amount) {
    (Message, int) data = peekBitsUlong(amount, _readBit);
    _readBit += amount;
    return (this, data.$2);
  }

  /// Adds a positive or negative number to the message, using fewer bits for smaller values.
  ///
  /// [value] : The value to add.
  /// Returns the message that the value was added to.
  /// The value is added in segments of 8 bits, 1 of which is used to indicate whether or not another segment follows. As a result, small values are
  /// added to the message using fewer bits, while large values will require a few more bits than they would if they were added via [addByte],
  /// [addUShort], [addUInt], or [addULong] (or their signed counterparts).
  Message addVarLong(int value) => addVarULong(Converter.zigZagEncodeLong(value));

  /// Adds a positive number to the message, using fewer bits for smaller values.
  ///
  /// [value] : The value to add.
  ///
  /// Returns the message that the value was added to.
  ///
  /// The value is added in segments of 8 bits, 1 of which is used to indicate whether or not another segment follows. As a result, small values are
  /// added to the message using fewer bits, while large values will require a few more bits than they would if they were added via [addByte],
  /// [addUShort], [addUInt], or [addULong] (or their signed counterparts).
  ///
  /// IMPORTANT: Originally takes a ulong [value] aka unsigned 64 bits as parameter. Dart only has int aka 64 signed bits. This might cause problems
  Message addVarULong(int value) {
    do {
      int byteValue = (value & 0x7f);
      value >>= 7;
      if (value != 0) // There's more to write
        byteValue |= 0x80;

      addByte(byteValue);
    } while (value != 0);

    return this;
  }

  /// Retrieves a positive or negative number from the message, using fewer bits for smaller values.
  ///
  /// Returns the value that was retrieved.
  ///
  /// The value is retrieved in segments of 8 bits, 1 of which is used to indicate whether or not another segment follows. As a result, small values are
  /// retrieved from the message using fewer bits, while large values will require a few more bits than they would if they were retrieved via [getByte],
  /// [getUShort], [getUInt], or [getULong] (or their signed counterparts).
  int getVarLong() => Converter.zigZagDecode(getVarULong());

  /// Retrieves a positive number from the message, using fewer bits for smaller values.
  ///
  /// Returns the value that was retrieved.
  ///
  /// The value is retrieved in segments of 8 bits, 1 of which is used to indicate whether or not another segment follows. As a result, small values are
  /// retrieved from the message using fewer bits, while large values will require a few more bits than they would if they were retrieved via [getByte],
  /// [getUShort], [getUInt], or [getULong] (or their signed counterparts).
  ///
  /// IMPORTANT: Originally returns a ulong aka unsigned 64 bits. Dart only has int aka 64 signed bits. This might cause problems
  int getVarULong() {
    int byteValue;
    int value = 0;
    int shift = 0;

    do {
      byteValue = getByte();
      value |= (byteValue & 0x7f) << shift;
      shift += 7;
    } while ((byteValue & 0x80) != 0);

    return value;
  }

  /// Adds a [byte] to the message.
  ///
  /// [value] : The [byte] to add.
  ///
  /// Returns the message that the [byte] was added to.
  Message addByte(int value) {
    if (unwrittenBits < _bitsPerByte) {
      throw new InsufficientCapacityException.withDetails(this, byteName, _bitsPerByte);
    }

    Converter.byteToBits(value, data, _writeBit);
    _writeBit += _bitsPerByte;
    return this;
  }

  /// Adds an [sbyte] to the message.
  ///
  /// [value] : The [sbyte] to add.
  ///
  /// Returns the message that the [sbyte] was added to.
  Message addSByte(int value) {
    if (unwrittenBits < _bitsPerByte) {
      throw new InsufficientCapacityException.withDetails(this, sByteName, _bitsPerByte);
    }

    Converter.sByteToBits(value, data, _writeBit);
    _writeBit += _bitsPerByte;
    return this;
  }

  /// Retrieves a [byte] from the message.
  ///
  /// Returns the [byte] that was retrieved.
  int getByte() {
    if (unreadBits < _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(byteName, "${Constants.byteDefault}"));
      return Constants.byteDefault;
    }

    int value = Converter.byteFromBits(data, _readBit);
    _readBit += _bitsPerByte;
    return value;
  }

  /// Retrieves an [sbyte] from the message.
  ///
  /// Returns the [sbyte] that was retrieved.
  int getSByte() {
    if (unreadBits < _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(sByteName, "${Constants.sbyteDefault}"));
      return Constants.sbyteDefault;
    }

    int value = Converter.sByteFromBits(data, _readBit);
    _readBit += _bitsPerByte;
    return value;
  }

  /// Adds a [byte] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  ///
  /// Returns the message that the array was added to.
  Message addBytes(Uint8List array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length * _bitsPerByte) throw new InsufficientCapacityException.withArrayDetails(this, array.length, byteName, _bitsPerByte);

    if (_writeBit % _bitsPerByte == 0) {
      data.buffer.asUint8List().setRange(_writeBit ~/ _bitsPerByte, array.length, array);
      _writeBit += array.length * _bitsPerByte;
    } else {
      for (int i = 0; i < array.length; i++) {
        Converter.byteToBits(array[i], data, _writeBit);
        _writeBit += _bitsPerByte;
      }
    }

    return this;
  }

  /// Adds an [sbyte] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  ///
  /// Returns the message that the array was added to.
  Message addSBytes(Int8List array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length * _bitsPerByte) {
      throw new InsufficientCapacityException.withArrayDetails(this, array.length, sByteName, _bitsPerByte);
    }

    for (int i = 0; i < array.length; i++) {
      Converter.sByteToBits(array[i], data, _writeBit);
      _writeBit += _bitsPerByte;
    }

    return this;
  }

  /// Retrieves a [byte] array from the message.
  ///
  /// Returns the array that was retrieved.
  Uint8List getBytes() => getBytesWithAmount(getVarULong());

  /// Retrieves a [byte] array from the message.
  ///
  /// [amount] : The amount of bytes to retrieve.
  /// Returns the array that was retrieved.
  Uint8List getBytesWithAmount(int amount) {
    Uint8List array = Uint8List(amount);
    _readBytes(amount, array);
    return array;
  }

  /// Populates a [byte] array with bytes retrieved from the message.
  ///
  /// [amount] : The amount of bytes to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void getBytesWithList(int amount, Uint8List intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, byteName));
    }

    _readBytes(amount, intoArray, startIndex);
  }

  /// Retrieves an [sbyte] array from the message.
  ///
  /// Returns the array that was retrieved.
  Int8List getSBytes() => getSBytesWithAmount(getVarULong());

  /// Retrieves an [sbyte] array from the message.
  ///
  /// [amount] : The amount of sbytes to retrieve.
  /// Returns the array that was retrieved.
  Int8List getSBytesWithAmount(int amount) {
    Int8List array = Int8List(amount);
    _readSBytes(amount, array);
    return array;
  }

  /// Populates a [sbyte] array with bytes retrieved from the message.
  ///
  /// [amount] : The amount of sbytes to retrieve.
  /// [intArray] : The array to populate.
  /// [startIndex] : The position at which to start populating [intArray].
  void getSBytesWithList(int amount, Int8List intArray, [int startIndex = 0]) {
    if (startIndex + amount > intArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intArray.length, startIndex, sByteName));
    }

    _readSBytes(amount, intArray, startIndex);
  }

  /// Reads a number of bytes from the message and writes them into the given array.
  ///
  /// [amount] : The amount of bytes to read.
  /// [intoArray] : The array to write the bytes into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readBytes(int amount, Uint8List intoArray, [int startIndex = 0]) {
    if (unreadBits < amount * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, byteName));
      amount = unreadBits ~/ _bitsPerByte;
    }

    if (_readBit % _bitsPerByte == 0) {
      intoArray.setRange(startIndex, startIndex + amount, data.buffer.asUint8List().sublist(_readBit ~/ _bitsPerByte));
      _readBit += amount * _bitsPerByte;
    } else {
      for (int i = 0; i < amount; i++) {
        intoArray[startIndex + i] = Converter.byteFromBits(data, _readBit);
        _readBit += _bitsPerByte;
      }
    }
  }

  /// Reads a number of sbytes from the message and writes them into the given array.
  ///
  /// [amount] : The amount of sbytes to read.
  /// [intoArray] : The array to write the sbytes into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readSBytes(int amount, Int8List intoArray, [int startIndex = 0]) {
    if (unreadBits < amount * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, sByteName));
      amount = unreadBits ~/ _bitsPerByte;
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = Converter.sByteFromBits(data, _readBit);
      _readBit += _bitsPerByte;
    }
  }

  /// Adds a [bool] to the message.
  ///
  /// [value] : The [bool] to add.
  ///
  /// Returns the message that the [bool] was added to.
  Message addBool(bool value) {
    if (unwrittenBits < 1) {
      throw new InsufficientCapacityException.withDetails(this, boolName, 1);
    }

    Converter.boolToBit(value, data, _writeBit++);
    return this;
  }

  /// Retrieves a [bool] from the message.
  ///
  /// Returns the [bool] that was retrieved.
  bool getBool() {
    if (unreadBits < 1) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(boolName, "${Constants.boolDefault}"));
      return Constants.boolDefault;
    }

    return Converter.boolFromBit(data, _readBit++);
  }

  /// Adds a [bool] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  ///
  /// Returns the message that the array was added to.
  Message addBools(BoolList array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length) {
      throw new InsufficientCapacityException.withArrayDetails(this, array.length, boolName, 1);
    }

    for (int i = 0; i < array.length; i++) {
      Converter.boolToBit(array[i], data, _writeBit++);
    }

    return this;
  }

  /// Retrieves a [bool] array from the message.
  ///
  /// Returns the array that was retrieved.
  BoolList getBools() => getBoolsWithAmount(getVarULong());

  /// Retrieves a [bool] array from the message.
  ///
  /// [amount] : The amount of bools to retrieve.
  ///
  /// Returns the array that was retrieved.
  BoolList getBoolsWithAmount(int amount) {
    BoolList array = new BoolList(amount);
    _readBools(amount, array);
    return array;
  }

  /// Populates a [bool] array with bools retrieved from the message.
  ///
  /// [amount] : The amount of bools to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void getBoolsWithList(int amount, BoolList intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, boolName));
    }

    _readBools(amount, intoArray, startIndex);
  }

  /// Reads a number of bools from the message and writes them into the given array.
  ///
  /// [amount] : The amount of bools to read.
  /// [intoArray] : The array to write the bools into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readBools(int amount, BoolList intoArray, [int startIndex = 0]) {
    if (unreadBits < amount) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, boolName));
      amount = unreadBits;
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = Converter.boolFromBit(data, _readBit++);
    }
  }

  /// Adds a [short] to the message.
  ///
  /// [value] : The [short] to add.
  ///
  /// Returns the message that the [short] was added to.
  Message addShort(int value) {
    if (unwrittenBits < Constants.shortBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withDetails(this, shortName, Constants.shortBytes * _bitsPerByte);

    Converter.shortToBits(value, data, _writeBit);
    _writeBit += Constants.shortBytes * _bitsPerByte;
    return this;
  }

  /// Adds a [ushort] to the message.
  ///
  /// [value] : The [ushort] to add.
  ///
  /// Returns the message that the [ushort] was added to.
  Message addUShort(int value) {
    if (unwrittenBits < Constants.ushortBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withDetails(this, uShortName, Constants.ushortBytes * _bitsPerByte);

    Converter.uShortToBits(value, data, _writeBit);
    _writeBit += Constants.ushortBytes * _bitsPerByte;
    return this;
  }

  /// Retrieves a [short] from the message.
  ///
  /// Returns the [short] that was retrieved.
  int getShort() {
    if (unreadBits < Constants.shortBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(shortName, "${Constants.shortDefault}"));
      return Constants.shortDefault;
    }

    int value = Converter.shortFromBits(data, _readBit);
    _readBit += Constants.shortBytes * _bitsPerByte;
    return value;
  }

  /// Retrieves a [ushort] from the message.
  ///
  /// Returns the [ushort] that was retrieved.
  int getUShort() {
    if (unreadBits < Constants.ushortBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(uShortName, "${Constants.ushortBytes}"));
      return Constants.ushortBytes;
    }

    int value = Converter.uShortFromBits(data, _readBit);
    _readBit += Constants.ushortBytes * _bitsPerByte;
    return value;
  }

  /// Adds a [short] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  ///
  /// Returns the message that the array was added to.
  Message addShorts(Int16List array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length * Constants.shortBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withArrayDetails(this, array.length, shortName, Constants.shortBytes * _bitsPerByte);

    for (int i = 0; i < array.length; i++) {
      array[i] = Converter.shortFromBits(data, _readBit);
      _readBit += Constants.shortBytes * _bitsPerByte;
    }

    return this;
  }

  /// Adds a [ushort] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  ///
  /// Returns the message that the array was added to.
  Message addUShorts(Uint16List array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length * Constants.ushortBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withArrayDetails(this, array.length, uShortName, Constants.ushortBytes * _bitsPerByte);

    for (int i = 0; i < array.length; i++) {
      array[i] = Converter.uShortFromBits(data, _readBit);
      _readBit += Constants.ushortBytes * _bitsPerByte;
    }

    return this;
  }

  /// Retrieves a [short] array from the message.
  ///
  /// Returns the array that was retrieved.
  Int16List getShorts() => getShortsWithAmount(getVarULong());

  /// Retrieves a [short] array from the message.
  ///
  /// [amount] : The amount of shorts to retrieve.
  ///
  /// Returns the array that was retrieved.
  Int16List getShortsWithAmount(int amount) {
    Int16List array = new Int16List(amount);
    _readShorts(amount, array);
    return array;
  }

  /// Populates a [short] array with shorts retrieved from the message.
  ///
  /// [amount] : The amount of shorts to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void getShortsWithList(int amount, Int16List intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, shortName));
    }

    _readShorts(amount, intoArray, startIndex);
  }

  /// Retrieves a [ushort] array from the message.
  ///
  /// Returns the array that was retrieved.
  Uint16List getUShorts() => getUShortsWithAmount(getVarULong());

  /// Retrieves a [ushort] array from the message.
  ///
  /// [amount] : The amount of ushorts to retrieve.
  ///
  /// Returns the array that was retrieved.
  Uint16List getUShortsWithAmount(int amount) {
    Uint16List array = new Uint16List(amount);
    _readUShorts(amount, array);
    return array;
  }

  /// Populates a [ushort] array with ushorts retrieved from the message.
  ///
  /// [amount] : The amount of ushorts to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void GetUShorts(int amount, Uint16List intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, uShortName));
    }

    _readUShorts(amount, intoArray, startIndex);
  }

  /// Reads a number of shorts from the message and writes them into the given array.
  ///
  /// [amount] : The amount of shorts to read.
  /// [intoArray] : The array to write the shorts into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readShorts(int amount, Int16List intoArray, [int startIndex = 0]) {
    if (unreadBits < amount * Constants.shortBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, shortName));
      amount = unreadBits ~/ (Constants.sbyteDefault * _bitsPerByte);
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = Converter.shortFromBits(data, _readBit);
      _readBit += Constants.shortBytes * _bitsPerByte;
    }
  }

  /// Reads a number of ushorts from the message and writes them into the given array.
  ///
  /// [amount] : The amount of ushorts to read.
  /// [intoArray] : The array to write the ushorts into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readUShorts(int amount, Uint16List intoArray, [int startIndex = 0]) {
    if (unreadBits < amount * Constants.ushortBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, uShortName));
      amount = unreadBits ~/ (Constants.ushortBytes * _bitsPerByte);
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = Converter.uShortFromBits(data, _readBit);
      _readBit += Constants.ushortBytes * _bitsPerByte;
    }
  }

  /// Adds an [int] to the message.
  ///
  /// [value] : The [int] to add.
  /// Returns the message that the [int] was added to.
  Message addInt(int value) {
    if (unwrittenBits < Constants.intBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withDetails(this, intName, Constants.intBytes * _bitsPerByte);

    Converter.intToBits(value, data, _writeBit);
    _writeBit += Constants.intBytes * _bitsPerByte;
    return this;
  }

  /// Adds a [uint] to the message.
  ///
  /// [value] : The [uint] to add.
  /// Returns the message that the [uint] was added to.
  Message addUInt(int value) {
    if (unwrittenBits < Constants.uintBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withDetails(this, uIntName, Constants.uintBytes * _bitsPerByte);

    Converter.uIntToBits(value, data, _writeBit);
    _writeBit += Constants.uintBytes * _bitsPerByte;
    return this;
  }

  /// Retrieves an [int] from the message.
  ///
  /// Returns the [int] that was retrieved.
  int getInt() {
    if (unreadBits < Constants.intBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(intName, "${Constants.intDefault}"));
      return Constants.intDefault;
    }

    int value = Converter.intFromBits(data, _readBit);
    _readBit += Constants.intBytes * _bitsPerByte;
    return value;
  }

  /// Retrieves a [uint] from the message.
  ///
  /// Returns the [uint] that was retrieved.
  int getUInt() {
    if (unreadBits < Constants.uintBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(uIntName, "${Constants.uintBytes}"));
      return Constants.uintBytes;
    }

    int value = Converter.uIntFromBits(data, _readBit);
    _readBit += Constants.uintBytes * _bitsPerByte;
    return value;
  }

  /// Adds an [int] array message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  /// Returns the message that the array was added to.
  Message addInts(Int32List array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length * Constants.intBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withArrayDetails(this, array.length, intName, Constants.intBytes * _bitsPerByte);

    for (int i = 0; i < array.length; i++) {
      Converter.intToBits(array[i], data, _writeBit);
      _writeBit += Constants.intBytes * _bitsPerByte;
    }

    return this;
  }

  /// Adds a [uint] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  /// Returns the message that the array was added to.
  Message addUInts(Uint32List array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length * Constants.uintBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withArrayDetails(this, array.length, uIntName, Constants.uintBytes * _bitsPerByte);

    for (int i = 0; i < array.length; i++) {
      Converter.uIntToBits(array[i], data, _writeBit);
      _writeBit += Constants.uintBytes * _bitsPerByte;
    }

    return this;
  }

  /// Retrieves an [int] array from the message.
  ///
  /// Returns the array that was retrieved.
  Int32List getInts() => getIntsWithAmount(getVarULong());

  /// Retrieves an [int] array from the message.
  ///
  /// [amount] : The amount of ints to retrieve.
  /// Returns the array that was retrieved.
  Int32List getIntsWithAmount(int amount) {
    Int32List array = new Int32List(amount);
    _readInts(amount, array);
    return array;
  }

  /// Populates an [int] array with ints retrieved from the message.
  ///
  /// [amount] : The amount of ints to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void getIntsWithList(int amount, Int32List intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, intName));
    }

    _readInts(amount, intoArray, startIndex);
  }

  /// Retrieves a [uint] array from the message.
  ///
  /// Returns the array that was retrieved.
  Uint32List getUInts() => getUIntsWithAmount(getVarULong());

  /// Retrieves a [uint] array from the message.
  ///
  /// [amount] : The amount of uints to retrieve.
  /// Returns the array that was retrieved.
  Uint32List getUIntsWithAmount(int amount) {
    Uint32List array = new Uint32List(amount);
    _readUInts(amount, array);
    return array;
  }

  /// Populates a [uint] array with uints retrieved from the message.
  ///
  /// [amount] : The amount of uints to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void GetUInts(int amount, Uint32List intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, uIntName));
    }

    _readUInts(amount, intoArray, startIndex);
  }

  /// Reads a number of ints from the message and writes them into the given array.
  ///
  /// [amount] : The amount of ints to read.
  /// [intoArray] : The array to write the ints into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readInts(int amount, Int32List intoArray, [int startIndex = 0]) {
    if (unreadBits < amount * Constants.intBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, intName));
      amount = unreadBits ~/ (Constants.intBytes * _bitsPerByte);
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = Converter.intFromBits(data, _readBit);
      _readBit += Constants.intBytes * _bitsPerByte;
    }
  }

  /// Reads a number of uints from the message and writes them into the given array.
  ///
  /// [amount] : The amount of uints to read.
  /// [intoArray] : The array to write the uints into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readUInts(int amount, Uint32List intoArray, [int startIndex = 0]) {
    if (unreadBits < amount * Constants.uintBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, uIntName));
      amount = unreadBits ~/ (Constants.uintBytes * _bitsPerByte);
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = Converter.uIntFromBits(data, _readBit);
      _readBit += Constants.uintBytes * _bitsPerByte;
    }
  }

  // TODO: Long

  // TODO: Float

  /// Adds a [double] to the message.
  ///
  /// [value] : The [double] to add.
  /// Returns the message that the [double] was added to.
  Message addDouble(double value) {
    if (unwrittenBits < Constants.doubleBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withDetails(this, doubleName, Constants.doubleBytes * _bitsPerByte);

    Converter.doubleToBits(value, data, _writeBit);
    _writeBit += Constants.doubleBytes * _bitsPerByte;
    return this;
  }

  /// Retrieves a [double] from the message.
  ///
  /// Returns the [double] that was retrieved.
  double getDouble() {
    if (unreadBits < Constants.doubleBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(doubleName, "${Constants.doubleDefault}"));
      return Constants.doubleDefault;
    }

    double value = Converter.doubleFromBits(data, _readBit);
    _readBit += Constants.doubleBytes * _bitsPerByte;
    return value;
  }

  /// Adds a [double] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  /// Returns the message that the array was added to.
  Message addDoubles(List<double> array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    if (unwrittenBits < array.length * Constants.doubleBytes * _bitsPerByte)
      throw new InsufficientCapacityException.withArrayDetails(this, array.length, doubleName, Constants.doubleBytes * _bitsPerByte);

    for (int i = 0; i < array.length; i++) {
      Converter.doubleToBits(array[i], data, _writeBit);
      _writeBit += Constants.doubleBytes * _bitsPerByte;
    }

    return this;
  }

  /// Retrieves a [double] array from the message.
  ///
  /// Returns the array that was retrieved.
  List<double> getDoubles() => getDoublesWithAmount(getVarULong());

  /// Retrieves a [double] array from the message.
  ///
  /// [amount] : The amount of doubles to retrieve.
  /// Returns the array that was retrieved.
  List<double> getDoublesWithAmount(int amount) {
    List<double> array = List.generate(amount, (index) => Constants.doubleDefault);
    _readDoubles(amount, []);
    return array;
  }

  /// Populates a [double] array with doubles retrieved from the message.
  ///
  /// [amount] : The amount of doubles to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void getDoublesWithList(int amount, List<double> intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, doubleName));
    }

    _readDoubles(amount, intoArray, startIndex);
  }

  /// Reads a number of doubles from the message and writes them into the given array.
  ///
  /// [amount] : The amount of doubles to read.
  /// [intoArray] : The array to write the doubles into.
  /// [startIndex] : The position at which to start writing into the array.
  void _readDoubles(int amount, List<double> intoArray, [int startIndex = 0]) {
    if (unreadBits < amount * Constants.doubleBytes * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError2(amount, doubleName));
      amount = unreadBits ~/ (Constants.doubleBytes * _bitsPerByte);
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = Converter.doubleFromBits(data, _readBit);
      _readBit += Constants.doubleBytes * _bitsPerByte;
    }
  }

  /// Adds a [String] to the message.
  ///
  /// [value] : The [String] to add.
  ///
  /// Returns the message that the [String] was added to.
  Message addString(String value) {
    addBytes(utf8.encode(value));
    return this;
  }

  /// Retrieves a [String] from the message.
  ///
  /// Returns the [String] that was retrieved.
  String getString() {
    int length = getVarULong(); // Get the length of the string (in bytes, NOT characters)
    if (unreadBits < length * _bitsPerByte) {
      RiptideLogger.log(LogType.error, _notEnoughBitsError(stringName, "shortened string"));
      length = unreadBits ~/ _bitsPerByte;
    }

    String value = utf8.decode(getBytesWithAmount(length));
    return value;
  }

  /// Adds a [String] array to the message.
  ///
  /// [array] : The array to add.
  /// [includeLength] : Whether or not to include the length of the array in the message.
  ///
  /// Returns the message that the array was added to.
  Message addStrings(List<String> array, [bool includeLength = true]) {
    if (includeLength) {
      addVarULong(array.length);
    }

    // It'd be ideal to throw an exception here (instead of in AddString) if the entire array isn't going to fit, but since each string could
    // be (and most likely is) a different length and some characters use more than a single byte, the only way of doing that would be to loop
    // through the whole array here and convert each string to bytes ahead of time, just to get the required byte count. Then if they all fit
    // into the message, they would all be converted again when actually being written into the byte array, which is obviously inefficient.

    for (int i = 0; i < array.length; i++) {
      addString(array[i]);
    }

    return this;
  }

  /// Retrieves a [String] array from the message.
  ///
  /// Returns the array that was retrieved.
  List<String> getStrings() => getStringsWithAmount(getVarULong());

  /// Retrieves a [String] array from the message.
  ///
  /// [amount] : The amount of strings to retrieve.
  ///
  /// Returns the array that was retrieved.
  List<String> getStringsWithAmount(int amount) {
    List<String> array = List.generate(amount, (index) => "");
    for (int i = 0; i < array.length; i++) array[i] = getString();

    return array;
  }

  /// Populates a [String] array with strings retrieved from the message.
  ///
  /// [amount] : The amount of strings to retrieve.
  /// [intoArray] : The array to populate.
  /// [startIndex] : The position at which to start populating the array.
  void getStringsWithList(int amount, List<String> intoArray, [int startIndex = 0]) {
    if (startIndex + amount > intoArray.length) {
      throw ArgumentError(_arrayNotLongEnoughError(amount, intoArray.length, startIndex, stringName));
    }

    for (int i = 0; i < amount; i++) {
      intoArray[startIndex + i] = getString();
    }
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
  ///
  /// Returns the error message.
  String _notEnoughBitsError(String valueName, [String defaultReturn = "0"]) {
    return "Message only contains $unreadBits unread ${Helper.correctForm(unreadBits, "bit")}, which is not enough to retrieve a value of type '$valueName'! Returning $defaultReturn.";
  }

  /// Constructs an error message for when a message contains insufficient unread bytes to retrieve an array of values.
  ///
  /// [arrayLength] : The expected length of the array.
  /// [valueName] : The name of the value type for which the retrieval attempt failed.
  ///
  /// Returns the error message.
  String _notEnoughBitsError2(int arrayLength, String valueName) {
    return "Message only contains $unreadBits unread ${Helper.correctForm(unreadBits, "bit")}, which is not enough to retrieve $arrayLength ${Helper.correctForm(arrayLength, valueName)}! Returned array will contain default elements.";
  }

  /// Constructs an error message for when a number of retrieved values do not fit inside the bounds of the provided array.
  ///
  /// [amount] : The number of values being retrieved.
  /// [arrayLength] : The length of the provided array.
  /// [startIndex] : The position in the array at which to begin writing values.
  /// [valueName] : The name of the value type which is being retrieved.
  /// [pluralValueName] : The name of the value type in plural form. If left empty, this will be set to valueName with an 's' appended to it.
  ///
  /// Returns the error message.
  String _arrayNotLongEnoughError(int amount, int arrayLength, int startIndex, String valueName, {String pluralValueName = ""}) {
    if (pluralValueName == "") {
      pluralValueName = "${valueName}s";
    }

    return "The amount of $pluralValueName to retrieve ($amount) is greater than the number of elements from the start index ($startIndex) to the end of the given array (length: $arrayLength)!";
  }
}
