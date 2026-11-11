import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/bot/presentation/bot_setup_screen.dart';
import 'package:upfleet_arena/features/profile/domain/profile.dart';
import 'package:upfleet_arena/features/rooms/domain/room_session_controller.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// Records what the screen asked for, without opening a room.
class _FakeSessionController extends RoomSessionController {
  BotDifficulty? difficulty;
  String? botName;
  Profile? profile;
  RoomConfig? config;

  @override
  RoomSessionState build() => const RoomSessionState();

  @override
  Future<void> startPractice({
    required Profile profile,
    BotDifficulty difficulty = BotDifficulty.medium,
    String? botName,
    int? botCount,
    List<BotDifficulty>? difficulties,
    List<String>? botNames,
    List<BotDifficulty>? botDifficulties,
    List<String>? opponentNames,
    int? opponentCount,
    RoomConfig? config,
  }) async {
    this.profile = profile;
    this.difficulty = difficulty;
    this.botName = botName;
    this.config = config;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSessionController controller;

  setUp(() {
    controller = _FakeSessionController();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profile.nickname': 'Thuyền trưởng',
      'profile.avatarId': '🦈',
    });
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localPreferencesProvider.overrideWithValue(
            LocalPreferences.withInstance(preferences),
          ),
          roomSessionControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('vi'),
          home: const BotSetupScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the three difficulties are offered', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Chơi với máy'), findsWidgets);
    expect(find.text('Dễ'), findsOneWidget);
    expect(find.text('Trung bình'), findsOneWidget);
    expect(find.text('Khó'), findsOneWidget);
    expect(find.text('Thuyền trưởng'), findsOneWidget);
  });

  testWidgets('starting the match sends the chosen difficulty', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Khó'));
    await tester.pump();
    await tester.tap(find.text('Bắt đầu chơi'));
    await tester.pump();

    expect(controller.difficulty, BotDifficulty.hard);
    expect(controller.botName, 'Máy (Khó)');
    expect(controller.profile?.displayName, 'Thuyền trưởng');
  });
}
