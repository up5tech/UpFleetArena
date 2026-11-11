import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/bot/presentation/bot_setup_screen.dart';
import 'package:upfleet_arena/features/home/presentation/home_screen.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

/// Mirrors the two real top-level routes the launcher uses.
GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const HomeScreen(),
    ),
    GoRoute(
      path: '/play-bot',
      builder: (BuildContext context, GoRouterState state) =>
          const BotSetupScreen(),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localPreferencesProvider.overrideWithValue(
            LocalPreferences.withInstance(preferences),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('vi'),
          routerConfig: _router(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openBotSetup(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Chơi với máy'));
    await tester.tap(find.text('Chơi với máy'));
    await tester.pumpAndSettle();
    expect(find.byType(BotSetupScreen), findsOneWidget);
  }

  testWidgets('the app bar back button returns Home', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await openBotSetup(tester);

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BotSetupScreen), findsNothing);
  });

  testWidgets('the system back button returns Home', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await openBotSetup(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BotSetupScreen), findsNothing);
  });
}
