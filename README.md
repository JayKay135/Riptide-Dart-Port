# Riptide Dart Port

[![pub package](https://img.shields.io/pub/v/riptide.svg)](https://pub.dev/packages/riptide)
[![pub points](https://img.shields.io/pub/points/riptide.svg)](https://pub.dev/packages/riptide)
[![package publisher](https://img.shields.io/pub/publisher/riptide.svg)](https://pub.dev/packages/riptide/publisher)

Dart port of [Riptide](https://github.com/RiptideNetworking/Riptide), a lightweight networking library from Tom Weiland.

This port provides functionality for establishing connections with clients and servers using the Riptide protocol.

## Compatibility

This port is up to date with Riptide [Commit bc3f3f2](https://github.com/RiptideNetworking/Riptide/commit/bc3f3f2) (Aug 19 2026, Riptide `v2.2.1` plus the fixes released since) and was tested for compatibility with it, using both the UDP and the TCP transport.

---

**NOTE:** Riptide itself is not backward compatible. This library will currently only work with Riptide `v2.1.2` and newer versions.

The older version (pub `0.0.3`) will still work with Riptide `v2.0.0`, but with limited features (e.g. missing tcp support).
For more details about which pub versions correspond to what Riptide version take a look at the [changelog](CHANGELOG.md).

## Important Notes

The dart language differs C# in some key aspects.

- There is no function overloading in dart. Therefore, you have to deal with many different function names in the message class.
  If you find a cleaner solution, do not hesitate to open up a pull request.
- There is no ulong type in dart. C#'s longs are signed 64bit values. So are the int values in dart. Longs can be represented without any issues in dart using ints. Unfortunately, there is no unsigned 64-bit type in dart, so ulongs are represented by ints as well. All 64 bits are transmitted unchanged, but **ulong values above 9223372036854775807 appear as negative ints in dart** (use `BigInt.from(value).toUnsigned(64)` if you need their unsigned value).
- Sockets are bound asynchronously in dart, so `Server.start` returns a `Future` which completes once the server is running (just like `Client.connect`).

## Compatible libraries in other languages

- C#: [Riptide](https://github.com/RiptideNetworking/Riptide)
- Python: [Pytide](https://github.com/ebosseck/PytideNetworking/tree/main)

## Getting started

The API is mostly identical to [Riptide](https://github.com/RiptideNetworking/Riptide).

## Usage

### Enable Logging

```dart
RiptideLogger.initialize(print, true);
```

Exceptions thrown by your event subscribers are caught and logged as errors. To pass them to a dedicated method (e.g. to show their stack traces), use:

```dart
RiptideLogger.initializeExtended(print, print, print, print, true,
    exceptionMethod: (exception, stackTrace) => print('$exception\n$stackTrace'));
```

### Create a new Server

```dart
Server server = Server();
await server.start(PORT, 10);

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
await client.connect(InternetAddress("127.0.0.1"), PORT);

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

### Events

```dart
// Invoked when the client is connected to the server
client.connected.subscribe((args) => print("Connected!"));
client.disconnected.subscribe((args) => print("Disconnected: ${args!.reason}"));

// Invoked when *other* clients connect to or disconnect from the server
client.clientConnected.subscribe((args) => print("Client ${args!.id} connected"));
client.clientDisconnected.subscribe((args) => print("Client ${args!.id} disconnected"));

server.clientConnected.subscribe((args) => print("Client ${args!.client.id} connected"));
server.clientDisconnected.subscribe((args) => print("Client ${args!.client.id} disconnected"));
```

### Send Messages

```dart
Message message = Message.createFromInt(MessageSendMode.reliable, MESSAGE_ID);
message.addString("Hello World !");

client.send(message); // or server.sendToAll(message), server.send(message, clientID), ...
```

Messages are returned to a pool once they're sent. If you want to send the same message multiple times, pass `false` for `shouldRelease` and release it manually afterwards:

```dart
server.send(message, firstClientID, false);
server.send(message, secondClientID, false);
message.release();
```

## Multi threaded Server/ Client

It is recommended to run the whole server/ client code execution in a separate isolate to increase performance.
This library provides a lightweight implementation of such an isolate.

Simply swap from

```dart
Server server = Server();
await server.start(PORT, 10);

Timer.periodic(const Duration(milliseconds: 20), (timer) {
    server.update();
});
```

to

```dart
MultiThreadedServer mtServer = MultiThreadedServer();
await mtServer.start(PORT, 10, loggingEnabled: true);
```

or

```dart
Client client = Client();
await client.connect(InternetAddress("127.0.0.1"), PORT);

Timer.periodic(const Duration(milliseconds: 20), (timer) {
    client.update();
});
```

to

```dart
MultiThreadedClient mtClient = MultiThreadedClient();
await mtClient.connect(InternetAddress("127.0.0.1"), PORT, loggingEnabled: true);
```

---

If you want to use a different transport with the multi-threaded variants, pass it as an argument in the constructor call.

e.g.

```dart
MultiThreadedClient mtClient = MultiThreadedClient(transportType: MultiThreadedTransportType.tcp);
await mtClient.connect(InternetAddress("127.0.0.1"), PORT, loggingEnabled: true);
```

The update interval, heartbeat interval and timeout time can be passed to `start`/`connect` as well, and servers accept a `relayFilter`.

### Messages and events

Messages are sent and handled like with a regular server/ client. Received messages and events are passed on to the isolate which created the server/ client, so you can safely use them in your UI code:

```dart
mtServer.registerMessageHandler(MESSAGE_ID, (int fromClientID, Message message) {
    // do something
});
mtClient.registerMessageHandler(MESSAGE_ID, (Message message) {
    // do something
});

mtServer.clientConnected.subscribe((args) => print("Client ${args!.id} connected from ${args.endPoint}"));
mtServer.clientDisconnected.subscribe((args) => print("Client ${args!.clientID} disconnected: ${args.disconnectReason}"));
mtClient.connected.subscribe((args) => print("Connected as client ${mtClient.id}!"));
mtClient.disconnected.subscribe((args) => print("Disconnected: ${args!.reason}"));

mtServer.sendToAllExcept(message, clientID);
mtServer.disconnectClient(clientID, Message.create().addString("Bye!"));
```

Notify messages are passed on as well, via `notifyReceived`, `notifyDelivered` and `notifyLost`. The client's `state`, `id`, `rtt` and `smoothRtt` are kept up to date.

### Accepting connections

To decide which clients may connect, set `handleConnection` before starting the server and accept or reject each attempt:

```dart
mtServer.handleConnection = (int attemptId, String endPoint, Message connectMessage) {
    if (connectMessage.getString() == PASSWORD) {
        mtServer.accept(attemptId);
    } else {
        mtServer.reject(attemptId, message: Message.create().addString("Wrong password!"));
    }
};
await mtServer.start(PORT, 10);

await mtClient.connect(InternetAddress("127.0.0.1"), PORT, message: Message.create().addString(PASSWORD));
```

### Lifecycle

- `start` completes once the server is running, and throws if it couldn't be started (e.g. because the port is in use).
- `connect` returns whether a connection attempt will be made. The client's isolate stops by itself once the client disconnects or fails to connect, and connecting again starts a new one.
- `stop`/`disconnect` complete once the isolate has exited.
- Sending while the server/ client's isolate isn't running throws a `StateError`.

## Additional Note

If you are using Android: Make sure to enable the internet permission in the AndroidManifest.xml.

Under _android/app/src/main/AndroidManifest.xml_ add

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    ...
    <uses-permission android:name="android.permission.INTERNET"/>
    ...
```

And if you are using an Android emulator with localhost, note that instead of localhost, you should use the ip 10.0.2.2.

## Low-Level Transports supported by this library

- [UDP Transport](https://github.com/JayKay135/Riptide-Dart-Port/tree/master/lib/src/transports/udp) (built-in)
- [TCP Transport](https://github.com/JayKay135/Riptide-Dart-Port/tree/master/lib/src/transports/tcp) (built-in)

## Contributions

Contributions are welcome, especially if you know about low-level udp/ tcp sockets and isolates.

## License

Distributed under the MIT license. See LICENSE.md for more information. Copyright © 2024 [VISUS](https://www.visus.uni-stuttgart.de/en/), [University of Stuttgart](https://www.uni-stuttgart.de/)

This project is supported by [VISUS](https://www.visus.uni-stuttgart.de/en/), [University of Stuttgart](https://www.uni-stuttgart.de/)
