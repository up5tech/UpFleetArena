import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';
import 'package:upfleet_arena/shared/widgets/board_canvas.dart';

/// The events the board reports during one touch.
class _Log {
  final List<CellCoord> previews = <CellCoord>[];
  final List<CellCoord> commits = <CellCoord>[];
  final List<CellCoord> downs = <CellCoord>[];
  int clears = 0;
  int dragEnds = 0;
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: Center(child: child)),
);

BoardCanvas _board(_Log log) => BoardCanvas(
  rows: 10,
  columns: 10,
  ships: const <ShipPlacement>[
    ShipPlacement(
      shipId: 'ship-1',
      length: 2,
      orientation: ShipOrientation.horizontal,
      row: 0,
      column: 0,
    ),
  ],
  selectedShipId: 'ship-1',
  onCellPreview: log.previews.add,
  onPreviewCleared: () => log.clears++,
  onCellCommit: log.commits.add,
  onPointerDown: log.downs.add,
  onDragEnd: () => log.dragEnds++,
);

/// The touchable grid is centred inside the widget, which can be wider than
/// the board when it sits in a scrolling page.
Rect _boardRect(WidgetTester tester) {
  final Rect outer = tester.getRect(find.byType(BoardCanvas));
  final double side = math.min(outer.width, outer.height);
  return Rect.fromLTWH(
    outer.left + (outer.width - side) / 2,
    outer.top + (outer.height - side) / 2,
    side,
    side,
  );
}

void main() {
  testWidgets('the ghost follows the first cell crossing, once per cell', (
    WidgetTester tester,
  ) async {
    final _Log log = _Log();
    // 15 px cells: crossing one cell is less than the 18 px touch slop that
    // the standard drag recognizers waited for.
    await tester.pumpWidget(
      _app(SizedBox(width: 150, height: 150, child: _board(log))),
    );

    final Rect board = _boardRect(tester);
    const double cell = 15;
    final TestGesture gesture = await tester.startGesture(
      Offset(board.left + cell * 0.5, board.top + cell * 0.5),
    );

    // A jitter inside the touched cell is still a tap: no ghost, no rebuild.
    await gesture.moveBy(const Offset(3, 0));
    await tester.pump();
    expect(log.previews, isEmpty);

    // The ghost appears as soon as the finger reaches the next cell, even
    // though the pointer has travelled less than a touch slop.
    await gesture.moveBy(const Offset(cell + 1, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(cell - 1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(log.previews, <CellCoord>[
      const CellCoord(0, 1),
      const CellCoord(0, 2),
    ]);
    expect(log.downs, <CellCoord>[const CellCoord(0, 0)]);
    expect(log.commits, isEmpty);
    expect(log.dragEnds, 1);
  });

  testWidgets('a small jitter is still a tap on the touched cell', (
    WidgetTester tester,
  ) async {
    final _Log log = _Log();
    await tester.pumpWidget(
      _app(SizedBox(width: 300, height: 300, child: _board(log))),
    );

    final Rect board = _boardRect(tester);
    const double cell = 30;
    final TestGesture gesture = await tester.startGesture(
      Offset(board.left + cell * 0.5, board.top + cell * 0.5),
    );
    await gesture.moveBy(const Offset(3, 2));
    await gesture.up();
    await tester.pump();

    expect(log.previews, isEmpty);
    expect(log.commits, <CellCoord>[const CellCoord(0, 0)]);
    expect(log.dragEnds, 0);
  });

  testWidgets('releasing outside the board cancels the drop', (
    WidgetTester tester,
  ) async {
    final _Log log = _Log();
    await tester.pumpWidget(
      _app(SizedBox(width: 300, height: 300, child: _board(log))),
    );

    final Rect board = _boardRect(tester);
    const double cell = 30;
    final TestGesture gesture = await tester.startGesture(
      Offset(board.left + cell * 0.5, board.top + cell * 0.5),
    );
    await gesture.moveBy(const Offset(cell * 4, 0));
    await tester.pump();
    // Leave the grid on the way out: the ghost disappears and nothing is
    // placed on release (PHASE3 §1.5).
    await gesture.moveTo(Offset(board.right + 40, board.top + cell * 0.5));
    await gesture.up();
    await tester.pump();

    expect(log.clears, greaterThan(0));
    expect(log.dragEnds, 0);
    expect(log.commits, isEmpty);
  });

  testWidgets('a cancelled pointer never places a ship', (
    WidgetTester tester,
  ) async {
    final _Log log = _Log();
    await tester.pumpWidget(
      _app(SizedBox(width: 300, height: 300, child: _board(log))),
    );

    final Rect board = _boardRect(tester);
    const double cell = 30;
    final TestGesture gesture = await tester.startGesture(
      Offset(board.left + cell * 0.5, board.top + cell * 0.5),
    );
    await gesture.moveBy(const Offset(cell * 3, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(log.previews, isNotEmpty);
    expect(log.clears, greaterThan(0));
    expect(log.dragEnds, 0);
    expect(log.commits, isEmpty);
  });

  testWidgets('the page does not scroll away during a ship drag', (
    WidgetTester tester,
  ) async {
    final _Log log = _Log();
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: <Widget>[
              SizedBox(width: 300, height: 300, child: _board(log)),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

    final Rect board = _boardRect(tester);
    const double cell = 30;
    final TestGesture gesture = await tester.startGesture(
      Offset(board.left + cell * 0.5, board.top + cell * 0.5),
    );
    await gesture.moveBy(const Offset(0, cell * 5));
    await gesture.up();
    await tester.pump();

    expect(controller.offset, 0);
    expect(log.dragEnds, 1);
  });
}
