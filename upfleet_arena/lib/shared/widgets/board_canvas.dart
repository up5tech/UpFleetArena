import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../app/theme/app_theme.dart';
import '../../game_engine/board/board.dart';
import '../../game_engine/placement/placement.dart';

/// The board of a player.
///
/// The board is drawn with a [CustomPainter] instead of one widget per cell,
/// so a 14×14 board stays cheap to render (PLAN.md §5.3). The widget reports
/// the cell the finger is on, the placement logic stays outside.
class BoardCanvas extends StatelessWidget {
  const BoardCanvas({
    super.key,
    required this.rows,
    required this.columns,
    required this.ships,
    this.shots = const <CellCoord>[],
    this.misses = const <CellCoord>[],
    this.shotColors = const <CellCoord, Color>{},
    this.sunkShips = const <String>{},
    this.preview,
    this.previewIsValid = true,
    this.onCellPreview,
    this.onPreviewCleared,
    this.onCellCommit,
    this.onDragStart,
    this.onDragEnd,
  });

  /// The number of rows of the board.
  final int rows;

  /// The number of columns of the board.
  final int columns;

  /// The ships that are already placed.
  final List<ShipPlacement> ships;

  /// The cells that were hit on this board.
  final List<CellCoord> shots;

  /// The cells that were fired at without hitting a ship.
  final List<CellCoord> misses;

  /// The colour of a hit, per cell.
  ///
  /// The own board uses it to show which player hit which cell.
  final Map<CellCoord, Color> shotColors;

  /// The ships that were sunk: their hulls are drawn in the sunk colour.
  final Set<String> sunkShips;

  /// The ship that would be placed at the cell under the finger.
  final ShipPlacement? preview;

  /// Whether the preview would fit on the board.
  final bool previewIsValid;

  /// Called while the finger moves over the board.
  final void Function(CellCoord cell)? onCellPreview;

  /// Called when a drag starts on a cell, before the first preview.
  ///
  /// A tap never fires it: the placement screen uses it to pick up the ship
  /// under the finger so an existing fleet stays editable.
  final void Function(CellCoord cell)? onDragStart;

  /// Called when the finger leaves the board or the gesture is cancelled.
  final VoidCallback? onPreviewCleared;

  /// Called when the finger is released over a cell.
  final void Function(CellCoord cell)? onCellCommit;

  /// Called when a drag ends.
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = math.min(
          constraints.maxWidth,
          constraints.maxHeight.isFinite ? constraints.maxHeight : constraints.maxWidth,
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
            label: AppLocalizations.of(context).ownBoardSemantics(rows, columns),
            container: true,
            child: SizedBox(
              width: cellSize * columns,
              height: cellSize * rows,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails details) {
                  final CellCoord? cell = cellAt(details.localPosition);
                  if (cell != null) onCellPreview?.call(cell);
                },
                onTapUp: (TapUpDetails details) {
                  final CellCoord? cell = cellAt(details.localPosition);
                  if (cell != null) onCellCommit?.call(cell);
                },
                onTapCancel: onPreviewCleared,
                onPanStart: (DragStartDetails details) {
                  final CellCoord? cell = cellAt(details.localPosition);
                  if (cell != null) {
                    onDragStart?.call(cell);
                    onCellPreview?.call(cell);
                  }
                },
                onPanUpdate: (DragUpdateDetails details) {
                  final CellCoord? cell = cellAt(details.localPosition);
                  if (cell != null) {
                    onCellPreview?.call(cell);
                  } else {
                    onPreviewCleared?.call();
                  }
                },
                onPanEnd: (DragEndDetails details) => onDragEnd?.call(),
                child: CustomPaint(
                  painter: BoardPainter(
                    rows: rows,
                    columns: columns,
                    ships: ships,
                    shots: shots,
                    misses: misses,
                    shotColors: shotColors,
                    sunkShips: sunkShips,
                    preview: preview,
                    previewIsValid: previewIsValid,
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

/// Draws the grid, the placed ships and the placement preview.
class BoardPainter extends CustomPainter {
  const BoardPainter({
    required this.rows,
    required this.columns,
    required this.ships,
    this.shots = const <CellCoord>[],
    this.misses = const <CellCoord>[],
    this.shotColors = const <CellCoord, Color>{},
    this.sunkShips = const <String>{},
    this.preview,
    this.previewIsValid = true,
  });

  /// The number of rows of the board.
  final int rows;

  /// The number of columns of the board.
  final int columns;

  /// The ships that are already placed.
  final List<ShipPlacement> ships;

  /// The cells that were hit on this board.
  final List<CellCoord> shots;

  /// The cells that were fired at without hitting a ship.
  final List<CellCoord> misses;

  /// The colour of a hit, per cell.
  final Map<CellCoord, Color> shotColors;

  /// The ships that were sunk.
  final Set<String> sunkShips;

  /// The ship that would be placed at the cell under the finger.
  final ShipPlacement? preview;

  /// Whether the preview would fit on the board.
  final bool previewIsValid;

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

    final Paint background = Paint()
      ..color = AppTheme.surface
      ..style = PaintingStyle.fill;
    canvas.drawRect(board, background);

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

    final Paint border = Paint()
      ..color = AppTheme.surfaceBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(board, border);

    for (final ShipPlacement ship in ships) {
      final bool sunk = sunkShips.contains(ship.shipId);
      _drawShip(
        canvas,
        ship,
        offsetX,
        offsetY,
        cellSize,
        sunk ? AppTheme.sunk : AppTheme.accent,
        sunk ? 0.32 : 0.85,
      );
    }

    final double radius = cellSize * .22;
    for (final CellCoord cell in misses) {
      final Offset center = Offset(offsetX + (cell.column + .5) * cellSize, offsetY + (cell.row + .5) * cellSize);
      canvas.drawCircle(center, radius, Paint()..color = AppTheme.miss);
    }
    for (final CellCoord cell in shots) {
      final Offset center = Offset(offsetX + (cell.column + .5) * cellSize, offsetY + (cell.row + .5) * cellSize);
      final Paint mark = Paint()
        ..color = shotColors[cell] ?? AppTheme.hit
        ..strokeWidth = math.max(2, cellSize * .12)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center.translate(-radius, -radius), center.translate(radius, radius), mark);
      canvas.drawLine(center.translate(-radius, radius), center.translate(radius, -radius), mark);
    }

    final ShipPlacement? ghost = preview;
    if (ghost != null) {
      _drawShip(
        canvas,
        ghost,
        offsetX,
        offsetY,
        cellSize,
        previewIsValid ? AppTheme.accent : AppTheme.danger,
        previewIsValid ? 0.45 : 0.55,
      );
    }
  }

  void _drawShip(
    Canvas canvas,
    ShipPlacement ship,
    double offsetX,
    double offsetY,
    double cellSize,
    Color color,
    double opacity,
  ) {
    final List<CellCoord> cells = ship.cells;
    if (cells.isEmpty) return;

    final Rect hull = Rect.fromLTRB(
      offsetX + cells.first.column * cellSize,
      offsetY + cells.first.row * cellSize,
      offsetX + (cells.last.column + 1) * cellSize,
      offsetY + (cells.last.row + 1) * cellSize,
    );

    final Paint fill = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    final RRect shape = RRect.fromRectAndRadius(
      hull.deflate(2),
      Radius.circular(math.min(8, cellSize * 0.2)),
    );
    canvas.drawRRect(shape, fill);

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(shape, stroke);
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.columns != columns ||
      oldDelegate.ships != ships ||
      oldDelegate.shots != shots ||
      oldDelegate.misses != misses ||
      oldDelegate.shotColors != shotColors ||
      oldDelegate.sunkShips != sunkShips ||
      oldDelegate.preview != preview ||
      oldDelegate.previewIsValid != previewIsValid;
}
