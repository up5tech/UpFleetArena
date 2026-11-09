import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/settings/app_locale.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/home/presentation/home_screen.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the home screen renders in Vietnamese when locale is vi', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('vi'),
          home: const HomeScreen(),
        ),
      ),
    );

    expect(find.text('Tạo phòng'), findsOneWidget);
    expect(find.text('Vào phòng'), findsOneWidget);
    expect(find.text('Hồ sơ & Cài đặt'), findsOneWidget);
    // English-only labels must not leak into the Vietnamese UI.
    expect(find.text('Create Room'), findsNothing);
    expect(find.text('Join Room'), findsNothing);
  });

  testWidgets('the home screen renders in English when locale is en', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const HomeScreen(),
        ),
      ),
    );

    expect(find.text('Create Room'), findsOneWidget);
    expect(find.text('Join Room'), findsOneWidget);
    expect(find.text('Profile & Settings'), findsOneWidget);
  });

  group('AppLocaleController', () {
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

    test('a fresh install follows the system locale', () {
      expect(container.read(appLocaleProvider), isNull);
    });

    test('choosing a language persists it and updates the state', () async {
      await container.read(appLocaleProvider.notifier).setLocale(
        const Locale('vi'),
      );
      expect(container.read(appLocaleProvider), const Locale('vi'));
      expect(preferences.getString('settings.locale'), 'vi');
    });

    test('returning to system clears the stored tag', () async {
      final AppLocaleController controller = container.read(
        appLocaleProvider.notifier,
      );
      await controller.setLocale(const Locale('vi'));
      await controller.setLocale(null);
      expect(container.read(appLocaleProvider), isNull);
      expect(preferences.getString('settings.locale'), isNull);
    });

    test('the stored tag is restored on a new container', () async {
      await container.read(appLocaleProvider.notifier).setLocale(
        const Locale('vi'),
      );
      final ProviderContainer reloaded = ProviderContainer(
        overrides: [
          localPreferencesProvider.overrideWithValue(
            LocalPreferences.withInstance(preferences),
          ),
        ],
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.read(appLocaleProvider), const Locale('vi'));
    });
  });
}