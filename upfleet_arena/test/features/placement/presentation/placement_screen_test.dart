import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/placement/presentation/placement_screen.dart';
import 'package:upfleet_arena/features/placement/widgets/board_canvas.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/shared/models/placement_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// A session controller with a fixed state, so the screen can be rendered
/// without a running room.
class _FakeSessionController extends RoomSessionController {
  _FakeSessionController({required this.session});

  final RoomSessionState session;
  final List<List<ShipPlacement>> sentLayouts = <List<ShipPlacement>>[];
  bool autoPlaceRequested = false;
  bool readyRequested = false;

  @override
  RoomSessionState build() => session;

  @override
  Future<List<String>> setPlacement(List<ShipPlacement> ships) async {
    sentLayouts.add(List<ShipPlacement>.from(ships));
    return const <String>[];
  }

  @override
  Future<void> autoPlace() async {
    autoPlaceRequested = true;
  }

  @override
  Future<List<String>> setPlacementReady() async {
    readyRequested = true;
    return const <String>[];
  }
}

RoomSnapshot _snapshot() => const RoomSnapshot(
  roomId: 'room-1',
  status: RoomStatus.lobby,
  config: RoomConfig.defaults,
  players: <PlayerSummary>[
    PlayerSummary(
      playerId: 'host-1',
      displayName: 'Host',
      avatarId: '🦈',
      role: PlayerRole.host,
      status: PlayerConnectionStatus.connected,
    ),
  ],
  viewerPlayerId: 'host-1',
  viewerIsHost: true,
  stateVersion: 1,
);

RoomSessionState _session({List<ShipLayout> ships = const <ShipLayout>[]}) =>
    RoomSessionState(
      role: RoomRole.host,
      status: RoomSessionStatus.inRoom,
      snapshot: _snapshot(),
      playerId: 'host-1',
      placement: PlacementState(
        playerId: 'host-1',
        ships: ships,
        ready: false,
        stateVersion: 1,
      ),
    );

Widget _app(_FakeSessionController controller) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(() => controller),
    ],
    child: const MaterialApp(home: PlacementScreen()),
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

  testWidgets('the fleet is incomplete until every ship is placed', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('Your fleet'), findsOneWidget);
    expect(find.text('4 cells'), findsOneWidget);

    final FilledButton ready = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Place every ship first'),
    );
    expect(ready.onPressed, isNull);
  });

  testWidgets('tapping a ship and a cell sends the placement', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('4 cells'));
    await tester.pump();

    final Rect board = tester.getRect(find.byType(BoardCanvas));
    final double cell = board.width / RoomConfig.defaults.columns;
    await tester.tapAt(Offset(board.left + cell * 2, board.top + cell * 2));
    await tester.pump();

    expect(controller.sentLayouts, hasLength(1));
    final List<ShipPlacement> sent = controller.sentLayouts.single;
    expect(sent, hasLength(1));
    expect(sent.single.shipId, 'ship-1');
    expect(sent.single.length, 4);
    expect(sent.single.row, 2);
    expect(sent.single.column, 2);
  });

  testWidgets('a ship outside the board is not sent', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('4 cells'));
    await tester.pump();

    final Rect board = tester.getRect(find.byType(BoardCanvas));
    final double cell = board.width / RoomConfig.defaults.columns;
    await tester.tapAt(
      Offset(board.left + cell * 9, board.top + cell * 9),
    );
    await tester.pump();

    expect(controller.sentLayouts, isEmpty);
    expect(find.text('That ship does not fit on the board.'), findsOneWidget);
  });

  testWidgets('auto place asks the host to fill the fleet', (
    WidgetTester tester,
  ) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(),
    );
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.text('Auto'));
    await tester.pump();

    expect(controller.autoPlaceRequested, isTrue);
  });

  testWidgets('a complete fleet can be confirmed', (WidgetTester tester) async {
    final _FakeSessionController controller = _FakeSessionController(
      session: _session(
        ships: const <ShipLayout>[
          ShipLayout(
            shipId: 'ship-1',
            length: 4,
            orientation: ShipOrientation.horizontal,
            row: 0,
            column: 0,
          ),
          ShipLayout(
            shipId: 'ship-2',
            length: 3,
            orientation: ShipOrientation.horizontal,
            row: 2,
            column: 0,
          ),
          ShipLayout(
            shipId: 'ship-3',
            length: 3,
            orientation: ShipOrientation.horizontal,
            row: 4,
            column: 0,
          ),
          ShipLayout(
            shipId: 'ship-4',
            length: 2,
            orientation: ShipOrientation.horizontal,
            row: 6,
            column: 0,
          ),
          ShipLayout(
            shipId: 'ship-5',
            length: 2,
            orientation: ShipOrientation.horizontal,
            row: 8,
            column: 0,
          ),
        ],
      ),
    );
    await tester.pumpWidget(_app(controller));

    final FilledButton ready = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'I am ready'),
    );
    expect(ready.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'I am ready'));
    await tester.pump();

    expect(controller.readyRequested, isTrue);
  });
}
