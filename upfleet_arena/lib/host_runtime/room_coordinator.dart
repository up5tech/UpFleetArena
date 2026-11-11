import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/config/app_config.dart';
import '../core/utils/secure_random.dart';
import '../game_engine/board/board.dart';
import '../game_engine/bot/bot_brain.dart';
import '../game_engine/combat/combat.dart';
import '../game_engine/combat/match_result.dart';
import '../game_engine/fleet/fleet_profile.dart';
import '../game_engine/placement/auto_placement.dart';
import '../game_engine/placement/placement.dart';
import '../game_engine/placement/placement_validator.dart';
import '../shared/models/match_models.dart';
import '../shared/models/placement_models.dart';
import '../shared/models/room_models.dart';
import '../shared/protocol/protocol_constants.dart';
import '../shared/protocol/protocol_message.dart';
import 'client_connection_registry.dart';
import 'projection_builder.dart';
import 'room_state.dart';

/// The reason a shot was rejected.
class _FireRejection {
  const _FireRejection(this.code, this.message);

  /// The stable error code of the rejection.
  final String code;

  /// The user-safe explanation.
  final String message;
}

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
    DateTime Function()? clock,
    this.botThinkingTime = const Duration(milliseconds: 900),
    Random? botRandom,
    String Function(BotDifficulty difficulty)? botNameBuilder,
  }) : registry = registry ?? ClientConnectionRegistry(),
       botRandom = botRandom ?? Random(),
       _botNameBuilder = botNameBuilder ?? _defaultBotName,
       _clock = clock ?? _monotonicClock();

  /// Names the computers the Host seats from [RoomConfig.botCount].
  ///
  /// The Host runtime has no access to the UI language, so the UI passes a
  /// localized name builder when it creates the room.
  final String Function(BotDifficulty difficulty) _botNameBuilder;

  static String _defaultBotName(BotDifficulty difficulty) {
    final String label = difficulty.name;
    return 'Computer (${label[0].toUpperCase()}${label.substring(1)})';
  }

  static DateTime Function() _monotonicClock() {
    final DateTime origin = DateTime.now();
    final Stopwatch elapsed = Stopwatch()..start();
    return () => origin.add(elapsed.elapsed);
  }

  Future<void>? _commandTail;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final Future<void>? previous = _commandTail;
    final Future<T> result = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    final Future<void> tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _commandTail = tail;
    unawaited(
      tail.then((_) {
        if (identical(_commandTail, tail)) _commandTail = null;
      }),
    );
    return result;
  }

  /// The connections this coordinator tracks.
  final ClientConnectionRegistry registry;

  /// The time source of the preparation deadline.
  final DateTime Function() _clock;

  /// Builds the per-recipient views of the room.
  final ProjectionBuilder projections;

  /// How long a computer opponent thinks before it fires.
  ///
  /// Tests shorten it so a whole match can be played without real waiting.
  final Duration botThinkingTime;

  /// The randomness a computer opponent uses.
  final Random botRandom;
  final StreamController<RoomSnapshot> _hostSnapshots =
      StreamController<RoomSnapshot>.broadcast();
  final StreamController<PlacementState> _hostPlacementStates =
      StreamController<PlacementState>.broadcast();
  final StreamController<ReadinessState> _hostReadinessStates =
      StreamController<ReadinessState>.broadcast();
  final StreamController<int> _hostCountdowns =
      StreamController<int>.broadcast();
  final StreamController<MatchStartState> _hostMatchStarts =
      StreamController<MatchStartState>.broadcast();
  final StreamController<String> _hostNotices =
      StreamController<String>.broadcast();
  final StreamController<int> _hostTurnCountdowns =
      StreamController<int>.broadcast();
  final StreamController<MatchSnapshot> _hostMatchSnapshots =
      StreamController<MatchSnapshot>.broadcast();
  final StreamController<MatchResult> _hostMatchResults =
      StreamController<MatchResult>.broadcast();

  final StreamController<ShotFeedback> _hostShotFeedbacks =
      StreamController<ShotFeedback>.broadcast();
  final StreamController<PublicActivity> _hostPublicActivities =
      StreamController<PublicActivity>.broadcast();

  Stream<ShotFeedback> get hostShotFeedbacks => _hostShotFeedbacks.stream;
  Stream<PublicActivity> get hostPublicActivities =>
      _hostPublicActivities.stream;

  Timer? _phaseTimer;

  Timer? _botTimer;

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

  /// The Host's own fleet layout.
  Stream<PlacementState> get hostPlacementStates => _hostPlacementStates.stream;

  /// The readiness of every member, as everybody may see it.
  Stream<ReadinessState> get hostReadinessStates => _hostReadinessStates.stream;

  /// The seconds that are left before the preparation ends.
  Stream<int> get hostCountdowns => _hostCountdowns.stream;

  /// The match that just started.
  Stream<MatchStartState> get hostMatchStarts => _hostMatchStarts.stream;

  /// The match state of the Host, as every client receives it.
  Stream<MatchSnapshot> get hostMatchSnapshots => _hostMatchSnapshots.stream;

  /// The final result of the match, once one player was left alive.
  Stream<MatchResult> get hostMatchResults => _hostMatchResults.stream;

  /// The seconds that are left before the current turn ends.
  Stream<int> get hostTurnCountdowns => _hostTurnCountdowns.stream;

  /// Messages the Host shows to its own player.
  Stream<String> get hostNotices => _hostNotices.stream;

  /// The seconds that are left before the preparation ends.
  ///
  /// Returns `null` when no preparation is running. The Host owns the
  /// deadline; a client never computes it (PLAN.md §9.4).
  int? get placementRemainingSeconds {
    final HostRoomState? room = _state;
    final DateTime? deadline = room?.placementDeadline;
    if (room == null || deadline == null) return null;
    final int left =
        (deadline.difference(_now()).inMicroseconds /
                Duration.microsecondsPerSecond)
            .ceil();
    return left < 0 ? 0 : left;
  }

  /// The seconds that are left before the current turn ends.
  ///
  /// Returns `null` when no turn is running.
  int? get turnRemainingSeconds {
    final HostRoomState? room = _state;
    final DateTime? deadline = room?.match?.turnDeadline;
    if (room == null || deadline == null) return null;
    final int left =
        (deadline.difference(_now()).inMicroseconds /
                Duration.microsecondsPerSecond)
            .ceil();
    return left < 0 ? 0 : left;
  }

  /// The current time of the Host.
  DateTime _now() => _clock();

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
    // The Host may have preset computers before the room is even listed.
    _syncBots(room);
    _emitHostSnapshot();
  }

  /// Seats a computer opponent in the room.
  ///
  /// Only the Host device can do this and only before the preparation starts.
  /// A bot has no socket: it occupies a normal seat and the Host runtime plays
  /// its turns with the same validation as a remote client (see [BotBrain]).
  ///
  /// Returns the validation problems, or an empty list on success.
  Future<List<String>> hostAddBot({
    required String displayName,
    required BotDifficulty difficulty,
  }) => _serialize(() => _hostAddBot(displayName, difficulty));

  Future<List<String>> _hostAddBot(
    String displayName,
    BotDifficulty difficulty,
  ) async {
    final HostRoomState? room = _state;
    if (room == null) return <String>['The room is not open.'];
    if (room.status != RoomStatus.lobby) {
      return <String>[
        'The computer can only join before the preparation starts.',
      ];
    }
    final String? nameProblem = DisplayNames.validate(displayName);
    if (nameProblem != null) return <String>[nameProblem];
    if (room.seatedCount >= room.config.maxPlayers) {
      return <String>['The room is full.'];
    }

    _seatBot(room, difficulty, displayName: displayName);
    // The computer count in the settings always reflects the seats, so a
    // later settings save keeps the computer that was just added.
    room.config = room.config.copyWith(
      botCount: room.config.botCount + 1,
      botDifficulty: difficulty,
    );
    room.stateVersion++;

    await _broadcastRoomState(room);
    await _broadcastReadiness(room);
    await _broadcastConfig(room);
    _emitHostSnapshot();
    return const <String>[];
  }

  /// Lowers the preset computer count when a computer gives up its seat.
  ///
  /// Otherwise a later settings save would seat the removed computer again.
  /// Returns whether the settings changed.
  bool _releaseBotPreset(HostRoomState room, HostPlayer target) {
    if (!target.isBot || room.config.botCount <= 0) return false;
    room.config = room.config.copyWith(botCount: room.config.botCount - 1);
    return true;
  }

  /// Seats one computer opponent and returns its seat.
  ///
  /// Bot names must not clash, otherwise two computers of the same strength
  /// would be indistinguishable in the lobby and in the match.
  HostPlayer _seatBot(
    HostRoomState room,
    BotDifficulty difficulty, {
    String? displayName,
  }) {
    final String playerId = SecureRandom.uuidV4();
    final HostPlayer bot = HostPlayer(
      playerId: playerId,
      displayName: _uniqueDisplayName(
        room,
        DisplayNames.normalize(displayName ?? _botNameBuilder(difficulty)),
      ),
      avatarId: '🤖',
      role: PlayerRole.player,
      deviceId: '',
      joinedAt: _now(),
      isBot: true,
      botDifficulty: difficulty,
    );
    room.players[playerId] = bot;
    return bot;
  }

  /// Makes the seated computers match the room settings.
  ///
  /// The Host owns the seats, so the preset typed into the room settings is
  /// applied here instead of in the settings screen. Computers that are no
  /// longer wanted (or that play at another strength) give up their seat.
  ///
  /// Returns whether the membership changed.
  bool _syncBots(HostRoomState room) {
    if (room.status != RoomStatus.lobby) return false;

    final BotDifficulty strength = room.config.botDifficulty;
    final int target = room.config.botCount;
    final List<HostPlayer> seated = room.orderedPlayers
        .where((HostPlayer player) => player.isBot && player.occupiesSeat)
        .toList();

    bool changed = false;
    int kept = 0;
    for (final HostPlayer bot in seated) {
      if (kept < target && bot.botDifficulty == strength) {
        kept++;
        continue;
      }
      bot.status = PlayerConnectionStatus.kicked;
      room.placements.remove(bot.playerId);
      changed = true;
    }

    for (int index = kept; index < target; index++) {
      // People always win a seat over a preset computer.
      if (room.seatedCount >= room.config.maxPlayers) break;
      _seatBot(room, strength);
      changed = true;
    }

    if (changed) room.stateVersion++;
    return changed;
  }

  /// A display name a new computer opponent can use without clashing.
  ///
  /// Two computers of the same strength would otherwise be indistinguishable
  /// in the lobby and in the match.
  String _uniqueDisplayName(HostRoomState room, String base) {
    final Set<String> taken = room.players.values
        .where((HostPlayer player) => player.occupiesSeat)
        .map((HostPlayer player) => player.displayName.toLowerCase())
        .toSet();
    if (!taken.contains(base.toLowerCase())) return base;

    for (int suffix = 2; suffix < 100; suffix++) {
      final String candidate = '$base $suffix';
      final String trimmed = candidate.length > DisplayNames.maximumLength
          ? candidate.substring(0, DisplayNames.maximumLength).trim()
          : candidate;
      if (!taken.contains(trimmed.toLowerCase())) return trimmed;
    }
    return base;
  }

  /// Routes one inbound frame to the matching rule.
  Future<void> handleMessage(
    ClientSession session,
    ProtocolMessage message,
  ) => _serialize(() async {
    try {
      await _handleMessage(session, message);
    } on Object {
      // Never leak raw exception text. A malformed command is rejected with a
      // stable code and the connection stays under Host control
      // (PLAN.md §8.4, §12).
      await _sendError(
        session,
        message,
        ProtocolErrorCode.malformedPayload,
        'That command could not be read.',
      );
    }
  });

  Future<void> _handleMessage(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    if (_state?.status == RoomStatus.closed) return;
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
      case ClientMessageType.placementSet:
        await _handlePlacementSet(session, message);
      case ClientMessageType.placementAuto:
        await _handlePlacementAuto(session, message);
      case ClientMessageType.placementReady:
        await _handlePlacementReady(session, message);
      case ClientMessageType.startPlacement:
        await _handleStartPlacement(session, message);
      case ClientMessageType.fire:
        await _handleFire(session, message);
      case ClientMessageType.requestSnapshot:
        await _handleSnapshotRequest(session, message);
      case ClientMessageType.heartbeat:
        _handleHeartbeat(session);
      case ClientMessageType.resume:
        await _handleResume(session, message);
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

    if (session.failedJoinAttempts >= 5) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.rateLimited,
        'Too many failed join attempts. The connection is being closed.',
      );
      await _transport?.closeConnection(session.connectionId);
      return;
    }

    final String code = (message.payload['code'] as String? ?? '')
        .trim()
        .toUpperCase();
    if (code.isEmpty || code != room.inviteCode) {
      session.failedJoinAttempts++;
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
        'The room no longer accepts new players.',
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
    await _sendPlacementState(room, playerId);
    await _broadcastReadiness(room);
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
    room.placements.remove(playerId);

    await _broadcastRoomState(room);
    await _broadcastReadiness(room);
    await _checkPreparationCancellation(room);
    _emitHostSnapshot();
    await _transport?.closeConnection(session.connectionId);
  }

  // ------------------------------------------------------------------ kick

  /// Removes a player from the room.
  ///
  /// This is the Host device acting on its own authority. Remote clients
  /// cannot reach it: they go through `_handleKick`, which verifies that the
  /// sender is the Host.
  Future<void> hostKick(String targetPlayerId) =>
      _serialize(() => _hostKick(targetPlayerId));

  Future<void> _hostKick(String targetPlayerId) async {
    final HostRoomState? room = _state;
    if (room == null || room.status == RoomStatus.closed) return;

    final HostPlayer? target = room.players[targetPlayerId];
    if (target == null) return;
    if (target.isHost) return;

    target.status = PlayerConnectionStatus.kicked;
    room.stateVersion++;
    room.placements.remove(target.playerId);

    final bool botRemoved = _releaseBotPreset(room, target);

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
    await _broadcastReadiness(room);
    if (botRemoved) await _broadcastConfig(room);
    await _checkPreparationCancellation(room);
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
    room.placements.remove(target.playerId);

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

    final bool botRemoved = _releaseBotPreset(room, target);

    await _broadcastRoomState(room);
    await _broadcastReadiness(room);
    if (botRemoved) await _broadcastConfig(room);
    await _checkPreparationCancellation(room);
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

    await _closeRoom(
      reason: 'host_closed',
      message: 'The host closed the room.',
    );
  }

  /// Closes the room and tells every client to return Home.
  ///
  /// This is the terminal operation of the room lifecycle: the Host stops
  /// advertising, all sockets close and the room state is dropped
  /// (PLAN.md §2.9, §9.5).
  Future<void> closeRoom({required String reason, required String message}) =>
      _serialize(() => _closeRoom(reason: reason, message: message));

  Future<void> _closeRoom({
    required String reason,
    required String message,
  }) async {
    final HostRoomState? room = _state;
    if (room == null || room.status == RoomStatus.closed) return;

    _stopPlacementTimer();
    _stopBotTimer();
    room.status = RoomStatus.closed;
    room.placementDeadline = null;
    room.match?.turnDeadline = null;
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
  Future<List<String>> hostUpdateConfig(RoomConfig config) =>
      _serialize(() => _hostUpdateConfig(config));

  Future<List<String>> _hostUpdateConfig(RoomConfig config) async {
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
    // People always keep their seat: a preset computer only takes a free one.
    final int people = room.players.values
        .where((HostPlayer player) => player.occupiesSeat && !player.isBot)
        .length;
    if (people + config.botCount > config.maxPlayers) {
      final int free = config.maxPlayers - people;
      problems.add(
        free <= 0
            ? 'The room has no free seat for a computer.'
            : 'Only $free of the seats are free for computers.',
      );
    }
    return problems;
  }

  /// Stores the accepted configuration and tells every client about it.
  Future<void> _applyConfig(HostRoomState room, RoomConfig config) async {
    // A new board size or a new fleet invalidates every layout that was
    // placed on the old one.
    final bool invalidatesLayouts =
        config.rows != room.config.rows ||
        config.columns != room.config.columns ||
        config.fleetPreset != room.config.fleetPreset;

    room.config = config;
    room.stateVersion++;
    // A preset with more or stronger computers is applied before the clients
    // hear about the new settings, so they see the seats and the values
    // together.
    final bool botsChanged = _syncBots(room);

    if (invalidatesLayouts) {
      for (final HostPlayerPlacement placement in room.placements.values) {
        placement.ships.clear();
        placement.ready = false;
      }
      // The clients keep showing their own board, so they have to receive the
      // cleared layout as well.
      for (final ClientSession client in registry.admittedSessions.toList()) {
        final String? playerId = client.playerId;
        if (playerId == null) continue;
        await _transport?.send(
          client.connectionId,
          ProtocolMessage(
            messageType: HostEventType.placementState,
            payload: _placementState(room, playerId).toJson(),
          ),
        );
      }
      await _broadcastReadiness(room);
      _emitHostPlacementState(room);
    }

    if (botsChanged) {
      await _broadcastRoomState(room);
      await _broadcastReadiness(room);
    }
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

  // ----------------------------------------------------------- placement

  /// The fleet layout of one member.
  ///
  /// The entry is created on first use, so a player that never placed a ship
  /// still shows up as "not ready".
  HostPlayerPlacement placementFor(String playerId) {
    final HostRoomState? room = _state;
    if (room == null) return HostPlayerPlacement(playerId: playerId);
    return room.placements.putIfAbsent(
      playerId,
      () => HostPlayerPlacement(playerId: playerId),
    );
  }

  /// The fleet profile the room currently asks for.
  FleetProfile _profile(HostRoomState room) =>
      FleetProfile.fromPreset(room.config.fleetPreset);

  /// The board the room currently uses.
  BoardSize _board(HostRoomState room) =>
      BoardSize(rows: room.config.rows, columns: room.config.columns);

  /// Applies a fleet layout as the Host device.
  ///
  /// Returns the validation problems, or an empty list on success.
  Future<List<String>> hostSetPlacement(List<ShipPlacement> ships) =>
      _serialize(() => _hostSetPlacement(ships));

  Future<List<String>> _hostSetPlacement(List<ShipPlacement> ships) async {
    final HostRoomState? room = _state;
    if (room == null) return const <String>[];
    if (!_acceptsPlacements(room)) {
      return <String>['The fleets cannot be changed any more.'];
    }

    final List<String> lockProblems = _layoutLockProblems(
      room,
      room.hostPlayerId,
    );
    if (lockProblems.isNotEmpty) return lockProblems;

    final PlacementError? error = validateFleetLayout(
      board: _board(room),
      profile: _profile(room),
      ships: ships,
    );
    if (error != null) return <String>[error.message];

    await _applyLayout(room, room.hostPlayerId, ships);
    return const <String>[];
  }

  /// Places the Host's own fleet automatically.
  Future<List<String>> hostAutoPlace() => _serialize(_hostAutoPlace);

  Future<List<String>> _hostAutoPlace() async {
    final HostRoomState? room = _state;
    if (room == null) return const <String>[];
    if (!_acceptsPlacements(room)) {
      return <String>['The fleets cannot be changed any more.'];
    }
    final List<String> problems = _layoutLockProblems(room, room.hostPlayerId);
    if (problems.isNotEmpty) return problems;
    await _autoPlace(room, room.hostPlayerId);
    return const <String>[];
  }

  /// Confirms the Host's own fleet.
  Future<List<String>> hostSetReady() => _serialize(_hostSetReady);

  Future<List<String>> _hostSetReady() async {
    final HostRoomState? room = _state;
    if (room == null) return const <String>[];
    return _confirmReady(room, room.hostPlayerId);
  }

  Future<void> _handlePlacementSet(
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
    if (!_acceptsPlacements(room)) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.placementPhaseNotActive,
        'The fleets cannot be changed any more.',
      );
      return;
    }

    final Object? rawShips = message.payload['ships'];
    if (rawShips is! List) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.invalidShipPlacement,
        'The fleet layout was malformed.',
      );
      return;
    }

    final List<String> lockProblems = _layoutLockProblems(room, playerId);
    if (lockProblems.isNotEmpty) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.placementLocked,
        lockProblems.join(' '),
      );
      return;
    }

    final List<ShipPlacement> ships = <ShipPlacement>[];
    for (final Object? entry in rawShips) {
      if (entry is! Map<String, dynamic>) {
        await _sendError(
          session,
          message,
          ProtocolErrorCode.invalidShipPlacement,
          'The fleet layout was malformed.',
        );
        return;
      }
      ships.add(ShipLayout.fromJson(entry).toPlacement());
    }

    final PlacementError? error = validateFleetLayout(
      board: _board(room),
      profile: _profile(room),
      ships: ships,
    );
    if (error != null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.invalidShipPlacement,
        error.message,
      );
      await _sendPlacementState(room, playerId);
      return;
    }

    await _applyLayout(room, playerId, ships);
  }

  Future<void> _handlePlacementAuto(
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
    if (!_acceptsPlacements(room)) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.placementPhaseNotActive,
        'The fleets cannot be changed any more.',
      );
      return;
    }

    final List<String> problems = _layoutLockProblems(room, playerId);
    if (problems.isNotEmpty) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.placementLocked,
        problems.join(' '),
      );
      return;
    }
    await _autoPlace(room, playerId);
  }

  Future<void> _handlePlacementReady(
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
    if (!_acceptsPlacements(room)) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.placementPhaseNotActive,
        'The fleets cannot be changed any more.',
      );
      return;
    }

    final List<String> problems = await _confirmReady(room, playerId);
    if (problems.isNotEmpty) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.fleetIncomplete,
        problems.join(' '),
      );
    }
  }

  /// Stores a validated fleet layout and tells everybody about it.
  Future<void> _applyLayout(
    HostRoomState room,
    String playerId,
    List<ShipPlacement> ships,
  ) async {
    final HostPlayerPlacement placement = placementFor(playerId);
    final bool wasReady = placement.ready;

    placement.ships
      ..clear()
      ..addEntries(
        ships.map(
          (ShipPlacement ship) =>
              MapEntry<String, ShipPlacement>(ship.shipId, ship),
        ),
      );
    // Changing the fleet invalidates the confirmation.
    placement.ready = false;

    room.stateVersion++;
    await _sendPlacementState(room, playerId);
    if (wasReady) await _broadcastReadiness(room);
  }

  /// Whether the room still accepts fleet layouts.
  ///
  /// The lobby accepts them and so does the preparation phase: a player who
  /// did not confirm a fleet may still place one until the deadline
  /// (PLAN.md §2.5).
  bool _acceptsPlacements(HostRoomState room) =>
      room.status == RoomStatus.lobby || room.status == RoomStatus.placement;

  /// The reasons a player may not change the fleet any more.
  ///
  /// A confirmed fleet is locked for the rest of the preparation phase
  /// (PLAN.md §2.5).
  List<String> _layoutLockProblems(HostRoomState room, String playerId) {
    if (room.status != RoomStatus.placement) return const <String>[];
    if (!placementFor(playerId).ready) return const <String>[];
    return <String>['Your fleet is confirmed and can no longer be changed.'];
  }

  /// Places the fleet of a member automatically.
  Future<void> _autoPlace(HostRoomState room, String playerId) async {
    final List<ShipPlacement> ships = autoPlaceFleet(
      board: _board(room),
      profile: _profile(room),
      random: Random(),
    );
    await _applyLayout(room, playerId, ships);
  }

  /// Confirms a complete fleet.
  Future<List<String>> _confirmReady(
    HostRoomState room,
    String playerId,
  ) async {
    if (!_acceptsPlacements(room)) {
      return <String>['The fleets cannot be changed any more.'];
    }
    final HostPlayerPlacement placement = placementFor(playerId);
    final List<ShipPlacement> ships = placement.ships.values.toList();

    if (!isFleetComplete(_profile(room), ships)) {
      return <String>['Place every ship before you are ready.'];
    }

    final PlacementError? error = validateFleetLayout(
      board: _board(room),
      profile: _profile(room),
      ships: ships,
    );
    if (error != null) return <String>[error.message];

    placement.ready = true;
    room.stateVersion++;
    await _sendPlacementState(room, playerId);
    await _broadcastReadiness(room);

    // The match starts as soon as every player confirmed a fleet.
    if (room.status == RoomStatus.placement && _everyoneReady(room)) {
      await _startMatch(room);
    }
    return const <String>[];
  }

  /// Whether every connected player confirmed a complete fleet.
  bool _everyoneReady(HostRoomState room) {
    final List<HostPlayer> players = _eligiblePlayers(room);
    if (players.length < RoomConfig.minimumPlayers) return false;
    return players.every(
      (HostPlayer player) =>
          room.placements[player.playerId]?.ready == true &&
          _hasLegalFleet(room, player.playerId),
    );
  }

  List<HostPlayer> _eligiblePlayers(HostRoomState room) =>
      room.orderedPlayers.where((HostPlayer player) {
        if (player.status != PlayerConnectionStatus.connected) return false;
        final ClientSession? session = registry.byPlayerId(player.playerId);
        return player.isHost ||
            player.isBot ||
            (session != null && _isLiveMember(room, session));
      }).toList();

  bool _hasLegalFleet(HostRoomState room, String playerId) {
    final List<ShipPlacement> ships =
        room.placements[playerId]?.ships.values.toList() ?? <ShipPlacement>[];
    return isFleetComplete(_profile(room), ships) &&
        validateFleetLayout(
              board: _board(room),
              profile: _profile(room),
              ships: ships,
            ) ==
            null;
  }

  /// Sends the exact fleet layout to its owner only.
  Future<void> _sendPlacementState(HostRoomState room, String playerId) async {
    final PlacementState state = _placementState(room, playerId);

    final ClientSession? session = registry.byPlayerId(playerId);
    if (session != null) {
      await _transport?.send(
        session.connectionId,
        ProtocolMessage(
          messageType: HostEventType.placementState,
          payload: state.toJson(),
        ),
      );
    }
    _emitHostPlacementState(room);
  }

  /// Tells everybody which members confirmed their fleet.
  ///
  /// The event carries no coordinates: the layout of a player stays private.
  Future<void> _broadcastReadiness(HostRoomState room) async {
    final ReadinessState state = _readinessState(room);

    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.placementReadyState,
          payload: state.toJson(),
        ),
      );
    }
    _emitHostReadinessState(room);
  }

  PlacementState _placementState(HostRoomState room, String playerId) {
    final HostPlayerPlacement placement = placementFor(playerId);
    return PlacementState(
      playerId: playerId,
      ships: placement.ships.values.map(ShipLayout.fromPlacement).toList(),
      ready: placement.ready,
      stateVersion: room.stateVersion,
    );
  }

  ReadinessState _readinessState(HostRoomState room) {
    return ReadinessState(
      players: room.orderedPlayers
          .where((HostPlayer player) => player.occupiesSeat)
          .map(
            (HostPlayer player) => PlayerReadiness(
              playerId: player.playerId,
              displayName: player.displayName,
              ready: room.placements[player.playerId]?.ready ?? false,
            ),
          )
          .toList(),
      stateVersion: room.stateVersion,
    );
  }

  // --------------------------------------------------------------- combat

  /// The Host-owned turn deadline check.
  ///
  /// When the player does not fire in time, the Host skips the turn and
  /// advances to the next living player (PLAN.md §2.7).
  Future<void> checkTurnDeadline() => _serialize(_checkTurnDeadline);

  Future<void> _checkTurnDeadline() async {
    final HostRoomState? room = _state;
    final HostMatchState? match = room?.match;
    if (room == null || match == null || room.status != RoomStatus.active) {
      return;
    }
    final int? remaining = turnRemainingSeconds;
    if (remaining == null) return;
    if (remaining > 0) {
      _emitHostTurnCountdown(remaining);
      return;
    }
    match.recordTimeout(match.activePlayerId);
    _completeTurn(room);
    await _emitTurnResolution(room);
  }

  void _completeTurn(HostRoomState room) {
    final HostMatchState match = room.match!;
    final String? next = getNextLivingPlayer(
      turnOrder: match.turnOrder,
      currentPlayerId: match.activePlayerId,
      isAlive: match.isAlive,
    );
    if (isMatchFinished(match.aliveCount) || next == null) {
      _stopPlacementTimer();
      match.turnDeadline = null;
      match.finishedAt = _now();
      room.status = RoomStatus.finished;
    } else {
      match.activePlayerId = next;
      match.turnNumber++;
      match.turnDeadline = _now().add(
        Duration(seconds: room.config.turnDurationSeconds),
      );
    }
    room.stateVersion++;
  }

  Future<void> _emitTurnResolution(HostRoomState room) async {
    if (room.status == RoomStatus.finished) {
      _stopBotTimer();
      await _finishMatch(room, room.match!.winnerPlayerId);
      return;
    }
    _emitHostTurnCountdown(turnRemainingSeconds!);
    await _broadcastTurnStarted(room);
    await _broadcastMatchSnapshot(room);
    _scheduleBotTurn(room);
  }

  // ------------------------------------------------------- computer opponent

  /// Lets a computer opponent take its turn when it owns the current one.
  void _scheduleBotTurn(HostRoomState room) {
    _stopBotTimer();
    final HostMatchState? match = room.match;
    if (match == null || room.status != RoomStatus.active) return;
    final HostPlayer? active = room.players[match.activePlayerId];
    if (active == null || !active.isBot || !match.isAlive(active.playerId)) {
      return;
    }
    _botTimer = Timer(botThinkingTime, () => unawaited(_playBotTurn()));
  }

  void _stopBotTimer() {
    _botTimer?.cancel();
    _botTimer = null;
  }

  Future<void> _playBotTurn() => _serialize(_performBotTurn);

  /// Plays one turn of a computer opponent.
  ///
  /// The bot goes through `_fireAs`, so the same validation rejects a repeated
  /// cell, a dead target or an expired turn as it does for a remote client
  /// (GAME_RULES.md §6).
  Future<void> _performBotTurn() async {
    final HostRoomState? room = _state;
    final HostMatchState? match = room?.match;
    if (room == null || match == null || room.status != RoomStatus.active) {
      return;
    }

    final String botId = match.activePlayerId;
    final HostPlayer? bot = room.players[botId];
    if (bot == null || !bot.isBot || !match.isAlive(botId)) return;

    final DateTime? deadline = match.turnDeadline;
    if (deadline == null || !_now().isBefore(deadline)) return;

    // One shot is resolved against every living fleet, so the bot reasons
    // about a single set of cells instead of per-opponent boards.
    final Map<CellCoord, ShotResult> known = <CellCoord, ShotResult>{};
    for (final String targetId in match.turnOrder) {
      if (targetId == botId || !match.isAlive(targetId)) continue;
      final Map<CellCoord, ShotResult> shots =
          match.attackHistory[botId]?[targetId] ??
          const <CellCoord, ShotResult>{};
      for (final MapEntry<CellCoord, ShotResult> entry in shots.entries) {
        final ShotResult? previous = known[entry.key];
        known[entry.key] = previous == null
            ? entry.value
            : strongerShotResult(previous, entry.value);
      }
    }

    final CellCoord? cell = BotBrain(
      difficulty: bot.botDifficulty ?? BotDifficulty.medium,
      random: botRandom,
    ).chooseCell(board: _board(room), shots: known);
    if (cell == null) return;

    await _fireAs(
      room,
      match,
      botId,
      cell.row,
      cell.column,
      matchId: match.matchId,
      turnNumber: match.turnNumber,
      expectedStateVersion: room.stateVersion,
    );
  }

  Future<List<String>> hostFire({
    required String matchId,
    required int turnNumber,
    required int expectedStateVersion,
    required int row,
    required int column,
  }) => _serialize(() async {
    final HostRoomState? room = _state;
    final HostMatchState? match = room?.match;
    if (room == null || match == null || room.status != RoomStatus.active) {
      return <String>['The match is not running.'];
    }
    final _FireRejection? rejection = await _fireAs(
      room,
      match,
      room.hostPlayerId,
      row,
      column,
      matchId: matchId,
      turnNumber: turnNumber,
      expectedStateVersion: expectedStateVersion,
    );
    return rejection == null ? const <String>[] : <String>[rejection.message];
  });

  bool _isLiveMember(HostRoomState room, ClientSession session) =>
      session.isAdmitted &&
      identical(registry.byConnectionId(session.connectionId), session) &&
      identical(registry.byPlayerId(session.playerId!), session) &&
      room.players[session.playerId]?.status ==
          PlayerConnectionStatus.connected;

  Future<void> _handleFire(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null) return;
    if (!_isLiveMember(room, session) ||
        (message.playerId != null && message.playerId != session.playerId) ||
        (message.payload.containsKey('playerId') &&
            message.payload['playerId'] != session.playerId)) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.notRoomMember,
        'This connection is not authenticated as that room member.',
      );
      return;
    }
    final HostMatchState? match = room.match;
    if (match == null || room.status != RoomStatus.active) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.matchAlreadyFinished,
        'The match is not running.',
      );
      return;
    }
    final Object? row = message.payload['row'];
    final Object? column = message.payload['column'];
    final Object? matchId = message.payload['matchId'];
    final Object? turnNumber = message.payload['turnNumber'];
    if (message.requestId == null ||
        message.requestId!.trim().isEmpty ||
        row is! int ||
        column is! int ||
        matchId is! String ||
        matchId.isEmpty ||
        turnNumber is! int ||
        message.expectedStateVersion == null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.malformedPayload,
        'A fire command requires a request ID, match, turn, version and cell.',
      );
      return;
    }
    if (message.roomId != null && message.roomId != room.roomId) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.stateVersionConflict,
        'That command belongs to another room.',
      );
      return;
    }
    final _FireRejection? rejection = await _fireAs(
      room,
      match,
      session.playerId!,
      row,
      column,
      matchId: matchId,
      turnNumber: turnNumber,
      expectedStateVersion: message.expectedStateVersion!,
      requestId: message.requestId,
    );
    if (rejection != null) {
      await _sendError(session, message, rejection.code, rejection.message);
    }
  }

  Future<_FireRejection?> _fireAs(
    HostRoomState room,
    HostMatchState match,
    String playerId,
    int row,
    int column, {
    required String matchId,
    required int turnNumber,
    required int expectedStateVersion,
    String? requestId,
  }) async {
    if (matchId != match.matchId ||
        turnNumber != match.turnNumber ||
        expectedStateVersion != room.stateVersion) {
      return const _FireRejection(
        ProtocolErrorCode.stateVersionConflict,
        'The match state changed. Request a fresh snapshot.',
      );
    }
    if (room.players[playerId]?.status != PlayerConnectionStatus.connected ||
        !match.isAlive(playerId) ||
        playerId != match.activePlayerId) {
      return const _FireRejection(
        ProtocolErrorCode.notYourTurn,
        'You cannot fire in this turn.',
      );
    }
    if (match.turnDeadline == null || !_now().isBefore(match.turnDeadline!)) {
      await _checkTurnDeadline();
      return const _FireRejection(
        ProtocolErrorCode.notYourTurn,
        'The turn deadline has expired.',
      );
    }
    if (row < 0 ||
        row >= room.config.rows ||
        column < 0 ||
        column >= room.config.columns) {
      return const _FireRejection(
        ProtocolErrorCode.invalidTargetCell,
        'That cell is outside the board.',
      );
    }
    // On the single shared map the shot needs no target: it is resolved
    // against every living opponent at the same cell.
    final List<String> targets = match.turnOrder
        .where((String id) => id != playerId && match.isAlive(id))
        .toList();
    if (targets.isEmpty) {
      return const _FireRejection(
        ProtocolErrorCode.targetNotAlive,
        'There is nobody left to shoot at.',
      );
    }
    final CellCoord cell = CellCoord(row, column);
    if (match.hasFiredAt(playerId, cell)) {
      return const _FireRejection(
        ProtocolErrorCode.cellAlreadyFiredAt,
        'You already fired at that cell.',
      );
    }

    final Map<String, ShotResult> results = <String, ShotResult>{};
    final List<String> eliminated = <String>[];
    int sunkShips = 0;
    bool hit = false;
    for (final String targetId in targets) {
      final PlayerBoard board = match.boards[targetId]!;
      final ShotResolution resolution = resolveShot(board, cell);
      results[targetId] = resolution.result;
      if (resolution.result != ShotResult.miss) hit = true;
      if (resolution.result == ShotResult.shipSunk) sunkShips++;
      match.attackHistory
              .putIfAbsent(
                playerId,
                () => <String, Map<CellCoord, ShotResult>>{},
              )
              .putIfAbsent(targetId, () => <CellCoord, ShotResult>{})[cell] =
          resolution.result;
      if (board.isEliminated && match.recordElimination(targetId)) {
        eliminated.add(targetId);
      }
    }
    match.recordVolley(playerId, hit: hit, shipsSunk: sunkShips);
    _completeTurn(room);

    await _sendShotFeedback(
      room,
      playerId,
      results,
      cell,
      requestId: requestId,
    );
    final String primaryTarget = _strongestTarget(results);
    await _broadcastPublicActivity(
      room,
      attackerPlayerId: playerId,
      involvedPlayerIds: results.keys.toSet(),
      targetPlayerId: primaryTarget,
      result: results[primaryTarget]!,
    );
    for (final String targetId in eliminated) {
      await _broadcastPlayerEliminated(room, targetId);
    }
    await _emitTurnResolution(room);
    return null;
  }

  Future<void> _finishMatch(HostRoomState room, String? winnerPlayerId) async {
    final MatchResult result = _buildResult(room, winnerPlayerId);

    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.finished,
          payload: result.toJson(),
        ),
      );
    }
    if (!_hostMatchResults.isClosed) _hostMatchResults.add(result);
    await _broadcastMatchSnapshot(room);
    await _broadcastRoomState(room);
    _emitHostSnapshot();
  }

  /// Builds the final ranking and statistics from Host-owned state.
  ///
  /// The ranking and every number come from the Host's own records, so all
  /// clients receive an identical result (PLAN.md §2.10).
  MatchResult _buildResult(HostRoomState room, String? winnerPlayerId) {
    final HostMatchState match = room.match!;
    final List<PlayerResultView> ranking =
        buildRanking(
          turnOrder: match.turnOrder,
          eliminationOrder: match.eliminationOrder,
          winnerPlayerId: winnerPlayerId,
        ).map((PlayerStanding standing) {
          final PlayerMatchStats stats =
              match.stats[standing.playerId] ?? PlayerMatchStats();
          return PlayerResultView(
            playerId: standing.playerId,
            displayName:
                room.players[standing.playerId]?.displayName ?? 'Player',
            rank: standing.rank,
            shots: stats.shots,
            hits: stats.hits,
            misses: stats.misses,
            shipsSunk: stats.shipsSunk,
            timeouts: match.timeouts[standing.playerId] ?? 0,
          );
        }).toList();

    return MatchResult(
      matchId: match.matchId,
      stateVersion: room.stateVersion,
      winnerPlayerId: winnerPlayerId,
      winnerDisplayName: winnerPlayerId == null
          ? null
          : room.players[winnerPlayerId]?.displayName,
      durationSeconds: match.finishedAt!.difference(match.startedAt).inSeconds,
      ranking: ranking,
      // The match is over, so every fleet may be reviewed. A fleet that is
      // still afloat never left the Host before this final broadcast.
      fleets: <FinalFleetView>[
        for (final PlayerResultView entry in ranking)
          if (match.boards[entry.playerId] case final PlayerBoard board)
            FinalFleetView(
              playerId: entry.playerId,
              ships: board.ships.values
                  .map(
                    (ShipState ship) => ShipView(
                      shipId: ship.shipId,
                      length: ship.length,
                      orientation: ship.placement.orientation,
                      row: ship.placement.row,
                      column: ship.placement.column,
                      hitCells: ship.hitCells.toList(),
                      sunk: ship.isSunk,
                    ),
                  )
                  .toList(),
              receivedShots: _shotsAgainst(room, entry.playerId),
            ),
      ],
    );
  }

  /// Tells the attacker the outcome of the volley and every target what it
  /// did to their fleet.
  ///
  /// One shot is resolved against every living opponent at once, so the
  /// attacker receives a single aggregate event whose target is the fleet
  /// that took the strongest result. Each target receives its own impact
  /// together with its own board.
  Future<void> _sendShotFeedback(
    HostRoomState room,
    String attackerPlayerId,
    Map<String, ShotResult> results,
    CellCoord cell, {
    String? requestId,
  }) async {
    if (results.isEmpty) return;

    final String primaryTarget = _strongestTarget(results);
    final ShotFeedback feedback = ShotFeedback(
      attackerPlayerId: attackerPlayerId,
      targetPlayerId: primaryTarget,
      row: cell.row,
      column: cell.column,
      result: results[primaryTarget]!,
    );

    if (room.hostPlayerId == attackerPlayerId && !_hostShotFeedbacks.isClosed) {
      _hostShotFeedbacks.add(feedback);
    }
    final ClientSession? attacker = registry.byPlayerId(attackerPlayerId);
    if (attacker != null) {
      await _transport?.send(
        attacker.connectionId,
        ProtocolMessage(
          messageType: HostEventType.shotResult,
          requestId: requestId,
          payload: feedback.toJson(),
        ),
      );
    }

    for (final MapEntry<String, ShotResult> entry in results.entries) {
      final ShotFeedback targetFeedback = ShotFeedback(
        attackerPlayerId: attackerPlayerId,
        targetPlayerId: entry.key,
        row: cell.row,
        column: cell.column,
        result: entry.value,
      );
      if (room.hostPlayerId == entry.key && !_hostShotFeedbacks.isClosed) {
        _hostShotFeedbacks.add(targetFeedback);
      }
      final ClientSession? target = registry.byPlayerId(entry.key);
      if (target != null) {
        await _transport?.send(
          target.connectionId,
          ProtocolMessage(
            messageType: HostEventType.shotResult,
            payload: <String, dynamic>{
              ...targetFeedback.toJson(),
              'ownBoard': _ownBoardView(room, entry.key)?.toJson(),
            },
          ),
        );
      }
    }
  }

  /// The target that took the strongest result of a volley.
  String _strongestTarget(Map<String, ShotResult> results) {
    String strongest = results.keys.first;
    for (final MapEntry<String, ShotResult> entry in results.entries) {
      if (shotResultStrength(entry.value) >
          shotResultStrength(results[strongest]!)) {
        strongest = entry.key;
      }
    }
    return strongest;
  }

  /// Tells the players who were not part of a volley that a shot happened.
  ///
  /// The event carries no coordinates: the exact fleets stay hidden, and the
  /// shared map already shows the marks to everybody (PLAN.md §2.2). A shot
  /// is resolved against every living opponent, so every participant is
  /// excluded and only an eliminated spectator — or a player who already
  /// left the match — receives the feed event.
  Future<void> _broadcastPublicActivity(
    HostRoomState room, {
    required String attackerPlayerId,
    required Set<String> involvedPlayerIds,
    required String targetPlayerId,
    required ShotResult result,
  }) async {
    final PublicActivity activity = PublicActivity(
      attackerPlayerId: attackerPlayerId,
      targetPlayerId: targetPlayerId,
      result: result,
    );
    if (!involvedPlayerIds.contains(room.hostPlayerId) &&
        room.hostPlayerId != attackerPlayerId &&
        !_hostPublicActivities.isClosed) {
      _hostPublicActivities.add(activity);
    }
    for (final ClientSession client in registry.admittedSessions.toList()) {
      final String? playerId = client.playerId;
      if (playerId == attackerPlayerId ||
          involvedPlayerIds.contains(playerId)) {
        continue;
      }
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.publicActivity,
          payload: activity.toJson(),
        ),
      );
    }
  }

  /// Announces that a player lost their whole fleet.
  Future<void> _broadcastPlayerEliminated(
    HostRoomState room,
    String playerId,
  ) async {
    final HostPlayer? player = room.players[playerId];
    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.playerEliminated,
          payload: <String, dynamic>{
            'playerId': playerId,
            'displayName': player?.displayName,
          },
        ),
      );
    }
  }

  /// Announces whose turn it is.
  Future<void> _broadcastTurnStarted(HostRoomState room) async {
    final HostMatchState match = room.match!;
    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.turnStarted,
          payload: <String, dynamic>{
            'activePlayerId': match.activePlayerId,
            'turnNumber': match.turnNumber,
            'remainingSeconds': turnRemainingSeconds,
          },
        ),
      );
    }
  }

  /// Sends every client its own view of the match.
  Future<void> _broadcastMatchSnapshot(HostRoomState room) async {
    for (final ClientSession client in registry.admittedSessions.toList()) {
      final String? playerId = client.playerId;
      if (playerId == null) continue;
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.stateSnapshot,
          payload: <String, dynamic>{
            'snapshot': _matchSnapshot(room, playerId).toJson(),
          },
        ),
      );
    }
    _emitHostMatchSnapshot(room);
  }

  /// Builds the match state one recipient may see.
  MatchSnapshot _matchSnapshot(HostRoomState room, String viewerPlayerId) {
    final HostMatchState match = room.match!;
    return MatchSnapshot(
      matchId: match.matchId,
      stateVersion: room.stateVersion,
      turnNumber: match.turnNumber,
      activePlayerId: match.activePlayerId,
      turnRemainingSeconds: turnRemainingSeconds,
      players: match.turnOrder
          .map((String playerId) => room.players[playerId]!)
          .map(
            (HostPlayer player) => MatchPlayerView(
              playerId: player.playerId,
              displayName: player.displayName,
              alive: match.isAlive(player.playerId),
              timeouts: match.timeouts[player.playerId] ?? 0,
              shipsRemaining: _shipsAfloat(match, player.playerId),
            ),
          )
          .toList(),
      ownBoard: _ownBoardView(room, viewerPlayerId),
      mapShots: _mapShots(room),
      sunkShips: _sunkShips(match),
      winnerPlayerId: room.status == RoomStatus.finished
          ? match.winnerPlayerId
          : null,
    );
  }

  /// The ships of every fleet that are already sunk.
  ///
  /// A sunk ship is public: every one of its cells was hit, and every hit is
  /// already a mark on the shared map, so its outline tells the room nothing
  /// it did not already know. The fleets that are still afloat stay with the
  /// Host and their owner (GAME_RULES.md §2).
  List<SunkShipView> _sunkShips(HostMatchState match) {
    final List<SunkShipView> sunk = <SunkShipView>[];
    for (final String playerId in match.turnOrder) {
      final PlayerBoard? board = match.boards[playerId];
      if (board == null) continue;
      for (final ShipState ship in board.ships.values) {
        if (!ship.isSunk) continue;
        sunk.add(
          SunkShipView(
            ownerPlayerId: playerId,
            shipId: ship.shipId,
            length: ship.length,
            orientation: ship.placement.orientation,
            row: ship.placement.row,
            column: ship.placement.column,
          ),
        );
      }
    }
    return sunk;
  }

  /// The number of ships of a player that are still afloat.
  ///
  /// Aggregate status only: it is public because the public activity events
  /// already announce every sunk ship (PLAN.md §6.6).
  int _shipsAfloat(HostMatchState match, String playerId) {
    final PlayerBoard? board = match.boards[playerId];
    if (board == null) return 0;
    return board.ships.length - board.sunkCount;
  }

  /// The own board of a player, with the impacts it received.
  OwnBoardView? _ownBoardView(HostRoomState room, String playerId) {
    final PlayerBoard? board = room.match?.boards[playerId];
    if (board == null) return null;
    return OwnBoardView(
      ships: board.ships.values
          .map(
            (ShipState ship) => ShipView(
              shipId: ship.shipId,
              length: ship.length,
              orientation: ship.placement.orientation,
              row: ship.placement.row,
              column: ship.placement.column,
              hitCells: ship.hitCells.toList(),
              sunk: ship.isSunk,
            ),
          )
          .toList(),
      shotsReceived: board.shotsReceived.toList(),
      receivedShots: _shotsAgainst(room, playerId),
    );
  }

  /// Every shot on the single shared battle map.
  ///
  /// A volley leaves one shot mark per shooter and cell, carrying the
  /// strongest result it had on any fleet. The marks are public: the shared
  /// map is what the whole room looks at (GAME_RULES.md §2).
  List<ShotView> _mapShots(HostRoomState room) {
    final Map<String, Map<String, Map<CellCoord, ShotResult>>>? history =
        room.match?.attackHistory;
    if (history == null) return const <ShotView>[];
    final Map<String, ShotView> merged = <String, ShotView>{};
    for (final MapEntry<String, Map<String, Map<CellCoord, ShotResult>>>
        attacker
        in history.entries) {
      for (final Map<CellCoord, ShotResult> shots in attacker.value.values) {
        for (final MapEntry<CellCoord, ShotResult> shot in shots.entries) {
          final String key =
              '${attacker.key}:${shot.key.row}:${shot.key.column}';
          final ShotView? previous = merged[key];
          merged[key] = ShotView(
            row: shot.key.row,
            column: shot.key.column,
            result: previous == null
                ? shot.value
                : strongerShotResult(previous.result, shot.value),
            attackerPlayerId: attacker.key,
          );
        }
      }
    }
    final List<ShotView> marks = merged.values.toList()
      ..sort((ShotView a, ShotView b) {
        final int byRow = a.row.compareTo(b.row);
        if (byRow != 0) return byRow;
        final int byColumn = a.column.compareTo(b.column);
        if (byColumn != 0) return byColumn;
        return a.attackerPlayerId.compareTo(b.attackerPlayerId);
      });
    return marks;
  }

  /// The shots that were fired at the target, by every player.
  ///
  /// The shared battle map shows the fire of everyone at once, so every shot
  /// carries the player who fired it. The ships of the target stay hidden:
  /// only the marks of the shots are shared (PLAN.md §2.2).
  List<ShotView> _shotsAgainst(HostRoomState room, String targetPlayerId) {
    final Map<String, Map<String, Map<CellCoord, ShotResult>>> history =
        room.match?.attackHistory ??
        const <String, Map<String, Map<CellCoord, ShotResult>>>{};
    final List<ShotView> shots = <ShotView>[];
    for (final MapEntry<String, Map<String, Map<CellCoord, ShotResult>>> entry
        in history.entries) {
      final Map<CellCoord, ShotResult>? cells = entry.value[targetPlayerId];
      if (cells == null) continue;
      for (final MapEntry<CellCoord, ShotResult> cell in cells.entries) {
        shots.add(
          ShotView(
            row: cell.key.row,
            column: cell.key.column,
            result: cell.value,
            attackerPlayerId: entry.key,
          ),
        );
      }
    }
    return shots;
  }

  void _emitHostTurnCountdown(int remainingSeconds) {
    if (_hostTurnCountdowns.isClosed) return;
    _hostTurnCountdowns.add(remainingSeconds);
  }

  void _emitHostMatchSnapshot(HostRoomState room) {
    if (_hostMatchSnapshots.isClosed) return;
    _hostMatchSnapshots.add(_matchSnapshot(room, room.hostPlayerId));
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
    if (room == null) return;
    if (!_isLiveMember(room, session) ||
        (message.playerId != null && message.playerId != session.playerId)) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.notRoomMember,
        'This connection is not an authenticated room member.',
      );
      return;
    }
    await _transport?.send(
      session.connectionId,
      ProtocolMessage(
        messageType: HostEventType.roomState,
        requestId: message.requestId,
        payload: <String, dynamic>{
          'snapshot': projections.buildFor(room, session.playerId).toJson(),
        },
      ),
    );
    if (room.match != null) {
      await _transport?.send(
        session.connectionId,
        ProtocolMessage(
          messageType: HostEventType.stateSnapshot,
          requestId: message.requestId,
          payload: <String, dynamic>{
            'snapshot': _matchSnapshot(room, session.playerId!).toJson(),
          },
        ),
      );
    }
  }

  // ----------------------------------------------------------- resume

  /// Reclaims a temporarily disconnected seat with a resume token.
  ///
  /// The Host validates the token, the grace period and the room phase before
  /// binding the new connection to the old player ID (PLAN.md §2.8). No Host
  /// migration or election is ever performed (PLAN.md §2.9).
  Future<void> _handleResume(
    ClientSession session,
    ProtocolMessage message,
  ) async {
    final HostRoomState? room = _state;
    if (room == null || room.status == RoomStatus.closed) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.roomNotFound,
        'This room is no longer active.',
      );
      return;
    }

    final String token = (message.payload['resumeToken'] as String? ?? '')
        .trim();
    if (token.isEmpty) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.sessionExpired,
        'The resume token is missing or invalid.',
      );
      return;
    }

    HostPlayer? player;
    for (final HostPlayer candidate in room.players.values) {
      if (candidate.resumeTokenHash != null &&
          candidate.resumeTokenHash == _hash(token)) {
        player = candidate;
        break;
      }
    }
    if (player == null) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.sessionExpired,
        'The resume token is no longer valid.',
      );
      return;
    }

    final String? claimedPlayerId = message.payload['playerId'] as String?;
    if (claimedPlayerId != null && claimedPlayerId != player.playerId) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.sessionExpired,
        'The resume token does not match this player.',
      );
      return;
    }

    if (player.isHost) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.sessionExpired,
        'The host cannot be resumed.',
      );
      return;
    }

    final ClientSession? existing = registry.byPlayerId(player.playerId);
    if (existing != null && !identical(existing, session) && !existing.closed) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.deviceAlreadyConnected,
        'This seat is already connected.',
      );
      return;
    }

    if (player.status != PlayerConnectionStatus.disconnected) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.sessionExpired,
        'This seat is not awaiting reconnection.',
      );
      return;
    }

    final DateTime now = _now();
    if (player.disconnectDeadline != null &&
        now.isAfter(player.disconnectDeadline!)) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.sessionExpired,
        'The reconnection grace period has expired.',
      );
      return;
    }

    // Bind the new connection to the existing player identity.
    player.status = PlayerConnectionStatus.connected;
    player.disconnectedAt = null;
    player.disconnectDeadline = null;
    player.lastHeartbeatAt = now;

    session.playerId = player.playerId;
    session.deviceId = player.deviceId;
    session.lastHeartbeatAt = now;
    registry.add(session);

    // Rotate the resume token so a captured token cannot be reused.
    final String newToken = SecureRandom.token();
    player.resumeTokenHash = _hash(newToken);

    room.stateVersion++;

    final HostMatchState? match = room.match;
    if (match != null &&
        room.status == RoomStatus.active &&
        match.activePlayerId == player.playerId) {
      match.turnDeadline = now.add(
        Duration(seconds: room.config.turnDurationSeconds),
      );
    }

    await _transport?.send(
      session.connectionId,
      ProtocolMessage(
        messageType: HostEventType.joined,
        requestId: message.requestId,
        payload: <String, dynamic>{
          'playerId': player.playerId,
          'roomId': room.roomId,
          'resumeToken': newToken,
          'snapshot': projections.buildFor(room, player.playerId).toJson(),
        },
      ),
    );

    if (room.status == RoomStatus.placement) {
      await _sendPlacementState(room, player.playerId);
    }
    await _broadcastReadiness(room);

    if (match != null) {
      await _transport?.send(
        session.connectionId,
        ProtocolMessage(
          messageType: HostEventType.stateSnapshot,
          payload: <String, dynamic>{
            'snapshot': _matchSnapshot(room, player.playerId).toJson(),
          },
        ),
      );
    }

    await _broadcastRoomState(room);
    await _broadcastPlayerReconnected(room, player.playerId);
    _emitHostSnapshot();
  }

  // -------------------------------------------------------------- helpers

  /// Marks a member as disconnected when their socket drops.
  ///
  /// The seat is kept for [AppConfig.nonHostGracePeriodSeconds] seconds so
  /// the member can reclaim it with their resume token (PLAN.md §2.8). The
  /// Host never elects a replacement or migrates authority (PLAN.md §2.9).
  Future<void> handleConnectionLost(ClientSession session) async {
    final HostRoomState? room = _state;
    final String? playerId = session.playerId;
    if (room == null || playerId == null) return;

    final HostPlayer? player = room.players[playerId];
    if (player == null) return;
    if (player.status != PlayerConnectionStatus.connected) return;
    session.closed = true;
    if (player.isHost) {
      // The Host never reconnects or migrates: a Host loss is terminal for
      // the room. The socket drop is surfaced to clients through the missing
      // heartbeat (PLAN.md §2.9, §9.5).
      return;
    }

    final DateTime now = _now();
    player.status = PlayerConnectionStatus.disconnected;
    player.disconnectedAt = now;
    player.disconnectDeadline = now.add(
      const Duration(seconds: AppConfig.nonHostGracePeriodSeconds),
    );
    room.stateVersion++;

    final HostMatchState? match = room.match;
    if (match != null &&
        room.status == RoomStatus.active &&
        match.activePlayerId == playerId) {
      // Pause the turn timer for at most the grace period. The deadline can
      // never outlive the reconnect grace period (PLAN.md §2.8).
      match.turnDeadline = player.disconnectDeadline;
    }

    _emitHostSnapshot();
    await _broadcastPlayerDisconnected(room, playerId);
    await _broadcastRoomState(room);
    await _checkPreparationCancellation(room);
  }

  /// Tells every client that a member lost their connection.
  Future<void> _broadcastPlayerDisconnected(
    HostRoomState room,
    String playerId,
  ) async {
    final HostPlayer? player = room.players[playerId];
    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.playerDisconnected,
          payload: <String, dynamic>{
            'playerId': playerId,
            'displayName': player?.displayName,
            'status': PlayerConnectionStatus.disconnected.wire,
            'stateVersion': room.stateVersion,
          },
        ),
      );
    }
  }

  /// Tells every client that a member reclaimed their seat.
  Future<void> _broadcastPlayerReconnected(
    HostRoomState room,
    String playerId,
  ) async {
    final HostPlayer? player = room.players[playerId];
    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.playerReconnected,
          payload: <String, dynamic>{
            'playerId': playerId,
            'displayName': player?.displayName,
            'status': PlayerConnectionStatus.connected.wire,
            'stateVersion': room.stateVersion,
          },
        ),
      );
    }
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

  void _emitHostPlacementState(HostRoomState room) {
    if (_hostPlacementStates.isClosed) return;
    _hostPlacementStates.add(_placementState(room, room.hostPlayerId));
  }

  void _emitHostReadinessState(HostRoomState room) {
    if (_hostReadinessStates.isClosed) return;
    _hostReadinessStates.add(_readinessState(room));
  }

  void _emitHostCountdown(int remainingSeconds) {
    if (_hostCountdowns.isClosed) return;
    _hostCountdowns.add(remainingSeconds);
  }

  void _emitHostMatchStart(MatchStartState state) {
    if (_hostMatchStarts.isClosed) return;
    _hostMatchStarts.add(state);
  }

  void _emitHostNotice(String notice) {
    if (_hostNotices.isClosed) return;
    _hostNotices.add(notice);
  }

  // ------------------------------------------------------- preparation

  /// Starts the preparation phase as the Host device.
  ///
  /// Returns the validation problems, or an empty list on success.
  Future<List<String>> hostStartPlacement() => _serialize(_hostStartPlacement);

  Future<List<String>> _hostStartPlacement() async {
    final HostRoomState? room = _state;
    if (room == null) return const <String>[];
    if (room.status != RoomStatus.lobby) {
      return <String>['The preparation has already started.'];
    }

    final List<String> problems = _preparationProblems(room);
    if (problems.isNotEmpty) return problems;

    await _startPreparation(room);
    return const <String>[];
  }

  Future<void> _handleStartPlacement(
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
        'Only the host can start the preparation.',
      );
      return;
    }
    if (room.status != RoomStatus.lobby) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.roomAlreadyStarted,
        'The preparation has already started.',
      );
      return;
    }

    final List<String> problems = _preparationProblems(room);
    if (problems.isNotEmpty) {
      await _sendError(
        session,
        message,
        ProtocolErrorCode.notEnoughPlayers,
        problems.join(' '),
      );
      return;
    }

    await _startPreparation(room);
  }

  /// The reasons the preparation cannot start yet.
  List<String> _preparationProblems(HostRoomState room) {
    final List<String> problems = <String>[];
    final int connected = _eligiblePlayers(room).length;
    if (connected < RoomConfig.minimumPlayers) {
      problems.add(
        'At least ${RoomConfig.minimumPlayers} connected players are needed '
        'to start the preparation.',
      );
    }
    problems.addAll(room.config.validate());
    return problems;
  }

  /// Moves the room into the preparation phase and starts the deadline.
  Future<void> _startPreparation(HostRoomState room) async {
    room.status = RoomStatus.placement;
    room.placementDeadline = _now().add(
      Duration(seconds: room.config.placementDurationSeconds),
    );
    room.stateVersion++;

    _startPhaseTimer();

    await _broadcastRoomState(room);
    await _broadcastPlacementStarted(room);
    _emitHostCountdown(room.config.placementDurationSeconds);
    _emitHostSnapshot();
    // A computer opponent has nobody to place its ships for it, so the Host
    // places them and confirms them right away
    // (GAME_RULES.md §5 "Auto Place").
    await _placeBotFleets(room);
    if (_everyoneReady(room)) await _startMatch(room);
  }

  /// Places and confirms the fleet of every computer opponent.
  Future<void> _placeBotFleets(HostRoomState room) async {
    for (final HostPlayer player in _eligiblePlayers(room)) {
      if (!player.isBot) continue;
      final HostPlayerPlacement placement = placementFor(player.playerId);
      if (placement.ready && _hasLegalFleet(room, player.playerId)) continue;

      final List<ShipPlacement> ships = autoPlaceFleet(
        board: _board(room),
        profile: _profile(room),
        random: Random(),
      );
      placement.ships
        ..clear()
        ..addEntries(
          ships.map(
            (ShipPlacement ship) =>
                MapEntry<String, ShipPlacement>(ship.shipId, ship),
          ),
        );
      placement.ready = true;
    }
    await _broadcastReadiness(room);
  }

  /// The Host-owned deadline check.
  ///
  /// The Host calls this on its own timer and again after the app resumes,
  /// so a preparation that ran out while the app was suspended still ends at
  /// the right moment (PLAN.md §9.4).
  Future<void> checkPreparationDeadline() =>
      _serialize(_checkPreparationDeadline);

  Future<void> _checkPreparationDeadline() async {
    final HostRoomState? room = _state;
    if (room == null || room.status != RoomStatus.placement) return;
    final int? remaining = placementRemainingSeconds;
    if (remaining == null) return;

    _emitHostCountdown(remaining);
    if (remaining > 0) return;

    await _completePreparation(room);
  }

  /// Ends the preparation: the Host completes the fleets that are missing and
  /// starts the match (PLAN.md §2.5).
  Future<void> _completePreparation(HostRoomState room) async {
    _stopPlacementTimer();
    room.stateVersion++;

    for (final HostPlayer player in _eligiblePlayers(room)) {
      final HostPlayerPlacement placement = placementFor(player.playerId);
      if (placement.ready && _hasLegalFleet(room, player.playerId)) continue;

      final List<ShipPlacement> ships = autoPlaceFleet(
        board: _board(room),
        profile: _profile(room),
        random: Random(),
      );
      final PlacementError? error = validateFleetLayout(
        board: _board(room),
        profile: _profile(room),
        ships: ships,
      );
      if (error != null) {
        await _cancelPreparation(
          room,
          'The automatic fleet could not be placed. The preparation was '
          'cancelled.',
        );
        return;
      }

      placement.ships
        ..clear()
        ..addEntries(
          ships.map(
            (ShipPlacement ship) =>
                MapEntry<String, ShipPlacement>(ship.shipId, ship),
          ),
        );
      placement.ready = true;
      await _sendPlacementState(room, player.playerId);
    }

    await _broadcastReadiness(room);
    await _startMatch(room);
  }

  /// Starts the match with a randomized turn order (PLAN.md §2.6).
  Future<void> _startMatch(HostRoomState room) async {
    if (room.status != RoomStatus.placement || room.match != null) return;
    final List<HostPlayer> players = _eligiblePlayers(room);
    if (players.length < RoomConfig.minimumPlayers) {
      await _cancelPreparation(
        room,
        'Not enough players are left to start the match.',
      );
      return;
    }

    if (!_everyoneReady(room)) return;

    final List<HostPlayer> order = List<HostPlayer>.from(players)
      ..shuffle(Random());
    final String matchId = SecureRandom.uuidV4();

    final Map<String, PlayerBoard> boards = <String, PlayerBoard>{};
    for (final HostPlayer player in order) {
      boards[player.playerId] = PlayerBoard(
        playerId: player.playerId,
        ships: placementFor(player.playerId).ships.values.toList(),
      );
    }

    room.match = HostMatchState(
      matchId: matchId,
      turnOrder: order.map((HostPlayer player) => player.playerId).toList(),
      activePlayerId: order.first.playerId,
      startedAt: _now(),
      boards: boards,
    );
    room.match!.turnDeadline = _now().add(
      Duration(seconds: room.config.turnDurationSeconds),
    );
    room.status = RoomStatus.active;
    room.placementDeadline = null;
    room.stateVersion++;
    _startPhaseTimer();

    final MatchStartState state = MatchStartState(
      matchId: matchId,
      turnOrder: order
          .map(
            (HostPlayer player) => TurnOrderEntry(
              playerId: player.playerId,
              displayName: player.displayName,
            ),
          )
          .toList(),
      activePlayerId: order.first.playerId,
      boardRows: room.config.rows,
      boardColumns: room.config.columns,
      fleetPreset: room.config.fleetPreset,
      stateVersion: room.stateVersion,
    );

    await _broadcastRoomState(room);
    await _broadcastMatchStarted(state);
    _emitHostMatchStart(state);
    await _broadcastMatchSnapshot(room);
    _emitHostSnapshot();
    _scheduleBotTurn(room);
  }

  /// Cancels the preparation and returns the room to the lobby.
  Future<void> _cancelPreparation(HostRoomState room, String reason) async {
    _stopPlacementTimer();
    room.status = RoomStatus.lobby;
    room.placementDeadline = null;
    room.stateVersion++;

    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.placementCancelled,
          payload: <String, dynamic>{
            'reason': reason,
            'stateVersion': room.stateVersion,
          },
        ),
      );
    }
    await _broadcastRoomState(room);
    _emitHostNotice(reason);
    _emitHostSnapshot();
  }

  /// Cancels the preparation when too few players are left.
  Future<void> _checkPreparationCancellation(HostRoomState room) async {
    if (room.status != RoomStatus.placement) return;
    final int connected = _eligiblePlayers(room).length;
    if (connected < RoomConfig.minimumPlayers) {
      await _cancelPreparation(
        room,
        'Not enough players are left to start the match.',
      );
    }
  }

  /// Runs the deadline of the current phase.
  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      unawaited(_tickPhase());
    });
  }

  void _stopPlacementTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
  }

  /// Checks the deadline of the phase the room is in.
  Future<void> _tickPhase() async {
    final HostRoomState? room = _state;
    if (room == null) return;
    if (room.status == RoomStatus.placement) {
      await checkPreparationDeadline();
    } else if (room.status == RoomStatus.active) {
      await checkTurnDeadline();
    }
  }

  /// Tells every client that the preparation started.
  Future<void> _broadcastPlacementStarted(HostRoomState room) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'remainingSeconds': placementRemainingSeconds,
      'durationSeconds': room.config.placementDurationSeconds,
      'fleetPreset': room.config.fleetPreset.wire,
      'boardRows': room.config.rows,
      'boardColumns': room.config.columns,
      'stateVersion': room.stateVersion,
    };

    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.placementStarted,
          payload: payload,
        ),
      );
    }
  }

  /// Tells every client that the match started.
  Future<void> _broadcastMatchStarted(MatchStartState state) async {
    for (final ClientSession client in registry.admittedSessions.toList()) {
      await _transport?.send(
        client.connectionId,
        ProtocolMessage(
          messageType: HostEventType.started,
          payload: state.toJson(),
        ),
      );
    }
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
  Future<void> dispose() => _serialize(_dispose);

  Future<void> _dispose() async {
    _stopPlacementTimer();
    _stopBotTimer();
    await _hostSnapshots.close();
    await _hostPlacementStates.close();
    await _hostReadinessStates.close();
    await _hostCountdowns.close();
    await _hostMatchStarts.close();
    await _hostTurnCountdowns.close();
    await _hostMatchSnapshots.close();
    await _hostMatchResults.close();
    await _hostShotFeedbacks.close();
    await _hostPublicActivities.close();
    await _hostNotices.close();
    registry.clear();
    _state = null;
  }
}
