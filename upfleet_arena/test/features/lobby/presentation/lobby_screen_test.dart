import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/lobby/presentation/lobby_screen.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// A session controller with a fixed room, so the lobby renders without Host.
class _FakeSessionController extends RoomSessionController {
  _FakeSessionController({required this.session});

  final RoomSessionState session;
  String? addedName;
  BotDifficulty? addedDifficulty;
  String? kickedPlayerId;

  @override
  RoomSessionState build() => session;

  @override
  Future<List<String>> addBot({
    required String displayName,
    required BotDifficulty difficulty,
  }) async {
    addedName = displayName;
    addedDifficulty = difficulty;
    return const <String>[];
  }

  @override
  Future<void> kick(String playerId) async {
    kickedPlayerId = playerId;
  }
}

const RoomConfig _config = RoomConfig.defaults;

const PlayerSummary _host = PlayerSummary(
  playerId: 'host-1',
  displayName: 'Host',
  avatarId: '🦈',
  role: PlayerRole.host,
  status: PlayerConnectionStatus.connected,
);

const PlayerSummary _guest = PlayerSummary(
  playerId: 'player-2',
  displayName: 'Guest',
  avatarId: '🐙',
  role: PlayerRole.player,
  status: PlayerConnectionStatus.connected,
);

const PlayerSummary _computer = PlayerSummary(
  playerId: 'bot-1',
  displayName: 'Computer (Medium)',
  avatarId: '🤖',
  role: PlayerRole.player,
  status: PlayerConnectionStatus.connected,
  isBot: true,
);

RoomSnapshot _snapshot({
  required bool viewerIsHost,
  List<PlayerSummary> players = const <PlayerSummary>[_host, _guest],
}) => RoomSnapshot(
  roomId: 'room-1',
  status: RoomStatus.lobby,
  config: _config,
  players: players,
  viewerPlayerId: viewerIsHost ? 'host-1' : 'player-2',
  viewerIsHost: viewerIsHost,
  stateVersion: 3,
);

RoomSessionState _session({
  bool host = true,
  List<PlayerSummary> players = const <PlayerSummary>[_host, _guest],
}) => RoomSessionState(
  role: host ? RoomRole.host : RoomRole.client,
  status: RoomSessionStatus.inRoom,
  snapshot: _snapshot(viewerIsHost: host, players: players),
  playerId: host ? 'host-1' : 'player-2',
  inviteCode: host ? 'ABC234' : null,
  hostPort: 41234,
);

Widget _app(RoomSessionController controller) => ProviderScope(
  overrides: [roomSessionControllerProvider.overrideWith(() => controller)],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('vi'),
    home: const LobbyScreen(),
  ),
);

void main() {
  setUp(() {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1200,
      3000,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  testWidgets('the host can add a computer', (WidgetTester tester) async {
    final _FakeSessionController host = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(host));
    await tester.pump();

    expect(find.text('Thêm đối thủ máy'), findsOneWidget);
    expect(find.text('Thêm máy'), findsOneWidget);
  });

  testWidgets('a regular player cannot add a computer', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController guest = _FakeSessionController(
      session: _session(host: false),
    );
    await tester.pumpWidget(_app(guest));
    await tester.pump();

    expect(find.text('Thêm đối thủ máy'), findsNothing);
    expect(find.text('Thêm máy'), findsNothing);
  });

  testWidgets('a computer in the room is labelled as one', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(players: <PlayerSummary>[_host, _guest, _computer]),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.text('Computer (Medium)'), findsOneWidget);
    expect(find.text('Máy'), findsOneWidget);
  });

  testWidgets('adding a computer sends the chosen difficulty', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.text('Thêm máy'));
    await tester.pumpAndSettle();

    expect(find.text('Thêm đối thủ máy'), findsWidgets);
    await tester.tap(find.text('Khó'));
    await tester.pump();

    // The dialog's confirm button is the filled one; the card uses outlined.
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm máy'));
    await tester.pumpAndSettle();

    expect(controller.addedDifficulty, BotDifficulty.hard);
    expect(controller.addedName, 'Máy (Khó)');
  });
}
