import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/host_runtime/client_connection_registry.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
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

  /// Every frame of a type, no matter which connection it went to.
  List<ProtocolMessage> messagesOfType(String messageType) =>
      sent.values
          .expand((List<ProtocolMessage> messages) => messages)
          .where((ProtocolMessage message) => message.messageType == messageType)
          .toList();
}

/// A member that is seated in the room and bound to a connection.
class SeatedPlayer {
  const SeatedPlayer(this.playerId, this.session);

  /// The player identifier of the member.
  final String playerId;

  /// The connection the member is bound to.
  final ClientSession session;
}

void main() {
  group('placement', () {
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

    test('an accepted layout is stored and answered to its owner', () async {
      final SeatedPlayer alice = seatPlayer('Alice');

      await coordinator.handleMessage(alice.session, placementSet(standardFleet()));

      final PlacementState state = PlacementState.fromJson(
        transport
            .messagesFor(alice.session.connectionId, HostEventType.placementState)
            .single
            .payload,
      );
      expect(state.playerId, alice.playerId);
      expect(state.ships, hasLength(5));
      expect(state.ready, isFalse);
      expect(
        coordinator.placementFor(alice.playerId).ships,
        hasLength(5),
      );
    });

    test('the layout of a player never reaches another client', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      final SeatedPlayer bob = seatPlayer('Bob');

      await coordinator.handleMessage(alice.session, placementSet(standardFleet()));

      expect(
        transport.messagesFor(bob.session.connectionId, HostEventType.placementState),
        isEmpty,
      );
      // The public readiness carries no coordinates.
      for (final ProtocolMessage message in transport.messagesOfType(
        HostEventType.placementReadyState,
      )) {
        expect(message.payload.toString(), isNot(contains('ship-1')));
        expect(message.payload.toString(), isNot(contains('column')));
      }
    });

    test('an illegal layout is rejected and nothing is stored', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      final List<ShipPlacement> illegal = standardFleet()
        ..[1] = ShipPlacement(
          shipId: 'ship-2',
          length: 3,
          orientation: ShipOrientation.horizontal,
          row: 0,
          column: 1,
        );

      await coordinator.handleMessage(alice.session, placementSet(illegal));

      final ProtocolMessage error = transport
          .messagesFor(alice.session.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.invalidShipPlacement);
      expect(coordinator.placementFor(alice.playerId).ships, isEmpty);
    });

    test('a layout outside the board is rejected', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      final List<ShipPlacement> illegal = standardFleet()
        ..[0] = ShipPlacement(
          shipId: 'ship-1',
          length: 4,
          orientation: ShipOrientation.horizontal,
          row: 9,
          column: 8,
        );

      await coordinator.handleMessage(alice.session, placementSet(illegal));

      final ProtocolMessage error = transport
          .messagesFor(alice.session.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.invalidShipPlacement);
      expect(coordinator.placementFor(alice.playerId).ships, isEmpty);
    });

    test('an incomplete fleet cannot be confirmed', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.handleMessage(
        alice.session,
        placementSet(standardFleet().sublist(0, 3)),
      );

      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(messageType: ClientMessageType.placementReady),
      );

      final ProtocolMessage error = transport
          .messagesFor(alice.session.connectionId, HostEventType.error)
          .single;
      expect(error.payload['code'], ProtocolErrorCode.fleetIncomplete);
      expect(coordinator.placementFor(alice.playerId).ready, isFalse);
    });

    test('a complete fleet is confirmed and the readiness is public',
        () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      final SeatedPlayer bob = seatPlayer('Bob');

      await coordinator.handleMessage(alice.session, placementSet(standardFleet()));
      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(messageType: ClientMessageType.placementReady),
      );

      expect(coordinator.placementFor(alice.playerId).ready, isTrue);

      final ProtocolMessage ready = transport
          .messagesFor(bob.session.connectionId, HostEventType.placementReadyState)
          .last;
      final ReadinessState state = ReadinessState.fromJson(ready.payload);
      expect(state.isReady(alice.playerId), isTrue);
      expect(state.isReady(bob.playerId), isFalse);
    });

    test('changing the fleet clears the confirmation', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.handleMessage(alice.session, placementSet(standardFleet()));
      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(messageType: ClientMessageType.placementReady),
      );
      expect(coordinator.placementFor(alice.playerId).ready, isTrue);

      await coordinator.handleMessage(alice.session, placementSet(standardFleet()));

      expect(coordinator.placementFor(alice.playerId).ready, isFalse);
    });

    test('the automatic placement fills the whole fleet', () async {
      final SeatedPlayer alice = seatPlayer('Alice');

      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(messageType: ClientMessageType.placementAuto),
      );

      final PlacementState state = PlacementState.fromJson(
        transport
            .messagesFor(alice.session.connectionId, HostEventType.placementState)
            .single
            .payload,
      );
      expect(state.ships, hasLength(5));
      expect(
        coordinator.placementFor(alice.playerId).ships.keys,
        containsAll(<String>['ship-1', 'ship-2', 'ship-3', 'ship-4', 'ship-5']),
      );
    });

    test('a new board size clears every layout', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.handleMessage(alice.session, placementSet(standardFleet()));
      expect(coordinator.placementFor(alice.playerId).ships, hasLength(5));

      await coordinator.hostUpdateConfig(
        RoomConfig.defaults.copyWith(rows: 12),
      );

      expect(coordinator.placementFor(alice.playerId).ships, isEmpty);
      expect(coordinator.placementFor(alice.playerId).ready, isFalse);

      // The client is told to clear its own board as well.
      final PlacementState state = PlacementState.fromJson(
        transport
            .messagesFor(
              alice.session.connectionId,
              HostEventType.placementState,
            )
            .last
            .payload,
      );
      expect(state.ships, isEmpty);
    });

    test('the host places and confirms its own fleet', () async {
      final List<String> problems = await coordinator.hostSetPlacement(
        standardFleet(),
      );
      expect(problems, isEmpty);
      expect(
        coordinator.placementFor(coordinator.state!.hostPlayerId).ships,
        hasLength(5),
      );

      final List<String> readyProblems = await coordinator.hostSetReady();
      expect(readyProblems, isEmpty);
      expect(
        coordinator.placementFor(coordinator.state!.hostPlayerId).ready,
        isTrue,
      );
    });

    test('a player that leaves loses its layout', () async {
      final SeatedPlayer alice = seatPlayer('Alice');
      await coordinator.handleMessage(alice.session, placementSet(standardFleet()));

      await coordinator.handleMessage(
        alice.session,
        ProtocolMessage(messageType: ClientMessageType.leave),
      );

      expect(coordinator.placementFor(alice.playerId).ships, isEmpty);
    });
  });
}
