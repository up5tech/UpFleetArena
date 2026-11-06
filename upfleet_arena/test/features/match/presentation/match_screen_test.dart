import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/match/presentation/match_screen.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// A session controller with a fixed state, so the screen can be rendered
/// without a running match.
class _FakeSessionController extends RoomSessionController {
  _FakeSessionController({required this.session});

  final RoomSessionState session;

  @override
  RoomSessionState build() => session;
}

RoomSessionState _session() => RoomSessionState(
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
  match: const MatchStartState(
    matchId: 'match-1',
    turnOrder: <TurnOrderEntry>[
      TurnOrderEntry(playerId: 'player-2', displayName: 'Bob'),
      TurnOrderEntry(playerId: 'player-1', displayName: 'Alice'),
    ],
    activePlayerId: 'player-2',
    boardRows: 10,
    boardColumns: 10,
    fleetPreset: FleetPreset.standard,
    stateVersion: 9,
  ),
);

void main() {
  testWidgets('the turn order shows who shoots first', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomSessionControllerProvider.overrideWith(
            () => _FakeSessionController(session: _session()),
          ),
        ],
        child: const MaterialApp(home: MatchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn order'), findsOneWidget);
    expect(find.text('Bob shoots first'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice (you)'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Board 10×10 · Standard fleet'), findsOneWidget);
  });

  testWidgets('a match that did not start yet says so', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomSessionControllerProvider.overrideWith(
            () => _FakeSessionController(
              session: const RoomSessionState(
                role: RoomRole.client,
                status: RoomSessionStatus.inRoom,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: MatchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The match has not started yet.'), findsOneWidget);
  });
}
