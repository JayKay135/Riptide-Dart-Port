import 'dart:io';

/// Sets the send and receive buffer sizes of a socket.
///
/// [setRawOption] : The socket's setRawOption method.
/// [size] : The size to use for the socket's send and receive buffers.
///
/// NOTE: C# sets the SendBufferSize and ReceiveBufferSize of its sockets, which dart:io only supports through raw socket
/// options whose values differ between platforms.
void setSocketBufferSizes(void Function(RawSocketOption option) setRawOption, int size) {
  bool isLinux = Platform.isLinux || Platform.isAndroid;
  int sendBufferOption = isLinux ? 7 : 0x1001; // SO_SNDBUF
  int receiveBufferOption = isLinux ? 8 : 0x1002; // SO_RCVBUF

  try {
    setRawOption(RawSocketOption.fromInt(RawSocketOption.levelSocket, sendBufferOption, size));
    setRawOption(RawSocketOption.fromInt(RawSocketOption.levelSocket, receiveBufferOption, size));
  } on SocketException {
    // The buffer sizes only affect performance, so the operating system's defaults are used if they can't be changed
  } on UnsupportedError {
    // Same as above
  }
}
