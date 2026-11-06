import 'room_models.dart';

/// The preparation countdown as the Host last reported it.
///
/// The countdown is display-only: the Host owns the deadline and decides when
/// the preparation ends. A client clock never moves the transition
/// (PLAN.md §9.4).
class PlacementCountdown {
  const PlacementCountdown({
    required this.remainingSeconds,
    required this.syncedAt,
  });

  /// The seconds that were left when the Host reported the countdown.
  final int remainingSeconds;

  /// When the value was received.
  final DateTime syncedAt;

  /// The seconds that are left now, according to the local clock.
  int remainingAt(DateTime now) {
    final int elapsed = now.difference(syncedAt).inSeconds;
    final int left = remainingSeconds - elapsed;
    return left < 0 ? 0 : left;
  }

  /// Serializes the countdown.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'remainingSeconds': remainingSeconds,
  };

  /// Parses a countdown received from the Host.
  factory PlacementCountdown.fromJson(Map<String, dynamic> json) =>
      PlacementCountdown(
        remainingSeconds: json['remainingSeconds'] as int? ?? 0,
        syncedAt: DateTime.now(),
      );
}

/// One entry of the turn order.
class TurnOrderEntry {
  const TurnOrderEntry({required this.playerId, required this.displayName});

  /// The player the entry belongs to.
  final String playerId;

  /// The display name of the player.
  final String displayName;

  /// Serializes the entry.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'displayName': displayName,
  };

  /// Parses an entry received from the Host.
  factory TurnOrderEntry.fromJson(Map<String, dynamic> json) => TurnOrderEntry(
    playerId: json['playerId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Player',
  );
}

/// The state of a match that just started.
///
/// The turn order is randomized by the Host: the first player is picked at
/// random and the remaining players follow in a random order
/// (PLAN.md §2.6).
class MatchStartState {
  const MatchStartState({
    required this.matchId,
    required this.turnOrder,
    required this.activePlayerId,
    required this.boardRows,
    required this.boardColumns,
    required this.fleetPreset,
    required this.stateVersion,
  });

  /// The identifier of the match.
  final String matchId;

  /// The players in the order they take their turns.
  final List<TurnOrderEntry> turnOrder;

  /// The player who takes the first turn.
  final String activePlayerId;

  /// The number of rows of every board.
  final int boardRows;

  /// The number of columns of every board.
  final int boardColumns;

  /// The fleet every player placed.
  final FleetPreset fleetPreset;

  /// The room state version the state belongs to.
  final int stateVersion;

  /// The entry of a player, or `null` when the player is not in the match.
  TurnOrderEntry? entryOf(String playerId) {
    for (final TurnOrderEntry entry in turnOrder) {
      if (entry.playerId == playerId) return entry;
    }
    return null;
  }

  /// The display name of the player who takes the first turn.
  String get activePlayerName => entryOf(activePlayerId)?.displayName ?? '';

  /// Serializes the state.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'matchId': matchId,
    'turnOrder': turnOrder
        .map((TurnOrderEntry entry) => entry.toJson())
        .toList(),
    'activePlayerId': activePlayerId,
    'boardRows': boardRows,
    'boardColumns': boardColumns,
    'fleetPreset': fleetPreset.wire,
    'stateVersion': stateVersion,
  };

  /// Parses a state received from the Host.
  factory MatchStartState.fromJson(Map<String, dynamic> json) {
    final Object? rawOrder = json['turnOrder'];
    final List<TurnOrderEntry> turnOrder = <TurnOrderEntry>[];
    if (rawOrder is List) {
      for (final Object? entry in rawOrder) {
        if (entry is Map<String, dynamic>) {
          turnOrder.add(TurnOrderEntry.fromJson(entry));
        }
      }
    }
    return MatchStartState(
      matchId: json['matchId'] as String? ?? '',
      turnOrder: turnOrder,
      activePlayerId: json['activePlayerId'] as String? ?? '',
      boardRows: json['boardRows'] as int? ?? 10,
      boardColumns: json['boardColumns'] as int? ?? 10,
      fleetPreset: FleetPreset.fromWire(json['fleetPreset'] as String?),
      stateVersion: json['stateVersion'] as int? ?? 0,
    );
  }
}
