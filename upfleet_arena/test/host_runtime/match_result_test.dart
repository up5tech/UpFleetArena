import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/combat/match_result.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/host_runtime/client_connection_registry.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';
import 'package:upfleet_arena/shared/protocol/protocol_constants.dart';
import 'package:upfleet_arena/shared/protocol/protocol_message.dart';

class _Transport implements RoomTransport {
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

  List<ProtocolMessage> of(String playerId, String type) =>
      (sent['connection-$playerId'] ?? <ProtocolMessage>[])
          .where((ProtocolMessage message) => message.messageType == type)
          .toList();
}

/// The small fleet is `[3, 2, 2]`: seven cells on rows 0, 2 and 4 of one
/// band of the shared map, so row 9 is open water for every player.
List<ShipPlacement> _fleetAt(int columnOffset) => <ShipPlacement>[
  for (final (int index, int length) in FleetPreset.small.shipLengths.indexed)
    ShipPlacement(
      shipId: 'ship-${index + 1}',
      length: length,
      orientation: ShipOrientation.horizontal,
      row: index * 2,
      column: columnOffset,
    ),
];

const int _bandSpacing = 5;

class _Fixture {
  _Fixture({List<String> opponents = const <String>['alice']}) {
    coordinator = RoomCoordinator(clock: () => now)..attach(transport);
    coordinator.createRoom(
      hostDisplayName: 'Host',
      avatarId: 'host',
      deviceId: 'host-device',
      config: RoomConfig.defaults.copyWith(
        columns: 14,
        fleetPreset: FleetPreset.small,
      ),
      tcpPort: 41234,
    );
    for (final String id in opponents) {
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
    final List<String> order = <String>[...opponents, host];
    final Map<String, List<ShipPlacement>> fleets =
        <String, List<ShipPlacement>>{
          for (final (int index, String id) in order.indexed)
            id: _fleetAt(index * _bandSpacing),
        };
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
    coordinator.hostMatchResults.listen(results.add);
    coordinator.hostMatchSnapshots.listen(snapshots.add);
  }

  DateTime now = DateTime.utc(2026, 1, 1, 12);
  Duration step = Duration.zero;
  final _Transport transport = _Transport();
  late final RoomCoordinator coordinator;
  final Map<String, ClientSession> sessions = <String, ClientSession>{};
  final List<MatchResult> results = <MatchResult>[];
  final List<MatchSnapshot> snapshots = <MatchSnapshot>[];
  int request = 0;

  HostRoomState get room => coordinator.state!;
  HostMatchState get match => room.match!;
  String get host => room.hostPlayerId;

  /// The first column of the fleet of the player on the shared map.
  int band(String playerId) => match.turnOrder.indexOf(playerId) * _bandSpacing;

  Future<void> shoot(String attacker, {int row = 0, int column = 0}) async {
    now = now.add(step);
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
      return;
    }
    final ProtocolMessage command = ProtocolMessage(
      messageType: ClientMessageType.fire,
      requestId: 'fire-${++request}',
      roomId: room.roomId,
      expectedStateVersion: room.stateVersion,
      payload: <String, dynamic>{
        'matchId': match.matchId,
        'turnNumber': match.turnNumber,
        'row': row,
        'column': column,
      },
    );
    await coordinator.handleMessage(sessions[attacker]!, command);
    expect(transport.of(attacker, HostEventType.error), isEmpty);
  }

  Future<void> timeout() async {
    now = match.turnDeadline!;
    await coordinator.checkTurnDeadline();
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Sinks the whole fleet of the target while the other players miss into
  /// the water, so nobody is eliminated by accident.
  Future<void> sink(String target) async {
    final List<CellCoord> cells = _fleetAt(band(target))
        .expand((ShipPlacement ship) => ship.cells)
        .toList();
    int hit = 0;
    int water = 0;
    while (match.isAlive(target)) {
      final String attacker = match.activePlayerId;
      if (attacker == target) {
        await shoot(attacker, row: 9, column: water++);
      } else {
        final CellCoord cell = cells[hit++];
        await shoot(attacker, row: cell.row, column: cell.column);
      }
    }
  }

  Future<MatchResult> resultOf(String playerId) async {
    await settle();
    final List<ProtocolMessage> messages = transport.of(
      playerId,
      HostEventType.finished,
    );
    expect(messages, hasLength(1));
    return MatchResult.fromJson(messages.single.payload);
  }
}

void main() {
  late _Fixture f;
  setUp(() {
    f = _Fixture();
  });
  tearDown(() => f.coordinator.dispose());

  test(
    'the winner, the ranking, the statistics and the duration are Host truth',
    () async {
      f.step = const Duration(seconds: 20);
      await f.sink('alice');

      expect(f.room.status, RoomStatus.finished);
      await f.settle();
      expect(f.results, hasLength(1));
      final MatchResult result = f.results.single;

      expect(result.matchId, 'match-1');
      expect(result.stateVersion, f.room.stateVersion);
      expect(result.winnerPlayerId, f.host);
      expect(result.winnerDisplayName, 'Host');
      // Fourteen accepted shots, twenty seconds apart.
      expect(result.durationSeconds, 280);
      expect(
        result.ranking
            .map((PlayerResultView entry) => (entry.rank, entry.playerId))
            .toList(),
        <(int, String)>[(1, f.host), (2, 'alice')],
      );

      final PlayerResultView winner = result.standingOf(f.host)!;
      expect(winner.displayName, 'Host');
      expect(winner.shots, 7);
      expect(winner.hits, 7);
      expect(winner.misses, 0);
      expect(winner.shipsSunk, 3);
      expect(winner.timeouts, 0);

      final PlayerResultView loser = result.standingOf('alice')!;
      expect(loser.shots, 7);
      expect(loser.hits, 0);
      expect(loser.misses, 7);
      expect(loser.shipsSunk, 0);
      expect(loser.shots, loser.hits + loser.misses);
    },
  );

  test('every client receives a byte-identical result', () async {
    await f.coordinator.dispose();
    f = _Fixture(opponents: <String>['alice', 'bob']);
    await f.sink('bob');
    await f.sink('alice');

    expect(f.room.status, RoomStatus.finished);
    await f.settle();
    final MatchResult hostResult = f.results.single;
    final MatchResult aliceResult = await f.resultOf('alice');
    final MatchResult bobResult = await f.resultOf('bob');

    expect(aliceResult.toJson(), hostResult.toJson());
    expect(bobResult.toJson(), hostResult.toJson());
  });

  test(
    'the ranking is the reverse elimination order behind the winner',
    () async {
      await f.coordinator.dispose();
      f = _Fixture(opponents: <String>['alice', 'bob']);
      await f.sink('bob');
      expect(f.match.eliminationOrder, <String>['bob']);
      await f.sink('alice');

      expect(f.match.eliminationOrder, <String>['bob', 'alice']);
      expect(f.match.eliminated, <String>{'bob', 'alice'});
      await f.settle();
      final MatchResult result = f.results.single;

      expect(result.winnerPlayerId, f.host);
      expect(
        result.ranking
            .map((PlayerResultView entry) => (entry.rank, entry.playerId))
            .toList(),
        <(int, String)>[(1, f.host), (2, 'alice'), (3, 'bob')],
      );
      expect(
        result.ranking.map((PlayerResultView e) => e.playerId).toSet().length,
        3,
      );
      // Bob sank nothing and hit nothing: every one of his shots was water.
      final PlayerResultView bob = result.standingOf('bob')!;
      expect(bob.hits, 0);
      expect(bob.shipsSunk, 0);
      expect(bob.shots, bob.misses);
      // Between them the two survivors sank all six opposing ships.
      expect(
        result.ranking.fold(
          0,
          (int sum, PlayerResultView e) => sum + e.shipsSunk,
        ),
        6,
      );
      expect(result.standingOf(f.host)!.shipsSunk, 3);
      expect(result.standingOf('alice')!.shipsSunk, 3);
    },
  );

  test(
    'timeouts are reported per player and a timeout never eliminates',
    () async {
      expect(f.match.activePlayerId, 'alice');
      await f.timeout();
      expect(f.match.isAlive('alice'), isTrue);
      expect(f.match.timeouts['alice'], 1);
      expect(f.match.activePlayerId, f.host);

      await f.sink('alice');
      await f.settle();
      final MatchResult result = f.results.single;

      expect(result.standingOf('alice')!.timeouts, 1);
      expect(result.standingOf(f.host)!.timeouts, 0);
      // The skipped turn fired no shot, so it is absent from the statistics.
      expect(result.standingOf('alice')!.shots, 6);
    },
  );

  test(
    'a rejected shot changes no statistic and broadcasts no result',
    () async {
      await f.shoot('alice', row: 9, column: 9);
      await f.shoot(f.host, row: 0, column: f.band('alice'));
      final Map<String, Map<String, int>> before = _statsOf(f);
      final int version = f.room.stateVersion;

      // Alice owns the turn again and repeats a cell she already fired at.
      final ProtocolMessage repeated = ProtocolMessage(
        messageType: ClientMessageType.fire,
        requestId: 'repeated',
        roomId: f.room.roomId,
        expectedStateVersion: version,
        payload: <String, dynamic>{
          'matchId': f.match.matchId,
          'turnNumber': f.match.turnNumber,
          'row': 9,
          'column': 9,
        },
      );
      await f.coordinator.handleMessage(f.sessions['alice']!, repeated);

      expect(
        f.transport.of('alice', HostEventType.error).last.payload['code'],
        ProtocolErrorCode.cellAlreadyFiredAt,
      );
      expect(f.room.stateVersion, version);
      expect(_statsOf(f), before);
      await f.settle();
      expect(f.results, isEmpty);
      expect(f.transport.of('alice', HostEventType.finished), isEmpty);
    },
  );

  test('an eliminated player is skipped and cannot fire', () async {
    await f.coordinator.dispose();
    f = _Fixture(opponents: <String>['alice', 'bob']);
    await f.sink('bob');

    expect(f.match.isAlive('bob'), isFalse);
    final int version = f.room.stateVersion;
    final ProtocolMessage command = ProtocolMessage(
      messageType: ClientMessageType.fire,
      requestId: 'ghost',
      roomId: f.room.roomId,
      expectedStateVersion: version,
      payload: <String, dynamic>{
        'matchId': f.match.matchId,
        'turnNumber': f.match.turnNumber,
        'row': 0,
        'column': 0,
      },
    );
    await f.coordinator.handleMessage(f.sessions['bob']!, command);

    expect(
      f.transport.of('bob', HostEventType.error).last.payload['code'],
      ProtocolErrorCode.notYourTurn,
    );
    expect(f.room.stateVersion, version);
    expect(f.match.eliminationOrder, <String>['bob']);
  });

  test('the remaining fleet count is public aggregate status only', () async {
    await f.coordinator.dispose();
    f = _Fixture(opponents: <String>['alice', 'bob']);
    // Sink the first ship of bob: three cells, shared between two attackers.
    await f.shoot('alice', row: 0, column: f.band('bob'));
    await f.shoot('bob', row: 9, column: 0);
    await f.shoot(f.host, row: 0, column: f.band('bob') + 1);
    await f.shoot('alice', row: 0, column: f.band('bob') + 2);

    await f.settle();
    for (final String viewer in f.match.turnOrder) {
      final MatchSnapshot snapshot = viewer == f.host
          ? f.snapshots.last
          : MatchSnapshot.fromJson(
              f.transport
                      .of(viewer, HostEventType.stateSnapshot)
                      .last
                      .payload['snapshot']
                  as Map<String, dynamic>,
            );
      expect(snapshot.playerById('bob')!.shipsRemaining, 2);
      expect(snapshot.playerById('alice')!.shipsRemaining, 3);
      expect(snapshot.playerById(f.host)!.shipsRemaining, 3);
      // The aggregate count never travels with a position or a ship layout.
      expect(snapshot.playerById('bob')!.toJson().keys.toSet(), <String>{
        'playerId',
        'displayName',
        'alive',
        'timeouts',
        'shipsRemaining',
      });
    }
  });
}

/// A comparable snapshot of the Host statistics.
Map<String, Map<String, int>> _statsOf(
  _Fixture f,
) => <String, Map<String, int>>{
  for (final MapEntry<String, PlayerMatchStats> entry in f.match.stats.entries)
    entry.key: <String, int>{
      'shots': entry.value.shots,
      'hits': entry.value.hits,
      'misses': entry.value.misses,
      'shipsSunk': entry.value.shipsSunk,
    },
};
