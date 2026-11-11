import '../board/board.dart';
import '../fleet/fleet_profile.dart';
import 'placement.dart';

/// The reason a placement was rejected.
enum PlacementProblem {
  /// The ship reaches outside the board.
  outOfBounds,

  /// The ship overlaps another ship.
  overlapping,

  /// The ship identifier is not part of the fleet.
  unknownShip,

  /// The ship length does not match the fleet profile.
  wrongLength,

  /// The ship span does not match the fleet profile: a square ship sent as a
  /// line, or the other way round.
  wrongShape,

  /// The fleet is not placed completely.
  incompleteFleet,
}

/// A rejected placement, with a message the UI can show as-is.
class PlacementError {
  const PlacementError(this.problem, this.message);

  /// The machine-readable reason.
  final PlacementProblem problem;

  /// A user-safe explanation.
  final String message;

  @override
  String toString() => 'PlacementError(${problem.name}): $message';
}

/// Validates a fleet profile against the board dimensions.
///
/// Returns an empty list when the fleet can be placed, otherwise the reasons.
List<String> validateFleetProfile(
  FleetProfile profile,
  int rows,
  int columns,
) {
  final List<String> problems = validateBoardConfig(rows, columns);
  if (profile.shipLengths.any((int length) => length <= 0)) {
    problems.add('A ship must be at least one cell long.');
  }
  if (profile.shipSpans.any((int span) => span <= 0)) {
    problems.add('A ship must be at least one cell wide.');
  }
  final int longestSide = rows > columns ? rows : columns;
  for (int index = 0; index < profile.shipLengths.length; index++) {
    final int length = profile.shipLengths[index];
    final int span = profile.spanAt(index);
    if (length > longestSide || span > longestSide) {
      problems.add(
        'A $length×$span ship does not fit on a $rows×$columns board.',
      );
    }
  }
  if (profile.totalCells > rows * columns) {
    problems.add(
      'The fleet occupies ${profile.totalCells} cells and does not fit on a '
      '$rows×$columns board.',
    );
  }
  return problems;
}

/// Validates one ship against the board and the other ships.
///
/// The candidate may be a ship that is already on the board: it is compared
/// against every other ship, never against itself.
PlacementError? validateShipPlacement({
  required BoardSize board,
  required FleetProfile profile,
  required List<ShipPlacement> ships,
  required ShipPlacement candidate,
}) {
  final int? expectedLength = profile.lengthOf(candidate.shipId);
  if (expectedLength == null) {
    return PlacementError(
      PlacementProblem.unknownShip,
      'That ship is not part of this fleet.',
    );
  }
  final int expectedSpan = profile.spanOf(candidate.shipId) ?? 1;
  final int expectedCells = expectedLength * expectedSpan;
  // A ship whose cells form a square may be drawn as a block instead of a
  // line: the cells stay the same, only the footprint changes.
  final int? side = profile.squareSideOf(candidate.shipId);
  final bool asLine =
      candidate.length == expectedLength && candidate.span == expectedSpan;
  final bool asBlock =
      side != null && candidate.length == side && candidate.span == side;
  if (!asLine && !asBlock) {
    if (candidate.length * candidate.span != expectedCells) {
      return PlacementError(
        PlacementProblem.wrongLength,
        'This ship covers $expectedCells cells.',
      );
    }
    return PlacementError(
      PlacementProblem.wrongShape,
      side == null
          ? 'This ship is one cell wide.'
          : 'This ship covers $expectedCells cells as a line or as a '
                '$side×$side block.',
    );
  }

  final List<CellCoord> cells = candidate.cells;
  for (final CellCoord cell in cells) {
    if (!board.contains(cell)) {
      return PlacementError(
        PlacementProblem.outOfBounds,
        'That ship does not fit on the board.',
      );
    }
  }

  final Set<CellCoord> taken = <CellCoord>{};
  for (final ShipPlacement ship in ships) {
    if (ship.shipId == candidate.shipId) continue;
    taken.addAll(ship.cells);
  }
  for (final CellCoord cell in cells) {
    if (taken.contains(cell)) {
      return PlacementError(
        PlacementProblem.overlapping,
        'That ship overlaps another one.',
      );
    }
  }
  return null;
}

/// Validates a whole fleet layout.
///
/// The layout may be incomplete — a player places the ships one by one — but
/// every ship that is placed has to be legal.
PlacementError? validateFleetLayout({
  required BoardSize board,
  required FleetProfile profile,
  required List<ShipPlacement> ships,
}) {
  final Set<String> seen = <String>{};
  for (final ShipPlacement ship in ships) {
    if (!seen.add(ship.shipId)) {
      return PlacementError(
        PlacementProblem.unknownShip,
        'The same ship was sent twice.',
      );
    }
    final PlacementError? error = validateShipPlacement(
      board: board,
      profile: profile,
      ships: ships,
      candidate: ship,
    );
    if (error != null) return error;
  }
  return null;
}

/// Whether every ship of the fleet is placed.
bool isFleetComplete(FleetProfile profile, List<ShipPlacement> ships) {
  final Set<String> placed = ships
      .where((ShipPlacement ship) => ship.isPlaced)
      .map((ShipPlacement ship) => ship.shipId)
      .toSet();
  return placed.length == profile.shipCount &&
      profile.shipIds.every(placed.contains);
}
