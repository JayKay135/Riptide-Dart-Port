# Riptide Dart Port

Dart port of [Riptide](https://github.com/RiptideNetworking/Riptide), a lightweight networking library from Tom Weiland.

This port provides functionality for establishing connections with clients and servers using the Riptide protocol. 

## Compatibility

This port was last tested for functionality with Riptide [Commit 933cafd](https://github.com/RiptideNetworking/Riptide/commit/933cafd6208b379eed4837f6e395e911f37a93d7), Jan 04 2024

---

**NOTE:** Riptide itself is not backward compatible. This library will currently only work with Riptide version ```v2.1.2```. 

The older version (pub ```0.0.3```) will still work with Riptide ```v.2.0.0```, but with limited features (e.g. missing tcp support).

## Important Notes

The dart language differs C# in some key aspects. 
- There is no function overloading in dart. Therefore, you have to deal with many different function names in the message class.
If you find a cleaner solution, do not hesitate to open up a pull request.
- There is no ulong type in dart. C#'s longs are signed 64bit values. So are the int values in dart. Longs can be represented without any issues in dart using ints. Unfortunately, there is no unsigned 64-bit type in dart. The representation of ulongs in dart is, therefore, not easily possible. Currently, ulongs will get parsed to ints. **Please note that this might result in data loss**.


## Compatible libraries in other languages

- C#: [Riptide](https://github.com/RiptideNetworking/Riptide)
- Python: [Pytide](https://github.com/ebosseck/PytideNetworking/tree/main)

## Getting started

The API is mostly identical to [Riptide](https://github.com/RiptideNetworking/Riptide).

### Installation
In your projects pubspec.yaml file add riptide under your dependencies.
```yaml
dependencies:
    riptide: ^0.0.3
```
or run
```bash
dart pub add riptide
```

## Usage

### Enable Logging
```dart
RiptideLogger.initialize(print, true);
```

### Create a new Server
```dart
Server server = Server();
server.start(PORT, 10);

// timer to periodically update the server
Timer.periodic(const Duration(milliseconds: 20), (timer) {
    server.update();
});
```

Handling received message:
```dart
server.registerMessageHandler(MESSAGE_ID, handleMessage);

void handleMessage(int clientID, Message message) {
    // do something
}
```

### Create a new Client
```dart
Client client = Client();
client.connect(InternetAddress("127.0.0.1"), PORT);

// timer to periodically update the client
Timer.periodic(const Duration(milliseconds: 20), (timer) {
    client.update();
});
```

Handling received message:
```dart
client.registerMessageHandler(MESSAGE_ID, handleMessage);

void handleMessage(Message message) {
    // do something
}
```

### Send Messages
```dart
Message message = Message.createFromInt(MessageSendMode.reliable, MESSAGE_ID);
message.addString("Hello World !");

client.send(message);
server.sendToAll(message);
```

## Multi threaded Server/ Client
It is recommended to run the whole server/ client code execution in a separate isolate to increase performance.
This library provides a lightweight implementation of such an isolate.

Simply swap from
```dart
Server server = Server();
server.start(PORT, 10);

Timer.periodic(const Duration(milliseconds: 20), (timer) {
    server.update();
});
```
to
```dart
MultiThreadedServer mtServer = MultiThreadedServer();
mtServer.start(PORT, 10, loggingEnabled: true);
```
or
```dart
Client client = Client();
client.connect(InternetAddress("127.0.0.1"), PORT);

Timer.periodic(const Duration(milliseconds: 20), (timer) {
    client.update();
});
```
to
```dart
MultiThreadedClient mtClient = MultiThreadedClient();
mtClient.connect(InternetAddress("127.0.0.1"), PORT, loggingEnabled: true);
```

If you want to use a different transport with the multi-threaded variants, pass it as an argument in the constructor call.

e.g.
```dart
MultiThreadedClient mtClient = MultiThreadedClient(transportType: MultiThreadedTransportType.tcp);
mtClient.connect(InternetAddress("127.0.0.1"), PORT, loggingEnabled: true);
```

## Additional Note

If you are using Android: Make sure to enable the internet permission in the AndroidManifest.xml.

Under *android/app/src/main/AndroidManifest.xml* add 
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    ...
    <uses-permission android:name="android.permission.INTERNET"/>
    ...
```

And if you are using an Android emulator with localhost, note that instead of localhost, you should use the ip 10.0.2.2.

## Low-Level Transports supported by this library

* [UDP Transport](https://github.com/JayKay135/Riptide-Dart-Port/tree/master/lib/src/transports/udp) (built-in)
* [TCP Transport](https://github.com/JayKay135/Riptide-Dart-Port/tree/master/lib/src/transports/tcp) (built-in)

## Contributions

Contributions are welcome, especially if you know about low-level udp/ tcp sockets and isolates.

## License

Distributed under the MIT license. See LICENSE.md for more information. Copyright © 2023 [VISUS](https://www.visus.uni-stuttgart.de/en/), [University of Stuttgart](https://www.uni-stuttgart.de/)

This project is supported by [VISUS](https://www.visus.uni-stuttgart.de/en/), University of Stuttgart


