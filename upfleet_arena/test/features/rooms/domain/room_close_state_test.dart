import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/profile/domain/profile.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';

/// A container with the real controller: a practice room runs entirely in
/// process, so no sockets or discovery are needed.
Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      localPreferencesProvider.overrideWithValue(
        LocalPreferences.withInstance(preferences),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(roomSessionControllerProvider.notifier)
      .startPractice(
        profile: const Profile(displayName: 'Alice', avatarId: 'captain'),
      );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'closing a practice room clears the room, not just the status',
    () async {
      final ProviderContainer container = await _container();
      final RoomSessionController controller = container.read(
        roomSessionControllerProvider.notifier,
      );

      expect(container.read(roomSessionControllerProvider).snapshot, isNotNull);
      expect(container.read(roomSessionControllerProvider).isInRoom, isTrue);

      await controller.closeRoom();
      final RoomSessionState after = container.read(
        roomSessionControllerProvider,
      );

      expect(after.status, RoomSessionStatus.closed);
      // The client-facing notice must not be stored on the device that closed
      // the room: otherwise every later setup / preparation screen repeats it.
      expect(after.errorMessage, isNull);
      expect(after.snapshot, isNull);
      expect(after.placement, isNull);
      expect(after.countdown, isNull);
      expect(after.placementError, isNull);
      expect(after.notice, isNull);
    },
  );

  test('acknowledging a closed room returns to a clean idle session', () async {
    final ProviderContainer container = await _container();
    final RoomSessionController controller = container.read(
      roomSessionControllerProvider.notifier,
    );
    await controller.closeRoom();

    controller.acknowledgeClosedRoom();
    final RoomSessionState after = container.read(
      roomSessionControllerProvider,
    );

    expect(after.status, RoomSessionStatus.idle);
    expect(after.errorMessage, isNull);
    expect(after.errorCode, isNull);
    expect(after.snapshot, isNull);
    expect(after.isInRoom, isFalse);

    // An acknowledgement outside a closed room must not clobber a live one.
    controller.acknowledgeClosedRoom();
    expect(
      container.read(roomSessionControllerProvider).status,
      RoomSessionStatus.idle,
    );
  });
}
