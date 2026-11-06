import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/utils/secure_random.dart';
import '../shared/models/room_models.dart';
import '../shared/protocol/protocol_constants.dart';
import '../shared/protocol/protocol_message.dart';
import 'client_connection_registry.dart';
import 'projection_builder.dart';
import 'room_state.dart';

/// The Host-side room authority.
///
/// The coordinator owns room membership, admission rules and the room
/// lifecycle. It is the only component allowed to change the room state, and
/// every change is validated here rather than in the client UI
/// (PLAN.md §6.5, §13.3).
///
/// The coordinator never touches sockets directly: it emits
/// [ProtocolMessage] frames through a [RoomTransport], which keeps the rules
/// testable without a network.
class RoomCoordinator {
  RoomCoordinator({
    ClientConnectionRegistry? registry,
    this.projections = const ProjectionBuilder(),
  }) : registry = registry ?? ClientConnectionRegistry();

  /// The connections this coordinator tracks.
  final ClientConnectionRegistry registry;

  /// Builds the per-recipient views of the room.
  final ProjectionBuilder projections;
  final StreamController<RoomSnapshot> _hostSnapshots =
      StreamController<RoomSnapshot>.broadcast();

  HostRoomState? _state;
  RoomTransport? _transport;
  void Function()? _onRoomClosed;

  /// The current room, or `null` when no room is open.
  HostRoomState? get state => _state;

  /// Whether a room is currently open.
  bool get hasRoom => _state != null;

  /// The invitation code of the open room.
  String? get inviteCode => _state?.inviteCode;

  /// The Host's own view of the room.
  ///
  /// The Host does not connect to itself over TCP; its UI reads the room
  /// state through this stream.
  Stream<RoomSnapshot> get hostSnapshots => _hostSnapshots.stream;

  /// Connects the coordinator to a transport.
  ///
  /// [onRoomClosed] is invoked when the room is closed, so the transport
  /// layer can stop advertising the service.
  void attach(RoomTransport transport, {void Function()? onRoomClosed}) {
    _transport = transport;
    _onRoomClosed = onRoomClosed;
  }

  /// Creates the room and seats the Host as its first member.
  void createRoom({
    required String hostDisplayName,
    required String avatarId,
    required String deviceId,
    required RoomConfig config,
    required int tcpPort,
  }) {
    final DateTime now = DateTime.now();
    final String hostPlayerId = SecureRandom.uuidV4();

    final HostRoomState room = HostRoomState(
      roomId: SecureRandom.uuidV4(),
      inviteCode: SecureRandom.inviteCode(),
      hostPlayerId: hostPlayerId,
      config: config,
      createdAt: now,
      hostTcpPort: tcpPort,
    );

    room.players[hostPlayerId] = HostPlayer(
      playerId: hostPlayerId,
      displayName: DisplayNames.normalize(hostDisplayName),
      avatarId: avatarId,
      role: PlayerRole.host,
      deviceId: deviceId,
      joinedAt: now,
    );

    _state = room;
    _emitHostSnapshot();
  }

  /// Routes one inbound frame to the matching rule.
  Future<void> handleMessage(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    // The protocol version is checked before routing: an unknown version may
    // use message shapes this Host does not understand (PLAN.md §12).
    if (message.protocolVersion != AppProtocol.version) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.unsupportedProtocolVersion,
        'This build speaks protocol version ${AppProtocol.version}. '
        'Please update the app on both devices.',
      );
      await _transport?.closeConnection(session.connectionId);
      return;
    }

    switch (message.messageType) {
      case ClientMessageType.join:
        await _handleJoin(session, message);
      case ClientMessageType.leave:
        await _handleLeave(session, message);
      case ClientMessageType.kick:
        await _handleKick(session, message);
      case ClientMessageType.close:
        await _handleClose(session, message);
      case ClientMessageType.configUpdate:
        await _handleConfigUpdate(session, message);
      case ClientMessageType.requestSnapshot:
        await _handleSnapshotRequest(session, message);
      case ClientMessageType.heartbeat:
        _handleHeartbeat(session);
      default:
        await _sendError(
          session,
          message,
          ProtocolErrorCode.unknownMessageType,
          'Unsupported command "${message.messageType}".',
        );
    }
  }

  // ------------------------------------------------------------------ join

  Future<void> _handleJoin(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.roomNotFound,
        'This room is no longer active.',
      );
      return;
    }

    if (session.isAdmitted) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.alreadyJoined,
        'This connection has already joined the room.',
      );
      return;
    }

    final String code =
        (message.payload['code'] as String? ?? '').trim().toUpperCase();
    if (code.isEmpty || code != room.inviteCode) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.roomCodeInvalid,
        'That invitation code is not correct.',
      );
      return;
    }

    if (room.status != RoomStatus.lobby) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.roomAlreadyStarted,
        'The match has already started.',
      );
      return;
    }

    final String rawName = message.payload['displayName'] as String? ?? '';
    final String? nameProblem = DisplayNames.validate(rawName);
    if (nameProblem != null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.invalidDisplayName,
        nameProblem,
      );
      return;
    }

    final String deviceId = message.payload['deviceId'] as String? ?? '';
    if (deviceId.isNotEmpty && room.playerByDeviceId(deviceId) != null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.deviceAlreadyConnected,
        'This device is already in the room.',
      );
      return;
    }

    if (room.seatedCount >= room.config.maxPlayers) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.roomFull,
        'The room is full.',
      );
      return;
    }

    final String playerId = SecureRandom.uuidV4();
    final String resumeToken = SecureRandom.token();

    final HostPlayer player = HostPlayer(
      playerId: playerId,
      displayName: DisplayNames.normalize(rawName),
      avatarId: message.payload['avatarId'] as String? ?? '',
      role: PlayerRole.player,
      deviceId: deviceId,
      joinedAt: DateTime.now(),
      // Only the hash is kept; the raw token exists solely in the joiner's
      // response and on the joining device (PLAN.md §12).
      resumeTokenHash: _hash(resumeToken),
    );

    room.players[playerId] = player;
    session.playerId = playerId;
    session.deviceId = deviceId;
    session.lastHeartbeatAt = DateTime.now();
    room.stateVersion++;

    await _transport?.send(
      session.connectionId,
      ProtocolMessage(
        messageType: HostEventType.joined,
        requestId: message.requestId,
        payload: <String, dynamic>{
          'playerId': playerId,
          'roomId': room.roomId,
          'resumeToken': resumeToken,
          'snapshot': projections.buildFor(room, playerId).toJson(),
        },
      ),
    );

    await _broadcastRoomState(room);
    _emitHostSnapshot();
  }

  // ----------------------------------------------------------------- leave

  Future<void> _handleLeave(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null) return;

    final String? playerId = session.playerId;
    if (playerId == null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.notRoomMember,
        'You are not a member of this room.',
      );
      return;
    }

    final HostPlayer? player = room.players[playerId];
    if (player == null) return;

    player.status = PlayerConnectionStatus.left;
    room.stateVersion++;

    await _broadcastRoomState(room);
    _emitHostSnapshot();
    await _transport?.closeConnection(session.connectionId);
  }

  // ------------------------------------------------------------------ kick

  /// Removes a player from the room.
  ///
  /// This is the Host device acting on its own authority. Remote clients
  /// cannot reach it: they go through `_handleKick`, which verifies that the
  /// sender is the Host.
  Future<void> hostKick(String targetPlayerId) async {
    final HostRoomState? room = _state;
    if (room == null) return;

    final HostPlayer? target = room.players[targetPlayerId];
    if (target == null) return;
    if (target.isHost) return;

    target.status = PlayerConnectionStatus.kicked;
    room.stateVersion++;

    final ClientSession? targetSession = registry.byPlayerId(target.playerId);
    if (targetSession != null) {
      await _transport?.send(
        targetSession.connectionId,
        ProtocolMessage(
          messageType: HostEventType.closed,
          payload: <String, dynamic>{
            'reason': 'kicked',
            'message': 'The host removed you from the room.',
          },
        ),
      );
      await _transport?.closeConnection(targetSession.connectionId);
    }

    await _broadcastRoomState(room);
    _emitHostSnapshot();
  }

  Future<void> _handleKick(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null) return;

    if (session.playerId != room.hostPlayerId) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.hostOnlyAction,
        'Only the host can remove a player.',
      );
      return;
    }

    final String? targetId = message.payload['targetPlayerId'] as String?;
    final HostPlayer? target = targetId == null ? null : room.players[targetId];
    if (target == null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.playerNotFound,
        'That player is no longer in the room.',
      );
      return;
    }
    if (target.isHost) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.hostOnlyAction,
        'The host cannot be removed.',
      );
      return;
    }

    target.status = PlayerConnectionStatus.kicked;
    room.stateVersion++;

    final ClientSession? targetSession = registry.byPlayerId(target.playerId);
    if (targetSession != null) {
      await _transport?.send(
        targetSession.connectionId,
        ProtocolMessage(
          messageType: HostEventType.closed,
          payload: <String, dynamic>{
            'reason': 'kicked',
            'message': 'The host removed you from the room.',
          },
        ),
      );
      await _transport?.closeConnection(targetSession.connectionId);
    }

    await _broadcastRoomState(room);
    _emitHostSnapshot();
  }

  // ----------------------------------------------------------------- close

  Future<void> _handleClose(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null) return;

    if (session.playerId != room.hostPlayerId) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.hostOnlyAction,
        'Only the host can close the room.',
      );
      return;
    }

    await closeRoom(reason: 'host_closed', message: 'The host closed the room.');
  }

  /// Closes the room and tells every client to return Home.
  ///
  /// This is the terminal operation of the room lifecycle: the Host stops
  /// advertising, all sockets close and the room state is dropped
  /// (PLAN.md §2.9, §9.5).
  Future<void> closeRoom({
    required String reason,
    required String message,
  }) async {
    final HostRoomState? room = _state;
    if (room == null) return;

    room.status = RoomStatus.closed;
    room.stateVersion++;

    for (final ClientSession session in registry.admittedSessions.toList()) {
      await _transport?.send(
        session.connectionId,
        ProtocolMessage(
          messageType: HostEventType.closed,
          payload: <String, dynamic>{'reason': reason, 'message': message},
        ),
      );
    }

    await _transport?.closeAll();
    registry.clear();
    _emitHostSnapshot();
    _onRoomClosed?.call();
  }

  // ----------------------------------------------------------- config

  /// Applies new room settings as the Host device.
  ///
  /// Remote clients cannot reach this: they go through `_handleConfigUpdate`,
  /// which verifies that the sender is the Host.
  ///
  /// Returns the validation problems, or an empty list on success.
  Future<List<String>> hostUpdateConfig(RoomConfig config) async {
    final HostRoomState? room = _state;
    if (room == null) return const <String>[];
    if (room.status != RoomStatus.lobby) {
      return <String>['The room settings can no longer be changed.'];
    }

    final List<String> problems = _configProblems(room, config);
    if (problems.isNotEmpty) return problems;

    await _applyConfig(room, config);
    return const <String>[];
  }

  /// Collects every reason the configuration cannot be accepted.
  List<String> _configProblems(HostRoomState room, RoomConfig config) {
    final List<String> problems = config.validate();
    if (config.maxPlayers < room.seatedCount) {
      problems.add(
        'The capacity cannot be lower than the ${room.seatedCount} players '
        'already seated in the room.',
      );
    }
    return problems;
  }

  /// Stores the accepted configuration and tells every client about it.
  Future<void> _applyConfig(HostRoomState room, RoomConfig config) async {
    room.config = config;
    room.stateVersion++;
    await _broadcastConfig(room);
    _emitHostSnapshot();
  }

  /// Sends the accepted configuration to every admitted client.
  ///
  /// Each client receives its own projection (PLAN.md §6.6).
  Future<void> _broadcastConfig(HostRoomState room) async {
    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.configUpdated,
          payload: <String, dynamic>{
            'config': room.config.toJson(),
            'stateVersion': room.stateVersion,
            'snapshot': projections.buildFor(room, client.playerId).toJson(),
          },
        ),
      );
    }
  }

  Future<void> _handleConfigUpdate(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null) return;

    if (session.playerId != room.hostPlayerId) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.hostOnlyAction,
        'Only the host can change the room settings.',
      );
      return;
    }
    if (room.status != RoomStatus.lobby) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.roomAlreadyStarted,
        'The room settings can no longer be changed.',
      );
      return;
    }

    final Object? rawConfig = message.payload['config'];
    if (rawConfig is! Map<String, dynamic>) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.invalidRoomConfig,
        'The room settings were malformed.',
      );
      return;
    }

    final RoomConfig parsed;
    try {
      parsed = RoomConfig.fromJson(rawConfig);
    } on FormatException {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.invalidRoomConfig,
        'The room settings were malformed.',
      );
      return;
    }

    final List<String> problems = _configProblems(room, parsed);
    if (problems.isNotEmpty) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.invalidRoomConfig,
        problems.join(' '),
      );
      return;
    }

    await _applyConfig(room, parsed);
  }

  // ----------------------------------------------------------- heartbeat

  void _handleHeartbeat(ClientSession session) {
    session.lastHeartbeatAt = DateTime.now();
    final String? playerId = session.playerId;
    final HostRoomState? room = _state;
    if (playerId == null || room == null) return;
    room.playerById(playerId)?.lastHeartbeatAt = session.lastHeartbeatAt;
  }

  Future<void> _handleSnapshotRequest(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null || session.playerId == null) return;
    await _transport?.send(
      session.connectionId,
      ProtocolMessage(
        messageType: HostEventType.stateSnapshot,
        requestId: message.requestId,
        payload: <String, dynamic>{
          'snapshot': projections.buildFor(room, session.playerId).toJson(),
        },
      ),
    );
  }

  // -------------------------------------------------------------- helpers

  /// Marks a member as disconnected when their socket drops.
  void handleConnectionLost(ClientSession session) {
    final HostRoomState? room = _state;
    final String? playerId = session.playerId;
    if (room == null || playerId == null) return;

    final HostPlayer? player = room.players[playerId];
    if (player == null) return;
    if (player.status != PlayerConnectionStatus.connected) return;

    player.status = PlayerConnectionStatus.disconnected;
    player.disconnectedAt = DateTime.now();
    room.stateVersion++;
    _emitHostSnapshot();
  }

  /// Sends the current room state to every admitted client.
  ///
  /// Each client receives its own projection.
  Future<void> _broadcastRoomState(HostRoomState room) async {
    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.roomState,
          payload: <String, dynamic>{
            'snapshot': projections.buildFor(room, client.playerId).toJson(),
          },
        ),
      );
    }
  }

  void _emitHostSnapshot() {
    final HostRoomState? room = _state;
    if (room == null || _hostSnapshots.isClosed) return;
    _hostSnapshots.add(projections.buildFor(room, room.hostPlayerId));
  }

  Future<void> _sendError(
    ClientSession session,
    ProtocolMessage request,
    String code,
    String message,
  ) async {
    await _transport?.send(
      session.connectionId,
      ProtocolMessage(
        messageType: HostEventType.error,
        requestId: request.requestId,
        payload: <String, dynamic>{'code': code, 'message': message},
      ),
    );
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  /// Releases the resources held by the coordinator.
  Future<void> dispose() async {
    await _hostSnapshots.close();
    registry.clear();
    _state = null;
  }
}
