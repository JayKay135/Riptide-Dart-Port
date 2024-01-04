import 'dart:io';

import 'package:riptide/riptide.dart';

enum ClientToServerId { serverTest }

enum ServerToClientId { clientTest }

void createClient() {
  Client client = Client();
  client.connect(InternetAddress('127.0.0.1'), 7777);

  client.registerMessageHandler(ServerToClientId.clientTest.index,
      (Message message) {
    print(message);
  });

  client.clientConnected.subscribe((args) {
    // send a test message to the server on connection
    Message message = Message.createFromInt(
        MessageSendMode.reliable, ClientToServerId.serverTest.index);
    message.addString('Hello Server!');
    client.send(message);
  });
}

void createServer() {
  Server server = Server();
  server.start(7777, 10);

  server.registerMessageHandler(ClientToServerId.serverTest.index,
      (fromClientID, message) {
    print("received message from client $fromClientID");
  });

  server.clientConnected.subscribe((args) {
    // send a test message to each connecting client
    Message message = Message.createFromInt(
        MessageSendMode.reliable, ServerToClientId.clientTest.index);
    message.addString('Hello Client!');
    server.send(message, args!.client.id);
  });
}
