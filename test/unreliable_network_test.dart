import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:riptide/riptide.dart';
import 'package:riptide/src/transports/event_args.dart' as transport;
import 'package:riptide/src/transports/ipeer.dart';
import 'package:riptide/src/utils/event_handler.dart';
import 'package:test/test.dart';

/// An in-memory network which randomly drops, delays and reorders datagrams.
class UnreliableNetwork {
  final Random random;
  final double lossRate;
  final int maxDelay;
  final bool reorder;
  final Stopwatch _time = Stopwatch()..start();
  final List<(int deliverAt, void Function() deliver)> _inFlight = [];

  UnreliableNetwork(int seed, {required this.lossRate, required this.maxDelay, required this.reorder})
      : random = Random(seed);

  void send(Uint8List data, int amount, void Function(Uint8List data) deliver) {
    if (random.nextDouble() < lossRate) {
      return;
    }

    Uint8List copy = Uint8List.fromList(data.sublist(0, amount));
    int delay = reorder ? random.nextInt(maxDelay + 1) : maxDelay;
    _inFlight.add((_time.elapsedMilliseconds + delay, () => deliver(copy)));
  }

  /// Delivers all datagrams which are due (in random order if reordering is enabled).
  void deliverDue() {
    int now = _time.elapsedMilliseconds;
    List<(int, void Function())> due = _inFlight.where((d) => d.$1 <= now).toList();
    if (reorder) {
      due.shuffle(random);
    }

    _inFlight.removeWhere((d) => d.$1 <= now);
    for (var (_, deliver) in due) {
      deliver();
    }
  }
}

class TestConnection extends Connection {
  final UnreliableNetwork network;
  late void Function(Uint8List data) deliverToOtherEnd;
  late void Function(Uint8List data) onReceived;

  TestConnection(this.network);

  @override
  void send(Uint8List dataBuffer, int amount) => network.send(dataBuffer, amount, deliverToOtherEnd);
}

class TestServer implements IServer {
  final UnreliableNetwork network;

  TestServer(this.network);

  @override
  Event<transport.ConnectedEventArgs> connected = Event<transport.ConnectedEventArgs>();

  @override
  Event<transport.DataReceivedEventArgs> dataReceived = Event<transport.DataReceivedEventArgs>();

  @override
  Event<transport.DisconnectedEventArgs> disconnected = Event<transport.DisconnectedEventArgs>();

  @override
  late int port;

  @override
  Future<void> start(int port) async => this.port = port;

  /// Links the given client connection to the server, like the first connect message does in the UDP transport.
  void link(TestConnection clientConnection) {
    TestConnection? serverConnection;
    clientConnection.deliverToOtherEnd = (Uint8List data) {
      if ((data[0] & Message.headerBitmask) == MessageHeader.connect.index) {
        if (serverConnection != null) {
          return; // Like the built-in transports, only the first connect message is passed on
        }

        serverConnection = TestConnection(network);
        serverConnection!.deliverToOtherEnd = clientConnection.onReceived;
        connected.invoke(transport.ConnectedEventArgs(serverConnection!));
      }

      if (serverConnection != null && !serverConnection!.isNotConnected) {
        dataReceived.invoke(transport.DataReceivedEventArgs(data, data.length, serverConnection!));
      }
    };
  }

  @override
  void close(Connection connection) {}

  @override
  void shutdown() {}

  @override
  void poll() => network.deliverDue();
}

class TestClient implements IClient {
  final UnreliableNetwork network;
  final TestServer server;

  TestClient(this.network, this.server);

  @override
  // ignore: strict_raw_type
  Event connected = Event();

  @override
  // ignore: strict_raw_type
  Event connectionFailed = Event();

  @override
  Event<transport.DataReceivedEventArgs> dataReceived = Event<transport.DataReceivedEventArgs>();

  @override
  Event<transport.DisconnectedEventArgs> disconnected = Event<transport.DisconnectedEventArgs>();

  @override
  Future<(bool connected, Connection? connection, String error)> connect(InternetAddress hostAddress, int port) async {
    TestConnection connection = TestConnection(network);
    connection.onReceived = (Uint8List data) {
      if (!connection.isNotConnected) {
        dataReceived.invoke(transport.DataReceivedEventArgs(data, data.length, connection));
      }
    };
    server.link(connection);
    connected.invoke(null);
    return (true, connection, '');
  }

  @override
  void disconnect() {}

  @override
  void poll() => network.deliverDue();
}

void main() {
  // With this much loss and reordering (out of order notify messages are discarded), the connection quality checks
  // would rightfully disconnect, so they are only enabled with a more realistic network
  for (var (int seed, double lossRate, int maxDelay, bool reorder) in [
    (1, 0.2, 30, true),
    (2, 0.2, 30, true),
    (3, 0.2, 30, true),
    (4, 0.02, 2, false),
    (5, 0.02, 2, false),
  ]) {
    bool canQualityDisconnect = !reorder;
    String description = 'seed $seed, ${(lossRate * 100).round()}% loss, ${reorder ? 'reordering' : 'in order'}';
    test('reliable and notify messages over an unreliable network ($description)', () async {
      UnreliableNetwork network = UnreliableNetwork(seed, lossRate: lossRate, maxDelay: maxDelay, reorder: reorder);
      List<String> logs = [];
      RiptideLogger.initialize(logs.add, false);
      addTearDown(() => RiptideLogger.initializeExtended(null, null, null, null, false));
      TestServer serverTransport = TestServer(network);
      Server server = Server(transport: serverTransport);
      Client client = Client(transport: TestClient(network, serverTransport));
      server.heartbeatInterval = 100;
      client.heartbeatInterval = 100;

      List<int> received = [];
      server.registerMessageHandler(1, (int fromClientId, Message message) => received.add(message.getInt()));
      server.clientConnected.subscribe((args) {
        Connection connection = args!.client;
        connection.canQualityDisconnect = canQualityDisconnect;
        // Deliveries of notify messages are only known once the other end sends notify messages back
        connection.notifyReceived
            .subscribe((message) => connection.sendMessage(Message.createWithSendMode(MessageSendMode.notify)));
      });
      await server.start(1, 1);

      Future<void> updateUntil(bool Function() condition) async {
        Stopwatch stopwatch = Stopwatch()..start();
        while (!condition() && stopwatch.elapsed < const Duration(seconds: 60)) {
          server.update();
          client.update();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }

      await client.connect(InternetAddress.loopbackIPv4, 1, maxConnectionAttempts: 100);
      await updateUntil(() => client.isConnected && server.clientCount == 1 && server.clients.first.isConnected);
      expect(client.isConnected, isTrue);
      client.connection!.canQualityDisconnect = canQualityDisconnect;

      DisconnectedEventArgs? disconnected;
      client.disconnected.subscribe((args) => disconnected = args);
      int notifyDelivered = 0;
      int notifyLost = 0;
      client.connection!.notifyDelivered.subscribe((_) => notifyDelivered++);
      client.connection!.notifyLost.subscribe((_) => notifyLost++);

      const int count = 1000;
      for (int i = 0; i < count; i++) {
        client.send(Message.createFromInt(MessageSendMode.reliable, 1).addInt(i));
        client.send(Message.createWithSendMode(MessageSendMode.notify).addInt(i));
        if (i % 10 == 0) {
          server.update();
          client.update();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }

      await updateUntil(
          () => (received.length == count && client.connection!.pendingMessages.isEmpty) || disconnected != null);

      expect(disconnected?.reason, isNull, reason: logs.where((log) => log.contains('isconnect')).join(', '));
      expect(received.length, equals(count), reason: 'every reliable message is handled exactly once');
      expect(received.toSet().length, equals(count));
      expect(client.connection!.pendingMessages, isEmpty);
      expect(notifyDelivered + notifyLost, greaterThan(count * 0.8));
      if (lossRate > 0.1) {
        expect(notifyLost, greaterThan(0));
      }

      client.disconnect();
      server.stop();
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
