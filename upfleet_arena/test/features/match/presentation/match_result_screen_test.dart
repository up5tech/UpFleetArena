import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/features/match/presentation/match_result_screen.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// A session controller with a fixed state, so the result can be rendered
/// without a running match.
class _FakeSessionController extends RoomSessionController {
  _FakeSessionController({required this.session});

  final RoomSessionState session;
  bool left = false;
  bool closed = false;

  @override
  RoomSessionState build() => session;

  @override
  Future<void> leave() async {
    left = true;
    state = const RoomSessionState();
  }

  @override
  Future<void> closeRoom() async {
    closed = true;
    state = const RoomSessionState();
  }
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
);

const FinalFleetView _aliceFleet = FinalFleetView(
  playerId: 'player-1',
  ships: <ShipView>[
    ShipView(
      shipId: 'alice-1',
      length: 3,
      orientation: ShipOrientation.horizontal,
      row: 0,
      column: 0,
      hitCells: <CellCoord>[],
      sunk: false,
    ),
    ShipView(
      shipId: 'alice-2',
      length: 2,
      orientation: ShipOrientation.horizontal,
      row: 2,
      column: 0,
      hitCells: <CellCoord>[CellCoord(2, 0), CellCoord(2, 1)],
      sunk: true,
    ),
  ],
);

RoomSessionState _session({
  String viewer = 'player-1',
  RoomRole role = RoomRole.client,
  RoomSessionStatus status = RoomSessionStatus.inRoom,
  bool hasResult = true,
  int durationSeconds = 272,
  List<FinalFleetView> fleets = const <FinalFleetView>[],
}) => RoomSessionState(
  role: role,
  status: status,
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
  matchResult: hasResult
      ? MatchResult(
          matchId: _result.matchId,
          stateVersion: _result.stateVersion,
          winnerPlayerId: _result.winnerPlayerId,
          winnerDisplayName: _result.winnerDisplayName,
          durationSeconds: durationSeconds,
          ranking: _result.ranking,
          fleets: fleets,
        )
      : null,
);

Widget _app(_FakeSessionController controller) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(() => controller),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      routerConfig: GoRouter(
        initialLocation: '/match/result',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: Center(child: Text('Home'))),
          ),
          GoRoute(
            path: '/match/result',
            builder: (BuildContext context, GoRouterState state) =>
                const MatchResultScreen(),
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
    binding.platformDispatcher.views.first.physicalSize = const Size(1200, 3000);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  testWidgets('the winner sees their own victory and the full ranking', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));

    expect(find.text('You won the match.'), findsOneWidget);
    expect(find.text('Alice (you)'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Lasted 4m 32s · You finished #1'), findsOneWidget);
    expect(
      find.text('18 shots · 11 hits · 7 misses · 5 sunk · 0 timeouts'),
      findsOneWidget,
    );
    expect(
      find.text('14 shots · 8 hits · 6 misses · 3 sunk · 1 timeouts'),
      findsOneWidget,
    );
  });

  testWidgets('a finished match offers the fleet review', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: _session(fleets: const <FinalFleetView>[_aliceFleet]),
        ),
      ),
    );

    expect(find.text('Review all fleets'), findsOneWidget);
  });

  testWidgets('without revealed fleets the review is not offered', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_FakeSessionController(session: _session())));

    expect(find.text('Review all fleets'), findsNothing);
  });

  testWidgets('a defeated player sees the name of the winner and their own rank', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(viewer: 'player-2'))),
    );

    expect(find.text('Alice won the match.'), findsOneWidget);
    expect(find.text('Bob (you)'), findsOneWidget);
    expect(find.text('Lasted 4m 32s · You finished #2'), findsOneWidget);
  });

  testWidgets('a match shorter than a minute is shown in seconds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeSessionController(session: _session(durationSeconds: 47)),
      ),
    );

    expect(find.text('Lasted 47s · You finished #1'), findsOneWidget);
  });

  testWidgets('a client returns home by leaving the room', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('Return home'));
    await tester.pumpAndSettle();

    expect(controller.left, isTrue);
    expect(controller.closed, isFalse);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('the host ends the room for everyone', (WidgetTester tester) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(role: RoomRole.host),
    );
    await tester.pumpWidget(_app(controller));

    expect(
      find.text('The match is over. This closes the room for everyone.'),
      findsOneWidget,
    );

    await tester.tap(find.text('End room and return home'));
    await tester.pumpAndSettle();

    expect(controller.closed, isTrue);
    expect(controller.left, isFalse);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('the result stays readable after the host closed the room', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(status: RoomSessionStatus.closed),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('You won the match.'), findsOneWidget);
    expect(find.text('Alice (you)'), findsOneWidget);

    await tester.tap(find.text('Return home'));
    await tester.pumpAndSettle();

    expect(controller.left, isFalse);
    expect(controller.closed, isFalse);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('without a result the screen explains that the match is running', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeSessionController(session: _session(hasResult: false))),
    );

    expect(find.text('The match has not finished yet.'), findsOneWidget);
    expect(find.text('Final ranking'), findsNothing);
  });

  testWidgets('long names and stats fit a 320 px phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1;

    const MatchResult longResult = MatchResult(
      matchId: 'match-2',
      stateVersion: 7,
      winnerPlayerId: 'player-1',
      winnerDisplayName: 'A rather long winner name',
      durationSeconds: 3725,
      ranking: <PlayerResultView>[
        PlayerResultView(
          playerId: 'player-1',
          displayName: 'A rather long winner name',
          rank: 1,
          shots: 118,
          hits: 11,
          misses: 107,
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
          timeouts: 12,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        _FakeSessionController(
          session: RoomSessionState(
            role: RoomRole.client,
            status: RoomSessionStatus.inRoom,
            playerId: 'player-1',
            snapshot: const RoomSnapshot(
              roomId: 'room-1',
              status: RoomStatus.finished,
              config: RoomConfig.defaults,
              players: <PlayerSummary>[],
              viewerPlayerId: 'player-1',
              viewerIsHost: false,
              stateVersion: 7,
            ),
            matchResult: longResult,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('A rather long winner name (you)'), findsOneWidget);
    final Rect stats = tester.getRect(
      find.text('118 shots · 11 hits · 107 misses · 5 sunk · 0 timeouts'),
    );
    // The statistics keep the width of the card instead of a thin column.
    expect(stats.width, greaterThan(180));
  });
}