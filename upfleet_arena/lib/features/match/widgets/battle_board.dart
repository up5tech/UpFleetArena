import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/board/board.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../shared/models/match_models.dart';

/// The board of an opponent, as the shooter sees it.
///
/// The cells that were not fired at stay empty: the shooter never learns
/// where the ships are (PLAN.md §2.2). The viewer's own fleet is drawn
/// underneath, faded, so one board carries both the shot map and the fleet
/// the viewer has to protect.
class BattleBoard extends StatelessWidget {
  const BattleBoard({
    super.key,
    required this.rows,
    required this.columns,
    required this.shots,
    this.ownShips = const <ShipPlacement>[],
    this.ownSunkShips = const <String>{},
    this.selectedCell,
    this.onCellTapped,
    this.onCellDoubleTapped,
    this.enabled = true,
  });

  /// The number of rows of the board.
  final int rows;

  /// The number of columns of the board.
  final int columns;

  /// The shots the shooter already fired.
  final List<ShotView> shots;

  /// The viewer's own fleet, drawn faded under the shots.
  final List<ShipPlacement> ownShips;

  /// The viewer's ships that were sunk.
  final Set<String> ownSunkShips;

  /// The cell the shooter picked.
  final CellCoord? selectedCell;

  /// Called when the shooter taps a cell.
  final void Function(CellCoord cell)? onCellTapped;

  /// Called when the shooter double-taps a cell, i.e. fires at it.
  final void Function(CellCoord cell)? onCellDoubleTapped;

  /// Whether the board accepts input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = math.min(
          constraints.maxWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : constraints.maxWidth,
        );
        final double cellSize = math.min(
          available / columns,
          available / rows,
        );

        CellCoord? cellAt(Offset local) {
          final int column = (local.dx / cellSize).floor();
          final int row = (local.dy / cellSize).floor();
          if (row < 0 || row >= rows || column < 0 || column >= columns) {
            return null;
          }
          return CellCoord(row, column);
        }

        return Center(
          child: Semantics(
            label: AppLocalizations.of(context).targetBoardSemantics(rows, columns),
            container: true,
            child: SizedBox(
              width: cellSize * columns,
              height: cellSize * rows,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled
                    ? (TapDownDetails details) {
                        final CellCoord? cell = cellAt(details.localPosition);
                        if (cell != null) onCellTapped?.call(cell);
                      }
                    : null,
                onDoubleTapDown: enabled && onCellDoubleTapped != null
                    ? (TapDownDetails details) {
                        final CellCoord? cell = cellAt(details.localPosition);
                        if (cell != null) {
                          onCellTapped?.call(cell);
                          onCellDoubleTapped!(cell);
                        }
                      }
                    : null,
                onDoubleTap: enabled && onCellDoubleTapped != null
                    ? () {}
                    : null,
                child: CustomPaint(
                  painter: BattleBoardPainter(
                    rows: rows,
                    columns: columns,
                    shots: shots,
                    ownShips: ownShips,
                    ownSunkShips: ownSunkShips,
                    selectedCell: selectedCell,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Draws the grid, the shots and the picked cell.
class BattleBoardPainter extends CustomPainter {
  const BattleBoardPainter({
    required this.rows,
    required this.columns,
    required this.shots,
    this.ownShips = const <ShipPlacement>[],
    this.ownSunkShips = const <String>{},
    this.selectedCell,
  });

  /// The number of rows of the board.
  final int rows;

  /// The number of columns of the board.
  final int columns;

  /// The shots the shooter already fired.
  final List<ShotView> shots;

  /// The viewer's own fleet, drawn faded under the shots.
  final List<ShipPlacement> ownShips;

  /// The viewer's ships that were sunk.
  final Set<String> ownSunkShips;

  /// The cell the shooter picked.
  final CellCoord? selectedCell;

  @override
  void paint(Canvas canvas, Size size) {
    final double cellSize = math.min(
      size.width / columns,
      size.height / rows,
    );
    final double offsetX = (size.width - cellSize * columns) / 2;
    final double offsetY = (size.height - cellSize * rows) / 2;

    final Rect board = Rect.fromLTWH(
      offsetX,
      offsetY,
      cellSize * columns,
      cellSize * rows,
    );

    canvas.drawRect(board, Paint()..color = AppTheme.surface);

    final Paint grid = Paint()
      ..color = AppTheme.surfaceBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int column = 1; column < columns; column++) {
      final double x = offsetX + cellSize * column;
      canvas.drawLine(
        Offset(x, offsetY),
        Offset(x, offsetY + cellSize * rows),
        grid,
      );
    }
    for (int row = 1; row < rows; row++) {
      final double y = offsetY + cellSize * row;
      canvas.drawLine(
        Offset(offsetX, y),
        Offset(offsetX + cellSize * columns, y),
        grid,
      );
    }
    canvas.drawRect(
      board,
      Paint()
        ..color = AppTheme.surfaceBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // The own fleet stays visible but never competes with the shot markers.
    for (final ShipPlacement ship in ownShips) {
      final List<CellCoord> cells = ship.cells;
      if (cells.isEmpty) continue;
      final Rect hull = Rect.fromLTRB(
        offsetX + cells.first.column * cellSize,
        offsetY + cells.first.row * cellSize,
        offsetX + (cells.last.column + 1) * cellSize,
        offsetY + (cells.last.row + 1) * cellSize,
      );
      final RRect shape = RRect.fromRectAndRadius(
        hull.deflate(2),
        Radius.circular(math.min(8, cellSize * 0.2)),
      );
      final bool sunk = ownSunkShips.contains(ship.shipId);
      final Color color = sunk ? AppTheme.sunk : AppTheme.accent;
      canvas.drawRRect(
        shape,
        Paint()..color = color.withValues(alpha: 0.12),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..color = color.withValues(alpha: 0.38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    for (final ShotView shot in shots) {
      final Offset center = Offset(
        offsetX + (shot.column + 0.5) * cellSize,
        offsetY + (shot.row + 0.5) * cellSize,
      );
      switch (shot.result) {
        case ShotResult.miss:
          canvas.drawCircle(
            center,
            cellSize * 0.16,
            Paint()..color = AppTheme.miss,
          );
        case ShotResult.hit:
          canvas.drawCircle(
            center,
            cellSize * 0.3,
            Paint()..color = AppTheme.hit,
          );
        case ShotResult.shipSunk:
          canvas.drawCircle(
            center,
            cellSize * 0.34,
            Paint()..color = AppTheme.sunk,
          );
          canvas.drawCircle(
            center,
            cellSize * 0.16,
            Paint()..color = AppTheme.background,
          );
      }
    }

    final CellCoord? selected = selectedCell;
    if (selected != null) {
      final Rect highlight = Rect.fromLTWH(
        offsetX + selected.column * cellSize,
        offsetY + selected.row * cellSize,
        cellSize,
        cellSize,
      );
      canvas.drawRect(
        highlight,
        Paint()
          ..color = AppTheme.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BattleBoardPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.columns != columns ||
      oldDelegate.shots != shots ||
      oldDelegate.ownShips != ownShips ||
      oldDelegate.ownSunkShips != ownSunkShips ||
      oldDelegate.selectedCell != selectedCell;
}
