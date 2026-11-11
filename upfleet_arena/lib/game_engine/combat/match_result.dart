import 'combat.dart';

/// The combat statistics of one player, accumulated by the Host.
///
/// A sinking shot is a hit as well, so `shots == hits + misses` always holds
/// (PLAN.md §2.10).
class PlayerMatchStats {
  /// How many shots the player fired.
  int shots = 0;

  /// How many of them hit a ship, including the shots that sank one.
  int hits = 0;

  /// How many of them found no ship.
  int misses = 0;

  /// How many ships the player sank.
  int shipsSunk = 0;

  /// Records one shot that was resolved against every living fleet at once.
  ///
  /// The volley counts as one shot. It is a hit when at least one fleet had a
  /// ship on the cell, and every ship it sank is counted.
  void recordVolley({required bool hit, required int shipsSunk}) {
    shots++;
    if (hit) {
      hits++;
    } else {
      misses++;
    }
    this.shipsSunk += shipsSunk;
  }

  /// Records one accepted shot.
  void recordShot(ShotResult result) {
    shots++;
    switch (result) {
      case ShotResult.miss:
        misses++;
      case ShotResult.hit:
        hits++;
      case ShotResult.shipSunk:
        hits++;
        shipsSunk++;
    }
  }
}

/// The final standing of one player.
class PlayerStanding {
  const PlayerStanding({required this.rank, required this.playerId});

  /// The place of the player, starting at 1 for the winner.
  final int rank;

  /// The player the standing belongs to.
  final String playerId;
}

/// Orders the final ranking of a finished match.
///
/// The winner comes first, then the eliminated players in reverse order: the
/// fleet that sank last places second. Players that never sank keep their turn
/// order behind them (PLAN.md §2.10).
List<PlayerStanding> buildRanking({
  required List<String> turnOrder,
  required List<String> eliminationOrder,
  required String? winnerPlayerId,
}) {
  final List<String> ordered = <String>[];
  final Set<String> seen = <String>{};

  void place(String? playerId) {
    if (playerId == null || !seen.add(playerId)) return;
    ordered.add(playerId);
  }

  place(winnerPlayerId);
  for (final String playerId in eliminationOrder.reversed) {
    place(playerId);
  }
  for (final String playerId in turnOrder) {
    place(playerId);
  }

  return <PlayerStanding>[
    for (final (int index, String playerId) in ordered.indexed)
      PlayerStanding(rank: index + 1, playerId: playerId),
  ];
}
