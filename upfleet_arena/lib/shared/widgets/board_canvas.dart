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
    this.selectedShipId,
    this.preview,
    this.previewIsValid = true,
    this.onCellPreview,
    this.onPreviewCleared,
    this.onCellCommit,
    this.onPointerDown,
    this.onLongPressStart,
    this.onLongPressMove,
    this.onLongPressEnd,
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

  /// The ship the player is holding: its hull is drawn brighter, so it is
  /// clear which ship a rotate or a drag applies to.
  final String? selectedShipId;

  /// The ship that would be placed at the cell under the finger.
  final ShipPlacement? preview;

  /// Whether the preview would fit on the board.
  final bool previewIsValid;

  /// Called while the finger moves over the board.
  final void Function(CellCoord cell)? onCellPreview;

  /// Called with the cell the finger touched, before any gesture is
  /// recognized.
  ///
  /// The placement screen uses it to pick up the ship under the finger, so an
  /// auto-placed fleet stays editable and the hull keeps the grabbed cell
  /// under the finger while it is dragged.
  final void Function(CellCoord cell)? onPointerDown;

  /// Called when a press and hold is recognized on a cell.
  ///
  /// The placement screen uses it to grab the ship under the finger and then
  /// rotate it with a sideways swish.
  final void Function(CellCoord cell)? onLongPressStart;

  /// Called while the held finger moves to another cell.
  final void Function(CellCoord cell)? onLongPressMove;

  /// Called when the press and hold ends or is cancelled.
  final VoidCallback? onLongPressEnd;

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

        void previewAt(Offset local) {
          final CellCoord? cell = cellAt(local);
          if (cell != null) {
            onCellPreview?.call(cell);
          } else {
            onPreviewCleared?.call();
          }
        }

        return Center(
          child: Semantics(
            label: AppLocalizations.of(context).ownBoardSemantics(rows, columns),
            container: true,
            child: Listener(
              onPointerDown: (PointerDownEvent event) {
                final CellCoord? cell = cellAt(event.localPosition);
                if (cell != null) onPointerDown?.call(cell);
              },
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
                onLongPressStart: (LongPressStartDetails details) {
                  final CellCoord? cell = cellAt(details.localPosition);
                  if (cell != null) onLongPressStart?.call(cell);
                },
                onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) {
                  final CellCoord? cell = cellAt(details.localPosition);
                  if (cell != null) onLongPressMove?.call(cell);
                },
                onLongPressEnd: (LongPressEndDetails details) =>
                    onLongPressEnd?.call(),
                // Dragging is recognized per axis: a free pan needs twice the
                // touch slop, so a vertical drag inside a scrolling page would
                // be stolen by the scroll view before the board saw it.
                onVerticalDragStart: (DragStartDetails details) =>
                    previewAt(details.localPosition),
                onVerticalDragUpdate: (DragUpdateDetails details) =>
                    previewAt(details.localPosition),
                onVerticalDragEnd: (DragEndDetails details) => onDragEnd?.call(),
                onVerticalDragCancel: onDragEnd,
                onHorizontalDragStart: (DragStartDetails details) =>
                    previewAt(details.localPosition),
                onHorizontalDragUpdate: (DragUpdateDetails details) =>
                    previewAt(details.localPosition),
                onHorizontalDragEnd: (DragEndDetails details) =>
                    onDragEnd?.call(),
                onHorizontalDragCancel: onDragEnd,
                child: CustomPaint(
                  painter: BoardPainter(
                    rows: rows,
                    columns: columns,
                    ships: ships,
                    shots: shots,
                    misses: misses,
                    shotColors: shotColors,
                    sunkShips: sunkShips,
                    selectedShipId: selectedShipId,
                    preview: preview,
                    previewIsValid: previewIsValid,
                  ),
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
    this.selectedShipId,
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

  /// The ship the player is holding, drawn brighter than the rest.
  final String? selectedShipId;

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
        highlighted: ship.shipId == selectedShipId,
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
    double opacity, {
    bool highlighted = false,
  }) {
    final List<CellCoord> cells = ship.cells;
    if (cells.isEmpty) return;

    final Rect hull = Rect.fromLTRB(
      offsetX + cells.first.column * cellSize,
      offsetY + cells.first.row * cellSize,
      offsetX + (cells.last.column + 1) * cellSize,
      offsetY + (cells.last.row + 1) * cellSize,
    );

    if (highlighted) {
      // A soft halo marks the held hull, and a light ring on its edge
      // separates it from the ships that touch it.
      final Paint halo = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(6, cellSize * 0.22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          hull.deflate(cellSize * 0.1),
          Radius.circular(math.min(10, cellSize * 0.3)),
        ),
        halo,
      );
      final Paint ring = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, cellSize * 0.06);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          hull.deflate(1),
          Radius.circular(math.min(8, cellSize * 0.2)),
        ),
        ring,
      );
    }

    final Paint fill = Paint()
      ..color = color.withValues(alpha: highlighted ? 1 : opacity)
      ..style = PaintingStyle.fill;
    final RRect shape = RRect.fromRectAndRadius(
      hull.deflate(2),
      Radius.circular(math.min(8, cellSize * 0.2)),
    );
    canvas.drawRRect(shape, fill);

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlighted ? 3 : 2;
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
      oldDelegate.selectedShipId != selectedShipId ||
      oldDelegate.preview != preview ||
      oldDelegate.previewIsValid != previewIsValid;
}
