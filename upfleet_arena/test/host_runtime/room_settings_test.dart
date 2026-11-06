import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/host_runtime/client_connection_registry.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';
import 'package:upfleet_arena/shared/protocol/protocol_constants.dart';
import 'package:upfleet_arena/shared/protocol/protocol_message.dart';

/// A transport that keeps every frame, so the tests can inspect what the
/// Host sent to each connection.
class RecordingTransport implements RoomTransport {
  final Map<String, List<ProtocolMessage>> sent =
      <String, List<ProtocolMessage>>{};

  @override
  Future<void> send(String connectionId, ProtocolMessage message) async {
    sent.putIfAbsent(connectionId, () => <ProtocolMessage>[]).add(message);
  }

  @override
  Future<void> closeConnection(String connectionId) async {}

  @override
  Future<void> closeAll() async {}

  /// Every frame of a type sent to one connection.
  List<ProtocolMessage> messagesFor(String connectionId, String messageType) =>
      (sent[connectionId] ?? <ProtocolMessage>[])
          .where((ProtocolMessage message) => message.messageType == messageType)
          .toList();
}

void main() {
  group('room settings', () {
    late RoomCoordinator coordinator;
    late RecordingTransport transport;

    setUp(() {
      transport = RecordingTransport();
      coordinator = RoomCoordinator();
      coordinator.attach(transport);
      coordinator.createRoom(
        hostDisplayName: 'Host',
        avatarId: '🦈',
        deviceId: 'host-device',
        config: RoomConfig.defaults,
        tcpPort: 41234,
      );
    });

    tearDown(() => coordinator.dispose());

    /// Seats a member in the room and binds it to a connection.
    ClientSession seatPlayer(String name) {
      final HostPlayer player = HostPlayer(
        playerId: 'player-${name.toLowerCase()}',
        displayName: name,
        avatarId: '🐙',
        role: PlayerRole.player,
        deviceId: 'device-${name.toLowerCase()}',
        joinedAt: DateTime.now(),
      );
      coordinator.state!.players[player.playerId] = player;

      final ClientSession session = ClientSession(
        connectionId: 'connection-${name.toLowerCase()}',
        connectedAt: DateTime.now(),
      )..playerId = player.playerId;
      coordinator.registry.add(session);
      return session;
    }

    ProtocolMessage configUpdate(Map<String, dynamic> config) =>
        ProtocolMessage(
          messageType: ClientMessageType.configUpdate,
          payload: <String, dynamic>{'config': config},
        );

    test('the host settings reach every client', () async {
      final ClientSession alice = seatPlayer('Alice');
      final ClientSession bob = seatPlayer('Bob');

      final List<String> problems = await coordinator.hostUpdateConfig(
        RoomConfig.defaults.copyWith(
          rows: 12,
          columns: 14,
          fleetPreset: FleetPreset.large,
          maxPlayers: 4,
          placementDurationSeconds: 90,
          turnDurationSeconds: 45,
        ),
      );

      expect(problems, isEmpty);
      expect(coordinator.state!.config.rows, 12);
      expect(coordinator.state!.config.fleetPreset, FleetPreset.large);

      for (final ClientSession session in <ClientSession>[alice, bob]) {
        final List<ProtocolMessage> updates = transport.messagesFor(
          session.connectionId,
          HostEventType.configUpdated,
        );
        expect(updates, hasLength(1));

        final RoomSnapshot snapshot = RoomSnapshot.fromJson(
          updates.single.payload['snapshot'] as Map<String, dynamic>,
        );
        expect(snapshot.config.rows, 12);
        expect(snapshot.config.columns, 14);
        expect(snapshot.config.fleetPreset, FleetPreset.large);
        expect(snapshot.config.maxPlayers, 4);
        expect(snapshot.config.placementDurationSeconds, 90);
        expect(snapshot.config.turnDurationSeconds, 45);
        expect(
          updates.single.payload['stateVersion'],
          coordinator.state!.stateVersion,
        );
      }
    });

    test('the clients keep their own projection of the room', () async {
      final ClientSession alice = seatPlayer('Alice');

      await coordinator.hostUpdateConfig(
        RoomConfig.defaults.copyWith(maxPlayers: 4),
      );

      final RoomSnapshot snapshot = RoomSnapshot.fromJson(
        transport
            .messagesFor(alice.connectionId, HostEventType.configUpdated)
            .single
            .payload['snapshot'] as Map<String, dynamic>,
      );
      expect(snapshot.viewerPlayerId, alice.playerId);
      expect(snapshot.viewerIsHost, isFalse);
      expect(snapshot.stateVersion, coordinator.state!.stateVersion);
    });

    test('the state version increases with every accepted change', () async {
      final int before = coordinator.state!.stateVersion;

      await coordinator.hostUpdateConfig(
        RoomConfig.defaults.copyWith(rows: 11),
      );

      expect(coordinator.state!.stateVersion, before + 1);
    });

    test('a non-host cannot change the settings over the wire', () async {
      final ClientSession alice = seatPlayer('Alice');

      await coordinator.handleMessage(
        alice,
        configUpdate(RoomConfig.defaults.copyWith(maxPlayers: 2).toJson()),
      );

      final ProtocolMessage error = transport
          .messagesFor(alice.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.hostOnlyAction);
      expect(coordinator.state!.config.maxPlayers, 6);
    });

    test('a handcrafted configuration is rejected by the host runtime',
        () async {
      final ClientSession hostSession = ClientSession(
        connectionId: 'connection-host',
        connectedAt: DateTime.now(),
      )..playerId = coordinator.state!.hostPlayerId;
      coordinator.registry.add(hostSession);

      await coordinator.handleMessage(
        hostSession,
        configUpdate(<String, dynamic>{
          'rows': 4,
          'columns': 4,
          'fleetPreset': 'LARGE',
          'maxPlayers': 40,
          'placementDurationSeconds': 5,
          'turnDurationSeconds': 999,
        }),
      );

      final ProtocolMessage error = transport
          .messagesFor(hostSession.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.invalidRoomConfig);

      // The rejected values never reach the room.
      expect(coordinator.state!.config.rows, 10);
      expect(coordinator.state!.config.maxPlayers, 6);
      expect(coordinator.state!.config.turnDurationSeconds, 30);
    });

    test('a malformed configuration payload is rejected', () async {
      final ClientSession hostSession = ClientSession(
        connectionId: 'connection-host',
        connectedAt: DateTime.now(),
      )..playerId = coordinator.state!.hostPlayerId;
      coordinator.registry.add(hostSession);

      await coordinator.handleMessage(
        hostSession,
        configUpdate(<String, dynamic>{
          'rows': 'ten',
          'columns': 10,
          'fleetPreset': 'STANDARD',
          'maxPlayers': 4,
          'placementDurationSeconds': 120,
          'turnDurationSeconds': 30,
        }),
      );

      final ProtocolMessage error = transport
          .messagesFor(hostSession.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.invalidRoomConfig);
      expect(coordinator.state!.config.rows, 10);
    });

    test('the capacity cannot drop below the seated player count', () async {
      seatPlayer('Alice');
      seatPlayer('Bob');

      final List<String> problems = await coordinator.hostUpdateConfig(
        RoomConfig.defaults.copyWith(maxPlayers: 2),
      );

      expect(problems, isNotEmpty);
      expect(coordinator.state!.config.maxPlayers, 6);
    });

    test('the settings are frozen once the room left the lobby', () async {
      coordinator.state!.status = RoomStatus.placement;

      final List<String> problems = await coordinator.hostUpdateConfig(
        RoomConfig.defaults.copyWith(rows: 12),
      );
      expect(problems, isNotEmpty);
      expect(coordinator.state!.config.rows, 10);

      final ClientSession hostSession = ClientSession(
        connectionId: 'connection-host',
        connectedAt: DateTime.now(),
      )..playerId = coordinator.state!.hostPlayerId;
      coordinator.registry.add(hostSession);

      await coordinator.handleMessage(
        hostSession,
        configUpdate(RoomConfig.defaults.copyWith(rows: 12).toJson()),
      );

      final ProtocolMessage error = transport
          .messagesFor(hostSession.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.roomAlreadyStarted);
      expect(coordinator.state!.config.rows, 10);
    });

    test('a fleet that does not fit on the board is rejected', () async {
      final RoomConfig tooSmall = RoomConfig.defaults.copyWith(
        rows: 4,
        columns: 4,
        fleetPreset: FleetPreset.large,
      );
      expect(tooSmall.validate().join(' '), contains('does not fit'));

      final List<String> problems = await coordinator.hostUpdateConfig(
        tooSmall,
      );

      expect(problems, isNotEmpty);
      expect(coordinator.state!.config.fleetPreset, FleetPreset.standard);
    });
  });
}
