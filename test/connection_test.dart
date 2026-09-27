import 'dart:async';
import 'dart:io';

import 'package:riptide/riptide.dart';
import 'package:test/test.dart';

/// The transports to run the tests with.
enum TransportType { udp, tcp }

/// Runs [peers]' update loops until [condition] is true, or fails the test after [timeout].
Future<void> updateUntil(List<Object> peers, bool Function() condition,
    {Duration timeout = const Duration(seconds: 5), String? reason, String Function()? details}) async {
  Stopwatch stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out waiting for ${reason ?? 'condition'}${details == null ? '' : ' (${details()})'}');
    }

    update(peers);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Runs [peers]' update loops for the given [duration].
Future<void> updateFor(List<Object> peers, Duration duration) async {
  Stopwatch stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {
    update(peers);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void update(List<Object> peers) {
  for (Object peer in peers) {
    if (peer is Server) {
      peer.update();
    } else if (peer is Client) {
      peer.update();
    }
  }
}

Server createServer(TransportType type) => Server(transport: type == TransportType.udp ? UdpServer() : TcpServer());

Client createClient(TransportType type) => Client(transport: type == TransportType.udp ? UdpClient() : TcpClient());

void main() {
  if (Platform.environment['RIPTIDE_TEST_LOGS'] != null) {
    RiptideLogger.initialize(print, true, timestampFormat: 'HH:mm:ss.SSS');
  }

  // Stay below the ephemeral port range (49152 and up on Windows), whose ports may be in use by other sockets
  int nextPort = 20000 + (pid % 150) * 100;

  for (TransportType type in TransportType.values) {
    group('${type.name}:', () {
      late int port;
      late Server server;
      late Client client;

      setUp(() async {
        server = createServer(type);
        while (true) {
          port = nextPort++;
          try {
            await server.start(port, 10);
            break;
          } on SocketException {
            // The port is in use, try the next one
          }
        }

        client = createClient(type);
      });

      tearDown(() {
        client.disconnect();
        server.stop();
      });

      Future<void> connect(Client client) async {
        expect(await client.connect(InternetAddress.loopbackIPv4, port), isTrue);
        await updateUntil([server, client], () => client.isConnected, reason: 'the client to connect');
      }

      test('client connects and disconnects', () async {
        int serverConnected = 0;
        int clientConnected = 0;
        int serverDisconnected = 0;
        server.clientConnected.subscribe((args) => serverConnected++);
        server.clientDisconnected.subscribe((args) => serverDisconnected++);
        client.connected.subscribe((args) => clientConnected++);

        await connect(client);
        await updateUntil([server, client], () => serverConnected == 1, reason: 'the server to register the client');
        expect(clientConnected, equals(1));
        expect(server.clientCount, equals(1));
        expect(client.id, equals(1));

        client.disconnect();
        await updateUntil([server, client], () => serverDisconnected == 1,
            reason: 'the server to notice the disconnect');
        expect(server.clientCount, equals(0));
      });

      test('messages are exchanged in both directions', () async {
        List<String> serverReceived = [];
        List<String> clientReceived = [];
        server.registerMessageHandler(1, (int fromClientId, Message message) {
          serverReceived.add('${message.getString()} ${message.getInt()} ${message.getDouble()}');
        });
        client.registerMessageHandler(2, (Message message) {
          clientReceived.add('${message.getString()} ${message.getBool()} ${message.getLong()}');
        });

        await connect(client);

        for (MessageSendMode sendMode in [MessageSendMode.reliable, MessageSendMode.unreliable]) {
          client.send(
              Message.createFromInt(sendMode, 1).addString('${sendMode.name} to server').addInt(-42).addDouble(1.5));
          server.sendToAll(
              Message.createFromInt(sendMode, 2).addString('${sendMode.name} to client').addBool(true).addLong(-7));
        }

        await updateUntil([server, client], () => serverReceived.length == 2 && clientReceived.length == 2,
            reason: 'the messages to arrive',
            details: () => 'server received $serverReceived, client received $clientReceived');
        expect(serverReceived, unorderedEquals(['reliable to server -42 1.5', 'unreliable to server -42 1.5']));
        expect(clientReceived, unorderedEquals(['reliable to client true -7', 'unreliable to client true -7']));
      });

      test('notify messages are exchanged and acknowledged', () async {
        await connect(client);
        await updateUntil([server, client], () => server.clientCount == 1, reason: 'the server to register the client');
        Connection serverSide = server.clients.first;

        List<String> serverReceived = [];
        List<String> clientReceived = [];
        List<int> delivered = [];
        serverSide.notifyReceived.subscribe((message) => serverReceived.add(message!.getString()));
        client.connection!.notifyReceived.subscribe((message) => clientReceived.add(message!.getString()));
        client.connection!.notifyDelivered.subscribe((sequenceId) => delivered.add(sequenceId!));

        for (int i = 0; i < 5; i++) {
          client.send(Message.createWithSendMode(MessageSendMode.notify).addString('to server $i'));
          server.send(Message.createWithSendMode(MessageSendMode.notify).addString('to client $i'), client.id);
          await updateFor([server, client], const Duration(milliseconds: 20));
        }

        await updateUntil([server, client], () => serverReceived.length == 5 && clientReceived.length == 5,
            reason: 'the notify messages to arrive');
        expect(serverReceived, equals(List.generate(5, (i) => 'to server $i')));
        expect(clientReceived, equals(List.generate(5, (i) => 'to client $i')));
        // Deliveries are only known once the other end sends a notify message back
        expect(delivered, isNotEmpty);
        expect(delivered, orderedEquals(List.generate(delivered.length, (i) => i + 1)));
      });

      test('reliable messages are delivered once and in the right amount', () async {
        int received = 0;
        List<int> deliveredIds = [];
        server.registerMessageHandler(1, (int fromClientId, Message message) => received++);

        await connect(client);
        client.connection!.reliableDelivered.subscribe((sequenceId) => deliveredIds.add(sequenceId!));

        for (int i = 0; i < 200; i++) {
          client.send(Message.createFromInt(MessageSendMode.reliable, 1).addInt(i));
        }

        await updateUntil([server, client], () => received == 200 && deliveredIds.length >= 200,
            reason: 'all reliable messages to be delivered',
            details: () => 'received $received, delivered ${deliveredIds.length}, '
                'pending ${client.connection!.pendingMessages.length}');
        await updateFor([server, client], const Duration(milliseconds: 300));
        expect(received, equals(200));
      });

      test('bursts of reliable messages sent in between updates are delivered', () async {
        int serverReceived = 0;
        int clientReceived = 0;
        server.registerMessageHandler(1, (int fromClientId, Message message) {
          serverReceived++;
          server.send(Message.createFromInt(MessageSendMode.reliable, 2).addInt(message.getInt()), fromClientId);
        });
        client.registerMessageHandler(2, (Message message) => clientReceived++);
        DisconnectedEventArgs? disconnected;
        client.disconnected.subscribe((args) => disconnected = args);

        await connect(client);
        // Let the RTT be measured, as resends are timed based on it
        await updateFor([server, client], const Duration(milliseconds: 1200));

        // NOTE: Dart's UDP sockets send and receive far fewer datagrams per second than C#'s (especially on Windows, and
        // even more so with both peers in the same isolate), which limits the size of bursts UDP can handle at once
        int count = type == TransportType.udp ? 300 : 5000;
        for (int i = 0; i < count; i++) {
          client.send(Message.createFromInt(MessageSendMode.reliable, 1).addInt(i));
        }

        await updateUntil([server, client], () => clientReceived == count || disconnected != null,
            reason: 'the burst to be echoed',
            details: () => 'server received $serverReceived, client received $clientReceived');
        expect(disconnected?.reason, isNull);
        expect(serverReceived, equals(count));
      });

      test('connect data, reject data and kick data are passed on', () async {
        List<String> connectData = [];
        server.handleConnection = (Connection pendingConnection, Message connectMessage) {
          String token = connectMessage.getString();
          connectData.add(token);
          if (token == 'let me in') {
            server.accept(pendingConnection);
          } else {
            server.reject(pendingConnection, message: Message.create().addString('go away'));
          }
        };

        ConnectionFailedEventArgs? failed;
        client.connectionFailed.subscribe((args) => failed = args);
        expect(
            await client.connect(InternetAddress.loopbackIPv4, port,
                message: Message.create().addString('wrong token')),
            isTrue);
        await updateUntil([server, client], () => failed != null, reason: 'the connection attempt to be rejected');
        expect(failed!.reason, equals(RejectReason.custom));
        expect(failed!.message!.getString(), equals('go away'));

        DisconnectedEventArgs? disconnected;
        client.disconnected.subscribe((args) => disconnected = args);
        expect(
            await client.connect(InternetAddress.loopbackIPv4, port, message: Message.create().addString('let me in')),
            isTrue);
        await updateUntil([server, client], () => server.clientCount == 1, reason: 'the client to be accepted');
        expect(connectData, equals(['wrong token', 'let me in']));

        server.disconnectClient(server.clients.first.id, Message.create().addString('bye'));
        await updateUntil([server, client], () => disconnected != null, reason: 'the client to be kicked');
        expect(disconnected!.reason, equals(DisconnectReason.kicked));
        expect(disconnected!.message!.getString(), equals('bye'));
      });

      test('abandoned connection attempts are cleaned up', () async {
        server.heartbeatInterval = 50;
        server.connectTimeoutTime = 300;
        int failed = 0;
        server.connectionFailed.subscribe((args) => failed++);
        server.handleConnection =
            (Connection pendingConnection, Message connectMessage) {}; // Neither accepts nor rejects

        expect(await client.connect(InternetAddress.loopbackIPv4, port), isTrue);
        await updateUntil([server, client], () => failed == 1, reason: 'the connection attempt to time out');

        // The same client can attempt to connect again, which requires the pending connection to be gone
        server.handleConnection = null;
        client.disconnect();
        await connect(client);
      });

      test('clients can reconnect and servers can restart', () async {
        int received = 0;
        server.registerMessageHandler(1, (int fromClientId, Message message) => received++);

        for (int round = 0; round < 3; round++) {
          await connect(client);
          client.send(Message.createFromInt(MessageSendMode.unreliable, 1));
          await updateUntil([server, client], () => received == round + 1, reason: 'the message of round $round');

          client.disconnect();
          await updateUntil([server, client], () => server.clientCount == 0, reason: 'the disconnect of round $round');

          server.stop();
          await server.start(port, 10);
        }

        await updateFor([server, client], const Duration(milliseconds: 100));
        expect(received, equals(3)); // Handlers must not have been subscribed multiple times
      });

      test('multiple clients on the same host', () async {
        Client otherClient = createClient(type);
        List<int> otherClientConnected = [];
        client.clientConnected.subscribe((args) => otherClientConnected.add(args!.id));
        Map<int, String> received = {};
        server.registerMessageHandler(
            1, (int fromClientId, Message message) => received[fromClientId] = message.getString());

        await connect(client);
        expect(await otherClient.connect(InternetAddress.loopbackIPv4, port), isTrue);
        await updateUntil([server, client, otherClient], () => otherClient.isConnected, reason: 'the second client');

        expect(client.id, isNot(equals(otherClient.id)));
        client.send(Message.createFromInt(MessageSendMode.reliable, 1).addString('first'));
        otherClient.send(Message.createFromInt(MessageSendMode.reliable, 1).addString('second'));
        await updateUntil([server, client, otherClient], () => received.length == 2 && otherClientConnected.isNotEmpty,
            reason: 'the messages of both clients');
        expect(received, equals({client.id: 'first', otherClient.id: 'second'}));
        expect(otherClientConnected, equals([otherClient.id]));

        otherClient.disconnect();
      });

      test('connections time out if the other end stops responding', () async {
        server.heartbeatInterval = 50;
        server.timeoutTime = 300;
        ServerDisconnectedEventArgs? disconnected;
        server.clientDisconnected.subscribe((args) => disconnected = args);

        await connect(client);
        await updateUntil([server], () => disconnected != null,
            reason: 'the server to time out the client', timeout: const Duration(seconds: 3));
        expect(disconnected!.reason, equals(DisconnectReason.timedOut));

        // The client never learns about it, so it times out as well
        client.heartbeatInterval = 50;
        client.timeoutTime = 300;
        DisconnectedEventArgs? clientDisconnected;
        client.disconnected.subscribe((args) => clientDisconnected = args);
        await updateUntil([client], () => clientDisconnected != null,
            reason: 'the client to time out', timeout: const Duration(seconds: 3));
        expect(clientDisconnected!.reason, equals(DisconnectReason.timedOut));
      });

      test('exceptions thrown by event subscribers do not break anything', () async {
        List<String> errors = [];
        RiptideLogger.initializeExtended(null, null, null, errors.add, false);
        addTearDown(() => RiptideLogger.initializeExtended(null, null, null, null, false));

        server.clientConnected.subscribe((args) => throw StateError('server subscriber'));
        client.connected.subscribe((args) => throw StateError('client subscriber'));
        server.handleConnection = (Connection pendingConnection, Message connectMessage) {
          server.accept(pendingConnection);
          throw StateError('connection handler');
        };
        int received = 0;
        server.messageReceived.subscribe((args) => throw StateError('message subscriber'));
        server.registerMessageHandler(1, (int fromClientId, Message message) => received++);

        await connect(client);
        await updateUntil([server, client], () => server.clientCount == 1 && server.clients.first.isConnected,
            reason: 'the server to register the client');
        client.send(Message.createFromInt(MessageSendMode.reliable, 1));
        await updateUntil([server, client], () => received == 1, reason: 'the message handler to be called');

        expect(errors.where((e) => e.contains('server subscriber')), hasLength(1));
        expect(errors.where((e) => e.contains('client subscriber')), hasLength(1));
        expect(errors.where((e) => e.contains('connection handler')), hasLength(1));
        expect(errors.where((e) => e.contains('message subscriber')), hasLength(1));
      });

      test('clients are notified when the server stops', () async {
        DisconnectedEventArgs? disconnected;
        client.disconnected.subscribe((args) => disconnected = args);

        await connect(client);
        await updateUntil([server, client], () => server.clientCount == 1, reason: 'the server to register the client');
        server.stop();
        await updateUntil([client], () => disconnected != null, reason: 'the client to be disconnected');
        expect(disconnected!.reason, equals(DisconnectReason.serverStopped));
      });

      if (type == TransportType.tcp) {
        test('connections sending invalid message sizes are closed', () async {
          Socket socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
          bool closed = false;
          socket.listen((_) {}, onDone: () => closed = true, onError: (Object _) => closed = true);
          socket.add([0xFF, 0xFF, 0xFF, 0x7F, 1, 2, 3]); // A size of int.MaxValue

          await updateUntil([server], () => closed, reason: 'the server to close the connection');
          socket.destroy();
        });
      }
    });
  }
}
