import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// Lets the pending zero-delay bot turn and its queued commands run.
Future<void> _settle() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

CellCoord? _firstUnfiredCell(
  HostMatchState match,
  String attackerId,
  String targetId,
  RoomConfig config,
) {
  final Map<CellCoord, ShotResult> fired =
      match.attackHistory[attackerId]?[targetId] ??
      const <CellCoord, ShotResult>{};
  for (int row = 0; row < config.rows; row++) {
    for (int column = 0; column < config.columns; column++) {
      final CellCoord cell = CellCoord(row, column);
      if (!fired.containsKey(cell)) return cell;
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
          bot.playerId,
          room.config,
        );
        if (cell == null) break;
        expect(
          await coordinator.hostFire(
            matchId: match.matchId,
            turnNumber: match.turnNumber,
            expectedStateVersion: room.stateVersion,
            targetPlayerId: bot.playerId,
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
}
