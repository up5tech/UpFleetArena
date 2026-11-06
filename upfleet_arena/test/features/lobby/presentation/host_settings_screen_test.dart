import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/lobby/presentation/host_settings_screen.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// A session controller with a fixed state, so the screen can be rendered
/// without a running room.
class _FakeSessionController extends RoomSessionController {
  _FakeSessionController({
    required this.session,
    this.saveProblems = const <String>[],
  });

  final RoomSessionState session;
  final List<String> saveProblems;

  @override
  RoomSessionState build() => session;

  @override
  Future<List<String>> updateConfig(RoomConfig config) async => saveProblems;
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

RoomSessionState _hostSession() => RoomSessionState(
  role: RoomRole.host,
  status: RoomSessionStatus.inRoom,
  snapshot: _snapshot(),
  inviteCode: 'ABC234',
  playerId: 'host-1',
);

RoomSessionState _clientSession() => RoomSessionState(
  role: RoomRole.client,
  status: RoomSessionStatus.inRoom,
  snapshot: _snapshot(),
  playerId: 'player-1',
);

Widget _app(RoomSessionState session, {List<String> saveProblems = const <String>[]}) {
  return ProviderScope(
    overrides: [
      roomSessionControllerProvider.overrideWith(
        () => _FakeSessionController(
          session: session,
          saveProblems: saveProblems,
        ),
      ),
    ],
    child: const MaterialApp(home: HostSettingsScreen()),
  );
}

void main() {
  setUp(() {
    // A tall surface keeps every control laid out, so the tests do not have
    // to scroll to reach the save button.
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1200, 2400);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  testWidgets('the host can edit and save the settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_hostSession()));

    expect(find.text('Room settings'), findsOneWidget);
    expect(
      find.text('Only the host can change the room settings. You see the '
          'current values here.'),
      findsNothing,
    );

    final FilledButton save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save settings'),
    );
    expect(save.onPressed, isNotNull);

    await tester.tap(find.byTooltip('Increase Rows'));
    await tester.pump();

    expect(find.text('11'), findsOneWidget);
  });

  testWidgets('a rejected save shows the reason', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(_hostSession(), saveProblems: <String>['The room is full.']),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
    await tester.pump();

    expect(find.text('The room is full.'), findsOneWidget);
  });

  testWidgets('a non-host sees the settings without the edit actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_clientSession()));

    expect(
      find.text('Only the host can change the room settings. You see the '
          'current values here.'),
      findsOneWidget,
    );

    final FilledButton save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save settings'),
    );
    expect(save.onPressed, isNull);

    final IconButton increase = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Increase Rows'),
        matching: find.byType(IconButton),
      ),
    );
    expect(increase.onPressed, isNull);
  });
}
