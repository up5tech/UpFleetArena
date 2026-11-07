import '../../shared/protocol/protocol_message.dart';

/// One accepted client connection inside a room.
///
/// The Host binds a player identity to the socket that authenticated it. A
/// later command may not claim a different identity (PLAN.md §12).
class ClientSession {
  ClientSession({
    required this.connectionId,
    required this.connectedAt,
    this.playerId,
    this.deviceId,
    this.lastHeartbeatAt,
  });

  /// Identifier of this connection within the Host session.
  final String connectionId;

  /// When the connection was accepted.
  final DateTime connectedAt;

  /// The admitted player, or `null` while the connection is not yet joined.
  String? playerId;

  /// The device identifier presented during the join handshake.
  String? deviceId;

  /// When the last heartbeat arrived.
  DateTime? lastHeartbeatAt;

  /// Whether the connection has been closed.
  bool closed = false;

  /// Failed room-code attempts on this connection.
  ///
  /// Used to rate-limit brute-force join attempts (PLAN.md §12).
  int failedJoinAttempts = 0;

  /// Whether the connection completed the join handshake.
  bool get isAdmitted => playerId != null && !closed;
}

/// Tracks every accepted connection and the identity bound to it.
class ClientConnectionRegistry {
  final Map<String, ClientSession> _sessions = <String, ClientSession>{};

  /// Every known connection, admitted or not.
  Iterable<ClientSession> get sessions => _sessions.values;

  /// Connections that completed the join handshake.
  Iterable<ClientSession> get admittedSessions =>
      _sessions.values.where((ClientSession s) => s.isAdmitted);

  /// Number of admitted connections.
  int get admittedCount => admittedSessions.length;

  /// Registers a new connection.
  void add(ClientSession session) => _sessions[session.connectionId] = session;

  /// Looks up a connection by its identifier.
  ClientSession? byConnectionId(String connectionId) => _sessions[connectionId];

  /// Looks up a connection by the player it is bound to.
  ClientSession? byPlayerId(String playerId) {
    for (final ClientSession session in _sessions.values) {
      if (session.playerId == playerId && !session.closed) return session;
    }
    return null;
  }

  /// Looks up an active connection that presented [deviceId].
  ///
  /// Used to reject a second concurrent connection from the same device
  /// (PLAN.md §7.3).
  ClientSession? byDeviceId(String deviceId) {
    if (deviceId.isEmpty) return null;
    for (final ClientSession session in _sessions.values) {
      if (session.deviceId == deviceId && session.isAdmitted) return session;
    }
    return null;
  }

  /// Removes a connection.
  void remove(String connectionId) => _sessions.remove(connectionId);

  /// Removes every connection.
  void clear() => _sessions.clear();
}

/// Sends frames to the connected clients.
///
/// The coordinator talks to the network only through this interface, which
/// keeps the room rules testable without real sockets.
abstract class RoomTransport {
  /// Sends [message] to the connection with [connectionId].
  Future<void> send(String connectionId, ProtocolMessage message);

  /// Closes a single connection.
  Future<void> closeConnection(String connectionId);

  /// Closes every connection.
  Future<void> closeAll();
}
