import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/services/screen_awake_service.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/lan_networking/domain/lan_discovery.dart';
import 'package:upfleet_arena/features/lan_networking/domain/lan_networking_providers.dart';
import 'package:upfleet_arena/features/profile/domain/profile.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// Records wakelock calls so the tests can prove the Host holds the lock only
/// while it is hosting.
class RecordingScreenAwake implements ScreenAwakeService {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enable() async => enableCalls++;

  @override
  Future<void> disable() async => disableCalls++;
}

/// An advertiser that does nothing, so no real mDNS traffic is emitted.
class NoopAdvertiser implements LanAdvertiserService {
  @override
  Stream<String> get diagnostics => const Stream<String>.empty();

  @override
  Future<void> start({
    required String label,
    required int port,
    Map<String, String> attributes = const <String, String>{},
  }) async {}

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingScreenAwake screenAwake;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    screenAwake = RecordingScreenAwake();
    container = ProviderContainer(
      overrides: [
        localPreferencesProvider.overrideWithValue(
          LocalPreferences.withInstance(preferences),
        ),
        screenAwakeServiceProvider.overrideWithValue(screenAwake),
        lanAdvertiserServiceProvider.overrideWithValue(NoopAdvertiser()),
      ],
    );
  });

  tearDown(() => container.dispose());

  const Profile profile = Profile(displayName: 'Host', avatarId: '🦈');

  test('creating a room takes the wakelock once', () async {
    final RoomSessionController controller = container.read(
      roomSessionControllerProvider.notifier,
    );
    await controller.createRoom(profile: profile);

    expect(container.read(roomSessionControllerProvider).isHost, isTrue);
    expect(screenAwake.enableCalls, 1);
    expect(screenAwake.disableCalls, 0);
  });

  test('closing the room releases the wakelock', () async {
    final RoomSessionController controller = container.read(
      roomSessionControllerProvider.notifier,
    );
    await controller.createRoom(profile: profile);
    await controller.closeRoom();

    expect(screenAwake.enableCalls, 1);
    expect(screenAwake.disableCalls, 1);
  });

  test('an invalid config never takes the wakelock', () async {
    final RoomSessionController controller = container.read(
      roomSessionControllerProvider.notifier,
    );
    // Zero players is below the minimum, so validation fails before hosting.
    final RoomConfig invalid = RoomConfig.defaults.copyWith(maxPlayers: 1);
    await controller.createRoom(profile: profile, config: invalid);

    expect(container.read(roomSessionControllerProvider).isInRoom, isFalse);
    expect(screenAwake.enableCalls, 0);
  });

  test('disposing the controller releases a held wakelock', () async {
    final RoomSessionController controller = container.read(
      roomSessionControllerProvider.notifier,
    );
    await controller.createRoom(profile: profile);
    expect(screenAwake.enableCalls, 1);

    container.dispose();
    // Give the unawaited teardown a turn to run.
    await Future<void>.delayed(Duration.zero);
    expect(screenAwake.disableCalls, 1);
  });
}