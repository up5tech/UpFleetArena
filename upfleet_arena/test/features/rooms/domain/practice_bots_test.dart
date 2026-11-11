import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/profile/domain/profile.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// Starts a practice match with the real authority, so the seats are counted
/// exactly as the player sees them in the lobby.
Future<ProviderContainer> _startPractice(int computers) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      localPreferencesProvider.overrideWithValue(
        LocalPreferences.withInstance(preferences),
      ),
    ],
  );
  addTearDown(() async {
    await container.read(roomSessionControllerProvider.notifier).closeRoom();
    container.dispose();
  });

  await container.read(roomSessionControllerProvider.notifier).startPractice(
    profile: const Profile(displayName: 'Alice', avatarId: 'captain'),
    difficulty: BotDifficulty.medium,
    config: RoomConfig.defaults.copyWith(
      botCount: computers,
      botDifficulty: BotDifficulty.medium,
    ),
  );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one computer takes exactly one seat', () async {
    final ProviderContainer container = await _startPractice(1);
    final RoomSessionState session = container.read(
      roomSessionControllerProvider,
    );

    expect(session.isInRoom, isTrue, reason: session.errorMessage);
    final RoomSnapshot snapshot = session.snapshot!;
    // The host plus the one computer.
    expect(snapshot.players.length, 2);
    expect(snapshot.config.botCount, 1);
  });

  test('two computers take exactly two seats', () async {
    final ProviderContainer container = await _startPractice(2);
    final RoomSessionState session = container.read(
      roomSessionControllerProvider,
    );

    expect(session.isInRoom, isTrue, reason: session.errorMessage);
    final RoomSnapshot snapshot = session.snapshot!;
    // The host plus the two computers.
    expect(snapshot.players.length, 3);
    expect(snapshot.config.botCount, 2);
  });
}
