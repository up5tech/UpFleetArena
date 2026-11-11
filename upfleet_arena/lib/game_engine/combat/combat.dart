import '../board/board.dart';
import '../placement/placement.dart';

/// The outcome of a shot.
enum ShotResult {
  /// The cell holds no ship.
  miss,

  /// The cell holds a ship that is not sunk yet.
  hit,

  /// The cell hit the last free cell of a ship.
  shipSunk;

  /// Parses a wire value, falling back to [ShotResult.miss].
  static ShotResult fromWire(String? value) => switch (value) {
    'hit' => ShotResult.hit,
    'shipSunk' => ShotResult.shipSunk,
    _ => ShotResult.miss,
  };

  /// Wire representation.
  String get wire => name;
}

/// Orders the outcomes of a shot from no effect to the strongest.
int shotResultStrength(ShotResult result) => switch (result) {
  ShotResult.miss => 0,
  ShotResult.hit => 1,
  ShotResult.shipSunk => 2,
};

/// The stronger of two outcomes of the same shot.
///
/// One shot is resolved against every living fleet at the same cell. The
/// shared map keeps a single mark per shooter and cell, so it carries the
/// strongest outcome: a sunk ship is never hidden by a miss elsewhere.
ShotResult strongerShotResult(ShotResult a, ShotResult b) =>
    shotResultStrength(a) >= shotResultStrength(b) ? a : b;

/// One ship on a board, with the cells that were hit.
class ShipState {
  ShipState({
    required this.shipId,
    required this.length,
    required this.placement,
  });

  /// The stable identifier of the ship inside its fleet.
  final String shipId;

  /// The length of the ship in cells.
  final int length;

  /// Where the ship lies on the board.
  final ShipPlacement placement;

  /// The cells of the ship that were hit.
  final Set<CellCoord> hitCells = <CellCoord>{};

  /// The cells the ship occupies.
  ///
  /// A square ship such as 2×2 or 3×3 covers more cells than its length.
  List<CellCoord> get cells => placement.cells;

  /// Whether every cell of the ship was hit.
  bool get isSunk => hitCells.length >= cells.length;

  /// The cells of the ship that are still free.
  List<CellCoord> get freeCells =>
      cells.where((CellCoord cell) => !hitCells.contains(cell)).toList();
}

/// The board of one player, as the Host owns it.
///
/// It holds the exact fleet and every shot that was fired at it
/// (PLAN.md §2.2).
class PlayerBoard {
  PlayerBoard({required this.playerId, required List<ShipPlacement> ships})
    : ships = <String, ShipState>{
        for (final ShipPlacement ship in ships)
          ship.shipId: ShipState(
            shipId: ship.shipId,
            length: ship.length,
            placement: ship,
          ),
      };

  /// The player the board belongs to.
  final String playerId;

  /// The ships of the fleet, keyed by the ship identifier.
  final Map<String, ShipState> ships;

  /// Every cell that was fired at.
  final Set<CellCoord> shotsReceived = <CellCoord>{};

  /// The number of ships that were sunk.
  int get sunkCount =>
      ships.values.where((ShipState ship) => ship.isSunk).length;

  /// The number of cells of the fleet that are still free.
  int get remainingCells => ships.values.fold(
    0,
    (int sum, ShipState ship) => sum + ship.freeCells.length,
  );

  /// Whether every ship of the fleet was sunk.
  bool get isEliminated =>
      ships.isNotEmpty && ships.values.every((ShipState ship) => ship.isSunk);

  /// The ship that covers the cell, or `null` when the cell is empty.
  ShipState? shipAt(CellCoord cell) {
    for (final ShipState ship in ships.values) {
      if (ship.cells.contains(cell)) return ship;
    }
    return null;
  }
}

/// The result of an accepted shot.
class ShotResolution {
  const ShotResolution({required this.result, this.shipId});

  /// What the shot did.
  final ShotResult result;

  /// The ship that was hit, or `null` for a miss.
  final String? shipId;

  @override
  String toString() => 'ShotResolution(${result.name}, $shipId)';
}

/// Applies damage idempotently; the coordinator validates attacker history.
ShotResolution resolveShot(PlayerBoard board, CellCoord cell) {
  board.shotsReceived.add(cell);

  final ShipState? ship = board.shipAt(cell);
  if (ship == null) {
    return const ShotResolution(result: ShotResult.miss);
  }

  final bool wasSunk = ship.isSunk;
  ship.hitCells.add(cell);
  return ShotResolution(
    result: !wasSunk && ship.isSunk ? ShotResult.shipSunk : ShotResult.hit,
    shipId: ship.shipId,
  );
}

/// Whether the ship was sunk by the given hits.
bool isShipSunk(ShipState ship, Set<CellCoord> hitCells) =>
    hitCells.length >= ship.cells.length;

/// Whether the whole fleet of the player was sunk.
bool isPlayerEliminated(PlayerBoard board) => board.isEliminated;

/// The next player that may act.
///
/// The order is circular: the search starts behind the current player and
/// skips everyone who is not alive any more (PLAN.md §2.6).
String? getNextLivingPlayer({
  required List<String> turnOrder,
  required String currentPlayerId,
  required bool Function(String playerId) isAlive,
}) {
  final int index = turnOrder.indexOf(currentPlayerId);
  if (index < 0 || turnOrder.length < 2) return null;

  for (int step = 1; step <= turnOrder.length; step++) {
    final String candidate = turnOrder[(index + step) % turnOrder.length];
    if (isAlive(candidate)) return candidate;
  }
  return null;
}

/// Whether the match is over because only one player is left alive.
bool isMatchFinished(int alivePlayers) => alivePlayers <= 1;
