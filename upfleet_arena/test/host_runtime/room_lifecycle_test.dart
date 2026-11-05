import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/lan_networking/domain/lan_discovery.dart';
import 'package:upfleet_arena/features/lan_networking/services/frame_codec.dart';
import 'package:upfleet_arena/features/lan_networking/services/tcp_host_service.dart';
import 'package:upfleet_arena/host_runtime/host_room_service.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';
import 'package:upfleet_arena/shared/protocol/protocol_constants.dart';
import 'package:upfleet_arena/shared/protocol/protocol_message.dart';

/// An advertiser that records what it was asked to publish, so the tests can
/// prove that no secret ends up in the discovery metadata.
class RecordingAdvertiser implements LanAdvertiserService {
  String? label;
  int? port;
  Map<String, String> attributes = <String, String>{};
  bool stopped = false;

  @override
  Stream<String> get diagnostics => const Stream<String>.empty();

  @override
  Future<void> start({
    required String label,
    required int port,
    Map<String, String> attributes = const <String, String>{},
  }) async {
    this.label = label;
    this.port = port;
    this.attributes = attributes;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// A minimal TCP client used to drive the Host in the tests.
class TestClient {
  TestClient._(this.socket);

  final Socket socket;
  final FrameDecoder _decoder = FrameDecoder();
  final List<ProtocolMessage> _received = <ProtocolMessage>[];
  final List<Completer<ProtocolMessage>> _waiters =
      <Completer<ProtocolMessage>>[];

  static Future<TestClient> connect(int port) async {
    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
    );
    final TestClient client = TestClient._(socket);
    socket.listen(client._onData);
    return client;
  }

  void _onData(List<int> data) {
    for (final Map<String, dynamic> json in _decoder.addChunk(data)) {
      final ProtocolMessage message = ProtocolMessage.fromJson(json);
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(message);
      } else {
        _received.add(message);
      }
    }
  }

  void send(ProtocolMessage message) {
    socket.add(FrameCodec.encode(message.toJson()));
  }

  /// Waits for the next message, optionally of a given type.
  Future<ProtocolMessage> next({
    Duration timeout = const Duration(seconds: 3),
    String? ofType,
  }) async {
    for (int i = 0; i < _received.length; i++) {
      final ProtocolMessage message = _received[i];
      if (ofType == null || message.messageType == ofType) {
        _received.removeAt(i);
        return message;
      }
    }

    final Completer<ProtocolMessage> completer = Completer<ProtocolMessage>();
    _waiters.add(completer);
    final ProtocolMessage message = await completer.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'No message received${ofType == null ? '' : ' of type $ofType'}.',
      ),
    );
    if (ofType != null && message.messageType != ofType) {
      throw StateError('Expected $ofType but got ${message.messageType}.');
    }
    return message;
  }

  Future<void> close() => socket.close();
}

void main() {
  group('room lifecycle', () {
    late RoomCoordinator coordinator;
    late HostRoomService hostService;
    late RecordingAdvertiser advertiser;
    late int port;
    late String inviteCode;

    Future<void> startHost({RoomConfig? config}) async {
      coordinator = RoomCoordinator();
      advertiser = RecordingAdvertiser();
      hostService = HostRoomService(
        hostService: TcpHostService(),
        coordinator: coordinator,
        advertiser: advertiser,
      );
      port = await hostService.start(
        label: 'Host room',
        address: InternetAddress.loopbackIPv4,
      );
      coordinator.createRoom(
        hostDisplayName: 'Host',
        avatarId: '🦈',
        deviceId: 'host-device',
        config: config ?? RoomConfig.defaults,
        tcpPort: port,
      );
      inviteCode = coordinator.inviteCode!;
    }

    Future<TestClient> joinAs(
      String name, {
      String? code,
      String deviceId = 'device',
      int protocolVersion = AppProtocol.version,
    }) async {
      final TestClient client = await TestClient.connect(port);
      client.send(
        ProtocolMessage(
          protocolVersion: protocolVersion,
          messageType: ClientMessageType.join,
          requestId: 'req-$name',
          payload: <String, dynamic>{
            'code': code ?? inviteCode,
            'displayName': name,
            'avatarId': '🐙',
            'deviceId': deviceId,
          },
        ),
      );
      return client;
    }

    setUp(startHost);
    tearDown(() async {
      await hostService.stop();
      await coordinator.dispose();
    });

    test('the host is seated as the first member', () {
      final HostRoomState? state = coordinator.state;
      expect(state, isNotNull);
      expect(state!.players.length, 1);
      expect(state.hostPlayerId, state.players.keys.first);
      expect(state.players[state.hostPlayerId]!.isHost, isTrue);
    });

    test('the invitation code has six unambiguous characters', () {
      expect(inviteCode, hasLength(6));
      expect(
        inviteCode,
        matches(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$')),
      );
    });

    test('a valid join is accepted and returns a filtered snapshot', () async {
      final TestClient client = await joinAs('Alice');

      final ProtocolMessage joined = await client.next(
        ofType: HostEventType.joined,
      );
      final String playerId = joined.payload['playerId'] as String;
      expect(playerId, isNotEmpty);
      expect(joined.payload['roomId'], coordinator.state!.roomId);
      expect(joined.payload['resumeToken'], isNotEmpty);

      final Map<String, dynamic> raw =
          joined.payload['snapshot'] as Map<String, dynamic>;
      final RoomSnapshot snapshot = RoomSnapshot.fromJson(raw);
      expect(snapshot.players, hasLength(2));
      expect(snapshot.viewerPlayerId, playerId);
      expect(snapshot.viewerIsHost, isFalse);
      expect(snapshot.config.maxPlayers, RoomConfig.defaults.maxPlayers);

      // The Host badge is authoritative and comes from the Host.
      final PlayerSummary host = snapshot.players.firstWhere(
        (PlayerSummary player) => player.isHost,
      );
      expect(host.displayName, 'Host');

      await client.close();
    });

    test('the joiner never receives another player private data', () async {
      final TestClient client = await joinAs('Alice');
      final ProtocolMessage joined = await client.next(
        ofType: HostEventType.joined,
      );
      final RoomSnapshot snapshot = RoomSnapshot.fromJson(
        joined.payload['snapshot'] as Map<String, dynamic>,
      );

      // The lobby projection carries identity only — no fleet data exists
      // yet, and no resume token of another member is exposed.
      for (final PlayerSummary player in snapshot.players) {
        expect(player.toJson().keys, isNot(contains('resumeToken')));
      }
      await client.close();
    });

    test('an incorrect invitation code is rejected', () async {
      final TestClient client = await joinAs('Mallory', code: 'WRONG1');

      final ProtocolMessage error = await client.next(
        ofType: HostEventType.error,
      );
      expect(error.payload['code'], ProtocolErrorCode.roomCodeInvalid);
      expect(coordinator.state!.players, hasLength(1));

      await client.close();
    });

    test('an unsupported protocol version is rejected', () async {
      final TestClient client = await joinAs(
        'Alice',
        protocolVersion: AppProtocol.version + 7,
      );

      final ProtocolMessage error = await client.next(
        ofType: HostEventType.error,
      );
      expect(error.payload['code'], ProtocolErrorCode.unsupportedProtocolVersion);
      expect(coordinator.state!.players, hasLength(1));

      await client.close();
    });

    test('a reserved display name is rejected', () async {
      final TestClient client = await joinAs('Host');

      final ProtocolMessage error = await client.next(
        ofType: HostEventType.error,
      );
      expect(error.payload['code'], ProtocolErrorCode.invalidDisplayName);

      await client.close();
    });

    test('the room rejects more players than its capacity', () async {
      await startHost(config: RoomConfig.defaults.copyWith(maxPlayers: 2));

      final TestClient first = await joinAs('Alice', deviceId: 'phone-1');
      await first.next(ofType: HostEventType.joined);

      final TestClient second = await joinAs('Bob', deviceId: 'phone-2');
      final ProtocolMessage error = await second.next(
        ofType: HostEventType.error,
      );
      expect(error.payload['code'], ProtocolErrorCode.roomFull);

      await first.close();
      await second.close();
    });

    test('the same device cannot join twice at the same time', () async {
      final TestClient first = await joinAs('Alice', deviceId: 'phone-1');
      await first.next(ofType: HostEventType.joined);

      final TestClient second = await joinAs('Alice', deviceId: 'phone-1');
      final ProtocolMessage error = await second.next(
        ofType: HostEventType.error,
      );
      expect(error.payload['code'], ProtocolErrorCode.deviceAlreadyConnected);

      await first.close();
      await second.close();
    });

    test('the host can remove a player and the player is notified', () async {
      final TestClient client = await joinAs('Alice');
      final ProtocolMessage joined = await client.next(
        ofType: HostEventType.joined,
      );
      final String playerId = joined.payload['playerId'] as String;

      await coordinator.hostKick(playerId);

      final ProtocolMessage closed = await client.next(
        ofType: HostEventType.closed,
      );
      expect(closed.payload['reason'], 'kicked');

      expect(
        coordinator.state!.players[playerId]!.status,
        PlayerConnectionStatus.kicked,
      );

      await client.close();
    });

    test('a client cannot send a host-only command', () async {
      final TestClient client = await joinAs('Alice');
      await client.next(ofType: HostEventType.joined);

      client.send(
        ProtocolMessage(
          messageType: ClientMessageType.close,
          payload: <String, dynamic>{},
        ),
      );

      final ProtocolMessage error = await client.next(
        ofType: HostEventType.error,
      );
      expect(error.payload['code'], ProtocolErrorCode.hostOnlyAction);
      expect(coordinator.state!.status, RoomStatus.lobby);

      await client.close();
    });

    test('a client cannot change the room configuration', () async {
      final TestClient client = await joinAs('Alice');
      await client.next(ofType: HostEventType.joined);

      client.send(
        ProtocolMessage(
          messageType: ClientMessageType.configUpdate,
          payload: <String, dynamic>{
            'config': RoomConfig.defaults.copyWith(maxPlayers: 2).toJson(),
          },
        ),
      );

      final ProtocolMessage error = await client.next(
        ofType: HostEventType.error,
      );
      expect(error.payload['code'], ProtocolErrorCode.hostOnlyAction);
      expect(coordinator.state!.config.maxPlayers, 6);

      await client.close();
    });

    test('an invalid configuration is rejected by the host', () async {
      final List<String> problems = await coordinator.hostUpdateConfig(
        RoomConfig(
          rows: 4,
          columns: 4,
          maxPlayers: 40,
          placementDurationSeconds: 5,
          turnDurationSeconds: 999,
        ),
      );

      expect(problems, isNotEmpty);
      // The rejected values never reach the room.
      expect(coordinator.state!.config.rows, 10);
      expect(coordinator.state!.config.maxPlayers, 6);
    });

    test('a valid configuration from the host reaches every client', () async {
      final TestClient client = await joinAs('Alice');
      await client.next(ofType: HostEventType.joined);

      final List<String> problems = await coordinator.hostUpdateConfig(
        RoomConfig.defaults.copyWith(maxPlayers: 4),
      );

      expect(problems, isEmpty);
      expect(coordinator.state!.config.maxPlayers, 4);

      final ProtocolMessage updated = await client.next(
        ofType: HostEventType.configUpdated,
      );
      final RoomSnapshot snapshot = RoomSnapshot.fromJson(
        updated.payload['snapshot'] as Map<String, dynamic>,
      );
      expect(snapshot.config.maxPlayers, 4);

      await client.close();
    });

    test('closing the room disconnects every client', () async {
      final TestClient client = await joinAs('Alice');
      await client.next(ofType: HostEventType.joined);

      await coordinator.closeRoom(
        reason: 'host_closed',
        message: 'The host closed the room.',
      );

      final ProtocolMessage closed = await client.next(
        ofType: HostEventType.closed,
      );
      expect(closed.payload['reason'], 'host_closed');
      expect(coordinator.state!.status, RoomStatus.closed);
      expect(advertiser.stopped, isTrue);

      await client.close();
    });

    test('the invitation code never appears in the discovery metadata', () {
      expect(advertiser.label, 'Host room');
      expect(advertiser.port, port);
      expect(advertiser.attributes.containsKey('code'), isFalse);
      for (final String value in advertiser.attributes.values) {
        expect(value.contains(inviteCode), isFalse);
      }
      expect(advertiser.label!.contains(inviteCode), isFalse);
    });

    test('the state version increases exactly once per accepted change', () async {
      final int before = coordinator.state!.stateVersion;
      final TestClient client = await joinAs('Alice');
      await client.next(ofType: HostEventType.joined);

      expect(coordinator.state!.stateVersion, before + 1);

      await client.close();
    });
  });
}
