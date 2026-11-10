import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/host_runtime/client_connection_registry.dart';
import 'package:upfleet_arena/host_runtime/room_coordinator.dart';
import 'package:upfleet_arena/host_runtime/room_state.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

void main() {
  group('preset computers', () {
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

    List<HostPlayer> seatedBots() => room.players.values
        .where((HostPlayer player) => player.isBot && player.occupiesSeat)
        .toList();

    /// Seats a remote player the way the admission rules would.
    void seatHuman(String name) {
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
    }

    Future<List<String>> preset(int count, BotDifficulty difficulty) =>
        coordinator.hostUpdateConfig(
          room.config.copyWith(botCount: count, botDifficulty: difficulty),
        );

    test('saving a preset seats the computers', () async {
      expect(await preset(2, BotDifficulty.hard), isEmpty);

      final List<HostPlayer> bots = seatedBots();
      expect(bots, hasLength(2));
      expect(
        bots.every((HostPlayer bot) => bot.botDifficulty == BotDifficulty.hard),
        isTrue,
      );
      expect(
        bots.map((HostPlayer bot) => bot.displayName).toSet(),
        hasLength(2),
      );
      expect(room.config.botCount, 2);
    });

    test('the preset follows the count up and down', () async {
      await preset(2, BotDifficulty.medium);
      expect(room.seatedCount, 3);

      await preset(1, BotDifficulty.medium);
      expect(seatedBots(), hasLength(1));
      expect(room.seatedCount, 2);

      await preset(3, BotDifficulty.medium);
      expect(seatedBots(), hasLength(3));
      expect(room.seatedCount, 4);
    });

    test('changing the strength swaps the computers', () async {
      await preset(2, BotDifficulty.easy);
      final List<String> before = seatedBots()
          .map((HostPlayer bot) => bot.playerId)
          .toList();

      await preset(2, BotDifficulty.hard);

      final List<HostPlayer> after = seatedBots();
      expect(after, hasLength(2));
      expect(
        after.every(
          (HostPlayer bot) => bot.botDifficulty == BotDifficulty.hard,
        ),
        isTrue,
      );
      expect(
        after.map((HostPlayer bot) => bot.playerId),
        isNot(contains(anyOf(before))),
      );
    });

    test('a room filled by the preset can play a match', () async {
      await preset(1, BotDifficulty.medium);

      expect(await coordinator.hostStartPlacement(), isEmpty);
      final HostPlayer bot = seatedBots().single;
      expect(room.placements[bot.playerId]!.ready, isTrue);

      expect(await coordinator.hostAutoPlace(), isEmpty);
      expect(await coordinator.hostSetReady(), isEmpty);

      expect(room.status, RoomStatus.active);
      expect(room.match!.turnOrder, hasLength(2));
      expect(room.match!.turnOrder, contains(bot.playerId));
    });

    test('a computer never takes the host seat', () async {
      final List<String> problems = await preset(
        RoomConfig.defaults.maxPlayers,
        BotDifficulty.easy,
      );

      expect(problems, isNotEmpty);
      expect(room.config.botCount, 0);
      expect(seatedBots(), isEmpty);
    });

    test('a full room of people leaves no seat for a computer', () async {
      for (int index = 0; index < 5; index++) {
        seatHuman('Player$index');
      }
      expect(room.seatedCount, RoomConfig.defaults.maxPlayers);

      final List<String> problems = await preset(1, BotDifficulty.easy);

      expect(problems.join(' '), contains('no free seat'));
      expect(room.config.botCount, 0);
      expect(seatedBots(), isEmpty);
    });

    test('removing a computer lowers the preset', () async {
      await preset(2, BotDifficulty.medium);
      final HostPlayer bot = seatedBots().first;

      await coordinator.hostKick(bot.playerId);

      expect(room.config.botCount, 1);
      expect(seatedBots(), hasLength(1));
    });

    test('adding a computer by hand is part of the preset', () async {
      expect(
        await coordinator.hostAddBot(
          displayName: 'Computer (Hard)',
          difficulty: BotDifficulty.hard,
        ),
        isEmpty,
      );
      expect(room.config.botCount, 1);

      // Saving the settings again keeps the seat instead of dropping it.
      expect(await preset(1, BotDifficulty.hard), isEmpty);
      expect(seatedBots(), hasLength(1));
    });

    test('the preset computers travel with the room settings', () {
      const RoomConfig config = RoomConfig(
        botCount: 2,
        botDifficulty: BotDifficulty.hard,
        maxPlayers: 4,
      );

      final RoomConfig decoded = RoomConfig.fromJson(config.toJson());

      expect(decoded.botCount, 2);
      expect(decoded.botDifficulty, BotDifficulty.hard);
      expect(decoded.validate(), isEmpty);
    });

    test('a configuration without computers still parses', () {
      final Map<String, dynamic> json = RoomConfig.defaults.toJson()
        ..remove('botCount')
        ..remove('botDifficulty');

      final RoomConfig decoded = RoomConfig.fromJson(json);

      expect(decoded.botCount, 0);
      expect(decoded.botDifficulty, BotDifficulty.medium);
    });
  });
}
