/// Protocol-wide constants shared by the Host runtime and every client.
///
/// Source of truth: PLAN.md §6.4 (Direct TCP protocol), §8 (LAN Message
/// Protocol) and §18 (Recommended Initial Configuration).
library;

/// Application protocol version.
///
/// Bump this whenever the wire format changes in a non-backward-compatible
/// way. The Host rejects clients advertising a different version with
/// `UNSUPPORTED_PROTOCOL_VERSION` (PLAN.md §8.4).
class AppProtocol {
  const AppProtocol._();

  /// Current protocol version (PLAN.md §8.1).
  static const int version = 1;

  /// mDNS / Bonjour service type used to advertise and discover rooms.
  ///
  /// The invitation code is deliberately NOT part of this service type or of
  /// any discovery metadata: every device on the LAN can inspect mDNS
  /// announcements (PLAN.md §6.3 step 4).
  static const String serviceType = '_upfleet._tcp';

  /// Maximum accepted inbound frame payload, in bytes (PLAN.md §6.4).
  static const int maxFrameBytes = 64 * 1024;

  /// Heartbeat cadence advertised by the Host (PLAN.md §2.9, §9.5).
  static const Duration hostHeartbeatInterval = Duration(seconds: 3);

  /// Client-side timeout after which the Host is considered lost.
  static const Duration hostLostTimeout = Duration(seconds: 10);
}

/// Stable machine-readable error codes (PLAN.md §8.4).
///
/// These strings are part of the wire contract: clients switch on them, so
/// never reword an existing code. Add new codes instead.
class ProtocolErrorCode {
  const ProtocolErrorCode._();

  static const String roomNotFound = 'ROOM_NOT_FOUND';
  static const String roomCodeInvalid = 'ROOM_CODE_INVALID';
  static const String roomFull = 'ROOM_FULL';
  static const String roomAlreadyStarted = 'ROOM_ALREADY_STARTED';
  static const String hostOnlyAction = 'HOST_ONLY_ACTION';
  static const String invalidRoomConfig = 'INVALID_ROOM_CONFIG';
  static const String unsupportedProtocolVersion = 'UNSUPPORTED_PROTOCOL_VERSION';
  static const String placementPhaseNotActive = 'PLACEMENT_PHASE_NOT_ACTIVE';
  static const String invalidShipPlacement = 'INVALID_SHIP_PLACEMENT';
  static const String fleetIncomplete = 'FLEET_INCOMPLETE';
  static const String notYourTurn = 'NOT_YOUR_TURN';
  static const String targetNotAlive = 'TARGET_NOT_ALIVE';
  static const String invalidTargetCell = 'INVALID_TARGET_CELL';
  static const String cellAlreadyFiredAt = 'CELL_ALREADY_FIRED_AT';
  static const String matchAlreadyFinished = 'MATCH_ALREADY_FINISHED';
  static const String stateVersionConflict = 'STATE_VERSION_CONFLICT';
  static const String sessionExpired = 'SESSION_EXPIRED';
  static const String hostClosingRoom = 'HOST_CLOSING_ROOM';
  static const String lanPermissionDenied = 'LAN_PERMISSION_DENIED';
  static const String hostUnreachable = 'HOST_UNREACHABLE';
  static const String rateLimited = 'RATE_LIMITED';

  // Frame-level codes used by the transport layer before a session exists.
  static const String frameTooLarge = 'FRAME_TOO_LARGE';
  static const String malformedFrame = 'MALFORMED_FRAME';
  static const String malformedPayload = 'MALFORMED_PAYLOAD';
}

/// Client-to-Host message types (PLAN.md §8.2).
class ClientMessageType {
  const ClientMessageType._();

  static const String join = 'room:join';
  static const String leave = 'room:leave';
  static const String configUpdate = 'room:config:update';
  static const String kick = 'room:player:kick';
  static const String startPlacement = 'room:start-placement';
  static const String close = 'room:close';
  static const String placementSet = 'placement:set';
  static const String placementAuto = 'placement:auto';
  static const String placementReady = 'placement:ready';
  static const String fire = 'game:fire';
  static const String requestSnapshot = 'game:request-snapshot';
  static const String heartbeat = 'client:heartbeat';
  static const String resume = 'session:resume';

  /// Phase 0 proof-of-concept message used to validate the transport.
  static const String ping = 'client:ping';
}

/// Host-to-client event types (PLAN.md §8.3).
class HostEventType {
  const HostEventType._();

  static const String joined = 'room:joined';
  static const String roomState = 'room:state';
  static const String playerJoined = 'room:player-joined';
  static const String playerLeft = 'room:player-left';
  static const String configUpdated = 'room:config-updated';
  static const String closed = 'room:closed';
  static const String placementStarted = 'placement:started';
  static const String placementState = 'placement:state';
  static const String placementReadyState = 'placement:ready-state';
  static const String placementCompleted = 'placement:completed';
  static const String started = 'game:started';
  static const String turnStarted = 'game:turn-started';
  static const String shotResult = 'game:shot-result';
  static const String publicActivity = 'game:public-activity';
  static const String playerEliminated = 'game:player-eliminated';
  static const String playerDisconnected = 'game:player-disconnected';
  static const String playerReconnected = 'game:player-reconnected';
  static const String stateSnapshot = 'game:state-snapshot';
  static const String finished = 'game:finished';
  static const String aborted = 'game:aborted';
  static const String heartbeat = 'host:heartbeat';
  static const String error = 'protocol:error';

  /// Phase 0 proof-of-concept reply to [ClientMessageType.ping].
  static const String pong = 'host:pong';
}
