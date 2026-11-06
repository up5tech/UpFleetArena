import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/host_runtime/client_connection_registry.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';
import 'package:upfleet_arena/shared/models/placement_models.dart';
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

  List<ProtocolMessage> messagesFor(String connectionId, String messageType) =>
      (sent[connectionId] ?? <ProtocolMessage>[])
          .where((ProtocolMessage message) => message.messageType == messageType)
          .toList();

  List<ProtocolMessage> messagesOfType(String messageType) =>
      sent.values
          .expand((List<ProtocolMessage> messages) => messages)
          .where((ProtocolMessage message) => message.messageType == messageType)
          .toList();
}

/// A member that is seated in the room and bound to a connection.
class SeatedPlayer {
  const SeatedPlayer(this.playerId, this.session);

  final String playerId;
  final ClientSession session;
}

void main() {
  group('preparation', () {
    late RoomCoordinator coordinator;
    late RecordingTransport transport;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      transport = RecordingTransport();
      coordinator = RoomCoordinator(clock: () => now);
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

    SeatedPlayer seatPlayer(String name) {
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
      return SeatedPlayer(player.playerId, session);
    }

    List<ShipPlacement> standardFleet() => <ShipPlacement>[
      ShipPlacement(
        shipId: 'ship-1',
        length: 4,
        orientation: ShipOrientation.horizontal,
        row: 0,
        column: 0,
      ),
      ShipPlacement(
        shipId: 'ship-2',
        length: 3,
        orientation: ShipOrientation.horizontal,
        row: 2,
        column: 0,
      ),
      ShipPlacement(
        shipId: 'ship-3',
        length: 3,
        orientation: ShipOrientation.horizontal,
        row: 4,
        column: 0,
      ),
      ShipPlacement(
        shipId: 'ship-4',
        length: 2,
        orientation: ShipOrientation.horizontal,
        row: 6,
        column: 0,
      ),
      ShipPlacement(
        shipId: 'ship-5',
        length: 2,
        orientation: ShipOrientation.horizontal,
        row: 8,
        column: 0,
      ),
    ];

    ProtocolMessage placementSet(List<ShipPlacement> ships) =>
        ProtocolMessage(
          messageType: ClientMessageType.placementSet,
          payload: <String, dynamic>{
            'ships': ships
                .map((ShipPlacement ship) => ShipLayout.fromPlacement(ship).toJson())
                .toList(),
          },
        );

    Future<void> placeAndConfirm(SeatedPlayer player) async {
      await coordinator.handleMessage(
        player.session,
        placementSet(standardFleet()),
      );
      await coordinator.handleMessage(
        player.session,
        ProtocolMessage(messageType: ClientMessageType.placementReady),
      );
    }

    test('the host starts the preparation and every client is told', () async {
      final SeatedPlayer alice = seatPlayer('Alice');

      final List<String> problems = await coordinator.hostStartPlacement();
      expect(problems, isEmpty);
      expect(coordinator.state!.status, RoomStatus.placement);

      final ProtocolMessage started = transport
          .messagesFor(alice.session.connectionId, HostEventType.placementStarted)
          .single;
      expect(started.payload['remainingSeconds'], 120);
      expect(started.payload['durationSeconds'], 120);
      expect(started.payload['fleetPreset'], FleetPreset.standard.wire);
    });

    test('a client cannot start the preparation', () async {
      final SeatedPlayer alice = seatPlayer('Alice');

      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(messageType: ClientMessageType.startPlacement),
      );

      final ProtocolMessage error = transport
          .messagesFor(alice.session.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.hostOnlyAction);
      expect(coordinator.state!.status, RoomStatus.lobby);
    });

    test('the preparation needs two connected players', () async {
      final List<String> problems = await coordinator.hostStartPlacement();
      expect(problems, isNotEmpty);
      expect(coordinator.state!.status, RoomStatus.lobby);
    });

    test('the match starts as soon as every player is ready', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.hostStartPlacement();

      await coordinator.hostSetPlacement(standardFleet());
      await coordinator.hostSetReady();
      expect(coordinator.state!.status, RoomStatus.placement);

      await placeAndConfirm(alice);

      expect(coordinator.state!.status, RoomStatus.active);

      final ProtocolMessage started = transport
          .messagesFor(alice.session.connectionId, HostEventType.started)
          .single;
      final MatchStartState match = MatchStartState.fromJson(started.payload);
      expect(match.turnOrder, hasLength(2));
      expect(
        match.turnOrder.map((TurnOrderEntry entry) => entry.playerId).toSet(),
        hasLength(2),
      );
      expect(match.activePlayerId, match.turnOrder.first.playerId);
    });

    test('the timeout completes the missing fleets and starts the match',
        () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.hostStartPlacement();

      // Only the host confirmed a fleet; Alice did not.
      await coordinator.hostSetPlacement(standardFleet());
      await coordinator.hostSetReady();

      now = now.add(const Duration(seconds: 121));
      await coordinator.checkPreparationDeadline();

      expect(coordinator.state!.status, RoomStatus.active);
      // The Host completed the fleet of Alice.
      expect(
        coordinator.placementFor(alice.playerId).ships,
        hasLength(5),
      );
      expect(coordinator.placementFor(alice.playerId).ready, isTrue);
    });

    test('the deadline does not end the preparation early', () async {
      seatPlayer('Alice');
      await coordinator.hostStartPlacement();

      now = now.add(const Duration(seconds: 30));
      await coordinator.checkPreparationDeadline();

      expect(coordinator.state!.status, RoomStatus.placement);
      expect(transport.messagesOfType(HostEventType.started), isEmpty);
    });

    test('a client clock cannot move the transition', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.hostStartPlacement();


      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(
          messageType: 'game:request-snapshot',
          payload: <String, dynamic>{'timeRemaining': 0},
        ),
      );

      expect(coordinator.state!.status, RoomStatus.placement);
    });

    test('the preparation is cancelled when too few players are left',
        () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.hostStartPlacement();

      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(messageType: ClientMessageType.leave),
      );

      expect(coordinator.state!.status, RoomStatus.lobby);
      final ProtocolMessage cancelled = transport
          .messagesFor(
            'connection-alice',
            HostEventType.placementCancelled,
          )
          .last;
      expect(cancelled.payload['reason'], isNotEmpty);
    });

    test('a confirmed fleet cannot be changed during the preparation',
        () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.hostStartPlacement();

      await placeAndConfirm(alice);
      expect(coordinator.placementFor(alice.playerId).ready, isTrue);

      await coordinator.handleMessage(
        alice.session,
        placementSet(standardFleet()),
      );

      final ProtocolMessage error = transport
          .messagesFor(alice.session.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.placementLocked);
    });

    test('the preparation can still be prepared while it runs', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.hostStartPlacement();

      await coordinator.handleMessage(
        alice.session,
        placementSet(standardFleet()),
      );

      expect(coordinator.placementFor(alice.playerId).ships, hasLength(5));
      expect(
        transport.messagesFor(
          alice.session.connectionId,
          HostEventType.error,
        ),
        isEmpty,
      );
    });

    test('the countdown follows the Host clock', () async {
      seatPlayer('Alice');
      await coordinator.hostStartPlacement();

      expect(coordinator.placementRemainingSeconds, 120);

      now = now.add(const Duration(seconds: 45));
      expect(coordinator.placementRemainingSeconds, 75);

      await coordinator.checkPreparationDeadline();
      expect(coordinator.placementRemainingSeconds, 75);
    });
  });
}
