import '../../game_engine/board/board.dart';
import '../../game_engine/combat/combat.dart';
import '../../game_engine/placement/placement.dart';
import 'room_models.dart';

/// A countdown as the Host last reported it.
///
/// The countdown is display-only: the Host owns the deadline and decides
/// when the phase ends. A client clock never moves the transition
/// (PLAN.md §9.4).
class Countdown {
  Countdown({required this.remainingSeconds}) : _elapsed = Stopwatch()..start();

  final int remainingSeconds;
  final Stopwatch _elapsed;

  int get remaining => (remainingSeconds - _elapsed.elapsed.inSeconds)
      .clamp(0, remainingSeconds);

  /// Serializes the countdown.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'remainingSeconds': remainingSeconds,
  };

  /// Parses a countdown received from the Host.
  factory Countdown.fromJson(Map<String, dynamic> json) => Countdown(
    remainingSeconds: json['remainingSeconds'] as int? ?? 0,
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

/// A ship of the own board, as its owner sees it.
class ShipView {
  const ShipView({
    required this.shipId,
    required this.length,
    required this.orientation,
    required this.row,
    required this.column,
    required this.hitCells,
    required this.sunk,
  });

  /// The identifier of the ship.
  final String shipId;

  /// The length of the ship in cells.
  final int length;

  /// The direction the ship points to.
  final ShipOrientation orientation;

  /// The row of the anchor cell.
  final int row;

  /// The column of the anchor cell.
  final int column;

  /// The cells of the ship that were hit.
  final List<CellCoord> hitCells;

  /// Whether the ship was sunk.
  final bool sunk;

  /// Serializes the ship.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'shipId': shipId,
    'length': length,
    'orientation': orientation.wire,
    'row': row,
    'column': column,
    'hitCells': hitCells
        .map((CellCoord cell) => <String, dynamic>{
              'row': cell.row,
              'column': cell.column,
            })
        .toList(),
    'sunk': sunk,
  };

  /// Parses a ship received from the Host.
  factory ShipView.fromJson(Map<String, dynamic> json) => ShipView(
    shipId: json['shipId'] as String? ?? '',
    length: json['length'] as int? ?? 0,
    orientation: ShipOrientation.fromWire(json['orientation'] as String?),
    row: json['row'] as int? ?? 0,
    column: json['column'] as int? ?? 0,
    hitCells: _readCells(json['hitCells']),
    sunk: json['sunk'] as bool? ?? false,
  );
}

/// The own board of a player.
class OwnBoardView {
  const OwnBoardView({required this.ships, required this.shotsReceived});

  /// The ships of the fleet.
  final List<ShipView> ships;

  /// Every cell that was fired at.
  final List<CellCoord> shotsReceived;

  /// Serializes the board.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'ships': ships.map((ShipView ship) => ship.toJson()).toList(),
    'shotsReceived': _writeCells(shotsReceived),
  };

  /// Parses a board received from the Host.
  factory OwnBoardView.fromJson(Map<String, dynamic> json) => OwnBoardView(
    ships: _readViews(json['ships']),
    shotsReceived: _readCells(json['shotsReceived']),
  );
}

/// One shot of the shooter against a target.
class ShotView {
  const ShotView({
    required this.row,
    required this.column,
    required this.result,
  });

  /// The row of the cell.
  final int row;

  /// The column of the cell.
  final int column;

  /// What the shot did.
  final ShotResult result;

  /// The cell of the shot.
  CellCoord get cell => CellCoord(row, column);

  /// Serializes the shot.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'row': row,
    'column': column,
    'result': result.wire,
  };

  /// Parses a shot received from the Host.
  factory ShotView.fromJson(Map<String, dynamic> json) => ShotView(
    row: json['row'] as int? ?? 0,
    column: json['column'] as int? ?? 0,
    result: ShotResult.fromWire(json['result'] as String?),
  );
}

/// The board of an opponent, as the shooter sees it.
///
/// It carries the shots of the shooter and nothing else: the position of the
/// opponent's ships stays hidden (PLAN.md §2.2).
class TargetBoardView {
  const TargetBoardView({
    required this.playerId,
    required this.displayName,
    required this.alive,
    required this.shots,
  });

  /// The opponent the board belongs to.
  final String playerId;

  /// The display name of the opponent.
  final String displayName;

  /// Whether the opponent is still in the match.
  final bool alive;

  /// The shots the shooter fired at this opponent.
  final List<ShotView> shots;

  /// Serializes the board.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'displayName': displayName,
    'alive': alive,
    'shots': shots.map((ShotView shot) => shot.toJson()).toList(),
  };

  /// Parses a board received from the Host.
  factory TargetBoardView.fromJson(Map<String, dynamic> json) => TargetBoardView(
    playerId: json['playerId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Player',
    alive: json['alive'] as bool? ?? true,
    shots: _readShots(json['shots']),
  );
}

/// A player of the match.
class MatchPlayerView {
  const MatchPlayerView({
    required this.playerId,
    required this.displayName,
    required this.alive,
    required this.timeouts,
    required this.shipsRemaining,
  });

  /// The player the entry belongs to.
  final String playerId;

  /// The display name of the player.
  final String displayName;

  /// Whether the player is still in the match.
  final bool alive;

  /// How often the player ran out of time.
  final int timeouts;

  /// How many ships of the fleet are still afloat.
  ///
  /// This is aggregate status only: it never carries a coordinate or a ship
  /// position, so every player may see it (PLAN.md §6.6).
  final int shipsRemaining;

  /// Serializes the player.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'displayName': displayName,
    'alive': alive,
    'timeouts': timeouts,
    'shipsRemaining': shipsRemaining,
  };

  /// Parses a player received from the Host.
  factory MatchPlayerView.fromJson(Map<String, dynamic> json) =>
      MatchPlayerView(
        playerId: json['playerId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Player',
        alive: json['alive'] as bool? ?? true,
        timeouts: json['timeouts'] as int? ?? 0,
        shipsRemaining: json['shipsRemaining'] as int? ?? 0,
      );
}

/// A public shot event, without any coordinate.
///
/// The other players of the room only learn that a shot happened and what it
/// did — never where it hit (PLAN.md §2.2).
class PublicActivity {
  const PublicActivity({
    required this.attackerPlayerId,
    required this.targetPlayerId,
    required this.result,
  });

  /// The player who fired.
  final String attackerPlayerId;

  /// The player who was fired at.
  final String targetPlayerId;

  /// What the shot did.
  final ShotResult result;

  /// Serializes the activity.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'attackerPlayerId': attackerPlayerId,
    'targetPlayerId': targetPlayerId,
    'result': result.wire,
  };

  /// Parses an activity received from the Host.
  factory PublicActivity.fromJson(Map<String, dynamic> json) => PublicActivity(
    attackerPlayerId: json['attackerPlayerId'] as String? ?? '',
    targetPlayerId: json['targetPlayerId'] as String? ?? '',
    result: ShotResult.fromWire(json['result'] as String?),
  );
}

/// The permission-filtered state of the match.
///
/// Every client receives its own view: the own board is exact, the boards of
/// the opponents only carry the shots the client fired at them
/// (PLAN.md §6.6, §8).
class MatchSnapshot {
  const MatchSnapshot({
    required this.matchId,
    required this.stateVersion,
    required this.turnNumber,
    required this.activePlayerId,
    required this.players,
    required this.targets,
    this.turnRemainingSeconds,
    this.ownBoard,
    this.winnerPlayerId,
  });

  /// The identifier of the match.
  final String matchId;

  /// The room state version the snapshot belongs to.
  final int stateVersion;

  /// The number of the current turn.
  final int turnNumber;

  /// The player who may fire.
  final String activePlayerId;

  /// The seconds that are left before the turn ends.
  final int? turnRemainingSeconds;

  /// Every player of the match.
  final List<MatchPlayerView> players;

  /// The own board of the recipient.
  final OwnBoardView? ownBoard;

  /// The boards of the opponents, from the view of the recipient.
  final List<TargetBoardView> targets;

  /// The winner, once the match is over.
  final String? winnerPlayerId;

  /// The player the recipient may shoot at.
  TargetBoardView? targetById(String playerId) {
    for (final TargetBoardView target in targets) {
      if (target.playerId == playerId) return target;
    }
    return null;
  }

  /// The opponents that are still alive.
  List<TargetBoardView> get livingTargets =>
      targets.where((TargetBoardView target) => target.alive).toList();

  /// The player view of a player, or `null` when the player is unknown.
  MatchPlayerView? playerById(String playerId) {
    for (final MatchPlayerView player in players) {
      if (player.playerId == playerId) return player;
    }
    return null;
  }

  /// Serializes the snapshot.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'matchId': matchId,
    'stateVersion': stateVersion,
    'turnNumber': turnNumber,
    'activePlayerId': activePlayerId,
    'turnRemainingSeconds': turnRemainingSeconds,
    'players': players
        .map((MatchPlayerView player) => player.toJson())
        .toList(),
    'ownBoard': ownBoard?.toJson(),
    'targets': targets
        .map((TargetBoardView target) => target.toJson())
        .toList(),
    'winnerPlayerId': winnerPlayerId,
  };

  /// Parses a snapshot received from the Host.
  factory MatchSnapshot.fromJson(Map<String, dynamic> json) {
    final Object? rawOwnBoard = json['ownBoard'];
    return MatchSnapshot(
      matchId: json['matchId'] as String? ?? '',
      stateVersion: json['stateVersion'] as int? ?? 0,
      turnNumber: json['turnNumber'] as int? ?? 0,
      activePlayerId: json['activePlayerId'] as String? ?? '',
      turnRemainingSeconds: json['turnRemainingSeconds'] as int?,
      players: _readPlayers(json['players']),
      ownBoard: rawOwnBoard is Map<String, dynamic>
          ? OwnBoardView.fromJson(rawOwnBoard)
          : null,
      targets: _readTargets(json['targets']),
      winnerPlayerId: json['winnerPlayerId'] as String?,
    );
  }
}

/// The final standing and statistics of one player.
class PlayerResultView {
  const PlayerResultView({
    required this.playerId,
    required this.displayName,
    required this.rank,
    required this.shots,
    required this.hits,
    required this.misses,
    required this.shipsSunk,
    required this.timeouts,
  });

  /// The player the entry belongs to.
  final String playerId;

  /// The display name of the player.
  final String displayName;

  /// The place of the player, starting at 1 for the winner.
  final int rank;

  /// How many shots the player fired.
  final int shots;

  /// How many shots hit a ship, including the ones that sank it.
  final int hits;

  /// How many shots found no ship.
  final int misses;

  /// How many ships the player sank.
  final int shipsSunk;

  /// How often the player ran out of time.
  final int timeouts;

  /// Serializes the entry.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'displayName': displayName,
    'rank': rank,
    'shots': shots,
    'hits': hits,
    'misses': misses,
    'shipsSunk': shipsSunk,
    'timeouts': timeouts,
  };

  /// Parses an entry received from the Host.
  factory PlayerResultView.fromJson(Map<String, dynamic> json) =>
      PlayerResultView(
        playerId: json['playerId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Player',
        rank: json['rank'] as int? ?? 0,
        shots: json['shots'] as int? ?? 0,
        hits: json['hits'] as int? ?? 0,
        misses: json['misses'] as int? ?? 0,
        shipsSunk: json['shipsSunk'] as int? ?? 0,
        timeouts: json['timeouts'] as int? ?? 0,
      );
}

/// The final result of a finished match, built and broadcast by the Host.
///
/// Every client receives the same result: the ranking and the statistics are
/// Host truth, never a client calculation (PLAN.md §2.10, §6.6).
class MatchResult {
  const MatchResult({
    required this.matchId,
    required this.stateVersion,
    required this.winnerPlayerId,
    required this.winnerDisplayName,
    required this.durationSeconds,
    required this.ranking,
  });

  /// The identifier of the match.
  final String matchId;

  /// The room state version the match ended on.
  final int stateVersion;

  /// The last player alive, or `null` when nobody survived.
  final String? winnerPlayerId;

  /// The display name of the winner.
  final String? winnerDisplayName;

  /// How long the match ran, from the first turn to the last shot.
  final int durationSeconds;

  /// Every player, ordered from the winner down.
  final List<PlayerResultView> ranking;

  /// The standing of a player, or `null` when the player is unknown.
  PlayerResultView? standingOf(String playerId) {
    for (final PlayerResultView entry in ranking) {
      if (entry.playerId == playerId) return entry;
    }
    return null;
  }

  /// Serializes the result.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'matchId': matchId,
    'stateVersion': stateVersion,
    'winnerPlayerId': winnerPlayerId,
    'winnerDisplayName': winnerDisplayName,
    'durationSeconds': durationSeconds,
    'ranking': ranking
        .map((PlayerResultView entry) => entry.toJson())
        .toList(),
  };

  /// Parses a result received from the Host.
  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final Object? rawRanking = json['ranking'];
    return MatchResult(
      matchId: json['matchId'] as String? ?? '',
      stateVersion: json['stateVersion'] as int? ?? 0,
      winnerPlayerId: json['winnerPlayerId'] as String?,
      winnerDisplayName: json['winnerDisplayName'] as String?,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      ranking: rawRanking is List
          ? rawRanking
                .whereType<Map<String, dynamic>>()
                .map(PlayerResultView.fromJson)
                .toList()
          : const <PlayerResultView>[],
    );
  }
}

/// The feedback of a shot, sent to the attacker and the target.
class ShotFeedback {
  const ShotFeedback({
    required this.attackerPlayerId,
    required this.targetPlayerId,
    required this.row,
    required this.column,
    required this.result,
  });

  /// The player who fired.
  final String attackerPlayerId;

  /// The player who was fired at.
  final String targetPlayerId;

  /// The row of the cell.
  final int row;

  /// The column of the cell.
  final int column;

  /// What the shot did.
  final ShotResult result;

  /// The cell of the shot.
  CellCoord get cell => CellCoord(row, column);

  /// Serializes the feedback.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'attackerPlayerId': attackerPlayerId,
    'targetPlayerId': targetPlayerId,
    'row': row,
    'column': column,
    'result': result.wire,
  };

  /// Parses a feedback received from the Host.
  factory ShotFeedback.fromJson(Map<String, dynamic> json) => ShotFeedback(
    attackerPlayerId: json['attackerPlayerId'] as String? ?? '',
    targetPlayerId: json['targetPlayerId'] as String? ?? '',
    row: json['row'] as int? ?? 0,
    column: json['column'] as int? ?? 0,
    result: ShotResult.fromWire(json['result'] as String?),
  );
}

List<CellCoord> _readCells(Object? raw) {
  if (raw is! List) return const <CellCoord>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(
        (Map<String, dynamic> cell) => CellCoord(
          cell['row'] as int? ?? 0,
          cell['column'] as int? ?? 0,
        ),
      )
      .toList();
}

List<Map<String, dynamic>> _writeCells(List<CellCoord> cells) => cells
    .map(
      (CellCoord cell) => <String, dynamic>{
        'row': cell.row,
        'column': cell.column,
      },
    )
    .toList();

List<ShipView> _readViews(Object? raw) {
  if (raw is! List) return const <ShipView>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(ShipView.fromJson)
      .toList();
}

List<ShotView> _readShots(Object? raw) {
  if (raw is! List) return const <ShotView>[];
  return raw.whereType<Map<String, dynamic>>().map(ShotView.fromJson).toList();
}

List<MatchPlayerView> _readPlayers(Object? raw) {
  if (raw is! List) return const <MatchPlayerView>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(MatchPlayerView.fromJson)
      .toList();
}

List<TargetBoardView> _readTargets(Object? raw) {
  if (raw is! List) return const <TargetBoardView>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(TargetBoardView.fromJson)
      .toList();
}
