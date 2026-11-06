import '../../shared/models/room_models.dart';

/// The fleet a player has to place.
///
/// A fleet is described by its ship lengths: the count and the length of
/// every ship drive both the placement validation and the sinking rules
/// (PLAN.md §2.4).
class FleetProfile {
  const FleetProfile(this.shipLengths);

  /// The length of every ship, longest first.
  final List<int> shipLengths;

  /// The number of ships in the fleet.
  int get shipCount => shipLengths.length;

  /// The number of cells the whole fleet occupies.
  int get totalCells =>
      shipLengths.fold(0, (int sum, int length) => sum + length);

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

  /// Builds the profile of a fleet preset.
  factory FleetProfile.fromPreset(FleetPreset preset) =>
      FleetProfile(preset.shipLengths);

  @override
  bool operator ==(Object other) {
    if (other is! FleetProfile) return false;
    if (other.shipLengths.length != shipLengths.length) return false;
    for (int index = 0; index < shipLengths.length; index++) {
      if (other.shipLengths[index] != shipLengths[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(shipLengths);

  @override
  String toString() => 'FleetProfile($shipLengths)';
}
