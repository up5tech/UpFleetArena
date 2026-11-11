import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/fleet/fleet_profile.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/game_engine/placement/placement_validator.dart';
import 'package:upfleet_arena/host_runtime/client_connection_registry.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';
import 'package:upfleet_arena/shared/protocol/protocol_constants.dart';
import 'package:upfleet_arena/shared/protocol/protocol_message.dart';

class RecordingTransport implements RoomTransport {
  final Map<String, List<ProtocolMessage>> sent = {};
  Completer<void>? gate;
  Completer<void>? entered;
  bool closed = false;
  int sendsAfterClose = 0;

  @override
  Future<void> send(String connectionId, ProtocolMessage message) async {
    if (closed) sendsAfterClose++;
    sent.putIfAbsent(connectionId, () => []).add(message);
    final Completer<void>? blocked = gate;
    if (blocked != null) {
      if (!entered!.isCompleted) entered!.complete();
      await blocked.future;
    }
  }

  void block() {
    gate = Completer<void>();
    entered = Completer<void>();
  }

  void release() {
    gate?.complete();
    gate = null;
  }

  @override
  Future<void> closeConnection(String connectionId) async {}

  @override
  Future<void> closeAll() async {
    closed = true;
  }

  List<ProtocolMessage> messages(String playerId, String type) =>
      (sent['connection-$playerId'] ?? [])
          .where((message) => message.messageType == type)
          .toList();
}

/// The standard fleet, shifted into one band of the shared map.
///
/// Every player of the fixture owns a band of five columns, so a shot can hit
/// one fleet without touching the others while the map stays shared.
List<ShipPlacement> fleetAt(int columnOffset) => [
  for (final (int index, int length) in FleetPreset.standard.shipLengths.indexed)
    ShipPlacement(
      shipId: 'ship-${index + 1}',
      length: length,
      span: FleetPreset.standard.spanAt(index),
      orientation: ShipOrientation.horizontal,
      row: index * 2,
      column: columnOffset,
    ),
];

const int _bandSpacing = 5;

class MatchFixture {
  MatchFixture({bool twoPlayers = false}) {
    coordinator = RoomCoordinator(clock: () => now)..attach(transport);
    coordinator.createRoom(
      hostDisplayName: 'Host',
      avatarId: 'host',
      deviceId: 'host-device',
      // Wide enough for one five-column band per player.
      config: RoomConfig.defaults.copyWith(columns: 14),
      tcpPort: 41234,
    );
    for (final String id in ['alice', if (!twoPlayers) 'bob']) {
      room.players[id] = HostPlayer(
        playerId: id,
        displayName: id,
        avatarId: id,
        role: PlayerRole.player,
        deviceId: '$id-device',
        joinedAt: now,
      );
      sessions[id] = ClientSession(
        connectionId: 'connection-$id',
        connectedAt: now,
        playerId: id,
        deviceId: '$id-device',
      );
      coordinator.registry.add(sessions[id]!);
    }
    final List<String> order = twoPlayers
        ? <String>[host, 'alice']
        : <String>['alice', 'bob', host];
    final Map<String, List<ShipPlacement>> fleets =
        <String, List<ShipPlacement>>{
          for (final (int index, String id) in order.indexed)
            id: fleetAt(index * _bandSpacing),
        };
    final List<ShipPlacement> probe = fleets[order.first]!;
    expect(
      isFleetComplete(FleetProfile.fromPreset(FleetPreset.standard), probe),
      isTrue,
    );
    expect(
      validateFleetLayout(
        board: const BoardSize(rows: 10, columns: 14),
        profile: FleetProfile.fromPreset(FleetPreset.standard),
        ships: probe,
      ),
      isNull,
    );
    for (final String id in order) {
      coordinator
          .placementFor(id)
          .ships
          .addEntries(
            fleets[id]!.map(
              (ShipPlacement ship) => MapEntry(ship.shipId, ship),
            ),
          );
      coordinator.placementFor(id).ready = true;
    }
    room.status = RoomStatus.active;
    room.match = HostMatchState(
      matchId: 'match-1',
      turnOrder: order,
      activePlayerId: order.first,
      startedAt: now,
      boards: <String, PlayerBoard>{
        for (final String id in order)
          id: PlayerBoard(playerId: id, ships: fleets[id]!),
      },
    )..turnDeadline = now.add(const Duration(seconds: 30));
    coordinator.hostShotFeedbacks.listen(feedback.add);
    coordinator.hostPublicActivities.listen(activities.add);
    coordinator.hostMatchSnapshots.listen(snapshots.add);
    coordinator.hostSnapshots.listen(rooms.add);
  }

  DateTime now = DateTime.utc(2026, 1, 1, 12);
  final RecordingTransport transport = RecordingTransport();
  late final RoomCoordinator coordinator;
  final Map<String, ClientSession> sessions = {};
  final List<ShotFeedback> feedback = [];
  final List<PublicActivity> activities = [];
  final List<MatchSnapshot> snapshots = [];
  final List<RoomSnapshot> rooms = [];
  int request = 0;

  HostRoomState get room => coordinator.state!;
  HostMatchState get match => room.match!;
  String get host => room.hostPlayerId;

  /// The first column of the fleet of the player.
  int band(String playerId) => match.turnOrder.indexOf(playerId) * _bandSpacing;

  List<ShipPlacement> fleetOf(String playerId) => fleetAt(band(playerId));

  ProtocolMessage fire({int row = 0, int column = 0}) => ProtocolMessage(
    messageType: ClientMessageType.fire,
    requestId: 'fire-${++request}',
    roomId: room.roomId,
    expectedStateVersion: room.stateVersion,
    payload: {
      'matchId': match.matchId,
      'turnNumber': match.turnNumber,
      'row': row,
      'column': column,
    },
  );

  Future<void> shoot(String attacker, {int row = 0, int column = 0}) async {
    expect(match.activePlayerId, attacker);
    if (attacker == host) {
      expect(
        await coordinator.hostFire(
          matchId: match.matchId,
          turnNumber: match.turnNumber,
          expectedStateVersion: room.stateVersion,
          row: row,
          column: column,
        ),
        isEmpty,
      );
    } else {
      final ProtocolMessage command = fire(row: row, column: column);
      await coordinator.handleMessage(sessions[attacker]!, command);
      expect(transport.messages(attacker, HostEventType.error), isEmpty);
      expect(
        transport.messages(attacker, HostEventType.shotResult).last.requestId,
        command.requestId,
      );
    }
  }

  /// Fires at the first cell of the fleet of [target].
  Future<void> shootAt(String attacker, String target) =>
      shoot(attacker, row: 0, column: band(target));

  Future<void> timeout() async {
    now = match.turnDeadline!;
    await coordinator.checkTurnDeadline();
  }

  /// Lets the broadcast streams deliver the events already queued.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<MatchSnapshot> view(String playerId) async {
    await settle();
    return playerId == host
        ? snapshots.last
        : MatchSnapshot.fromJson(
            transport
                    .messages(playerId, HostEventType.stateSnapshot)
                    .last
                    .payload['snapshot']
                as Map<String, dynamic>,
          );
  }

  Future<void> rejected(
    ClientSession session,
    ProtocolMessage command,
    String code,
  ) async {
    final int version = room.stateVersion;
    final int turn = match.turnNumber;
    final String active = match.activePlayerId;
    final DateTime? deadline = match.turnDeadline;
    final Map<String, List<CellCoord>> damage = {
      for (final entry in match.boards.entries)
        entry.key: entry.value.shotsReceived.toList(),
    };
    await coordinator.handleMessage(session, command);
    final ProtocolMessage error = transport
        .messages(session.playerId!, HostEventType.error)
        .last;
    expect(error.payload['code'], code);
    expect(error.requestId, command.requestId);
    expect(room.stateVersion, version);
    expect(match.turnNumber, turn);
    expect(match.activePlayerId, active);
    expect(match.turnDeadline, deadline);
    expect({
      for (final entry in match.boards.entries)
        entry.key: entry.value.shotsReceived.toList(),
    }, damage);
  }
}

/// The own board of a player as the projection carries it.
Map<String, dynamic> _ownBoardJson(
  String playerId,
  List<ShipPlacement> fleet,
  List<(int, int, ShotResult, String)> received,
) => <String, dynamic>{
  'ships': [
    for (final ShipPlacement ship in fleet)
      {
        'shipId': ship.shipId,
        'length': ship.length,
        'span': ship.span,
        'orientation': 'horizontal',
        'row': ship.row,
        'column': ship.column,
        'hitCells': [
          for (final (int row, int column, ShotResult result, String _)
              in received)
            if (result != ShotResult.miss &&
                ship.cells.contains(CellCoord(row, column)))
              {'row': row, 'column': column},
        ],
        'sunk': false,
      },
  ],
  'shotsReceived': [
    for (final (int row, int column, ShotResult _, String _) in received)
      {'row': row, 'column': column},
  ],
  'receivedShots': [
    for (final (int row, int column, ShotResult result, String attacker)
        in received)
      {
        'row': row,
        'column': column,
        'result': result.wire,
        'attackerPlayerId': attacker,
      },
  ],
};

void main() {
  late MatchFixture f;
  setUp(() {
    f = MatchFixture();
  });
  tearDown(() => f.coordinator.dispose());

  test('one shot hits every living fleet at once and advances once', () async {
    final int version = f.room.stateVersion;
    await f.shootAt('alice', 'bob');
    expect(f.room.stateVersion, version + 1);
    expect(f.match.turnNumber, 2);
    expect(f.match.activePlayerId, 'bob');
    // The shot resolved against both living opponents, not only bob.
    expect(f.match.boards['bob']!.ships['ship-1']!.hitCells, {
      const CellCoord(0, 5),
    });
    expect(f.match.boards[f.host]!.shotsReceived, {const CellCoord(0, 5)});
    expect(f.match.boards[f.host]!.ships['ship-1']!.hitCells, isEmpty);

    // The attacker gets one aggregate event; the target gets its own board.
    final ProtocolMessage attacker = f.transport
        .messages('alice', HostEventType.shotResult)
        .single;
    expect(
      attacker.payload.keys,
      unorderedEquals([
        'attackerPlayerId',
        'targetPlayerId',
        'row',
        'column',
        'result',
      ]),
    );
    expect(attacker.payload['result'], 'hit');
    expect(attacker.payload['targetPlayerId'], 'bob');
    expect(
      f.transport.messages('bob', HostEventType.shotResult).single.payload.keys,
      unorderedEquals([
        'attackerPlayerId',
        'targetPlayerId',
        'row',
        'column',
        'result',
        'ownBoard',
      ]),
    );
    // The host was a target of the same volley and saw the miss on its board.
    expect(f.feedback.single.targetPlayerId, f.host);
    expect(f.feedback.single.result, ShotResult.miss);
    // Every living player was involved, so no public spectator event exists.
    expect(f.activities, isEmpty);

    await f.shoot('bob', row: 9, column: 0);
    expect(f.feedback.last.result, ShotResult.miss);
    await f.shoot(f.host, row: 0, column: f.band('bob') + 1);
    expect(f.feedback.last.result, ShotResult.hit);
    expect(f.match.activePlayerId, 'alice');
    expect(f.match.turnNumber, 4);
    expect(f.room.stateVersion, version + 3);
  });

  test('a cell is fired at once per attacker on the single map', () async {
    await f.shootAt('alice', 'bob');
    expect(f.match.boards['bob']!.shotsReceived, {const CellCoord(0, 5)});
    expect(f.match.boards[f.host]!.shotsReceived, {const CellCoord(0, 5)});
    await f.shoot('bob', row: 9, column: 0);
    await f.shootAt(f.host, 'bob');
    expect(f.match.boards['bob']!.ships['ship-1']!.hitCells, {
      const CellCoord(0, 5),
    });

    // Alice already fired at that cell of the map, whichever fleet it hit.
    await f.rejected(
      f.sessions['alice']!,
      f.fire(column: 5),
      ProtocolErrorCode.cellAlreadyFiredAt,
    );
    f.transport.sent.clear();
    await f.shootAt('alice', f.host);
    expect(
      f.match.attackHistory['alice']!.keys,
      unorderedEquals(['bob', f.host]),
    );
  });

  test(
    'sink is emitted only on the first transition even for another attacker',
    () async {
      await f.shoot('alice', row: 8, column: 5);
      await f.shoot('bob', row: 9, column: 0);
      await f.shoot(f.host, row: 8, column: 6);
      expect(f.feedback.last.result, ShotResult.shipSunk);
      await f.shoot('alice', row: 8, column: 6);
      expect(
        f.transport
            .messages('alice', HostEventType.shotResult)
            .last
            .payload['result'],
        'hit',
      );
      expect(f.match.boards['bob']!.sunkCount, 1);
      expect(f.match.boards['bob']!.remainingCells, 12);
    },
  );

  test('one shot sinks a ship in every fleet that shares the cell', () async {
    // Both opponents keep a one-cell ship on the same cell of the shared map.
    for (final String id in ['bob', f.host]) {
      f.match.boards[id] = PlayerBoard(
        playerId: id,
        ships: <ShipPlacement>[
          ShipPlacement(
            shipId: 'ship-1',
            length: 1,
            orientation: ShipOrientation.horizontal,
            row: 4,
            column: 4,
          ),
        ],
      );
    }
    await f.shoot('alice', row: 4, column: 4);

    expect(f.match.boards['bob']!.isEliminated, isTrue);
    expect(f.match.boards[f.host]!.isEliminated, isTrue);
    // The volley counts once and every ship it sank is counted.
    expect(f.match.stats['alice']!.shots, 1);
    expect(f.match.stats['alice']!.hits, 1);
    expect(f.match.stats['alice']!.shipsSunk, 2);
    expect(f.match.eliminationOrder, <String>['bob', f.host]);
    expect(f.feedback.last.result, ShotResult.shipSunk);
    expect(f.room.status, RoomStatus.finished);
    expect(f.match.winnerPlayerId, 'alice');

    // Every sunk hull is published with the player who owned it, so the room
    // can outline it in that player's colour.
    final MatchSnapshot snapshot = await f.view('alice');
    expect(
      snapshot.sunkShips.map(
        (SunkShipView ship) => (ship.ownerPlayerId, ship.row, ship.column),
      ),
      containsAll(<(String, int, int)>[
        ('bob', 4, 4),
        (f.host, 4, 4),
      ]),
    );
  });

  test('a fleet that is still afloat stays hidden', () async {
    await f.shoot('alice', row: 0, column: f.band('bob'));
    expect(f.match.boards['bob']!.ships['ship-1']!.hitCells, {
      const CellCoord(0, 5),
    });

    // A hit that does not sink the ship publishes no hull: the fleet is still
    // hidden on the shared map.
    final MatchSnapshot snapshot = await f.view('alice');
    expect(snapshot.sunkShips, isEmpty);
  });

  test('every projection carries the one map and the own impacts', () async {
    await f.shootAt('alice', 'bob');
    await f.shoot('bob', row: 9, column: 0);
    await f.shoot(f.host, row: 0, column: f.band('bob') + 1);

    final List<Map<String, dynamic>> mapShots = <Map<String, dynamic>>[
      {'row': 0, 'column': 5, 'result': 'hit', 'attackerPlayerId': 'alice'},
      {'row': 0, 'column': 6, 'result': 'hit', 'attackerPlayerId': f.host},
      {'row': 9, 'column': 0, 'result': 'miss', 'attackerPlayerId': 'bob'},
    ];
    final Map<String, List<(int, int, ShotResult, String)>> received =
        <String, List<(int, int, ShotResult, String)>>{
          'alice': <(int, int, ShotResult, String)>[
            (9, 0, ShotResult.miss, 'bob'),
            (0, 6, ShotResult.miss, f.host),
          ],
          'bob': <(int, int, ShotResult, String)>[
            (0, 5, ShotResult.hit, 'alice'),
            (0, 6, ShotResult.hit, f.host),
          ],
          f.host: <(int, int, ShotResult, String)>[
            (0, 5, ShotResult.miss, 'alice'),
            (9, 0, ShotResult.miss, 'bob'),
          ],
        };

    for (final String viewer in f.match.turnOrder) {
      final MatchSnapshot snapshot = await f.view(viewer);
      expect(snapshot.toJson(), {
        'matchId': 'match-1',
        'stateVersion': f.room.stateVersion,
        'turnNumber': 4,
        'activePlayerId': 'alice',
        'turnRemainingSeconds': 30,
        'players': [
          for (final String id in f.match.turnOrder)
            {
              'playerId': id,
              'displayName': f.room.players[id]!.displayName,
              'alive': true,
              'timeouts': 0,
              'shipsRemaining': 5,
            },
        ],
        'ownBoard': _ownBoardJson(viewer, f.fleetOf(viewer), received[viewer]!),
        'mapShots': mapShots,
        // No ship went down in this volley triple.
        'sunkShips': <Map<String, dynamic>>[],
        'winnerPlayerId': null,
      });
    }
    // Bob took part in two volleys and fired one, so three events reach him.
    expect(f.transport.messages('bob', HostEventType.shotResult), hasLength(3));
    expect(
      f.transport.messages('alice', HostEventType.publicActivity),
      isEmpty,
    );
  });

  test(
    'malformed fire fields are rejected without throwing or changing state',
    () async {
      final ProtocolMessage valid = f.fire();
      for (final String field in ['row', 'column', 'matchId', 'turnNumber']) {
        for (final Object? value in [null, true, [], {}, 1.5]) {
          await f.rejected(
            f.sessions['alice']!,
            valid.copyWith(payload: {...valid.payload, field: value}),
            ProtocolErrorCode.malformedPayload,
          );
        }
        final Map<String, dynamic> missing = {...valid.payload}..remove(field);
        await f.rejected(
          f.sessions['alice']!,
          valid.copyWith(payload: missing),
          ProtocolErrorCode.malformedPayload,
        );
      }
      for (final String? requestId in [null, '', '  ']) {
        await f.rejected(
          f.sessions['alice']!,
          ProtocolMessage(
            messageType: ClientMessageType.fire,
            requestId: requestId,
            expectedStateVersion: f.room.stateVersion,
            payload: valid.payload,
          ),
          ProtocolErrorCode.malformedPayload,
        );
      }
      await f.rejected(
        f.sessions['alice']!,
        ProtocolMessage(
          messageType: ClientMessageType.fire,
          requestId: 'missing-version',
          payload: valid.payload,
        ),
        ProtocolErrorCode.malformedPayload,
      );
    },
  );

  test(
    'auth checks the live registry identity and rejects spoofed player IDs',
    () async {
      final ClientSession alice = f.sessions['alice']!;
      await f.rejected(
        alice,
        f.fire().copyWith(playerId: f.host),
        ProtocolErrorCode.notRoomMember,
      );
      final ProtocolMessage command = f.fire();
      await f.rejected(
        alice,
        command.copyWith(payload: {...command.payload, 'playerId': f.host}),
        ProtocolErrorCode.notRoomMember,
      );
      await f.rejected(
        ClientSession(
          connectionId: alice.connectionId,
          connectedAt: f.now,
          playerId: 'alice',
        ),
        command,
        ProtocolErrorCode.notRoomMember,
      );
      alice.closed = true;
      await f.rejected(alice, command, ProtocolErrorCode.notRoomMember);
      alice.closed = false;
      for (final status in [
        PlayerConnectionStatus.disconnected,
        PlayerConnectionStatus.left,
        PlayerConnectionStatus.kicked,
      ]) {
        f.room.players['alice']!.status = status;
        await f.rejected(alice, command, ProtocolErrorCode.notRoomMember);
      }
      f.room.players['alice']!.status = PlayerConnectionStatus.connected;
      f.coordinator.registry.remove(alice.connectionId);
      await f.rejected(alice, command, ProtocolErrorCode.notRoomMember);
    },
  );

  test(
    'stale room, match, turn and envelope version never consume the turn',
    () async {
      final ProtocolMessage command = f.fire();
      for (final message in [
        command.copyWith(roomId: 'old-room'),
        command.copyWith(payload: {...command.payload, 'matchId': 'old-match'}),
        command.copyWith(payload: {...command.payload, 'turnNumber': 0}),
        command.copyWith(expectedStateVersion: f.room.stateVersion - 1),
      ]) {
        await f.rejected(
          f.sessions['alice']!,
          message,
          ProtocolErrorCode.stateVersionConflict,
        );
      }
      f.transport.sent.clear();
      await f.shootAt('alice', 'bob');
      await f.rejected(
        f.sessions['alice']!,
        command,
        ProtocolErrorCode.stateVersionConflict,
      );
    },
  );

  test('only a living active attacker can fire in bounds', () async {
    await f.rejected(
      f.sessions['bob']!,
      f.fire(),
      ProtocolErrorCode.notYourTurn,
    );
    for (final (int row, int column) in [(-1, 0), (10, 0), (0, -1), (0, 14)]) {
      await f.rejected(
        f.sessions['alice']!,
        f.fire(row: row, column: column),
        ProtocolErrorCode.invalidTargetCell,
      );
    }
    f.match.eliminated.add('alice');
    await f.rejected(
      f.sessions['alice']!,
      f.fire(),
      ProtocolErrorCode.notYourTurn,
    );
  });

  test(
    'host API validates match, turn and version rather than refreshing them',
    () async {
      await f.timeout();
      await f.timeout();
      final int version = f.room.stateVersion;
      final int turn = f.match.turnNumber;
      for (final (String matchId, int turnNumber, int expectedVersion) in [
        ('old-match', turn, version),
        ('match-1', turn - 1, version),
        ('match-1', turn, version - 1),
      ]) {
        expect(
          await f.coordinator.hostFire(
            matchId: matchId,
            turnNumber: turnNumber,
            expectedStateVersion: expectedVersion,
            row: 0,
            column: 0,
          ),
          isNotEmpty,
        );
        expect(f.room.stateVersion, version);
        expect(f.match.turnNumber, turn);
      }
      await f.shoot(f.host, column: f.band('alice'));
    },
  );

  test(
    'simultaneous fires commit exactly once before transport completes',
    () async {
      final ProtocolMessage first = f.fire(column: 5);
      final ProtocolMessage second = f.fire(column: 6);
      final int version = f.room.stateVersion;
      f.transport.block();
      final Future<void> a = f.coordinator.handleMessage(
        f.sessions['alice']!,
        first,
      );
      await f.transport.entered!.future;
      expect(f.match.activePlayerId, 'bob');
      expect(f.match.turnNumber, 2);
      expect(f.room.stateVersion, version + 1);
      final Future<void> b = f.coordinator.handleMessage(
        f.sessions['alice']!,
        second,
      );
      f.transport.release();
      await Future.wait([a, b]);
      expect(f.room.stateVersion, version + 1);
      expect(f.match.boards['bob']!.shotsReceived, {const CellCoord(0, 5)});
      expect(
        f.transport.messages('alice', HostEventType.error).single.requestId,
        second.requestId,
      );
      expect(
        f.transport
            .messages('alice', HostEventType.error)
            .single
            .payload['code'],
        ProtocolErrorCode.stateVersionConflict,
      );
    },
  );

  test(
    'ceil countdown permits a shot one microsecond before deadline',
    () async {
      f.now = f.match.turnDeadline!.subtract(const Duration(microseconds: 1));
      expect(f.coordinator.turnRemainingSeconds, 1);
      await f.coordinator.checkTurnDeadline();
      expect(f.match.turnNumber, 1);
      await f.shootAt('alice', 'bob');
      expect(f.match.timeouts, isEmpty);
    },
  );

  for (final bool timeoutFirst in [false, true]) {
    test(
      'exact-deadline fire racing timeout never damages ($timeoutFirst)',
      () async {
        final ProtocolMessage command = f.fire(column: 5);
        final int version = f.room.stateVersion;
        f.now = f.match.turnDeadline!;
        expect(f.coordinator.turnRemainingSeconds, 0);
        Future<void> fire() =>
            f.coordinator.handleMessage(f.sessions['alice']!, command);
        await Future.wait(
          timeoutFirst
              ? [f.coordinator.checkTurnDeadline(), fire()]
              : [fire(), f.coordinator.checkTurnDeadline()],
        );
        expect(f.match.boards['bob']!.shotsReceived, isEmpty);
        expect(f.match.boards[f.host]!.shotsReceived, isEmpty);
        expect(f.match.timeouts, {'alice': 1});
        expect(f.match.turnNumber, 2);
        expect(f.room.stateVersion, version + 1);
        expect(
          f.transport.messages('alice', HostEventType.error).single.requestId,
          command.requestId,
        );
      },
    );
  }

  test(
    'a pending shot emission cannot consume its old deadline again',
    () async {
      final DateTime oldDeadline = f.match.turnDeadline!;
      f.now = oldDeadline.subtract(const Duration(microseconds: 1));
      f.transport.block();
      final Future<void> shot = f.coordinator.handleMessage(
        f.sessions['alice']!,
        f.fire(column: 5),
      );
      await f.transport.entered!.future;
      final DateTime nextDeadline = f.match.turnDeadline!;
      expect(nextDeadline.isAfter(oldDeadline), isTrue);
      f.now = oldDeadline;
      final Future<void> tick = f.coordinator.checkTurnDeadline();
      f.transport.release();
      await Future.wait([shot, tick]);
      expect(f.match.turnNumber, 2);
      expect(f.match.timeouts, isEmpty);
      expect(f.match.turnDeadline, nextDeadline);
    },
  );

  test(
    'timeout streaks belong to each player and reset only on their shot',
    () async {
      for (int i = 0; i < 6; i++) {
        await f.timeout();
      }
      expect(f.match.timeouts, {'alice': 2, 'bob': 2, f.host: 2});
      expect(f.match.consecutiveTimeouts, 2);
      await f.shootAt('alice', 'bob');
      expect(f.match.consecutiveTimeouts, 2);
      await f.timeout();
      await f.timeout();
      expect(f.match.consecutiveTimeouts, 0);
      expect((await f.view('alice')).playerById('alice')!.timeouts, 2);
    },
  );

  test(
    'snapshot recovery returns correlated room and private current match',
    () async {
      await f.shootAt('alice', 'bob');
      final Map<String, dynamic> expected = (await f.view('alice')).toJson();
      f.transport.sent.clear();
      await f.coordinator.handleMessage(
        f.sessions['alice']!,
        const ProtocolMessage(
          messageType: ClientMessageType.requestSnapshot,
          requestId: 'recover',
        ),
      );
      final List<ProtocolMessage> messages =
          f.transport.sent['connection-alice']!;
      expect(messages.map((m) => m.messageType), [
        HostEventType.roomState,
        HostEventType.stateSnapshot,
      ]);
      expect(messages.map((m) => m.requestId), ['recover', 'recover']);
      expect(messages.last.payload, {'snapshot': expected});
      expect(f.transport.sent.keys, ['connection-alice']);
    },
  );

  test(
    'close waits for emissions and suppresses all later commands and ticks',
    () async {
      f.transport.block();
      final Future<void> shot = f.coordinator.handleMessage(
        f.sessions['alice']!,
        f.fire(column: 5),
      );
      await f.transport.entered!.future;
      final Future<void> close = f.coordinator.closeRoom(
        reason: 'host_closed',
        message: 'Closed',
      );
      final Future<void> late = f.coordinator.handleMessage(
        f.sessions['bob']!,
        f.fire(),
      );
      f.transport.release();
      await Future.wait([shot, close, late]);
      await f.coordinator.checkTurnDeadline();
      expect(f.room.status, RoomStatus.closed);
      expect(f.match.turnDeadline, isNull);
      expect(f.transport.sendsAfterClose, 0);
      for (final messages in f.transport.sent.values) {
        expect(messages.last.messageType, HostEventType.closed);
      }
    },
  );

  test(
    'terminal victory is committed once, sent as room state, and immutable',
    () async {
      await f.coordinator.dispose();
      f = MatchFixture(twoPlayers: true);
      final List<CellCoord> cells = f
          .fleetOf('alice')
          .expand((ship) => ship.cells)
          .toList();
      for (int i = 0; i < cells.length; i++) {
        final int version = f.room.stateVersion;
        final CellCoord cell = cells[i];
        await f.shoot(f.host, row: cell.row, column: cell.column);
        expect(f.room.stateVersion, version + 1);
        if (i + 1 < cells.length) {
          // Alice fires into open water so only her fleet takes damage.
          await f.shoot('alice', row: 9, column: i);
        }
      }
      expect(f.room.status, RoomStatus.finished);
      expect(f.match.winnerPlayerId, f.host);
      expect(f.match.turnDeadline, isNull);
      expect(f.match.eliminated, {'alice'});
      expect(
        f.feedback.where((event) => event.result == ShotResult.shipSunk),
        hasLength(5),
      );
      expect(
        f.transport.messages('alice', HostEventType.finished),
        hasLength(1),
      );
      expect(
        f.transport.messages('alice', HostEventType.playerEliminated),
        hasLength(1),
      );
      expect(
        f.transport
            .messages('alice', HostEventType.roomState)
            .last
            .payload['snapshot']['status'],
        RoomStatus.finished.wire,
      );
      await f.settle();
      expect(f.rooms.last.status, RoomStatus.finished);
      expect(f.snapshots.last.winnerPlayerId, f.host);
      final int version = f.room.stateVersion;
      await f.rejected(
        f.sessions['alice']!,
        f.fire(),
        ProtocolErrorCode.matchAlreadyFinished,
      );
      expect(
        await f.coordinator.hostFire(
          matchId: f.match.matchId,
          turnNumber: f.match.turnNumber,
          expectedStateVersion: version,
          row: 9,
          column: 9,
        ),
        isNotEmpty,
      );
      await f.coordinator.checkTurnDeadline();
      expect(f.room.stateVersion, version);
    },
  );
}
