import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/host_runtime/client_connection_registry.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';
import 'package:upfleet_arena/shared/protocol/protocol_constants.dart';
import 'package:upfleet_arena/shared/protocol/protocol_message.dart';

/// Lets the pending zero-delay bot turn and its queued commands run.
Future<void> _settle() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

CellCoord? _firstUnfiredCell(
  HostMatchState match,
  String attackerId,
  RoomConfig config,
) {
  for (int row = 0; row < config.rows; row++) {
    for (int column = 0; column < config.columns; column++) {
      final CellCoord cell = CellCoord(row, column);
      if (!match.hasFiredAt(attackerId, cell)) return cell;
    }
  }
  return null;
}

void main() {
  group('practice room', () {
    late RoomCoordinator coordinator;
    late HostRoomState room;

    setUp(() {
      coordinator = RoomCoordinator(
        botThinkingTime: Duration.zero,
        botRandom: Random(7),
      );
      coordinator.createRoom(
        hostDisplayName: 'Host',
        avatarId: '🦈',
        deviceId: 'host-device',
        config: RoomConfig.defaults,
        tcpPort: 0,
      );
      room = coordinator.state!;
    });

    tearDown(() => coordinator.dispose());

    Future<HostPlayer> seatBot({
      BotDifficulty difficulty = BotDifficulty.medium,
    }) async {
      expect(
        await coordinator.hostAddBot(
          displayName: 'Computer',
          difficulty: difficulty,
        ),
        isEmpty,
      );
      return room.players.values.singleWhere((HostPlayer p) => p.isBot);
    }

    test(
      'the bot is seated, shown as a computer and places its fleet',
      () async {
        final HostPlayer bot = await seatBot();
        expect(bot.isBot, isTrue);
        expect(bot.botDifficulty, BotDifficulty.medium);

        final RoomSnapshot view = coordinator.projections.buildFor(
          room,
          room.hostPlayerId,
        );
        expect(view.playerById(bot.playerId)!.isBot, isTrue);
        expect(view.connectedCount, 2);

        expect(await coordinator.hostStartPlacement(), isEmpty);
        expect(room.status, RoomStatus.placement);

        final HostPlayerPlacement placement = room.placements[bot.playerId]!;
        expect(placement.ready, isTrue);
        expect(
          placement.ships.length,
          RoomConfig.defaults.fleetPreset.shipCount,
        );
      },
    );

    test('a computer cannot be seated once the preparation started', () async {
      await seatBot();
      expect(await coordinator.hostStartPlacement(), isEmpty);
      expect(
        await coordinator.hostAddBot(
          displayName: 'Late',
          difficulty: BotDifficulty.hard,
        ),
        isNotEmpty,
      );
    });

    test('the bot plays its turns and the match can be finished', () async {
      final HostPlayer bot = await seatBot(difficulty: BotDifficulty.hard);
      expect(await coordinator.hostStartPlacement(), isEmpty);
      expect(await coordinator.hostAutoPlace(), isEmpty);
      expect(await coordinator.hostSetReady(), isEmpty);
      expect(room.status, RoomStatus.active);

      int guard = 0;
      while (room.status == RoomStatus.active && guard++ < 600) {
        await _settle();
        if (room.status != RoomStatus.active) break;
        final HostMatchState match = room.match!;
        // The Host only fires on its own turn; the bot fires itself.
        if (match.activePlayerId != room.hostPlayerId) continue;
        final CellCoord? cell = _firstUnfiredCell(
          match,
          room.hostPlayerId,
          room.config,
        );
        if (cell == null) break;
        expect(
          await coordinator.hostFire(
            matchId: match.matchId,
            turnNumber: match.turnNumber,
            expectedStateVersion: room.stateVersion,
            row: cell.row,
            column: cell.column,
          ),
          isEmpty,
        );
      }

      expect(room.status, RoomStatus.finished);
      expect(room.match!.winnerPlayerId, isNotNull);
      expect(room.match!.attackHistory[bot.playerId], isNotEmpty);
    });
  });

  group('mixed room', () {
    late RoomCoordinator coordinator;
    late HostRoomState room;

    setUp(() {
      coordinator = RoomCoordinator(botThinkingTime: Duration.zero);
      coordinator.createRoom(
        hostDisplayName: 'Host',
        avatarId: '🦈',
        deviceId: 'host-device',
        config: RoomConfig.defaults,
        tcpPort: 0,
      );
      room = coordinator.state!;
    });

    tearDown(() => coordinator.dispose());

    /// Seats a remote player and returns the connection it talks through.
    (HostPlayer, ClientSession) seatHuman(String name) {
      final HostPlayer player = HostPlayer(
        playerId: 'player-$name',
        displayName: name,
        avatarId: '🐙',
        role: PlayerRole.player,
        deviceId: '$name-device',
        joinedAt: DateTime.now(),
      );
      room.players[player.playerId] = player;
      final ClientSession session = ClientSession(
        connectionId: 'connection-$name',
        connectedAt: DateTime.now(),
      )..playerId = player.playerId;
      coordinator.registry.add(session);
      return (player, session);
    }

    /// Lets a client place and confirm a fleet through the real protocol.
    Future<void> clientReady(ClientSession session) async {
      await coordinator.handleMessage(
        session,
        const ProtocolMessage(messageType: ClientMessageType.placementAuto),
      );
      await coordinator.handleMessage(
        session,
        const ProtocolMessage(messageType: ClientMessageType.placementReady),
      );
    }

    test('a computer joins a room of people and plays the match', () async {
      seatHuman('Alice');
      expect(
        await coordinator.hostAddBot(
          displayName: 'Computer (Hard)',
          difficulty: BotDifficulty.hard,
        ),
        isEmpty,
      );
      final HostPlayer bot = room.players.values.singleWhere(
        (HostPlayer player) => player.isBot,
      );
      expect(room.seatedCount, 3);

      expect(await coordinator.hostStartPlacement(), isEmpty);
      expect(room.placements[bot.playerId]!.ready, isTrue);

      await clientReady(coordinator.registry.byPlayerId('player-Alice')!);
      expect(await coordinator.hostAutoPlace(), isEmpty);
      expect(await coordinator.hostSetReady(), isEmpty);

      expect(room.status, RoomStatus.active);
      expect(room.match!.turnOrder, hasLength(3));
      expect(room.match!.turnOrder, contains(bot.playerId));
      expect(
        room.match!.boards.keys,
        containsAll(<String>['player-Alice', bot.playerId]),
      );
    });

    test('two computers of the same strength get distinct names', () async {
      await coordinator.hostAddBot(
        displayName: 'Computer (Easy)',
        difficulty: BotDifficulty.easy,
      );
      await coordinator.hostAddBot(
        displayName: 'Computer (Easy)',
        difficulty: BotDifficulty.easy,
      );
      final List<String> names = room.players.values
          .where((HostPlayer player) => player.isBot)
          .map((HostPlayer player) => player.displayName)
          .toList();
      expect(names, hasLength(2));
      expect(names.toSet(), hasLength(2));
    });

    test('the host can remove a computer again', () async {
      await coordinator.hostAddBot(
        displayName: 'Computer (Medium)',
        difficulty: BotDifficulty.medium,
      );
      final HostPlayer bot = room.players.values.singleWhere(
        (HostPlayer player) => player.isBot,
      );
      expect(room.seatedCount, 2);

      await coordinator.hostKick(bot.playerId);
      expect(room.seatedCount, 1);
      expect(room.players[bot.playerId]!.status, PlayerConnectionStatus.kicked);
    });
  });
}
