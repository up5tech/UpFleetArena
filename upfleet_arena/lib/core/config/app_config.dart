/// Application-wide constants frozen by PLAN.md §18.
///
/// These are *defaults*, not client-trusted constants: every value that
/// arrives from a client must be re-validated in the Host runtime
/// (PLAN.md §18 closing note).
class AppConfig {
  const AppConfig._();

  // ---------------------------------------------------------------- network

  /// The product ships as a LAN-only, host-authoritative game.
  static const String networkMode = 'LAN_ONLY';

  /// Transport used between clients and the Host.
  static const String transport = 'TCP';

  /// Discovery mechanism used for room discovery.
  static const String discovery = 'MDNS_BONJOUR';

  /// Topology: every client connects to the Host only.
  static const String topology = 'HOST_STAR';

  /// The game never requires Internet connectivity.
  static const bool internetRequired = false;

  /// The game never requires a backend service.
  static const bool backendRequired = false;

  /// Host migration is not supported (PLAN.md §19.6).
  static const bool hostMigration = false;

  /// Exiting the Host terminates the room for every participant.
  static const bool hostExitEndsRoom = true;

  /// Heartbeat cadence of the Host, in seconds.
  static const int hostHeartbeatIntervalSeconds = 3;

  /// Client-side timeout that marks the Host as lost, in seconds.
  static const int hostLostTimeoutSeconds = 10;

  // ---------------------------------------------------------------- players

  /// Minimum number of players required to start a match.
  static const int minimumPlayers = 2;

  /// Recommended maximum number of players for the first release.
  static const int recommendedMaximumPlayers = 6;

  // ------------------------------------------------------------------ room

  /// Length of the room invitation code.
  static const int invitationCodeLength = 6;

  /// Players cannot join once the placement phase started.
  static const bool allowJoinAfterPlacementStarts = false;

  /// The Host must stay in the foreground while hosting.
  static const bool hostForegroundRequired = true;

  /// Characters excluded from generated invitation codes.
  ///
  /// `0`, `O`, `1` and `I` are excluded to avoid visual ambiguity
  /// (PLAN.md §2.1).
  static const String ambiguousCodeCharacters = '0O1I';

  /// Alphabet used to generate invitation codes.
  static const String invitationCodeAlphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // ----------------------------------------------------------------- board

  /// Default board rows.
  static const int defaultBoardRows = 10;

  /// Default board columns.
  static const int defaultBoardColumns = 10;

  /// Smallest supported board dimension.
  static const int minimumBoardDimension = 8;

  /// Largest supported board dimension.
  static const int maximumBoardDimension = 14;

  // ----------------------------------------------------------------- fleet

  /// Default fleet preset key.
  static const String defaultFleetPreset = 'STANDARD';

  /// Ship lengths of the Standard Fleet preset (PLAN.md §2.4).
  static const List<int> standardFleetShipLengths = <int>[4, 3, 3, 2, 2];

  // ------------------------------------------------------------- placement

  /// Default placement duration, in seconds.
  static const int placementDurationSeconds = 120;

  /// Smallest selectable placement duration, in seconds.
  static const int minimumPlacementDurationSeconds = 60;

  /// Largest selectable placement duration, in seconds.
  static const int maximumPlacementDurationSeconds = 180;

  /// Ships may touch each other in the MVP.
  static const bool allowShipAdjacency = true;

  /// Ships may never overlap.
  static const bool allowShipOverlap = false;

  /// Incomplete fleets are auto-placed when the preparation timer expires.
  static const bool autoPlaceOnTimeout = true;

  // ---------------------------------------------------------------- combat

  /// Default turn duration, in seconds.
  static const int turnDurationSeconds = 30;

  /// Smallest selectable turn duration, in seconds.
  static const int minimumTurnDurationSeconds = 15;

  /// Largest selectable turn duration, in seconds.
  static const int maximumTurnDurationSeconds = 60;

  /// Shots allowed per turn.
  static const int shotsPerTurn = 1;

  /// A hit does not grant an extra shot in the MVP.
  static const bool extraShotOnHit = false;

  /// The active player may target any living opponent.
  static const String targetMode = 'ANY_LIVING_OPPONENT';

  /// Each attacker may fire at a given target cell only once.
  static const bool repeatedShotOnSameCellPerAttackerTarget = false;

  // --------------------------------------------------------- reconnection

  /// Grace period for a disconnected non-host player, in seconds.
  static const int nonHostGracePeriodSeconds = 30;

  /// The Host cannot be replaced or resumed.
  static const bool hostReconnectSupported = false;

  // ---------------------------------------------------------- persistence

  /// Active matches live only in Host memory.
  static const String activeMatchStorage = 'HOST_MEMORY_ONLY';

  /// Completed matches may be stored locally on each device.
  static const String matchHistoryStorage = 'OPTIONAL_LOCAL_ONLY';

  /// No cloud synchronization anywhere in the product.
  static const bool cloudSync = false;
}
