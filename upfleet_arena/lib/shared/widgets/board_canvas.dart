import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:flutter/gestures.dart';
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
///
/// A ship drag is handled at the pointer level instead of with the standard
/// drag recognizers: the recognizers only start after a touch slop and have to
/// fight the scroll view that contains the board, which made the ghost lag and
/// let a vertical drag be cancelled mid-way. An eager recognizer claims the
/// pointer as soon as a ship is picked up, while the [Listener] below reports
/// every move from the first pixel.
class BoardCanvas extends StatefulWidget {
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

  /// Called while the finger moves over a cell of the board.
  ///
  /// Only a change of cell is reported: a pointer sends many events for the
  /// same cell, and rebuilding for each one made dragging visibly stutter.
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

  /// Called when a drag ends over a cell of the board.
  ///
  /// A drag that ends outside the board, or that is cancelled, does not call
  /// it: the ghost simply disappears and nothing is placed.
  final VoidCallback? onDragEnd;

  bool get _interactive =>
      onCellPreview != null ||
      onCellCommit != null ||
      onPointerDown != null ||
      onDragEnd != null;

  @override
  State<BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends State<BoardCanvas> {
  /// The size of one cell, kept from the last layout for the pointer events.
  double _cellSize = 1;

  /// The pointer that started the current touch, if any.
  int? _pointer;
  Offset? _downPosition;
  CellCoord? _downCell;

  /// The last cell reported to the screen.
  CellCoord? _lastCell;

  /// Whether this touch belongs to the board or to the surrounding scroll view.
  bool _ownsGesture = false;
  bool _dragging = false;
  bool _longPressActive = false;
  Timer? _longPressTimer;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  CellCoord? _cellAt(Offset local) {
    final int column = (local.dx / _cellSize).floor();
    final int row = (local.dy / _cellSize).floor();
    if (row < 0 ||
        row >= widget.rows ||
        column < 0 ||
        column >= widget.columns) {
      return null;
    }
    return CellCoord(row, column);
  }

  /// A ship held by the player, or a ship lying under the finger, is a drag.
  ///
  /// A touch on empty water is left to the page, so the player can still
  /// scroll past a board that fills most of a phone screen.
  bool _shouldOwnGesture(CellCoord cell) {
    if (widget.selectedShipId != null) return true;
    for (final ShipPlacement ship in widget.ships) {
      if (ship.cells.contains(cell)) return true;
    }
    return false;
  }

  void _reportCell(CellCoord? cell) {
    if (cell == _lastCell) return;
    _lastCell = cell;
    if (cell == null) {
      widget.onPreviewCleared?.call();
    } else {
      widget.onCellPreview?.call(cell);
    }
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    final CellCoord? cell = _cellAt(event.localPosition);
    _pointer = event.pointer;
    _downPosition = event.localPosition;
    _downCell = cell;
    _lastCell = null;
    _dragging = false;
    _longPressActive = false;
    _ownsGesture = cell != null && _shouldOwnGesture(cell);
    if (cell == null) return;

    widget.onPointerDown?.call(cell);
    if (_ownsGesture) {
      _longPressTimer = Timer(kLongPressTimeout, () {
        _longPressActive = true;
        widget.onLongPressStart?.call(cell);
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || !_ownsGesture) return;
    final Offset down = _downPosition!;
    final CellCoord? cell = _cellAt(event.localPosition);
    if (!_dragging) {
      // A small jitter inside the touched cell is still a tap. Crossing into
      // another cell (or travelling a full touch slop) starts the drag without
      // waiting for the standard drag recognizer.
      final bool movedFar = (event.localPosition - down).distance > kTouchSlop;
      if (!movedFar && cell == _downCell) return;
      _dragging = true;
      _cancelLongPress();
    }

    if (_longPressActive) {
      // A held finger swished sideways rotates the ship instead of moving it.
      if (cell != null && cell != _lastCell) {
        _lastCell = cell;
        widget.onLongPressMove?.call(cell);
      }
      return;
    }
    _reportCell(cell);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    if (_ownsGesture) {
      final CellCoord? cell = _cellAt(event.localPosition);
      if (_longPressActive) {
        widget.onLongPressEnd?.call();
        _reportCell(null);
      } else if (_dragging) {
        if (cell == null) {
          // Releasing outside the board cancels the drop (PHASE3 §1.5).
          _reportCell(null);
        } else {
          _reportCell(cell);
          widget.onDragEnd?.call();
        }
      } else {
        _reportCell(null);
        if (cell != null) widget.onCellCommit?.call(cell);
      }
    }
    _finishPointer();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    if (_longPressActive) widget.onLongPressEnd?.call();
    if (_ownsGesture) _reportCell(null);
    _finishPointer();
  }

  void _finishPointer() {
    _cancelLongPress();
    _pointer = null;
    _downPosition = null;
    _downCell = null;
    _lastCell = null;
    _dragging = false;
    _longPressActive = false;
    _ownsGesture = false;
  }

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
          available / widget.columns,
          available / widget.rows,
        );
        _cellSize = cellSize;

        final Widget paint = RepaintBoundary(
          child: CustomPaint(
            painter: BoardPainter(
              rows: widget.rows,
              columns: widget.columns,
              ships: widget.ships,
              shots: widget.shots,
              misses: widget.misses,
              shotColors: widget.shotColors,
              sunkShips: widget.sunkShips,
              selectedShipId: widget.selectedShipId,
              preview: widget.preview,
              previewIsValid: widget.previewIsValid,
            ),
          ),
        );

        final Widget board = SizedBox(
          width: cellSize * widget.columns,
          height: cellSize * widget.rows,
          child: paint,
        );

        return Center(
          child: Semantics(
            label: AppLocalizations.of(context)
                .ownBoardSemantics(widget.rows, widget.columns),
            container: true,
            child: widget._interactive
                ? RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: <Type, GestureRecognizerFactory>{
                      _BoardGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _BoardGestureRecognizer
                          >(
                            () => _BoardGestureRecognizer(
                              shouldClaim: () => _ownsGesture,
                            ),
                            (_BoardGestureRecognizer instance) {
                              instance.shouldClaim = () => _ownsGesture;
                            },
                          ),
                    },
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerCancel,
                      child: board,
                    ),
                  )
                : board,
          ),
        );
      },
    );
  }
}

/// Claims the gesture on pointer down so the page cannot scroll away while a
/// ship is being dragged.
///
/// The claim is conditional: a touch on empty water with nothing selected is
/// left to the surrounding [ListView].
class _BoardGestureRecognizer extends EagerGestureRecognizer {
  _BoardGestureRecognizer({required this.shouldClaim});

  bool Function() shouldClaim;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!shouldClaim()) return;
    super.addAllowedPointer(event);
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
      !listEquals(oldDelegate.ships, ships) ||
      !listEquals(oldDelegate.shots, shots) ||
      !listEquals(oldDelegate.misses, misses) ||
      !mapEquals(oldDelegate.shotColors, shotColors) ||
      !setEquals(oldDelegate.sunkShips, sunkShips) ||
      oldDelegate.selectedShipId != selectedShipId ||
      oldDelegate.preview != preview ||
      oldDelegate.previewIsValid != previewIsValid;
}
