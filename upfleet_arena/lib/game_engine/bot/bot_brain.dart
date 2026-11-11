import 'dart:math';

import '../board/board.dart';
import '../combat/combat.dart';

/// How strong a computer opponent plays.
enum BotDifficulty {
  /// Fires at random cells and never follows up a hit.
  easy,

  /// Keeps firing around a hit until the ship is sunk.
  medium,

  /// Follows up hits and hunts on a checkerboard pattern.
  hard;

  /// Parses a wire value, falling back to [BotDifficulty.medium].
  static BotDifficulty fromWire(String? value) => switch (value) {
    'easy' => BotDifficulty.easy,
    'hard' => BotDifficulty.hard,
    _ => BotDifficulty.medium,
  };

  /// Wire representation.
  String get wire => name;
}

/// Decides where a computer opponent fires.
///
/// The brain is pure and stateless: it reads the board size and the cells the
/// bot already fired at, and answers with a cell. Every rule of a turn is
/// still validated by the Host, so a bot goes through the same path as a
/// remote client.
///
/// One shot is resolved against every living fleet, so the bot reasons about
/// a single set of cells instead of one board per opponent.
class BotBrain {
  BotBrain({required this.difficulty, Random? random})
    : _random = random ?? Random();

  /// The strength of this opponent.
  final BotDifficulty difficulty;

  final Random _random;

  /// Picks the next cell, or `null` when no cell is left.
  CellCoord? chooseCell({
    required BoardSize board,
    required Map<CellCoord, ShotResult> shots,
  }) {
    if (!_hasUnfiredCell(board, shots)) return null;
    return _chooseCell(board, shots);
  }

  /// Picks the cell to fire at.
  CellCoord _chooseCell(BoardSize board, Map<CellCoord, ShotResult> shots) {
    if (difficulty != BotDifficulty.easy) {
      final Set<CellCoord> open = _openHits(shots);
      if (open.isNotEmpty) {
        final List<CellCoord> pursuit = _pursuitCells(
          board,
          shots,
          open,
          alongAxisOnly: difficulty == BotDifficulty.hard,
        );
        if (pursuit.isNotEmpty) {
          return pursuit[_random.nextInt(pursuit.length)];
        }
      }
    }

    final List<CellCoord> free = _unfiredCells(board, shots);
    if (difficulty == BotDifficulty.hard) {
      // A ship of two or more cells always covers a cell whose row plus
      // column is even, so hunting only those cells halves the search area.
      final List<CellCoord> parity = free
          .where((CellCoord cell) => (cell.row + cell.column).isEven)
          .toList();
      if (parity.isNotEmpty) return parity[_random.nextInt(parity.length)];
    }
    return free[_random.nextInt(free.length)];
  }

  /// The hits that do not belong to a sunk ship yet.
  ///
  /// A bot cannot see which cells belonged to the ship that just sank, so the
  /// whole connected run around the sunk cell is treated as resolved. That is
  /// the closest a player with a pencil and paper can get.
  Set<CellCoord> _openHits(Map<CellCoord, ShotResult> shots) {
    final Set<CellCoord> open = <CellCoord>{
      for (final MapEntry<CellCoord, ShotResult> entry in shots.entries)
        if (entry.value != ShotResult.miss) entry.key,
    };
    for (final MapEntry<CellCoord, ShotResult> entry in shots.entries) {
      if (entry.value != ShotResult.shipSunk) continue;
      _removeConnected(open, entry.key);
    }
    return open;
  }

  void _removeConnected(Set<CellCoord> open, CellCoord origin) {
    final List<CellCoord> queue = <CellCoord>[origin];
    while (queue.isNotEmpty) {
      final CellCoord cell = queue.removeLast();
      if (!open.remove(cell)) continue;
      queue.addAll(<CellCoord>[
        CellCoord(cell.row - 1, cell.column),
        CellCoord(cell.row + 1, cell.column),
        CellCoord(cell.row, cell.column - 1),
        CellCoord(cell.row, cell.column + 1),
      ]);
    }
  }

  /// The cells that continue a damaged ship.
  ///
  /// With [alongAxisOnly] a hard opponent only tries to lengthen an existing
  /// line before probing the sides of a single hit.
  List<CellCoord> _pursuitCells(
    BoardSize board,
    Map<CellCoord, ShotResult> shots,
    Set<CellCoord> open, {
    required bool alongAxisOnly,
  }) {
    const List<CellCoord> neighbours = <CellCoord>[
      CellCoord(0, -1),
      CellCoord(0, 1),
      CellCoord(-1, 0),
      CellCoord(1, 0),
    ];

    final List<CellCoord> alongAxis = <CellCoord>[];
    final List<CellCoord> around = <CellCoord>[];
    final Set<CellCoord> seen = <CellCoord>{};

    for (final CellCoord hit in open) {
      for (final CellCoord step in neighbours) {
        final CellCoord candidate = CellCoord(
          hit.row + step.row,
          hit.column + step.column,
        );
        if (!board.contains(candidate)) continue;
        if (shots.containsKey(candidate)) continue;
        if (!seen.add(candidate)) continue;

        final int rowHits = open
            .where((CellCoord cell) => cell.row == candidate.row)
            .length;
        final int columnHits = open
            .where((CellCoord cell) => cell.column == candidate.column)
            .length;
        if (rowHits >= 2 || columnHits >= 2) {
          alongAxis.add(candidate);
        } else {
          around.add(candidate);
        }
      }
    }

    if (alongAxisOnly && alongAxis.isNotEmpty) return alongAxis;
    return <CellCoord>[...alongAxis, ...around];
  }

  List<CellCoord> _unfiredCells(
    BoardSize board,
    Map<CellCoord, ShotResult> shots,
  ) {
    final List<CellCoord> free = <CellCoord>[];
    for (int row = 0; row < board.rows; row++) {
      for (int column = 0; column < board.columns; column++) {
        final CellCoord cell = CellCoord(row, column);
        if (!shots.containsKey(cell)) free.add(cell);
      }
    }
    return free;
  }

  bool _hasUnfiredCell(BoardSize board, Map<CellCoord, ShotResult> shots) =>
      shots.length < board.cellCount;
}
