import 'dart:math';

import '../board/board.dart';
import '../fleet/fleet_profile.dart';
import 'placement.dart';

/// Places the whole fleet on the board without any overlap.
///
/// The ships are placed largest first and every ship takes a random free
/// spot, so the result is a legal layout that also looks hand-made. A ship
/// whose cells form a square is sometimes drawn as a block instead of a line.
/// The caller owns the random source, which keeps the algorithm testable
/// (PLAN.md §9.1).
List<ShipPlacement> autoPlaceFleet({
  required BoardSize board,
  required FleetProfile profile,
  required Random random,
}) {
  final List<String> shipIds = profile.shipIds;
  final List<int> order = List<int>.generate(
    shipIds.length,
    (int index) => index,
  )..sort(
    (int a, int b) => _cellsOf(profile, b).compareTo(_cellsOf(profile, a)),
  );

  final Map<String, ShipPlacement> placed = <String, ShipPlacement>{};

  for (final int index in order) {
    final String shipId = shipIds[index];
    final int baseLength = profile.shipLengths[index];
    final int baseSpan = profile.spanAt(index);
    final int? side = FleetProfile.squareSideFor(baseLength * baseSpan);
    // Half of the square-capable ships are seated as blocks, which keeps the
    // cell count and only changes the footprint.
    final bool asBlock = side != null && random.nextBool();
    final int length = asBlock ? side : baseLength;
    final int span = asBlock ? side : baseSpan;

    final List<ShipPlacement> candidates = _candidates(
      board: board,
      shipId: shipId,
      length: length,
      span: span,
    )..shuffle(random);

    ShipPlacement? chosen;
    for (final ShipPlacement candidate in candidates) {
      final bool overlaps = placed.values.any(
        (ShipPlacement ship) => ship.cells.any(
          (CellCoord cell) => candidate.cells.contains(cell),
        ),
      );
      if (!overlaps) {
        chosen = candidate;
        break;
      }
    }

    if (chosen == null) {
      // The fleet does not fit on this board. The caller validates the
      // profile before the placement starts, so this cannot happen in a
      // running room.
      continue;
    }
    placed[shipId] = chosen;
  }

  return shipIds
      .map((String shipId) => placed[shipId])
      .whereType<ShipPlacement>()
      .toList();
}

/// The number of cells the ship at [index] covers.
int _cellsOf(FleetProfile profile, int index) =>
    profile.shipLengths[index] * profile.spanAt(index);

/// Every position the ship would fit on.
List<ShipPlacement> _candidates({
  required BoardSize board,
  required String shipId,
  required int length,
  required int span,
}) {
  final List<ShipPlacement> candidates = <ShipPlacement>[];
  // A square ship covers the same cells in both directions, so one pass is
  // enough and the layout keeps no duplicates.
  final List<ShipOrientation> orientations = span == length
      ? <ShipOrientation>[ShipOrientation.horizontal]
      : ShipOrientation.values;

  for (int row = 0; row < board.rows; row++) {
    for (int column = 0; column < board.columns; column++) {
      for (final ShipOrientation orientation in orientations) {
        final ShipPlacement candidate = ShipPlacement(
          shipId: shipId,
          length: length,
          span: span,
          orientation: orientation,
          row: row,
          column: column,
        );
        if (candidate.cells.every(board.contains)) {
          candidates.add(candidate);
        }
      }
    }
  }
  return candidates;
}
