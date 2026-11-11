import 'dart:math';

import '../../shared/models/room_models.dart';

/// The fleet a player has to place.
///
/// A fleet is described by the size of its ships: the count, the length and
/// the span of every ship drive both the placement validation and the sinking
/// rules (PLAN.md §2.4). A ship is one cell thick unless its span equals its
/// length, which makes it a square block such as 2×2 or 3×3.
class FleetProfile {
  const FleetProfile(this.shipLengths, {this.shipSpans = const <int>[]});

  /// The length of every ship, longest first.
  final List<int> shipLengths;

  /// The cells every ship covers across its direction.
  ///
  /// Shorter than [shipLengths] when the last ships are lines: a missing entry
  /// means a span of one cell.
  final List<int> shipSpans;

  /// The number of ships in the fleet.
  int get shipCount => shipLengths.length;

  /// The number of cells the whole fleet occupies.
  int get totalCells {
    int sum = 0;
    for (int index = 0; index < shipLengths.length; index++) {
      sum += shipLengths[index] * spanAt(index);
    }
    return sum;
  }

  /// The span of the ship at [index], defaulting to a one-cell line.
  int spanAt(int index) =>
      index < shipSpans.length && shipSpans[index] > 0 ? shipSpans[index] : 1;

  /// The stable identifier of every ship, e.g. `ship-1`.
  ///
  /// The identifiers are derived from the profile, so the Host and the client
  /// name the same ship the same way without exchanging the list.
  List<String> get shipIds => List<String>.generate(
    shipCount,
    (int index) => 'ship-${index + 1}',
  );

  /// The length of the ship with the given identifier, or `null` when the
  /// identifier is not part of the fleet.
  int? lengthOf(String shipId) {
    final int index = shipIds.indexOf(shipId);
    return index < 0 ? null : shipLengths[index];
  }

  /// The span of the ship with the given identifier, or `null` when the
  /// identifier is not part of the fleet.
  int? spanOf(String shipId) {
    final int index = shipIds.indexOf(shipId);
    return index < 0 ? null : spanAt(index);
  }

  /// The number of cells one ship of the fleet covers.
  int? cellsOf(String shipId) {
    final int? length = lengthOf(shipId);
    final int? span = spanOf(shipId);
    if (length == null || span == null) return null;
    return length * span;
  }

  /// The side of the square block the ship may be drawn as, or `null` when
  /// its cells cannot form a square.
  ///
  /// Only 4, 9, 16 … cells can be laid out as a square, so a three-cell ship
  /// always stays a line.
  int? squareSideOf(String shipId) {
    final int? cells = cellsOf(shipId);
    return cells == null ? null : squareSideFor(cells);
  }

  /// The side of the square made of [cells] cells, or `null` when the count
  /// cannot form one.
  static int? squareSideFor(int cells) {
    if (cells < 4) return null;
    final int side = sqrt(cells).round();
    return side * side == cells ? side : null;
  }

  /// Builds the profile of a fleet preset.
  factory FleetProfile.fromPreset(FleetPreset preset) =>
      FleetProfile(preset.shipLengths, shipSpans: preset.shipSpans);

  @override
  bool operator ==(Object other) {
    if (other is! FleetProfile) return false;
    if (other.shipLengths.length != shipLengths.length) return false;
    for (int index = 0; index < shipLengths.length; index++) {
      if (other.shipLengths[index] != shipLengths[index]) return false;
      if (other.spanAt(index) != spanAt(index)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<int>[
    for (int index = 0; index < shipLengths.length; index++)
      Object.hash(shipLengths[index], spanAt(index)),
  ]);

  @override
  String toString() => 'FleetProfile($shipLengths, $shipSpans)';
}
