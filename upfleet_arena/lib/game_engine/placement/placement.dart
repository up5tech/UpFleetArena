import '../board/board.dart';

/// The direction a ship points to.
enum ShipOrientation {
  /// The ship lies on one row, growing to the right.
  horizontal,

  /// The ship lies on one column, growing downwards.
  vertical;

  /// Parses a wire value, falling back to [ShipOrientation.horizontal].
  static ShipOrientation fromWire(String? value) =>
      value == 'vertical' ? ShipOrientation.vertical : ShipOrientation.horizontal;

  /// The other orientation.
  ShipOrientation get flipped => this == ShipOrientation.horizontal
      ? ShipOrientation.vertical
      : ShipOrientation.horizontal;

  /// Wire representation.
  String get wire => name;
}

/// The cells a ship occupies.
///
/// The ship is anchored at its first cell: the leftmost cell for a
/// horizontal ship, the topmost cell for a vertical one.
List<CellCoord> getShipCells({
  required int row,
  required int column,
  required ShipOrientation orientation,
  required int length,
}) {
  return List<CellCoord>.generate(length, (int index) {
    return switch (orientation) {
      ShipOrientation.horizontal => CellCoord(row, column + index),
      ShipOrientation.vertical => CellCoord(row + index, column),
    };
  });
}

/// One ship on a board.
class ShipPlacement {
  const ShipPlacement({
    required this.shipId,
    required this.length,
    required this.orientation,
    required this.row,
    required this.column,
  });

  /// The stable identifier of the ship inside its fleet.
  final String shipId;

  /// The length of the ship in cells.
  final int length;

  /// The direction the ship points to.
  final ShipOrientation orientation;

  /// The row of the anchor cell.
  final int row;

  /// The column of the anchor cell.
  final int column;

  /// The cells the ship occupies.
  List<CellCoord> get cells => getShipCells(
    row: row,
    column: column,
    orientation: orientation,
    length: length,
  );

  /// Whether the ship is placed on the board.
  bool get isPlaced => row >= 0 && column >= 0;

  /// Returns a copy with the given fields replaced.
  ShipPlacement copyWith({
    int? length,
    ShipOrientation? orientation,
    int? row,
    int? column,
  }) => ShipPlacement(
    shipId: shipId,
    length: length ?? this.length,
    orientation: orientation ?? this.orientation,
    row: row ?? this.row,
    column: column ?? this.column,
  );

  /// Returns the ship rotated around its anchor cell.
  ShipPlacement rotated() => copyWith(orientation: orientation.flipped);

  @override
  bool operator ==(Object other) =>
      other is ShipPlacement &&
      other.shipId == shipId &&
      other.length == length &&
      other.orientation == orientation &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(shipId, length, orientation, row, column);

  @override
  String toString() =>
      'ShipPlacement($shipId, ${orientation.wire}, $row/$column, $length)';
}
