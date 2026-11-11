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
import 'package:upfleet_arena/features/match/widgets/shooter_colors.dart';
import 'package:upfleet_arena/features/match/widgets/shooter_dot.dart';
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
  final List<(int, int)> shots = <(int, int)>[];

  @override
  RoomSessionState build() => session;

  @override
  Future<void> fire({required int row, required int column}) async {
    shots.add((row, column));
  }
}

MatchSnapshot _snapshot({
  bool myTurn = true,
  bool eliminated = false,
  bool thirdPlayer = false,
  bool viewerFired = true,
  List<SunkShipView> sunkShips = const <SunkShipView>[],
}) => MatchSnapshot(
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
    if (eliminated || thirdPlayer)
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
    // The hit on the own fleet, with the player who fired it.
    receivedShots: <ShotView>[
      ShotView(
        row: 0,
        column: 1,
        result: ShotResult.hit,
        attackerPlayerId: 'player-2',
      ),
    ],
  ),
  // One map for the whole room: the own fleet and the fire of everybody.
  mapShots: <ShotView>[
    // The hit on the viewer's fleet, by the player who fired it.
    const ShotView(
      row: 0,
      column: 1,
      result: ShotResult.hit,
      attackerPlayerId: 'player-2',
    ),
    // The viewer's own earlier shot, which makes the how-to hint stale.
    if (viewerFired)
      const ShotView(
        row: 2,
        column: 3,
        result: ShotResult.miss,
        attackerPlayerId: 'player-1',
      ),
    const ShotView(
      row: 5,
      column: 5,
      result: ShotResult.hit,
      attackerPlayerId: 'player-3',
    ),
    // A miss by another player stays out of the map view.
    const ShotView(
      row: 7,
      column: 7,
      result: ShotResult.miss,
      attackerPlayerId: 'player-2',
    ),
  ],
  sunkShips: sunkShips,
);

RoomSessionState _session({
  bool myTurn = true,
  ShotFeedback? feedback,
  bool eliminated = false,
  bool thirdPlayer = false,
  bool viewerFired = true,
  List<PublicActivity> activityFeed = const <PublicActivity>[],
  MatchResult? matchResult,
  int turnSeconds = 22,
  List<SunkShipView> sunkShips = const <SunkShipView>[],
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
  matchSnapshot: _snapshot(
    myTurn: myTurn,
    eliminated: eliminated,
    thirdPlayer: thirdPlayer,
    viewerFired: viewerFired,
    sunkShips: sunkShips,
  ),
  lastShot: feedback,
  activityFeed: activityFeed,
  matchResult: matchResult,
  turnCountdown: Countdown(remainingSeconds: turnSeconds),
);

/// A sound player that records what would play, without any audio backend.
class _RecordingSoundPlayer implements SoundPlayer {
  final List<GameSound> played = <GameSound>[];

  @override
  Future<void> play(GameSound sound) async => played.add(sound);

  @override
  Future<void> dispose() async {}
}

/// A sound player that records nothing and touches no audio backend, so the
/// screen tests run without platform channels.
class _NoopSoundPlayer implements SoundPlayer {
  @override
  Future<void> play(GameSound sound) async {}

  @override
  Future<void> dispose() async {}
}

late SharedPreferences _testPreferences;

/// Double-taps a point, two taps inside the double-tap window.
Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _app(_FakeSessionController controller, {SoundPlayer? sounds}) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(() => controller),
      localPreferencesProvider.overrideWithValue(
        LocalPreferences.withInstance(_testPreferences),
      ),
      soundPlayerProvider.overrideWithValue(sounds ?? _NoopSoundPlayer()),
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

  testWidgets('the turn and the shared map are shown', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Turn 3 · 22s left'), findsOneWidget);
    expect(find.text('Shared map'), findsOneWidget);
    expect(find.byType(BattleBoard), findsOneWidget);
    // The own fleet is on the same map, not on a board of its own.
    expect(find.text('Your fleet'), findsNothing);
    expect(find.byType(BoardCanvas), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    // The map legend is three short glyphs, not a paragraph.
    expect(find.text('hit'), findsOneWidget);
    expect(find.text('sunk'), findsOneWidget);
    expect(find.text('your miss'), findsOneWidget);

    final BattleBoard board = tester.widget<BattleBoard>(
      find.byType(BattleBoard),
    );
    // The map carries the own fleet, every hit and only the own miss.
    expect(board.ships, hasLength(1));
    expect(board.ships.single.shipId, 'ship-1');
    expect(board.shots, hasLength(3));
    expect(
      board.shots.any(
        (ShotView shot) =>
            shot.result == ShotResult.miss &&
            shot.attackerPlayerId != 'player-1',
      ),
      isFalse,
    );
    expect(
      board.shots.map((ShotView shot) => shot.attackerPlayerId),
      containsAll(<String>['player-1', 'player-2', 'player-3']),
    );
    expect(
      board.shooterColors.keys,
      containsAll(<String>['player-1', 'player-2']),
    );
  });

  testWidgets('the shared map needs no target picker', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(thirdPlayer: true))),
    );

    // Every opponent is on the roster, but the map has no target to choose.
    expect(find.text('Bob'), findsWidgets);
    expect(find.text('Carol'), findsWidgets);
    expect(find.text('Target'), findsNothing);
    expect(find.byType(BattleBoard), findsOneWidget);
  });

  testWidgets('a wide screen shows a single board with the own fleet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));

    expect(find.byType(BattleBoard), findsOneWidget);
    final Rect attack = tester.getRect(find.byType(BattleBoard));
    // The player list stays in the column beside the only board.
    final Rect roster = tester.getRect(find.text('Turn order'));
    expect(roster.left, greaterThan(attack.right));
  });

  for (final double scale in <double>[1, 1.3]) {
    testWidgets('a 320 px phone keeps the player rows inside the panel '
        'at ${scale}x text', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 3000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _app(_FakeSessionController(session: _session(turnSeconds: 4))),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      // The clock, ships and timeouts move to a second line instead of
      // overflowing the panel.
      expect(tester.takeException(), isNull);
      expect(find.text('Turn order'), findsOneWidget);
      expect(find.text('3 ships left'), findsOneWidget);
      expect(find.text('1 timeouts'), findsOneWidget);
    });
  }

  testWidgets('the own fleet is drawn on the shared map', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(thirdPlayer: true))),
    );

    final BattleBoard board = tester.widget<BattleBoard>(
      find.byType(BattleBoard),
    );
    // The viewer's ship hull shares the board with every shot.
    expect(board.ships.single.shipId, 'ship-1');
    expect(board.sunkShips, isEmpty);
    expect(
      board.shots.any(
        (ShotView shot) =>
            shot.attackerPlayerId == 'player-2' &&
            shot.row == 0 &&
            shot.column == 1,
      ),
      isTrue,
    );
  });

  testWidgets('a sunk opponent fleet is outlined in the colour of its owner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(
            sunkShips: const <SunkShipView>[
              // The viewer's own sunk hull is already drawn as the own fleet.
              SunkShipView(
                ownerPlayerId: 'player-1',
                shipId: 'ship-1',
                length: 4,
                orientation: ShipOrientation.horizontal,
                row: 0,
                column: 0,
              ),
              SunkShipView(
                ownerPlayerId: 'player-2',
                shipId: 'ship-2',
                length: 2,
                orientation: ShipOrientation.vertical,
                row: 3,
                column: 3,
              ),
            ],
          ),
        ),
      ),
    );

    final BattleBoard board = tester.widget<BattleBoard>(
      find.byType(BattleBoard),
    );
    // Only the fleet of an opponent is outlined on the shared map.
    expect(board.sunkOpponentShips, hasLength(1));
    expect(board.sunkOpponentShips.single.ownerPlayerId, 'player-2');
    expect(
      board.shooterColors[board.sunkOpponentShips.single.ownerPlayerId],
      isNotNull,
    );
  });

  testWidgets('the shared map keeps every hit and the own miss', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(thirdPlayer: true))),
    );

    final BattleBoard board = tester.widget<BattleBoard>(
      find.byType(BattleBoard),
    );
    // The viewer sees their own miss plus the hits of everybody; the miss of
    // another player is not drawn.
    expect(board.shots, hasLength(3));
    expect(
      board.shots.map((ShotView shot) => shot.attackerPlayerId),
      containsAll(<String>['player-1', 'player-2', 'player-3']),
    );
    expect(
      board.shots.any(
        (ShotView shot) =>
            shot.result == ShotResult.miss &&
            shot.attackerPlayerId == 'player-2',
      ),
      isFalse,
    );
    // Every player has a colour of their own on the map.
    expect(
      board.shooterColors.keys,
      containsAll(<String>['player-1', 'player-2', 'player-3']),
    );
  });

  testWidgets('the shared map fits a 320 px phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(thirdPlayer: true))),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Shared map'), findsOneWidget);
    // The single map fits the narrow screen.
    final Rect map = tester.getRect(find.byType(BattleBoard));
    expect(map.right, lessThanOrEqualTo(320));
  });

  testWidgets('the map carries the colour of every shooter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));

    // A hit on the own fleet keeps the colour of the player who fired it.
    final BattleBoard board = tester.widget<BattleBoard>(
      find.byType(BattleBoard),
    );
    final ShotView hit = board.shots.firstWhere(
      (ShotView shot) => shot.result == ShotResult.hit,
    );
    expect(board.shooterColors[hit.attackerPlayerId], isNotNull);
    expect(board.shooterColors.keys, contains('player-2'));
  });

  testWidgets('firing sends the shot of the picked cell', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    final Rect board = tester.getRect(find.byType(BattleBoard));
    final double cell = board.width / RoomConfig.defaults.columns;
    // Double-tap the middle of the cell, not its edge: no fire button.
    await _doubleTapAt(
      tester,
      Offset(board.left + cell * 4.5, board.top + cell * 4.5),
    );

    // One shot at the cell, with no target to choose.
    expect(controller.shots, <(int, int)>[(4, 4)]);
  });

  testWidgets('before the first shot the map explains the double-tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(viewerFired: false))),
    );

    expect(
      find.text('Double-tap a cell to fire at every opponent.'),
      findsOneWidget,
    );
    expect(find.text('Your turn'), findsOneWidget);
  });

  testWidgets('after the first shot the double-tap hint is gone', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(viewerFired: true))),
    );

    expect(
      find.text('Double-tap a cell to fire at every opponent.'),
      findsNothing,
    );
    // The turn strip still says it is the viewer's turn.
    expect(find.text('Your turn'), findsOneWidget);
  });

  testWidgets('a player who is not active cannot fire', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(myTurn: false),
    );
    await tester.pumpWidget(_app(controller));

    // The strip above the map names the active player, and the map refuses
    // input for the whole turn.
    expect(find.text('Bob is shooting'), findsOneWidget);
    expect(tester.widget<BattleBoard>(find.byType(BattleBoard)).enabled, isFalse);

    final Rect board = tester.getRect(find.byType(BattleBoard));
    final double cell = board.width / RoomConfig.defaults.columns;
    await _doubleTapAt(
      tester,
      Offset(board.left + cell * 4.5, board.top + cell * 4.5),
    );

    expect(controller.shots, isEmpty);
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

    // The countdown lives once, in the strip above the map, not in the rows.
    expect(find.text('Turn 3 · 22s left'), findsOneWidget);
    expect(find.text('22s'), findsNothing);

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

  testWidgets('a turn that is nearly over warns in the turn strip', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(turnSeconds: 4))),
    );

    // The strip above the map is the one place that carries the clock, and it
    // switches to the warning icon and colour.
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.byIcon(Icons.gps_fixed), findsNothing);

    // The strip warns with the same colour.
    final Text turn = tester.widget<Text>(find.text('Turn 3 · 4s left'));
    expect(turn.style?.color, AppTheme.danger);
    expect(turn.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('a turn with time left keeps the normal colours', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));

    final Text turn = tester.widget<Text>(find.text('Turn 3 · 22s left'));
    expect(turn.style?.color, isNot(AppTheme.danger));
    expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });

  testWidgets('the last seconds of a turn play one warning', (
    WidgetTester tester,
  ) async {
    final _RecordingSoundPlayer sounds = _RecordingSoundPlayer();
    await tester.pumpWidget(
      _app(
        _FakeSessionController(session: _session(turnSeconds: 4)),
        sounds: sounds,
      ),
    );
    await tester.pump();

    expect(sounds.played, <GameSound>[GameSound.warning]);

    // The next ticks stay silent: the warning belongs to the turn.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds.played, <GameSound>[GameSound.warning]);
  });

  testWidgets('another player\'s last seconds stay silent', (
    WidgetTester tester,
  ) async {
    final _RecordingSoundPlayer sounds = _RecordingSoundPlayer();
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(myTurn: false, turnSeconds: 4),
        ),
        sounds: sounds,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(sounds.played, isEmpty);
  });

  testWidgets('a spectator hears no warning', (WidgetTester tester) async {
    final _RecordingSoundPlayer sounds = _RecordingSoundPlayer();
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(myTurn: false, eliminated: true, turnSeconds: 4),
        ),
        sounds: sounds,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(sounds.played, isEmpty);
  });

  testWidgets('a turn with time left plays no warning', (
    WidgetTester tester,
  ) async {
    final _RecordingSoundPlayer sounds = _RecordingSoundPlayer();
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session()), sounds: sounds),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(sounds.played, isEmpty);
  });

  testWidgets('a narrow screen keeps the players in the same scroll', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));
    await tester.pump();

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Alice (you)'), findsOneWidget);
    expect(find.text('1 timeouts'), findsOneWidget);
  });

  testWidgets('the spectator view fits a 320 px phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(myTurn: false, eliminated: true, turnSeconds: 4),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SpectatorView), findsOneWidget);
    final Rect status = tester.getRect(find.text('Bob is shooting'));
    expect(status.right, lessThanOrEqualTo(320));
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
    // The sunk notice asks the player what to do next.
    expect(find.text('Keep watching'), findsOneWidget);
    expect(find.text('Leave match'), findsOneWidget);
    expect(find.text('Bob is shooting'), findsOneWidget);
    expect(find.text('Turn 3 · 22s left'), findsOneWidget);
    expect(
      find.text('Double-tap a cell to fire at every opponent.'),
      findsNothing,
    );
    expect(find.text('Wait for your turn'), findsNothing);
    expect(controller.shots, isEmpty);
  });

  testWidgets('keeping an eye on the match drops the sunk notice', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(myTurn: false, eliminated: true),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('Keep watching'));
    await tester.pumpAndSettle();

    expect(find.text('Your fleet was sunk.'), findsNothing);
    expect(find.text('Keep watching'), findsNothing);
    // The spectator view stays, with a compact reminder of the state.
    expect(find.byType(SpectatorView), findsOneWidget);
    expect(find.text('Spectating'), findsOneWidget);
    expect(find.byType(BattleBoard), findsNothing);
  });

  testWidgets('leaving from the sunk notice asks for confirmation', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(myTurn: false, eliminated: true),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('Leave match'));
    await tester.pumpAndSettle();

    expect(find.text('Leave the match?'), findsOneWidget);
  });

  testWidgets('the spectator status strip warns when the turn runs out', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(myTurn: false, eliminated: true, turnSeconds: 4),
        ),
      ),
    );

    final Text turn = tester.widget<Text>(find.text('Turn 3 · 4s left'));
    expect(turn.style?.color, AppTheme.danger);
    expect(turn.style?.fontWeight, FontWeight.w600);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_empty), findsNothing);
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

    // The dots carry the colour the map paints each shooter with, so the
    // spectator list reads like the roster of the players.
    expect(
      tester
          .widgetList<ShooterDot>(find.byType(ShooterDot))
          .map((ShooterDot dot) => dot.colour)
          .toList(),
      <Color>[ShooterColors.palette[1], ShooterColors.palette[2]],
    );
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

  testWidgets('the final result opens the fleet review first', (
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
                path: '/match/result/fleets',
                builder: (BuildContext context, GoRouterState state) =>
                    const Scaffold(body: Center(child: Text('Fleet review'))),
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

    // The fleets are shown first; the result screen waits behind them.
    expect(find.text('Fleet review'), findsOneWidget);
    expect(find.text('Result screen'), findsNothing);
    expect(find.text('Your turn'), findsNothing);
  });
}
