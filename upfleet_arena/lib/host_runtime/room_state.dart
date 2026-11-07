import '../game_engine/board/board.dart';
import '../game_engine/combat/combat.dart';
import '../game_engine/combat/match_result.dart';
import '../game_engine/placement/placement.dart';
import '../shared/models/room_models.dart';

/// The Host-side authoritative record of a room member.
///
/// The Host keeps the complete truth; clients only ever receive a
/// [PlayerSummary] projection (PLAN.md §6.5, §6.6).
class HostPlayer {
  HostPlayer({
    required this.playerId,
    required this.displayName,
    required this.avatarId,
    required this.role,
    required this.deviceId,
    required this.joinedAt,
    this.resumeTokenHash,
    this.status = PlayerConnectionStatus.connected,
    this.disconnectedAt,
    this.lastHeartbeatAt,
  });

  /// Host-assigned identifier.
  final String playerId;

  /// The player's display name.
  final String displayName;

  /// The player's avatar identifier.
  final String avatarId;

  /// Host or regular player.
  final PlayerRole role;

  /// The device identifier this member joined from.
  final String deviceId;

  /// When the member joined.
  final DateTime joinedAt;

  /// Hash of the resume token issued for this member.
  ///
  /// The raw token is never stored on the Host and never logged
  /// (PLAN.md §6.6, §12).
  String? resumeTokenHash;

  /// Current connection state.
  PlayerConnectionStatus status;

  /// When the member was disconnected.
  DateTime? disconnectedAt;

  /// When the last heartbeat arrived.
  DateTime? lastHeartbeatAt;

  /// Whether the member is the Host.
  bool get isHost => role == PlayerRole.host;

  /// Whether the member still occupies a seat in the room.
  bool get occupiesSeat =>
      status == PlayerConnectionStatus.connected ||
      status == PlayerConnectionStatus.disconnected;

  /// Returns the client-visible projection of this member.
  PlayerSummary toSummary() => PlayerSummary(
    playerId: playerId,
    displayName: displayName,
    avatarId: avatarId,
    role: role,
    status: status,
  );
}

/// The Host-side placement state of one member.
///
/// The exact fleet layout never leaves the Host runtime: it is sent to its
/// owner only (PLAN.md §6.6, §8).
class HostPlayerPlacement {
  HostPlayerPlacement({required this.playerId});

  /// The member the placement belongs to.
  final String playerId;

  /// The ships that are placed on the board, keyed by the ship identifier.
  final Map<String, ShipPlacement> ships = <String, ShipPlacement>{};

  /// Whether the member confirmed a complete fleet.
  bool ready = false;
}

/// The Host-side state of the running match.
class HostMatchState {
  HostMatchState({
    required this.matchId,
    required this.turnOrder,
    required this.activePlayerId,
    required this.startedAt,
    Map<String, PlayerBoard>? boards,
  }) : boards = boards ?? <String, PlayerBoard>{};

  /// The identifier of the match.
  final String matchId;

  /// The player identifiers in the order they take their turns.
  final List<String> turnOrder;

  /// The player who takes the current turn.
  String activePlayerId;

  /// When the match started.
  final DateTime startedAt;

  /// The number of the current turn.
  int turnNumber = 1;

  /// When the current turn ends.
  DateTime? turnDeadline;

  /// How often the current player ran out of time in a row.
  int get consecutiveTimeouts => _timeoutStreaks[activePlayerId] ?? 0;

  final Map<String, int> _timeoutStreaks = <String, int>{};

  void recordTimeout(String playerId) {
    timeouts[playerId] = (timeouts[playerId] ?? 0) + 1;
    _timeoutStreaks[playerId] = (_timeoutStreaks[playerId] ?? 0) + 1;
  }

  /// Records one accepted shot and breaks the timeout streak of the shooter.
  void recordShot(String playerId, ShotResult result) {
    (stats[playerId] ??= PlayerMatchStats()).recordShot(result);
    _timeoutStreaks[playerId] = 0;
  }

  /// The combat statistics of every player, keyed by player ID.
  final Map<String, PlayerMatchStats> stats = <String, PlayerMatchStats>{};

  /// The players whose fleet sank, in the order they were eliminated.
  final List<String> eliminationOrder = <String>[];

  /// When the match ended, once one player was left alive.
  DateTime? finishedAt;

  /// Marks the fleet of a player as sunk. Returns whether it was the first
  /// time, so the caller only announces an elimination once.
  bool recordElimination(String playerId) {
    if (!eliminated.add(playerId)) return false;
    eliminationOrder.add(playerId);
    return true;
  }

  /// The exact board of every player, including the shots they received.
  final Map<String, PlayerBoard> boards;

  /// The shots of every attacker against every target.
  ///
  /// The first key is the attacker, the second the target and the value the
  /// cell with the result of the shot.
  final Map<String, Map<String, Map<CellCoord, ShotResult>>> attackHistory =
      <String, Map<String, Map<CellCoord, ShotResult>>>{};

  /// How often a player ran out of time.
  final Map<String, int> timeouts = <String, int>{};

  /// The players whose fleet was sunk.
  final Set<String> eliminated = <String>{};

  /// Whether the player is still in the match.
  bool isAlive(String playerId) =>
      boards.containsKey(playerId) && !eliminated.contains(playerId);

  /// The number of players that are still alive.
  int get aliveCount => turnOrder.where(isAlive).length;

  /// The winner, once the match is over.
  String? get winnerPlayerId {
    for (final String playerId in turnOrder) {
      if (isAlive(playerId)) return playerId;
    }
    return null;
  }
}

/// The Host-side authoritative room state.
///
/// It lives in Host memory only and disappears when the Host process ends
/// (PLAN.md §7.2, §18).
class HostRoomState {
  HostRoomState({
    required this.roomId,
    required this.inviteCode,
    required this.hostPlayerId,
    required this.config,
    required this.createdAt,
    required this.hostTcpPort,
    Map<String, HostPlayer>? players,
    Map<String, HostPlayerPlacement>? placements,
    this.status = RoomStatus.lobby,
    this.stateVersion = 1,
  }) : players = players ?? <String, HostPlayer>{},
       placements = placements ?? <String, HostPlayerPlacement>{};

  /// Locally generated room identifier.
  final String roomId;

  /// The six-character invitation code.
  ///
  /// Never part of discovery metadata (PLAN.md §6.3).
  final String inviteCode;

  /// The player ID of the Host.
  final String hostPlayerId;

  /// Host-controlled settings.
  RoomConfig config;

  /// When the room was created.
  final DateTime createdAt;

  /// The TCP port the Host listens on.
  final int hostTcpPort;

  /// Members, keyed by player ID.
  final Map<String, HostPlayer> players;

  /// The fleet layout of every member, keyed by player ID.
  final Map<String, HostPlayerPlacement> placements;

  /// Current lifecycle phase.
  RoomStatus status;

  /// When the preparation phase ends.
  ///
  /// Only the Host owns this deadline. It is set while the room is in the
  /// placement phase (PLAN.md §2.5, §9.4).
  DateTime? placementDeadline;

  /// The running match, once the preparation ended.
  HostMatchState? match;

  /// Monotonic state version, incremented on every accepted change.
  int stateVersion;

  /// Members that still occupy a seat.
  int get seatedCount =>
      players.values.where((HostPlayer p) => p.occupiesSeat).length;

  /// The members in display order: the Host first, then by join time.
  List<HostPlayer> get orderedPlayers {
    final List<HostPlayer> ordered = players.values.toList()
      ..sort((HostPlayer a, HostPlayer b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        final int byTime = a.joinedAt.compareTo(b.joinedAt);
        if (byTime != 0) return byTime;
        return a.playerId.compareTo(b.playerId);
      });
    return ordered;
  }

  /// Finds a member by ID.
  HostPlayer? playerById(String playerId) => players[playerId];

  /// Finds a member by device ID.
  HostPlayer? playerByDeviceId(String deviceId) {
    for (final HostPlayer player in players.values) {
      if (player.deviceId == deviceId && player.occupiesSeat) return player;
    }
    return null;
  }
}
