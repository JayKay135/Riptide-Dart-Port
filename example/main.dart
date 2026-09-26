import 'dart:async';
import 'dart:io';

import 'package:riptide/riptide.dart';

enum ClientToServerId { serverTest }

enum ServerToClientId { clientTest }

Future<Server> createServer() async {
  Server server = Server();
  await server.start(7777, 10);

  server.registerMessageHandler(ClientToServerId.serverTest.index, (fromClientID, message) {
    print("Server received '${message.getString()}' from client $fromClientID");
  });

  server.clientConnected.subscribe((args) {
    // send a test message to each connecting client
    Message message = Message.createFromInt(MessageSendMode.reliable, ServerToClientId.clientTest.index);
    message.addString('Hello Client!');
    server.send(message, args!.client.id);
  });

  return server;
}

Future<Client> createClient() async {
  Client client = Client();

  client.registerMessageHandler(ServerToClientId.clientTest.index, (Message message) {
    print("Client received '${message.getString()}'");
  });

  client.connected.subscribe((args) {
    // send a test message to the server once connected
    Message message = Message.createFromInt(MessageSendMode.reliable, ClientToServerId.serverTest.index);
    message.addString('Hello Server!');
    client.send(message);
  });

  await client.connect(InternetAddress.loopbackIPv4, 7777);
  return client;
}

Future<void> main() async {
  RiptideLogger.initialize(print, true);

  Server server = await createServer();
  Client client = await createClient();

  // Both the server and the client need to be updated regularly to send and handle messages
  Timer timer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
    server.update();
    client.update();
  });

  await Future<void>.delayed(const Duration(seconds: 2));

  timer.cancel();
  client.disconnect();
  server.stop();
}
