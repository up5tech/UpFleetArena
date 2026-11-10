/// Shared, transport-safe models for the room lifecycle.
///
/// These types travel between the Host runtime and the clients as JSON, so
/// every field is serialized explicitly and every enum is stored by name.
/// The Host owns the authoritative values; clients only render what they
/// receive (PLAN.md §6.5, §6.6).
library;

/// Lifecycle phase of a room.
enum RoomStatus {
  /// Players may join, the Host may configure the room.
  lobby,

  /// The preparation phase is running (Phase 4).
  placement,

  /// A match is in progress (Phase 5).
  active,

  /// The match finished.
  finished,

  /// The room was closed. Terminal.
  closed;

  /// Parses a wire value, falling back to [RoomStatus.lobby].
  static RoomStatus fromWire(String? value) => switch (value) {
    'placement' => RoomStatus.placement,
    'active' => RoomStatus.active,
    'finished' => RoomStatus.finished,
    'closed' => RoomStatus.closed,
    _ => RoomStatus.lobby,
  };

  /// Wire representation.
  String get wire => name;
}

/// Role of a room member.
enum PlayerRole {
  /// The device that created the room.
  host,

  /// A regular participant.
  player;

  /// Parses a wire value, falling back to [PlayerRole.player].
  static PlayerRole fromWire(String? value) =>
      value == 'host' ? PlayerRole.host : PlayerRole.player;

  /// Wire representation.
  String get wire => name;
}

/// Connection state of a room member.
enum PlayerConnectionStatus {
  /// The member is currently connected.
  connected,

  /// The member lost their connection and may resume their seat.
  disconnected,

  /// The member left the room on purpose.
  left,

  /// The Host removed the member from the room.
  kicked;

  /// Parses a wire value, falling back to [PlayerConnectionStatus.connected].
  static PlayerConnectionStatus fromWire(String? value) => switch (value) {
    'disconnected' => PlayerConnectionStatus.disconnected,
    'left' => PlayerConnectionStatus.left,
    'kicked' => PlayerConnectionStatus.kicked,
    _ => PlayerConnectionStatus.connected,
  };

  /// Wire representation.
  String get wire => name;
}

/// The fleet presets offered by the Host (PLAN.md §2.4).
enum FleetPreset {
  /// `[3, 2, 2]`.
  small(<int>[3, 2, 2]),

  /// `[4, 3, 3, 2, 2]`.
  standard(<int>[4, 3, 3, 2, 2]),

  /// `[5, 4, 3, 3, 2, 2]`.
  large(<int>[5, 4, 3, 3, 2, 2]);

  const FleetPreset(this.shipLengths);

  /// Length of each ship in this preset.
  final List<int> shipLengths;

  /// Number of ships in this preset.
  int get shipCount => shipLengths.length;

  /// Total number of cells the fleet occupies.
  int get totalCells =>
      shipLengths.fold(0, (int sum, int length) => sum + length);

  /// Wire key, e.g. `STANDARD`.
  String get wire => name.toUpperCase();

  /// Human-readable name of the preset.
  String get label => switch (this) {
    FleetPreset.small => 'Small',
    FleetPreset.standard => 'Standard',
    FleetPreset.large => 'Large',
  };

  /// The ship lengths as a readable list, e.g. `4, 3, 3, 2, 2`.
  String get shipSummary => shipLengths.join(', ');

  /// Parses a wire value, falling back to [FleetPreset.standard].
  static FleetPreset fromWire(String? value) {
    final String key = (value ?? '').toUpperCase();
    return FleetPreset.values.firstWhere(
      (FleetPreset preset) => preset.wire == key,
      orElse: () => FleetPreset.standard,
    );
  }
}

/// The Host-controlled room settings.
///
/// Every value is validated in the Host runtime. A client that sends a
/// handcrafted configuration is rejected with `INVALID_ROOM_CONFIG`
/// (PLAN.md §13.3).
class RoomConfig {
  const RoomConfig({
    this.rows = 10,
    this.columns = 10,
    this.fleetPreset = FleetPreset.standard,
    this.maxPlayers = 6,
    this.placementDurationSeconds = 120,
    this.turnDurationSeconds = 30,
  });

  /// Board rows. Range 8–14.
  final int rows;

  /// Board columns. Range 8–14.
  final int columns;

  /// Selected fleet preset.
  final FleetPreset fleetPreset;

  /// Maximum number of players, including the Host.
  final int maxPlayers;

  /// Preparation phase duration in seconds. Range 60–180.
  final int placementDurationSeconds;

  /// Turn duration in seconds. Range 15–60.
  final int turnDurationSeconds;

  /// Minimum supported board dimension.
  static const int minimumDimension = 8;

  /// Maximum supported board dimension.
  static const int maximumDimension = 14;

  /// Minimum number of players in a room.
  static const int minimumPlayers = 2;

  /// Maximum number of players in a room for the MVP.
  static const int maximumPlayers = 6;

  /// Minimum preparation duration in seconds.
  static const int minimumPlacementSeconds = 60;

  /// Maximum preparation duration in seconds.
  static const int maximumPlacementSeconds = 180;

  /// Minimum turn duration in seconds.
  static const int minimumTurnSeconds = 15;

  /// Maximum turn duration in seconds.
  static const int maximumTurnSeconds = 60;

  /// The recommended default configuration (PLAN.md §18).
  static const RoomConfig defaults = RoomConfig();

  /// Returns a copy with the given fields replaced.
  RoomConfig copyWith({
    int? rows,
    int? columns,
    FleetPreset? fleetPreset,
    int? maxPlayers,
    int? placementDurationSeconds,
    int? turnDurationSeconds,
  }) => RoomConfig(
    rows: rows ?? this.rows,
    columns: columns ?? this.columns,
    fleetPreset: fleetPreset ?? this.fleetPreset,
    maxPlayers: maxPlayers ?? this.maxPlayers,
    placementDurationSeconds: placementDurationSeconds ?? this.placementDurationSeconds,
    turnDurationSeconds: turnDurationSeconds ?? this.turnDurationSeconds,
  );

  /// Validates the configuration.
  ///
  /// Returns an empty list when the configuration is acceptable, otherwise a
  /// list of human-readable reasons.
  List<String> validate() {
    final List<String> problems = <String>[];

    if (rows < minimumDimension || rows > maximumDimension) {
      problems.add('Rows must be between $minimumDimension and $maximumDimension.');
    }
    if (columns < minimumDimension || columns > maximumDimension) {
      problems.add(
        'Columns must be between $minimumDimension and $maximumDimension.',
      );
    }
    if (maxPlayers < minimumPlayers || maxPlayers > maximumPlayers) {
      problems.add(
        'Player capacity must be between $minimumPlayers and $maximumPlayers.',
      );
    }
    if (placementDurationSeconds < minimumPlacementSeconds ||
        placementDurationSeconds > maximumPlacementSeconds) {
      problems.add(
        'The preparation timer must be between $minimumPlacementSeconds and '
        '$maximumPlacementSeconds seconds.',
      );
    }
    if (turnDurationSeconds < minimumTurnSeconds ||
        turnDurationSeconds > maximumTurnSeconds) {
      problems.add(
        'The turn timer must be between $minimumTurnSeconds and '
        '$maximumTurnSeconds seconds.',
      );
    }
    if (fleetPreset.totalCells > rows * columns) {
      problems.add(
        'The ${fleetPreset.wire.toLowerCase()} fleet does not fit on a '
        '$rows×$columns board.',
      );
    }
    return problems;
  }

  /// Whether this configuration passes validation.
  bool get isValid => validate().isEmpty;

  /// Serializes the configuration.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'rows': rows,
    'columns': columns,
    'fleetPreset': fleetPreset.wire,
    'maxPlayers': maxPlayers,
    'placementDurationSeconds': placementDurationSeconds,
    'turnDurationSeconds': turnDurationSeconds,
  };

  /// Parses a configuration received from a client.
  ///
  /// Throws [FormatException] when a value has the wrong type. Callers must
  /// still run [validate] on the result.
  factory RoomConfig.fromJson(Map<String, dynamic> json) {
    final int rows = _readInt(json, 'rows');
    final int columns = _readInt(json, 'columns');
    final int maxPlayers = _readInt(json, 'maxPlayers');
    final int placementSeconds = _readInt(json, 'placementDurationSeconds');
    final int turnSeconds = _readInt(json, 'turnDurationSeconds');

    return RoomConfig(
      rows: rows,
      columns: columns,
      fleetPreset: FleetPreset.fromWire(json['fleetPreset'] as String?),
      maxPlayers: maxPlayers,
      placementDurationSeconds: placementSeconds,
      turnDurationSeconds: turnSeconds,
    );
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final Object? value = json[key];
    if (value is int) return value;
    throw FormatException('Room configuration field "$key" must be an integer.');
  }
}

/// A member of a room, as seen by a client.
class PlayerSummary {
  const PlayerSummary({
    required this.playerId,
    required this.displayName,
    required this.avatarId,
    required this.role,
    required this.status,
    this.ready = false,
    this.isBot = false,
  });

  /// Host-assigned identifier of the player.
  final String playerId;

  /// Display name chosen by the player.
  final String displayName;

  /// Avatar identifier chosen by the player.
  final String avatarId;

  /// Host or regular player.
  final PlayerRole role;

  /// Connection state.
  final PlayerConnectionStatus status;

  /// Whether the player has completed their fleet. Used from Phase 4 on.
  final bool ready;

  /// Whether this member is a computer opponent.
  final bool isBot;

  /// Whether this member is the Host.
  bool get isHost => role == PlayerRole.host;

  /// Returns a copy with the given fields replaced.
  PlayerSummary copyWith({
    String? playerId,
    String? displayName,
    String? avatarId,
    PlayerRole? role,
    PlayerConnectionStatus? status,
    bool? ready,
    bool? isBot,
  }) => PlayerSummary(
    playerId: playerId ?? this.playerId,
    displayName: displayName ?? this.displayName,
    avatarId: avatarId ?? this.avatarId,
    role: role ?? this.role,
    status: status ?? this.status,
    ready: ready ?? this.ready,
    isBot: isBot ?? this.isBot,
  );

  /// Serializes the summary.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'displayName': displayName,
    'avatarId': avatarId,
    'role': role.wire,
    'status': status.wire,
    'ready': ready,
    'isBot': isBot,
  };

  /// Parses a summary received from the Host.
  factory PlayerSummary.fromJson(Map<String, dynamic> json) => PlayerSummary(
    playerId: json['playerId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Player',
    avatarId: json['avatarId'] as String? ?? '',
    role: PlayerRole.fromWire(json['role'] as String?),
    status: PlayerConnectionStatus.fromWire(json['status'] as String?),
    ready: json['ready'] as bool? ?? false,
    isBot: json['isBot'] as bool? ?? false,
  );
}

/// The permission-filtered view of the room sent to one recipient.
///
/// The Host never broadcasts a single serialized internal state; it builds one
/// projection per recipient (PLAN.md §6.6).
class RoomSnapshot {
  const RoomSnapshot({
    required this.roomId,
    required this.status,
    required this.config,
    required this.players,
    required this.viewerPlayerId,
    required this.viewerIsHost,
    required this.stateVersion,
  });

  /// Identifier of the room.
  final String roomId;

  /// Current lifecycle phase.
  final RoomStatus status;

  /// Host-controlled settings.
  final RoomConfig config;

  /// Members visible to the viewer.
  final List<PlayerSummary> players;

  /// The viewer's own player ID.
  final String? viewerPlayerId;

  /// Whether the viewer is the Host.
  final bool viewerIsHost;

  /// Monotonic state version of the room.
  final int stateVersion;

  /// Number of members that are currently connected.
  int get connectedCount => players
      .where(
        (PlayerSummary player) =>
            player.status == PlayerConnectionStatus.connected,
      )
      .length;

  /// Finds a member by ID.
  PlayerSummary? playerById(String playerId) {
    for (final PlayerSummary player in players) {
      if (player.playerId == playerId) return player;
    }
    return null;
  }

  /// Serializes the snapshot.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'roomId': roomId,
    'status': status.wire,
    'config': config.toJson(),
    'players': players
        .map((PlayerSummary player) => player.toJson())
        .toList(),
    'viewerPlayerId': viewerPlayerId,
    'viewerIsHost': viewerIsHost,
    'stateVersion': stateVersion,
  };

  /// Parses a snapshot received from the Host.
  factory RoomSnapshot.fromJson(Map<String, dynamic> json) {
    final Object? rawPlayers = json['players'];
    final List<PlayerSummary> players = <PlayerSummary>[];
    if (rawPlayers is List) {
      for (final Object? entry in rawPlayers) {
        if (entry is Map<String, dynamic>) {
          players.add(PlayerSummary.fromJson(entry));
        }
      }
    }

    final Object? rawConfig = json['config'];
    return RoomSnapshot(
      roomId: json['roomId'] as String? ?? '',
      status: RoomStatus.fromWire(json['status'] as String?),
      config: rawConfig is Map<String, dynamic>
          ? RoomConfig.fromJson(rawConfig)
          : RoomConfig.defaults,
      players: players,
      viewerPlayerId: json['viewerPlayerId'] as String?,
      viewerIsHost: json['viewerIsHost'] as bool? ?? false,
      stateVersion: json['stateVersion'] as int? ?? 0,
    );
  }
}

/// Validation rules for player display names.
///
/// PLAN.md §12 requires moderated display names and reserved system labels
/// that cannot be impersonated.
class DisplayNames {
  const DisplayNames._();

  /// Minimum accepted length.
  static const int minimumLength = 1;

  /// Maximum accepted length.
  static const int maximumLength = 20;

  /// Labels a player may not use.
  static const Set<String> reserved = <String>{
    'host',
    'system',
    'admin',
    'administrator',
    'moderator',
    'server',
    'upfleet',
    'upfleet arena',
  };

  /// Normalizes a display name: trims, collapses inner whitespace and
  /// removes control characters.
  static String normalize(String raw) {
    final StringBuffer buffer = StringBuffer();
    bool pendingSpace = false;
    bool wroteAnything = false;

    for (final int rune in raw.runes) {
      // Drop control characters entirely.
      if (rune < 0x20 || rune == 0x7F) continue;

      if (rune == 0x20) {
        pendingSpace = wroteAnything;
        continue;
      }
      if (pendingSpace) {
        buffer.writeCharCode(0x20);
        pendingSpace = false;
      }
      buffer.writeCharCode(rune);
      wroteAnything = true;
    }
    return buffer.toString();
  }

  /// Validates a display name.
  ///
  /// Returns `null` when the name is acceptable, otherwise the reason.
  static String? validate(String raw) {
    final String name = normalize(raw);
    if (name.length < minimumLength) {
      return 'Pick a nickname of at least $minimumLength character.';
    }
    if (name.length > maximumLength) {
      return 'Nicknames are limited to $maximumLength characters.';
    }
    if (reserved.contains(name.toLowerCase())) {
      return 'That nickname is reserved.';
    }
    return null;
  }
}
