import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/bot/presentation/add_bot_dialog.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

Widget _app() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('vi'),
  home: const Scaffold(body: SizedBox()),
);

void main() {
  testWidgets('the chosen difficulty is returned', (WidgetTester tester) async {
    BotDifficulty? result;
    await tester.pumpWidget(_app());

    unawaited(
      showAddBotDialog(tester.element(find.byType(Scaffold))).then(
        (BotDifficulty? value) => result = value,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Khó'));
    await tester.pump();
    await tester.tap(find.text('Thêm máy'));
    await tester.pumpAndSettle();

    expect(result, BotDifficulty.hard);
  });

  testWidgets('hints wrap inside the dialog on a narrow phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    unawaited(
      showAddBotDialog(tester.element(find.byType(Scaffold))).then((_) {}),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final Finder hardHint = find.text(
      'Dò theo ô so le và kết liễu tàu bị thương — đối thủ khó.',
    );
    expect(hardHint, findsOneWidget);

    // The explanation spans the dialog instead of the narrow strip left over
    // from two rows of icons.
    final Rect dialog = tester.getRect(
      find.ancestor(of: hardHint, matching: find.byType(AlertDialog)).first,
    );
    final Rect hint = tester.getRect(hardHint);
    expect(dialog.contains(hint.topLeft), isTrue);
    expect(dialog.contains(hint.bottomRight), isTrue);
    expect(hint.width, greaterThan(dialog.width / 2));
  });
}
