/// The board model of the pure game engine.
///
/// The engine is deliberately free of Flutter and networking: every rule in
/// this library can be unit-tested on its own (PLAN.md §9.1).
library;

/// A cell of a board.
class CellCoord {
  const CellCoord(this.row, this.column);

  /// The zero-based row, counted from the top.
  final int row;

  /// The zero-based column, counted from the left.
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CellCoord && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'r$row c$column';
}

/// The size of a board.
///
/// Rows and columns are stored independently so that a rectangular board
/// works exactly like a square one (PLAN.md §2.3).
class BoardSize {
  const BoardSize({required this.rows, required this.columns});

  /// The number of rows.
  final int rows;

  /// The number of columns.
  final int columns;

  /// The number of cells on the board.
  int get cellCount => rows * columns;

  /// Whether the cell lies on the board.
  bool contains(CellCoord cell) =>
      cell.row >= 0 &&
      cell.row < rows &&
      cell.column >= 0 &&
      cell.column < columns;

  @override
  bool operator ==(Object other) =>
      other is BoardSize && other.rows == rows && other.columns == columns;

  @override
  int get hashCode => Object.hash(rows, columns);

  @override
  String toString() => '$rows×$columns';
}

/// Validates the board dimensions.
///
/// Returns an empty list when the dimensions are acceptable, otherwise a list
/// of human-readable reasons.
List<String> validateBoardConfig(int rows, int columns) {
  final List<String> problems = <String>[];
  if (rows <= 0) {
    problems.add('The board must have at least one row.');
  }
  if (columns <= 0) {
    problems.add('The board must have at least one column.');
  }
  return problems;
}
