import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/features/match/presentation/final_fleets_screen.dart';
import 'package:upfleet_arena/features/match/widgets/shooter_colors.dart';
import 'package:upfleet_arena/features/match/widgets/shooter_dot.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';
import 'package:upfleet_arena/shared/widgets/board_canvas.dart';

/// A session controller with a fixed state, so the review can be rendered
/// without a running match.
class _FakeSessionController extends RoomSessionController {
  _FakeSessionController({required this.session});

  final RoomSessionState session;

  @override
  RoomSessionState build() => session;
}

const MatchResult _result = MatchResult(
  matchId: 'match-1',
  stateVersion: 42,
  winnerPlayerId: 'player-1',
  winnerDisplayName: 'Alice',
  durationSeconds: 272,
  ranking: <PlayerResultView>[
    PlayerResultView(
      playerId: 'player-1',
      displayName: 'Alice',
      rank: 1,
      shots: 18,
      hits: 11,
      misses: 7,
      shipsSunk: 5,
      timeouts: 0,
    ),
    PlayerResultView(
      playerId: 'player-2',
      displayName: 'Bob',
      rank: 2,
      shots: 14,
      hits: 8,
      misses: 6,
      shipsSunk: 3,
      timeouts: 1,
    ),
  ],
  fleets: <FinalFleetView>[
    FinalFleetView(
      playerId: 'player-1',
      ships: <ShipView>[
        ShipView(
          shipId: 'alice-1',
          length: 3,
          orientation: ShipOrientation.horizontal,
          row: 0,
          column: 0,
          hitCells: <CellCoord>[CellCoord(0, 1)],
          sunk: false,
        ),
        ShipView(
          shipId: 'alice-2',
          length: 2,
          orientation: ShipOrientation.vertical,
          row: 4,
          column: 4,
          hitCells: <CellCoord>[CellCoord(4, 4), CellCoord(5, 4)],
          sunk: true,
        ),
        ShipView(
          shipId: 'alice-3',
          length: 2,
          orientation: ShipOrientation.horizontal,
          row: 8,
          column: 8,
          hitCells: <CellCoord>[],
          sunk: false,
        ),
      ],
      receivedShots: <ShotView>[
        ShotView(
          row: 0,
          column: 1,
          result: ShotResult.hit,
          attackerPlayerId: 'player-2',
        ),
        ShotView(
          row: 4,
          column: 4,
          result: ShotResult.hit,
          attackerPlayerId: 'player-2',
        ),
        ShotView(
          row: 5,
          column: 4,
          result: ShotResult.shipSunk,
          attackerPlayerId: 'player-2',
        ),
        ShotView(
          row: 9,
          column: 0,
          result: ShotResult.miss,
          attackerPlayerId: 'player-2',
        ),
      ],
    ),
    FinalFleetView(
      playerId: 'player-2',
      ships: <ShipView>[
        ShipView(
          shipId: 'bob-1',
          length: 3,
          orientation: ShipOrientation.horizontal,
          row: 2,
          column: 2,
          hitCells: <CellCoord>[
            CellCoord(2, 2),
            CellCoord(2, 3),
            CellCoord(2, 4),
          ],
          sunk: true,
        ),
      ],
      receivedShots: <ShotView>[
        ShotView(
          row: 2,
          column: 2,
          result: ShotResult.hit,
          attackerPlayerId: 'player-1',
        ),
        ShotView(
          row: 2,
          column: 3,
          result: ShotResult.hit,
          attackerPlayerId: 'player-1',
        ),
        ShotView(
          row: 2,
          column: 4,
          result: ShotResult.shipSunk,
          attackerPlayerId: 'player-1',
        ),
      ],
    ),
  ],
);

/// The match as the map saw it: the players in turn order, which is what
/// hands out the shooter colours.
const MatchSnapshot _snapshot = MatchSnapshot(
  matchId: 'match-1',
  stateVersion: 42,
  turnNumber: 9,
  activePlayerId: 'player-1',
  players: <MatchPlayerView>[
    MatchPlayerView(
      playerId: 'player-1',
      displayName: 'Alice',
      alive: true,
      timeouts: 0,
      shipsRemaining: 2,
    ),
    MatchPlayerView(
      playerId: 'player-2',
      displayName: 'Bob',
      alive: false,
      timeouts: 1,
      shipsRemaining: 0,
    ),
  ],
);

RoomSessionState _session({
  MatchResult? matchResult = _result,
  String viewer = 'player-1',
  MatchSnapshot? matchSnapshot,
}) => RoomSessionState(
  role: RoomRole.client,
  status: RoomSessionStatus.inRoom,
  playerId: viewer,
  snapshot: const RoomSnapshot(
    roomId: 'room-1',
    status: RoomStatus.finished,
    config: RoomConfig.defaults,
    players: <PlayerSummary>[],
    viewerPlayerId: 'player-1',
    viewerIsHost: false,
    stateVersion: 42,
  ),
  matchSnapshot: matchSnapshot,
  matchResult: matchResult,
);

Widget _app(RoomSessionState session) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(
        () => _FakeSessionController(session: session),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const FinalFleetsScreen(),
    ),
  );
}

/// The review inside the routes of the app, so the OK button can be followed.
Widget _routedApp(RoomSessionState session) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(
        () => _FakeSessionController(session: session),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      routerConfig: GoRouter(
        initialLocation: '/match/result/fleets',
        routes: <RouteBase>[
          GoRoute(
            path: '/match/result/fleets',
            builder: (BuildContext context, GoRouterState state) =>
                const FinalFleetsScreen(),
          ),
          GoRoute(
            path: '/match/result',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: Center(child: Text('Result screen'))),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1200,
      4000,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  testWidgets('every fleet of the finished match is revealed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_session()));
    await tester.pumpAndSettle();

    expect(find.text('All fleets'), findsOneWidget);
    // Once in the colour legend at the top, once on the fleet card.
    expect(find.text('Alice (you)'), findsNWidgets(2));
    expect(find.text('Bob'), findsNWidgets(2));
    expect(find.text('3 ships · 1 sunk'), findsOneWidget);
    expect(find.text('1 ships · 1 sunk'), findsOneWidget);
    // One read-only board per fleet.
    expect(find.byType(BoardCanvas), findsNWidgets(2));
    // The result screen waits behind this button.
    expect(find.text('OK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the legend names every player with the colour they fired in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_session(matchSnapshot: _snapshot)));
    await tester.pumpAndSettle();

    expect(find.text('Shot colours'), findsOneWidget);
    final List<ShooterDot> dots = tester
        .widgetList<ShooterDot>(find.byType(ShooterDot))
        .toList();
    expect(dots, hasLength(2));
    expect(dots[0].colour, ShooterColors.palette[0]);
    expect(dots[1].colour, ShooterColors.palette[1]);
  });

  testWidgets('OK opens the result screen after the review', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_routedApp(_session(matchSnapshot: _snapshot)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Result screen'), findsOneWidget);
    expect(find.text('All fleets'), findsNothing);
  });

  testWidgets('every hit keeps the colour of the player who fired it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_session(matchSnapshot: _snapshot)));
    await tester.pumpAndSettle();

    final List<BoardCanvas> boards = tester
        .widgetList<BoardCanvas>(find.byType(BoardCanvas))
        .toList();
    expect(boards, hasLength(2));

    // Alice is first in the turn order, Bob second, so Alice fired in the
    // first palette colour and Bob in the second.
    final Color aliceColour = ShooterColors.palette[0];
    final Color bobColour = ShooterColors.palette[1];

    // Alice's fleet was hit by Bob, and Bob's miss stays colourless.
    expect(
      boards[0].shotColors[const CellCoord(0, 1)],
      bobColour,
    );
    expect(
      boards[0].shotColors[const CellCoord(5, 4)],
      bobColour,
    );
    expect(boards[0].shotColors.containsKey(const CellCoord(9, 0)), isFalse);

    // Bob's fleet was sunk by Alice.
    for (final CellCoord cell in <CellCoord>[
      const CellCoord(2, 2),
      const CellCoord(2, 3),
      const CellCoord(2, 4),
    ]) {
      expect(boards[1].shotColors[cell], aliceColour);
    }
  });

  testWidgets(
    'without a result the screen explains that the match is running',
    (WidgetTester tester) async {
      await tester.pumpWidget(_app(_session(matchResult: null)));

      expect(find.text('The match has not finished yet.'), findsOneWidget);
      expect(find.byType(BoardCanvas), findsNothing);
    },
  );
}
