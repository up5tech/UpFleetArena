import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/home/presentation/home_screen.dart';

void main() {
  testWidgets('Home shows the product identity and the phase map', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('UpFleet Arena'), findsOneWidget);
    expect(find.text('LAN Lab'), findsOneWidget);
    expect(find.text('Create Room'), findsOneWidget);
    expect(find.text('Join Room'), findsOneWidget);
  });

  testWidgets('Phase 1 entries are enabled and later phases are not', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Later'), findsWidgets);

    for (final String title in <String>[
      'LAN Lab',
      'Create Room',
      'Join Room',
    ]) {
      final Finder entry = find.widgetWithText(ListTile, title);
      expect(entry, findsOneWidget, reason: title);
      expect(tester.widget<ListTile>(entry).enabled, isTrue, reason: title);
    }

    for (final String title in <String>['Lobby', 'Ship Placement', 'Battle']) {
      final Finder entry = find.widgetWithText(ListTile, title);
      await tester.scrollUntilVisible(
        entry,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(entry, findsOneWidget, reason: title);
      expect(tester.widget<ListTile>(entry).enabled, isFalse, reason: title);
    }
  });

  testWidgets('The frozen defaults are listed for the tester', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

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
