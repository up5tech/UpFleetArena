import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/board/board.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../shared/models/match_models.dart';

/// The single shared battle map.
///
/// Every player and the whole of every fleet live on the same board: the own
/// ships are drawn as hulls, and the shots of everybody are drawn on top of
/// them. The shape of a mark tells what the shot did (miss, hit, sunk) and
/// its colour tells who fired it. The ships of the opponents stay hidden:
/// only the shots are shared (PLAN.md §2.2).
class BattleBoard extends StatelessWidget {
  const BattleBoard({
    super.key,
    required this.rows,
    required this.columns,
    required this.shots,
    this.ships = const <ShipPlacement>[],
    this.sunkShips = const <String>{},
    this.sunkOpponentShips = const <SunkShipView>[],
    this.shooterColors = const <String, Color>{},
    this.selectedCell,
    this.onCellTapped,
    this.onCellDoubleTapped,
    this.enabled = true,
  });

  /// The number of rows of the board.
  final int rows;

  /// The number of columns of the board.
  final int columns;

  /// The own ships, which share the map with every shot.
  final List<ShipPlacement> ships;

  /// The own ships that were sunk: their hulls are drawn in the sunk colour.
  final Set<String> sunkShips;

  /// The ships of the opponents that are already sunk.
  ///
  /// Their hulls are outlined in the colour of the player who owned them, so
  /// the room can tell whose fleet lost the ship. Only sunk ships are here: a
  /// fleet that is still afloat never reaches this widget.
  final List<SunkShipView> sunkOpponentShips;

  /// The shots of every player, on this board.
  final List<ShotView> shots;

  /// The colour of every shooter, keyed by player id.
  final Map<String, Color> shooterColors;

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
        final double cellSize = math.min(available / columns, available / rows);

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
            label: AppLocalizations.of(context)
                .battleMapSemantics(rows, columns),
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
                    ships: ships,
                    sunkShips: sunkShips,
                    sunkOpponentShips: sunkOpponentShips,
                    shots: shots,
                    shooterColors: shooterColors,
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

/// The own hulls are drawn faded on the shared map, so the coloured marks of
/// every shooter stay the first thing the eye reads.
const double _hullFillOpacity = 0.18;
const double _hullStrokeOpacity = 0.35;
const double _sunkHullFillOpacity = 0.14;
const double _sunkHullStrokeOpacity = 0.3;

/// The hull of a sunk opponent is only an outline, faded like the own fleet,
/// so it frames the marks without hiding them.
const double _sunkOpponentOutlineOpacity = 0.5;
const double _sunkOpponentOutlineWidth = 2;

/// Draws the grid, the own fleet, the shots of every player and the picked
/// cell.
class BattleBoardPainter extends CustomPainter {
  const BattleBoardPainter({
    required this.rows,
    required this.columns,
    required this.shots,
    this.ships = const <ShipPlacement>[],
    this.sunkShips = const <String>{},
    this.sunkOpponentShips = const <SunkShipView>[],
    this.shooterColors = const <String, Color>{},
    this.selectedCell,
  });

  /// The number of rows of the board.
  final int rows;

  /// The number of columns of the board.
  final int columns;

  /// The own ships, which share the map with every shot.
  final List<ShipPlacement> ships;

  /// The own ships that were sunk.
  final Set<String> sunkShips;

  /// The ships of the opponents that are already sunk.
  final List<SunkShipView> sunkOpponentShips;

  /// The shots of every player, on this board.
  final List<ShotView> shots;

  /// The colour of every shooter, keyed by player id.
  final Map<String, Color> shooterColors;

  /// The cell the shooter picked.
  final CellCoord? selectedCell;

  @override
  void paint(Canvas canvas, Size size) {
    final double cellSize = math.min(size.width / columns, size.height / rows);
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

    // The own fleet shares the map with the shots, so it is drawn first and
    // the marks land on top of it. The hulls stay faded: the fleet is only
    // the ground the marks are read against, so it must not compete with the
    // coloured shots of every player.
    for (final ShipPlacement ship in ships) {
      final bool sunk = sunkShips.contains(ship.shipId);
      _drawShip(
        canvas,
        ship,
        offsetX,
        offsetY,
        cellSize,
        sunk ? AppTheme.sunk : AppTheme.accent,
        sunk ? _sunkHullFillOpacity : _hullFillOpacity,
        sunk ? _sunkHullStrokeOpacity : _hullStrokeOpacity,
      );
    }

    // A sunk opponent hull is outlined in the colour of its owner and stays
    // faded, so the fleet reads as "this one is gone" without competing with
    // the marks of the shots it carries.
    for (final SunkShipView sunk in sunkOpponentShips) {
      _drawSunkOpponent(
        canvas,
        sunk,
        offsetX,
        offsetY,
        cellSize,
        shooterColors[sunk.ownerPlayerId] ?? AppTheme.textSecondary,
      );
    }

    // Group the shots by cell, so that several players firing at the same
    // cell each get their own visible mark instead of overlapping.
    final Map<String, List<ShotView>> shotsByCell = <String, List<ShotView>>{};
    for (final ShotView shot in shots) {
      shotsByCell
          .putIfAbsent('${shot.row},${shot.column}', () => <ShotView>[])
          .add(shot);
    }
    for (final MapEntry<String, List<ShotView>> entry in shotsByCell.entries) {
      final List<ShotView> cellShots = entry.value;
      final int count = cellShots.length;
      for (int i = 0; i < count; i++) {
        final ShotView shot = cellShots[i];
        final double angle = count == 1 ? 0 : (2 * math.pi * i / count);
        final double radiusOffset = count == 1 ? 0 : cellSize * 0.18;
        final Offset center = Offset(
          offsetX +
              (shot.column + 0.5) * cellSize +
              math.cos(angle) * radiusOffset,
          offsetY +
              (shot.row + 0.5) * cellSize +
              math.sin(angle) * radiusOffset,
        );
        final Color color =
            shooterColors[shot.attackerPlayerId] ?? AppTheme.accent;
        switch (shot.result) {
          case ShotResult.miss:
            // A miss is a small hollow ring, so it never looks like a hit.
            canvas.drawCircle(
              center,
              cellSize * 0.13,
              Paint()
                ..color = color.withValues(alpha: 0.75)
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(1.5, cellSize * 0.06),
            );
          case ShotResult.hit:
            canvas.drawCircle(center, cellSize * 0.18, Paint()..color = color);
          case ShotResult.shipSunk:
            canvas.drawCircle(center, cellSize * 0.22, Paint()..color = color);
            canvas.drawCircle(
              center,
              cellSize * 0.1,
              Paint()..color = AppTheme.background,
            );
        }
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

  /// Outlines the hull of a sunk opponent ship, without filling it.
  void _drawSunkOpponent(
    Canvas canvas,
    SunkShipView ship,
    double offsetX,
    double offsetY,
    double cellSize,
    Color color,
  ) {
    final List<CellCoord> cells = ship.placement.cells;
    if (cells.isEmpty) return;

    final Rect hull = Rect.fromLTRB(
      offsetX + cells.first.column * cellSize,
      offsetY + cells.first.row * cellSize,
      offsetX + (cells.last.column + 1) * cellSize,
      offsetY + (cells.last.row + 1) * cellSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        hull.deflate(2),
        Radius.circular(math.min(8, cellSize * 0.2)),
      ),
      Paint()
        ..color = color.withValues(alpha: _sunkOpponentOutlineOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _sunkOpponentOutlineWidth,
    );
  }

  void _drawShip(
    Canvas canvas,
    ShipPlacement ship,
    double offsetX,
    double offsetY,
    double cellSize,
    Color color,
    double opacity,
    double strokeOpacity,
  ) {
    final List<CellCoord> cells = ship.cells;
    if (cells.isEmpty) return;

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
    canvas.drawRRect(
      shape,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..color = color.withValues(alpha: strokeOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant BattleBoardPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.columns != columns ||
      oldDelegate.ships != ships ||
      oldDelegate.sunkShips != sunkShips ||
      oldDelegate.sunkOpponentShips != sunkOpponentShips ||
      oldDelegate.shots != shots ||
      oldDelegate.shooterColors != shooterColors ||
      oldDelegate.selectedCell != selectedCell;
}
