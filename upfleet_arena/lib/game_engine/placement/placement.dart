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
/// The ship is anchored at its top-left cell. A ship is one cell thick across
/// its direction ([span] = 1) unless it is a square block such as 2×2 or 3×3,
/// where the span equals the length. The cells are always listed row by row,
/// so the first cell is the top-left corner of the hull and the last one its
/// bottom-right corner.
List<CellCoord> getShipCells({
  required int row,
  required int column,
  required ShipOrientation orientation,
  required int length,
  int span = 1,
}) {
  final int across = orientation == ShipOrientation.horizontal ? length : span;
  final int down = orientation == ShipOrientation.horizontal ? span : length;
  return <CellCoord>[
    for (int rowOffset = 0; rowOffset < down; rowOffset++)
      for (int columnOffset = 0; columnOffset < across; columnOffset++)
        CellCoord(row + rowOffset, column + columnOffset),
  ];
}

/// One ship on a board.
///
/// A ship covers a [length] × [span] rectangle: a classic ship is one cell
/// thick, a square block such as 2×2 or 3×3 has a span equal to its length.
class ShipPlacement {
  const ShipPlacement({
    required this.shipId,
    required this.length,
    required this.orientation,
    required this.row,
    required this.column,
    this.span = 1,
  });

  /// The stable identifier of the ship inside its fleet.
  final String shipId;

  /// The length of the ship in cells, along its direction.
  final int length;

  /// The direction the ship points to.
  ///
  /// A square ship looks the same in both directions; the orientation is kept
  /// so the wire form stays uniform.
  final ShipOrientation orientation;

  /// The row of the anchor cell.
  final int row;

  /// The column of the anchor cell.
  final int column;

  /// The cells the ship covers across its direction.
  ///
  /// `1` for a line, the same as [length] for a square ship.
  final int span;

  /// Whether the ship is a square block rather than a line.
  bool get isSquare => span > 1 && span == length;

  /// The cells the ship occupies.
  List<CellCoord> get cells => getShipCells(
    row: row,
    column: column,
    orientation: orientation,
    length: length,
    span: span,
  );

  /// Whether the ship is placed on the board.
  bool get isPlaced => row >= 0 && column >= 0;

  /// Returns a copy with the given fields replaced.
  ShipPlacement copyWith({
    int? length,
    ShipOrientation? orientation,
    int? row,
    int? column,
    int? span,
  }) => ShipPlacement(
    shipId: shipId,
    length: length ?? this.length,
    orientation: orientation ?? this.orientation,
    row: row ?? this.row,
    column: column ?? this.column,
    span: span ?? this.span,
  );

  /// Returns the ship rotated around its anchor cell.
  ///
  /// A square ship keeps its footprint, so rotating it changes nothing.
  ShipPlacement rotated() => isSquare
      ? this
      : copyWith(orientation: orientation.flipped);

  @override
  bool operator ==(Object other) =>
      other is ShipPlacement &&
      other.shipId == shipId &&
      other.length == length &&
      other.orientation == orientation &&
      other.row == row &&
      other.column == column &&
      other.span == span;

  @override
  int get hashCode => Object.hash(shipId, length, orientation, row, column, span);

  @override
  String toString() =>
      'ShipPlacement($shipId, ${orientation.wire}, $row/$column, '
      '$length×$span)';
}
