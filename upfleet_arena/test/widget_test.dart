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

  testWidgets('Later phases are visible but disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Later'), findsWidgets);

    // The Phase 0 entry stays enabled.
    final Finder lanLab = find.widgetWithText(ListTile, 'LAN Lab');
    expect(lanLab, findsOneWidget);
    expect(tester.widget<ListTile>(lanLab).enabled, isTrue);

    final Finder createRoom = find.widgetWithText(ListTile, 'Create Room');
    expect(createRoom, findsOneWidget);
    expect(tester.widget<ListTile>(createRoom).enabled, isFalse);
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
