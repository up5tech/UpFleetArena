import '../../game_engine/placement/placement.dart';

/// The wire form of one placed ship.
///
/// Only the owner of a fleet ever receives these values: a ship layout is
/// never part of another player's view (PLAN.md §6.6, §8).
class ShipLayout {
  const ShipLayout({
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

  /// The cells the ship covers across its direction: `1` for a line, the
  /// length itself for a square ship such as 2×2 or 3×3.
  final int span;

  /// The direction the ship points to.
  final ShipOrientation orientation;

  /// The row of the anchor cell.
  final int row;

  /// The column of the anchor cell.
  final int column;

  /// Builds the wire form of a placement.
  factory ShipLayout.fromPlacement(ShipPlacement placement) => ShipLayout(
    shipId: placement.shipId,
    length: placement.length,
    span: placement.span,
    orientation: placement.orientation,
    row: placement.row,
    column: placement.column,
  );

  /// The domain placement of this ship.
  ShipPlacement toPlacement() => ShipPlacement(
    shipId: shipId,
    length: length,
    span: span,
    orientation: orientation,
    row: row,
    column: column,
  );

  /// Serializes the ship.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'shipId': shipId,
    'length': length,
    'span': span,
    'orientation': orientation.wire,
    'row': row,
    'column': column,
  };

  /// Parses a ship received from the Host.
  factory ShipLayout.fromJson(Map<String, dynamic> json) => ShipLayout(
    shipId: json['shipId'] as String? ?? '',
    length: json['length'] as int? ?? 0,
    span: json['span'] as int? ?? 1,
    orientation: ShipOrientation.fromWire(json['orientation'] as String?),
    row: json['row'] as int? ?? -1,
    column: json['column'] as int? ?? -1,
  );
}

/// The placement state of the player the message is addressed to.
///
/// It carries the exact fleet layout, so the Host sends it to its owner only.
class PlacementState {
  const PlacementState({
    required this.playerId,
    required this.ships,
    required this.ready,
    required this.stateVersion,
  });

  /// The owner of the fleet.
  final String playerId;

  /// The ships that are placed on the board.
  final List<ShipLayout> ships;

  /// Whether the player confirmed the fleet.
  final bool ready;

  /// The room state version the state belongs to.
  final int stateVersion;

  /// The domain placements of the fleet.
  List<ShipPlacement> toPlacements() =>
      ships.map((ShipLayout ship) => ship.toPlacement()).toList();

  /// Serializes the state.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'ships': ships.map((ShipLayout ship) => ship.toJson()).toList(),
    'ready': ready,
    'stateVersion': stateVersion,
  };

  /// Parses a state received from the Host.
  factory PlacementState.fromJson(Map<String, dynamic> json) {
    final Object? rawShips = json['ships'];
    final List<ShipLayout> ships = <ShipLayout>[];
    if (rawShips is List) {
      for (final Object? entry in rawShips) {
        if (entry is Map<String, dynamic>) {
          ships.add(ShipLayout.fromJson(entry));
        }
      }
    }
    return PlacementState(
      playerId: json['playerId'] as String? ?? '',
      ships: ships,
      ready: json['ready'] as bool? ?? false,
      stateVersion: json['stateVersion'] as int? ?? 0,
    );
  }
}

/// The readiness of one member, as everybody may see it.
class PlayerReadiness {
  const PlayerReadiness({
    required this.playerId,
    required this.displayName,
    required this.ready,
  });

  /// The member the readiness belongs to.
  final String playerId;

  /// The display name of the member.
  final String displayName;

  /// Whether the member confirmed a complete fleet.
  final bool ready;

  /// Serializes the readiness.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'displayName': displayName,
    'ready': ready,
  };

  /// Parses a readiness received from the Host.
  factory PlayerReadiness.fromJson(Map<String, dynamic> json) =>
      PlayerReadiness(
        playerId: json['playerId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Player',
        ready: json['ready'] as bool? ?? false,
      );
}

/// The public readiness of every member of the room.
///
/// It carries no coordinates: the fleet layout of a player stays private
/// (PLAN.md §8).
class ReadinessState {
  const ReadinessState({required this.players, required this.stateVersion});

  /// The readiness of every member that still occupies a seat.
  final List<PlayerReadiness> players;

  /// The room state version the state belongs to.
  final int stateVersion;

  /// Whether a member confirmed a complete fleet.
  bool isReady(String playerId) {
    for (final PlayerReadiness player in players) {
      if (player.playerId == playerId) return player.ready;
    }
    return false;
  }

  /// Serializes the state.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'players': players.map((PlayerReadiness player) => player.toJson()).toList(),
    'stateVersion': stateVersion,
  };

  /// Parses a state received from the Host.
  factory ReadinessState.fromJson(Map<String, dynamic> json) {
    final Object? rawPlayers = json['players'];
    final List<PlayerReadiness> players = <PlayerReadiness>[];
    if (rawPlayers is List) {
      for (final Object? entry in rawPlayers) {
        if (entry is Map<String, dynamic>) {
          players.add(PlayerReadiness.fromJson(entry));
        }
      }
    }
    return ReadinessState(
      players: players,
      stateVersion: json['stateVersion'] as int? ?? 0,
    );
  }
}
