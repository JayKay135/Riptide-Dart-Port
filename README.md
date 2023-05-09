# Riptide dart port

Dart port of [Riptide](https://github.com/RiptideNetworking/Riptide), a light weight networking library from Tom Weiland.

This port provides functionality for establishing connections with clients and servers using the Riptide protocol. 

## Compatibility

This port was last tested for functionality with Riptide [Commit a292470](https://github.com/RiptideNetworking/Riptide/commit/a29247052505cdb2f5e0c8994cb4006d6da857d4), Feb 12 2023

It was tested for Android and Windows devices.

## Getting started

The API is mostly identical to [Riptide](https://github.com/RiptideNetworking/Riptide).

### Installation
In you projects pubspec.yaml under dependencies add:
```yaml
riptide:
    git:
      url: https://github.com/JayKay135/Riptide-Dart-Port.git
      ref: master
```


## Usage

### Enable Logging
```dart
RiptideLogger.initialize2(print, print, print, print, true);
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
It is recommended to run the whole server/ client code execution in a seperate isolate to increase performance.
A lightweight implementation of such an isolate is provided by this library.

Simple swap from
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
mtServer.start(PORT, 10);
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
mtClient.connect(InternetAddress("127.0.0.1"), PORT);
```

## Low-Level Transports supported by this library

* UDP (built-in)

## Contributions

Contributions are very welcome. 
Especially if you know about low-level udp/ tcp sockets and isolates.

## License

Distributed under the MIT license. See LICENSE.md for more information. Copyright © 2023 [VISUS](https://www.visus.uni-stuttgart.de/en/), [University of Stuttgart](https://www.uni-stuttgart.de/)

This project is supported by [VISUS](https://www.visus.uni-stuttgart.de/en/), University of Stuttgart


