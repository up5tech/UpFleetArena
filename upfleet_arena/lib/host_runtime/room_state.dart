import '../../shared/models/room_models.dart';

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
    this.status = RoomStatus.lobby,
    this.stateVersion = 1,
  }) : players = players ?? <String, HostPlayer>{};

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

  /// Current lifecycle phase.
  RoomStatus status;

  /// Monotonic state version, incremented on every accepted change.
  int stateVersion;

  /// Members that still occupy a seat.
  int get seatedCount =>
      players.values.where((HostPlayer p) => p.occupiesSeat).length;

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
