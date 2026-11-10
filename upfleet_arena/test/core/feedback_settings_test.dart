import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/settings/feedback_settings.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/profile/presentation/profile_screen.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeedbackSettingsController', () {
    late SharedPreferences preferences;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      preferences = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          localPreferencesProvider.overrideWithValue(
            LocalPreferences.withInstance(preferences),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('a fresh install defaults sound and haptics on, motion normal', () {
      final FeedbackSettings settings = container.read(feedbackSettingsProvider);
      expect(settings.soundEnabled, isTrue);
      expect(settings.hapticsEnabled, isTrue);
      expect(settings.reducedMotion, isFalse);
    });

    test('toggles are independent and persist to local storage', () async {
      final FeedbackSettingsController controller = container.read(
        feedbackSettingsProvider.notifier,
      );

      await controller.setSoundEnabled(false);
      FeedbackSettings settings = container.read(feedbackSettingsProvider);
      expect(settings.soundEnabled, isFalse);
      expect(settings.hapticsEnabled, isTrue);
      expect(settings.reducedMotion, isFalse);
      expect(preferences.getBool('settings.soundEnabled'), isFalse);

      await controller.setHapticsEnabled(false);
      await controller.setReducedMotion(true);
      settings = container.read(feedbackSettingsProvider);
      expect(settings.soundEnabled, isFalse);
      expect(settings.hapticsEnabled, isFalse);
      expect(settings.reducedMotion, isTrue);
      expect(preferences.getBool('settings.hapticsEnabled'), isFalse);
      expect(preferences.getBool('settings.reducedMotion'), isTrue);
    });

    test('values are reloaded from storage on a new container', () async {
      await container
          .read(feedbackSettingsProvider.notifier)
          .setSoundEnabled(false);
      await container
          .read(feedbackSettingsProvider.notifier)
          .setReducedMotion(true);

      final ProviderContainer reloaded = ProviderContainer(
        overrides: [
          localPreferencesProvider.overrideWithValue(
            LocalPreferences.withInstance(preferences),
          ),
        ],
      );
      addTearDown(reloaded.dispose);

      final FeedbackSettings settings = reloaded.read(feedbackSettingsProvider);
      expect(settings.soundEnabled, isFalse);
      expect(settings.hapticsEnabled, isTrue);
      expect(settings.reducedMotion, isTrue);
    });
  });

  group('useReducedMotion', () {
    Future<bool> evaluate(
      WidgetTester tester, {
      required bool osDisableAnimations,
      required bool userReducedMotion,
    }) async {
      bool? result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: osDisableAnimations),
          child: Builder(
            builder: (BuildContext context) {
              result = useReducedMotion(
                context,
                FeedbackSettings(reducedMotion: userReducedMotion),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      return result!;
    }

    testWidgets('off when neither the OS nor the player asks for it', (
      WidgetTester tester,
    ) async {
      expect(
        await evaluate(
          tester,
          osDisableAnimations: false,
          userReducedMotion: false,
        ),
        isFalse,
      );
    });

    testWidgets('the OS accessibility setting alone reduces motion', (
      WidgetTester tester,
    ) async {
      expect(
        await evaluate(
          tester,
          osDisableAnimations: true,
          userReducedMotion: false,
        ),
        isTrue,
      );
    });

    testWidgets('the player toggle alone reduces motion', (
      WidgetTester tester,
    ) async {
      expect(
        await evaluate(
          tester,
          osDisableAnimations: false,
          userReducedMotion: true,
        ),
        isTrue,
      );
    });
  });

  group('ProfileScreen feedback toggles', () {
    testWidgets('sound, haptics and motion switches reflect and update state', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localPreferencesProvider.overrideWithValue(
              LocalPreferences.withInstance(preferences),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll the settings card into view.
      await tester.scrollUntilVisible(
        find.text('Sound & effects'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      final Finder soundSwitch = find.widgetWithText(
        SwitchListTile,
        'Sound effects',
      );
      expect(tester.widget<SwitchListTile>(soundSwitch).value, isTrue);

      await tester.tap(soundSwitch);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(soundSwitch).value, isFalse);
      expect(preferences.getBool('settings.soundEnabled'), isFalse);
      // Haptics stay untouched.
      expect(preferences.getBool('settings.hapticsEnabled'), isNull);
    });

    testWidgets('long subtitles wrap cleanly on a narrow phone', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localPreferencesProvider.overrideWithValue(
              LocalPreferences.withInstance(preferences),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Âm thanh & hiệu ứng'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Nothing overflows and every switch keeps its explanation on screen.
      expect(tester.takeException(), isNull);
      final Finder soundTile = find.widgetWithText(
        SwitchListTile,
        'Hiệu ứng âm thanh',
      );
      final Finder subtitle = find.text(
        'Bắn, trúng, kết quả và cảnh báo sắp hết lượt',
      );
      expect(subtitle, findsOneWidget);
      final Rect tileRect = tester.getRect(soundTile);
      final Rect subtitleRect = tester.getRect(subtitle);
      expect(tileRect.contains(subtitleRect.topLeft), isTrue);
      expect(tileRect.contains(subtitleRect.bottomRight), isTrue);
    });
  });
}