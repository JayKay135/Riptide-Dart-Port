import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:riptide/riptide.dart';
import 'package:test/test.dart';

/// Waits until [condition] is true, or fails the test after [timeout].
Future<void> waitFor(bool Function() condition, String reason, {Duration timeout = const Duration(seconds: 10)}) async {
  Stopwatch stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out waiting for $reason');
    }

    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  // Stay below the ephemeral port range (49152 and up on Windows), whose ports may be in use by other sockets
  int nextPort = 30000 + (pid % 150) * 100;

  for (MultiThreadedTransportType type in MultiThreadedTransportType.values) {
    group('${type.name}:', () {
      late int port;
      late MultiThreadedServer server;
      List<MultiThreadedClient> clients = [];

      MultiThreadedClient createClient() {
        MultiThreadedClient client = MultiThreadedClient(transportType: type);
        clients.add(client);
        return client;
      }

      Future<void> startServer() async {
        while (true) {
          port = nextPort++;
          try {
            await server.start(port, 10, heartbeatInterval: 100);
            return;
          } on RemoteError {
            // The port is in use, try the next one
          }
        }
      }

      Future<void> connect(MultiThreadedClient client, {Message? message}) async {
        expect(
            await client.connect(InternetAddress.loopbackIPv4, port, message: message, heartbeatInterval: 100), isTrue);
        await waitFor(() => client.isConnected, 'the client to connect');
      }

      setUp(() => server = MultiThreadedServer(transportType: type));

      tearDown(() async {
        for (MultiThreadedClient client in clients) {
          await client.disconnect();
        }
        clients.clear();
        await server.stop();
      });

      test('connects, exchanges messages and disconnects', () async {
        List<MultiThreadedServerConnectedEventArgs> connected = [];
        List<MultiThreadedServerDisconnectedEventArgs> disconnected = [];
        List<String> serverReceived = [];
        List<String> clientReceived = [];
        List<int> serverEvents = [];
        List<int> clientEvents = [];
        server.clientConnected.subscribe((args) => connected.add(args!));
        server.clientDisconnected.subscribe((args) => disconnected.add(args!));
        server.messageReceived.subscribe((args) => serverEvents.add(args!.messageID));
        server.registerMessageHandler(1, (int fromClientID, Message message) {
          serverReceived.add('$fromClientID ${message.getString()} ${message.getInt()}');
        });

        await startServer();
        expect(server.isRunning, isTrue);
        expect(server.port, equals(port));

        MultiThreadedClient client = createClient();
        int connectedEvents = 0;
        client.connected.subscribe((_) => connectedEvents++);
        client.messageReceived.subscribe((args) => clientEvents.add(args!.messageID));
        client.registerMessageHandler(2, (Message message) => clientReceived.add(message.getString()));
        await connect(client);

        expect(connectedEvents, equals(1));
        expect(client.id, isNotNull);
        await waitFor(() => server.clientCount == 1, 'the server to register the client');
        expect(server.clientIds, equals([client.id]));
        expect(connected.single.id, equals(client.id));
        expect(connected.single.endPoint, startsWith('127.0.0.1:'));

        client.send(Message.createFromInt(MessageSendMode.reliable, 1).addString('hello server').addInt(-5));
        server.send(Message.createFromInt(MessageSendMode.reliable, 2).addString('hello client'), client.id!);
        server.sendToAll(Message.createFromInt(MessageSendMode.unreliable, 2).addString('hello everyone'));
        await waitFor(() => serverReceived.length == 1 && clientReceived.length == 2, 'the messages to arrive');
        expect(serverReceived, equals(['${client.id} hello server -5']));
        expect(clientReceived, unorderedEquals(['hello client', 'hello everyone']));
        expect(serverEvents, equals([1]));
        expect(clientEvents, equals([2, 2]));

        await waitFor(() => client.rtt > 0 && client.smoothRtt > 0, 'the RTT to be measured');

        await client.disconnect();
        expect(client.isNotConnected, isTrue);
        await waitFor(() => disconnected.isNotEmpty, 'the server to notice the disconnect');
        expect(disconnected.single.clientID, equals(connected.single.id));
        expect(disconnected.single.disconnectReason, equals(DisconnectReason.disconnected));
        expect(server.clientCount, equals(0));
      });

      test('passes notify messages on in both directions', () async {
        List<String> serverReceived = [];
        List<String> clientReceived = [];
        List<int> clientDelivered = [];
        List<int> serverDelivered = [];
        server.notifyReceived.subscribe((args) {
          serverReceived.add('${args!.fromClientID} ${args.message.getString()}');
          // Notify messages are only known to be delivered once the other end sends notify messages back
          server.send(Message.createWithSendMode(MessageSendMode.notify).addString('echo'), args.fromClientID);
        });
        server.notifyDelivered.subscribe((args) => serverDelivered.add(args!.sequenceID));
        await startServer();

        MultiThreadedClient client = createClient();
        client.notifyReceived.subscribe((message) {
          clientReceived.add(message!.getString());
          // Send the next notify message once the previous one was echoed, so every echo gets acknowledged
          if (clientReceived.length <= 5) {
            client
                .send(Message.createWithSendMode(MessageSendMode.notify).addString('notify ${clientReceived.length}'));
          }
        });
        client.notifyDelivered.subscribe((sequenceId) => clientDelivered.add(sequenceId!));
        await connect(client);
        // Like with Server, notify messages are only passed on once the server considers the client to be connected
        await waitFor(() => server.clientCount == 1, 'the server to register the client');

        client.send(Message.createWithSendMode(MessageSendMode.notify).addString('notify 0'));
        await waitFor(() => serverReceived.length >= 6 && clientReceived.length >= 5, 'the notify messages to arrive');
        expect(serverReceived.take(6), equals(List.generate(6, (i) => '${client.id} notify $i')));
        expect(clientReceived, everyElement(equals('echo')));
        await waitFor(() => clientDelivered.length >= 5 && serverDelivered.length >= 5, 'the deliveries to be known');
        expect(clientDelivered.take(5), equals([1, 2, 3, 4, 5]));
        expect(serverDelivered.take(5), equals([1, 2, 3, 4, 5]));
      });

      test('lets connection attempts be accepted and rejected', () async {
        List<String> attempts = [];
        server.handleConnection = (int attemptId, String endPoint, Message connectMessage) {
          String token = connectMessage.getString();
          attempts.add(token);
          if (token == 'let me in') {
            server.accept(attemptId);
          } else {
            server.reject(attemptId, message: Message.create().addString('go away'));
          }
        };
        await startServer();

        MultiThreadedClient client = createClient();
        ConnectionFailedEventArgs? failed;
        client.connectionFailed.subscribe((args) => failed = args);
        expect(await client.connect(InternetAddress.loopbackIPv4, port, message: Message.create().addString('wrong')),
            isTrue);
        await waitFor(() => failed != null, 'the connection attempt to be rejected');
        expect(failed!.reason, equals(RejectReason.custom));
        expect(failed!.message!.getString(), equals('go away'));
        expect(client.isNotConnected, isTrue);

        await connect(client, message: Message.create().addString('let me in'));
        expect(attempts, equals(['wrong', 'let me in']));
        await waitFor(() => server.clientCount == 1, 'the server to register the client');
      });

      test('sends to all but one client, relays messages and kicks clients', () async {
        MessageRelayFilter relayFilter = MessageRelayFilter.fromSize(10, [3]);
        int serverHandled = 0;
        server.registerMessageHandler(3, (int fromClientID, Message message) => serverHandled++);
        await server.stop();
        port = nextPort++;
        await server.start(port, 10, heartbeatInterval: 100, relayFilter: relayFilter);

        MultiThreadedClient first = createClient();
        MultiThreadedClient second = createClient();
        List<String> firstReceived = [];
        List<String> secondReceived = [];
        List<int> otherClientsConnected = [];
        first.clientConnected.subscribe((args) => otherClientsConnected.add(args!.id));
        for (var (MultiThreadedClient client, List<String> received) in [
          (first, firstReceived),
          (second, secondReceived)
        ]) {
          client.registerMessageHandler(2, (Message message) => received.add(message.getString()));
          client.registerMessageHandler(3, (Message message) => received.add('relayed ${message.getString()}'));
        }
        await connect(first);
        await connect(second);
        await waitFor(() => otherClientsConnected.isNotEmpty, 'the first client to learn about the second one');
        expect(otherClientsConnected, equals([second.id]));

        server.sendToAllExcept(Message.createFromInt(MessageSendMode.reliable, 2).addString('not for you'), first.id!);
        first.send(Message.createFromInt(MessageSendMode.reliable, 3).addString('from first'));
        await waitFor(() => secondReceived.length == 2, 'the second client to receive the messages');
        expect(secondReceived, unorderedEquals(['not for you', 'relayed from first']));
        expect(firstReceived, isEmpty);
        expect(serverHandled, equals(0));

        DisconnectedEventArgs? kicked;
        first.disconnected.subscribe((args) => kicked = args);
        server.disconnectClient(first.id!, Message.create().addString('bye'));
        await waitFor(() => kicked != null, 'the first client to be kicked');
        expect(kicked!.reason, equals(DisconnectReason.kicked));
        expect(kicked!.message!.getString(), equals('bye'));
        expect(first.isNotConnected, isTrue);
        expect(second.isConnected, isTrue);
      });

      test('can be stopped and restarted', () async {
        await startServer();
        MultiThreadedClient client = createClient();
        await connect(client);

        DisconnectedEventArgs? disconnected;
        client.disconnected.subscribe((args) => disconnected = args);
        await waitFor(() => server.clientCount == 1, 'the server to register the client');
        await server.stop();
        expect(server.isRunning, isFalse);
        expect(server.clientCount, equals(0));
        await waitFor(() => disconnected != null, 'the client to be disconnected');
        expect(disconnected!.reason, equals(DisconnectReason.serverStopped));

        await server.start(port, 10, heartbeatInterval: 100);
        await connect(client);
        await waitFor(() => server.clientCount == 1, 'the server to register the client again');
      });

      test('reports errors', () async {
        expect(() => server.send(Message.createFromInt(MessageSendMode.reliable, 1), 1), throwsStateError);
        expect(() => createClient().send(Message.createFromInt(MessageSendMode.reliable, 1)), throwsStateError);

        await startServer();
        MultiThreadedServer other = MultiThreadedServer(transportType: type);
        await expectLater(other.start(port, 10), throwsA(isA<RemoteError>()));
        expect(other.isRunning, isFalse);

        if (type == MultiThreadedTransportType.tcp) {
          MultiThreadedClient client = createClient();
          expect(await client.connect(InternetAddress.loopbackIPv4, nextPort++), isFalse);
          expect(client.isNotConnected, isTrue);
        }
      });
    });
  }
}
