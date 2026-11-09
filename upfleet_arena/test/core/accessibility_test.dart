import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upfleet_arena/core/providers.dart';
import 'package:upfleet_arena/core/storage/local_preferences.dart';
import 'package:upfleet_arena/features/match/widgets/battle_board.dart';
import 'package:upfleet_arena/features/profile/presentation/profile_screen.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';
import 'package:upfleet_arena/shared/widgets/board_canvas.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the target board exposes a descriptive semantic label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(const BattleBoard(rows: 10, columns: 10, shots: [])),
    );

    expect(
      find.bySemanticsLabel(
        'Target board, 10 rows by 10 columns. Tap a cell to select it.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the own board exposes a descriptive semantic label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(const BoardCanvas(rows: 8, columns: 8, ships: [])),
    );

    expect(
      find.bySemanticsLabel('Your board, 8 rows by 8 columns.'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('board labels are translated in Vietnamese', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('vi'),
        home: const Scaffold(
          body: BoardCanvas(rows: 8, columns: 8, ships: []),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Bàn của bạn, 8 hàng và 8 cột.'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('avatar options are labeled buttons that report selection', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localPreferencesProvider.overrideWithValue(
            LocalPreferences.withInstance(preferences),
          ),
        ],
        child: _wrap(const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The default avatar is the fallback octopus.
    final Finder selected = find.bySemanticsLabel('Avatar 🐙');
    expect(selected, findsOneWidget);
    final SemanticsNode node = tester.getSemantics(selected);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isSelected, Tristate.isTrue);

    // Every avatar choice is announced, not just a bare emoji.
    expect(find.bySemanticsLabel(RegExp('^Avatar ')), findsNWidgets(12));
    handle.dispose();
  });
}