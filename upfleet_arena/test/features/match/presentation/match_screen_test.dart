import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/features/match/presentation/match_screen.dart';
import 'package:upfleet_arena/features/match/widgets/battle_board.dart';
import 'package:upfleet_arena/features/match/widgets/spectator_view.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';
import 'package:upfleet_arena/shared/widgets/board_canvas.dart';

/// A session controller with a fixed state, so the screen can be rendered
/// without a running match.
class _FakeSessionController extends RoomSessionController {
  _FakeSessionController({required this.session});

  final RoomSessionState session;
  final List<(String, int, int)> shots = <(String, int, int)>[];

  @override
  RoomSessionState build() => session;

  @override
  Future<void> fire({
    required String targetPlayerId,
    required int row,
    required int column,
  }) async {
    shots.add((targetPlayerId, row, column));
  }
}

MatchSnapshot _snapshot({bool myTurn = true, bool eliminated = false}) =>
    MatchSnapshot(
      matchId: 'match-1',
      stateVersion: 9,
      turnNumber: 3,
      activePlayerId: myTurn ? 'player-1' : 'player-2',
      turnRemainingSeconds: 22,
      players: <MatchPlayerView>[
        MatchPlayerView(
          playerId: 'player-1',
          displayName: 'Alice',
          alive: !eliminated,
          timeouts: 0,
          shipsRemaining: eliminated ? 0 : 1,
        ),
        const MatchPlayerView(
          playerId: 'player-2',
          displayName: 'Bob',
          alive: true,
          timeouts: 1,
          shipsRemaining: 3,
        ),
        if (eliminated)
          const MatchPlayerView(
            playerId: 'player-3',
            displayName: 'Carol',
            alive: true,
            timeouts: 0,
            shipsRemaining: 4,
          ),
      ],
      ownBoard: const OwnBoardView(
        ships: <ShipView>[
          ShipView(
            shipId: 'ship-1',
            length: 4,
            orientation: ShipOrientation.horizontal,
            row: 0,
            column: 0,
            hitCells: <CellCoord>[CellCoord(0, 1)],
            sunk: false,
          ),
        ],
        shotsReceived: <CellCoord>[CellCoord(0, 1)],
      ),
      targets: <TargetBoardView>[
        const TargetBoardView(
          playerId: 'player-2',
          displayName: 'Bob',
          alive: true,
          shots: <ShotView>[
            ShotView(row: 2, column: 3, result: ShotResult.miss),
          ],
        ),
        if (eliminated)
          const TargetBoardView(
            playerId: 'player-3',
            displayName: 'Carol',
            alive: true,
            shots: <ShotView>[],
          ),
      ],
    );

RoomSessionState _session({
  bool myTurn = true,
  ShotFeedback? feedback,
  bool eliminated = false,
  List<PublicActivity> activityFeed = const <PublicActivity>[],
  MatchResult? matchResult,
}) => RoomSessionState(
  role: RoomRole.client,
  status: RoomSessionStatus.inRoom,
  snapshot: const RoomSnapshot(
    roomId: 'room-1',
    status: RoomStatus.active,
    config: RoomConfig.defaults,
    players: <PlayerSummary>[],
    viewerPlayerId: 'player-1',
    viewerIsHost: false,
    stateVersion: 9,
  ),
  playerId: 'player-1',
  matchSnapshot: _snapshot(myTurn: myTurn, eliminated: eliminated),
  lastShot: feedback,
  activityFeed: activityFeed,
  matchResult: matchResult,
  turnCountdown: Countdown(remainingSeconds: 22),
);

Widget _app(_FakeSessionController controller) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(() => controller),
    ],
    child: const MaterialApp(home: MatchScreen()),
  );
}

void main() {
  setUp(() {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1200, 3000);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  testWidgets('the turn and the target are shown', (WidgetTester tester) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Turn 3 · 22s left'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byType(BattleBoard), findsOneWidget);
  });

  testWidgets('firing sends the shot of the picked cell', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('Bob'));
    await tester.pump();

    final Rect board = tester.getRect(find.byType(BattleBoard));
    final double cell = board.width / RoomConfig.defaults.columns;
    await tester.tapAt(Offset(board.left + cell * 4, board.top + cell * 4));
    await tester.pump();

    await tester.tap(find.text('Fire at this cell'));
    await tester.pump();

    expect(controller.shots, hasLength(1));
    expect(controller.shots.single.$1, 'player-2');
    expect(controller.shots.single.$2, 4);
    expect(controller.shots.single.$3, 4);
  });

  testWidgets('a player who is not active cannot fire', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(myTurn: false),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('Bob is shooting'), findsOneWidget);

    final FilledButton fire = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Wait for your turn'),
    );
    expect(fire.onPressed, isNull);
  });

  testWidgets('the result of a shot is shown', (WidgetTester tester) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(
        feedback: const ShotFeedback(
          attackerPlayerId: 'player-1',
          targetPlayerId: 'player-2',
          row: 1,
          column: 1,
          result: ShotResult.hit,
        ),
      ),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('Your shot hit a ship.'), findsOneWidget);
  });

  testWidgets('the players tab shows the turn order and the timeouts', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();

    expect(find.text('Alice (you)'), findsOneWidget);
    expect(find.text('1 timeouts'), findsOneWidget);
    expect(find.text('In the match'), findsNWidgets(2));
    expect(find.text('3 ships left'), findsOneWidget);
  });

  testWidgets('an eliminated player spectates instead of fighting', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(myTurn: false, eliminated: true),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('Spectating'), findsOneWidget);
    expect(find.text('Battle'), findsNothing);
    expect(find.byType(SpectatorView), findsOneWidget);
    expect(find.byType(BattleBoard), findsNothing);
    expect(find.text('Your fleet was sunk.'), findsOneWidget);
    expect(
      find.text('You are watching the rest of the match. You cannot fire.'),
      findsOneWidget,
    );
    expect(find.text('Bob is shooting'), findsOneWidget);
    expect(find.text('Turn 3 · 22s left'), findsOneWidget);
    expect(find.text('Fire at this cell'), findsNothing);
    expect(find.text('Wait for your turn'), findsNothing);
    expect(controller.shots, isEmpty);
  });

  testWidgets('the spectator roster lists only the living players', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(myTurn: false, eliminated: true),
        ),
      ),
    );

    expect(find.text('Still in the match'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('3 ships left'), findsOneWidget);
    expect(find.text('4 ships left'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('the spectator feed describes public shots without coordinates', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(
            myTurn: false,
            eliminated: true,
            activityFeed: const <PublicActivity>[
              PublicActivity(
                attackerPlayerId: 'player-2',
                targetPlayerId: 'player-3',
                result: ShotResult.miss,
              ),
              PublicActivity(
                attackerPlayerId: 'player-3',
                targetPlayerId: 'player-2',
                result: ShotResult.shipSunk,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Bob missed Carol.'), findsOneWidget);
    expect(find.text('Carol sank a ship of Bob.'), findsOneWidget);
    expect(find.textContaining('C4'), findsNothing);
    expect(find.textContaining('row'), findsNothing);
  });

  testWidgets('an empty feed is explained', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(myTurn: false, eliminated: true),
        ),
      ),
    );

    expect(find.text('No public shots yet.'), findsOneWidget);
  });

  testWidgets('the own board stays available to a spectator', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(myTurn: false, eliminated: true),
        ),
      ),
    );

    await tester.tap(find.text('Your board'));
    await tester.pumpAndSettle();

    expect(find.text('Your fleet'), findsOneWidget);
    expect(find.byType(BoardCanvas), findsOneWidget);
  });

  testWidgets('the final result opens the result screen', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomSessionControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/match',
            routes: <RouteBase>[
              GoRoute(
                path: '/match',
                builder: (BuildContext context, GoRouterState state) =>
                    const MatchScreen(),
              ),
              GoRoute(
                path: '/match/result',
                builder: (BuildContext context, GoRouterState state) =>
                    const Scaffold(body: Center(child: Text('Result screen'))),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Your turn'), findsOneWidget);

    controller.state = controller.state.copyWith(
      matchResult: const MatchResult(
        matchId: 'match-1',
        stateVersion: 10,
        winnerPlayerId: 'player-1',
        winnerDisplayName: 'Alice',
        durationSeconds: 47,
        ranking: <PlayerResultView>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Result screen'), findsOneWidget);
    expect(find.text('Your turn'), findsNothing);
  });
}
