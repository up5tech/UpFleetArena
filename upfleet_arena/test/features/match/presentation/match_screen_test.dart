import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/app/theme/app_theme.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/services/match_feedback.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/match/presentation/match_screen.dart';
import 'package:upfleet_arena/features/match/widgets/battle_board.dart';
import 'package:upfleet_arena/features/match/widgets/spectator_view.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';
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
  int turnSeconds = 22,
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
  turnCountdown: Countdown(remainingSeconds: turnSeconds),
);

/// A sound player that records nothing and touches no audio backend, so the
/// screen tests run without platform channels.
class _NoopSoundPlayer implements SoundPlayer {
  @override
  Future<void> play(GameSound sound) async {}

  @override
  Future<void> dispose() async {}
}

late SharedPreferences _testPreferences;

Widget _app(_FakeSessionController controller) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(() => controller),
      localPreferencesProvider.overrideWithValue(
        LocalPreferences.withInstance(_testPreferences),
      ),
      soundPlayerProvider.overrideWithValue(_NoopSoundPlayer()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const MatchScreen(),
    ),
  );
}

void main() {
  setUp(() async {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1200,
      3000,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _testPreferences = await SharedPreferences.getInstance();
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
    expect(find.widgetWithText(ChoiceChip, 'Bob'), findsOneWidget);
    expect(find.byType(BattleBoard), findsOneWidget);
    // The own fleet shares the battle view instead of a second tab.
    expect(find.text('Your board'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Your fleet'), findsOneWidget);
    expect(find.byType(BoardCanvas), findsOneWidget);
  });

  testWidgets('a wide screen shows both fleets side by side', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));

    expect(find.text('Your fleet'), findsOneWidget);

    final Rect attack = tester.getRect(find.byType(BattleBoard));
    final Rect own = tester.getRect(find.byType(BoardCanvas));
    // The own fleet starts to the right of the attack board, not below it.
    expect(own.left, greaterThan(attack.right));
    expect(own.top, lessThan(attack.bottom));
  });

  testWidgets('a narrow screen stacks the own fleet below', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));
    await tester.pump();

    final Rect attack = tester.getRect(find.byType(BattleBoard));
    final Rect own = tester.getRect(find.byType(BoardCanvas));
    expect(own.top, greaterThan(attack.bottom));
  });

  testWidgets('firing sends the shot of the picked cell', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bob'));
    await tester.pump();

    final Rect board = tester.getRect(find.byType(BattleBoard));
    final double cell = board.width / RoomConfig.defaults.columns;
    // Tap the middle of the cell, not its edge.
    await tester.tapAt(
      Offset(board.left + cell * 4.5, board.top + cell * 4.5),
    );
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

  testWidgets('a wide screen lists the players beside the boards', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    // No tabs on a wide screen: the roster is part of the same scroll.
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Players'), findsNothing);
    expect(find.text('Turn order'), findsOneWidget);
    expect(find.text('Alice (you)'), findsOneWidget);
    expect(find.text('1 timeouts'), findsOneWidget);
    expect(find.byTooltip('In the match'), findsNWidgets(2));
    expect(find.text('3 ships left'), findsOneWidget);

    // Only the player whose turn it is carries the countdown.
    expect(find.text('22s'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('22s')).style?.color,
      AppTheme.accent,
    );
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Alice (you)'), matching: find.byType(Row))
            .first,
        matching: find.text('22s'),
      ),
      findsOneWidget,
    );

    // One line per player keeps the column short next to the boards.
    final Size row = tester.getSize(
      find
          .ancestor(of: find.text('Alice (you)'), matching: find.byType(Row))
          .first,
    );
    expect(row.height, lessThan(34));

    // The roster sits in the second column, beside the attack board.
    final Rect attack = tester.getRect(find.byType(BattleBoard));
    final Rect roster = tester.getRect(find.text('Turn order'));
    expect(roster.left, greaterThan(attack.right));
  });

  testWidgets('a turn that is nearly over warns in the player list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(turnSeconds: 4))),
    );

    final Text clock = tester.widget<Text>(find.text('4s'));
    expect(clock.style?.color, AppTheme.danger);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
  });

  testWidgets('a narrow screen keeps the players in a tab', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session())),
    );
    await tester.pump();

    expect(find.byType(TabBar), findsOneWidget);
    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();

    expect(find.text('Alice (you)'), findsOneWidget);
    expect(find.text('1 timeouts'), findsOneWidget);
  });

  testWidgets('an eliminated player spectates instead of fighting', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(myTurn: false, eliminated: true),
    );
    await tester.pumpWidget(_app(controller));

    // Wide screen: the spectator view replaces the battle view, with no tabs.
    expect(find.byType(TabBar), findsNothing);
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

    // The sunk fleet is still there, below the spectator feed.
    await tester.dragUntilVisible(
      find.text('Your fleet'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
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
          localPreferencesProvider.overrideWithValue(
            LocalPreferences.withInstance(_testPreferences),
          ),
          soundPlayerProvider.overrideWithValue(_NoopSoundPlayer()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
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
