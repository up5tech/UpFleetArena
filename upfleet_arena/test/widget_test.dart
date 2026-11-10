import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/home/presentation/home_screen.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

Widget _homeApp() => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const HomeScreen(),
  ),
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  testWidgets('Home shows the product identity and the main entries', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_homeApp());

    expect(find.text('UpFleet Arena'), findsOneWidget);
    expect(find.text('Create Room'), findsOneWidget);
    expect(find.text('Join Room'), findsOneWidget);

    final Finder profile = find.widgetWithText(ListTile, 'Profile & Settings');
    await _scrollTo(tester, profile);
    expect(profile, findsOneWidget);
  });

  testWidgets('Every implemented screen has an enabled entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_homeApp());

    for (final String title in <String>[
      'Create Room',
      'Join Room',
      'Profile & Settings',
      'Lobby',
      'Ship Placement',
      'Battle',
      'LAN Lab',
    ]) {
      final Finder entry = find.widgetWithText(ListTile, title);
      await _scrollTo(tester, entry);
      expect(entry, findsOneWidget, reason: title);
      expect(tester.widget<ListTile>(entry).enabled, isTrue, reason: title);
    }
  });

  testWidgets('The in-room entries ask for a room when none is active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_homeApp());

    final Finder lobby = find.widgetWithText(ListTile, 'Lobby');
    await _scrollTo(tester, lobby);
    await tester.ensureVisible(lobby);
    await tester.pumpAndSettle();
    await tester.tap(lobby);
    await tester.pump();

    expect(find.text('Create or join a room first.'), findsOneWidget);
    // The tap must not navigate away from Home.
    expect(find.text('UpFleet Arena'), findsOneWidget);
  });

  testWidgets('The frozen defaults are listed for the tester', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_homeApp());

    await tester.scrollUntilVisible(
      find.text('Frozen defaults'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Frozen defaults'), findsOneWidget);
    expect(find.text('LAN_ONLY · HOST_STAR'), findsOneWidget);
    expect(find.text('2–6'), findsOneWidget);
    expect(find.text('10×10'), findsOneWidget);
    expect(find.textContaining('Host exit ends the room'), findsOneWidget);
  });
}
