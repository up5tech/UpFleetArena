import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/screen_awake_service.dart';
import '../../../game_engine/bot/bot_brain.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../host_runtime/host_room_service.dart';
import '../../../host_runtime/room_coordinator.dart';
import '../../../shared/models/match_models.dart';
import '../../../shared/models/placement_models.dart';
import '../../../shared/models/room_models.dart';
import '../../../shared/protocol/protocol_constants.dart';
import '../../lan_networking/domain/lan_discovery.dart';
import '../../lan_networking/domain/lan_networking_providers.dart';
import '../../profile/domain/profile.dart';
import '../data/room_client_session.dart';

/// The role this device plays in the current room.
enum RoomRole {
  /// Not in a room.
  none,

  /// This device created the room and runs the authority.
  host,

  /// This device joined someone else's room.
  client,
}

/// Progress of the current room operation.
enum RoomSessionStatus {
  /// Nothing is running.
  idle,

  /// The room is being created or joined.
  working,

  /// The device is a member of the room.
  inRoom,

  /// The room ended.
  closed,

  /// The operation failed.
  failed,
}

/// Immutable view of the current room session.
@immutable
class RoomSessionState {
  const RoomSessionState({
    this.role = RoomRole.none,
    this.status = RoomSessionStatus.idle,
    this.snapshot,
    this.inviteCode,
    this.roomId,
    this.playerId,
    this.errorCode,
    this.errorMessage,
    this.hostPort,
    this.hostAddresses = const <String>[],
    this.placement,
    this.readiness,
    this.placementError,
    this.countdown,
    this.match,
    this.notice,
    this.matchSnapshot,
    this.lastShot,
    this.turnCountdown,
    this.firePending = false,
    this.combatError,
    this.lastActivity,
    this.matchResult,
    this.activityFeed = const <PublicActivity>[],
    this.practiceMode = false,
  });

  /// Whether this device hosts, joined, or is outside a room.
  final RoomRole role;

  /// Progress of the current operation.
  final RoomSessionStatus status;

  /// The latest room state.
  final RoomSnapshot? snapshot;

  /// The invitation code, for the Host.
  final String? inviteCode;

  /// The room identifier.
  final String? roomId;

  /// The player ID assigned by the Host.
  final String? playerId;

  /// Stable error code of the last failure.
  final String? errorCode;

  /// User-safe explanation of the last failure.
  final String? errorMessage;

  /// The port the Host listens on.
  final int? hostPort;

  /// The Host's local IPv4 addresses, shown for the manual fallback.
  final List<String> hostAddresses;

  /// The exact fleet layout of this device, confirmed by the Host.
  final PlacementState? placement;

  /// The readiness of every member.
  final ReadinessState? readiness;

  /// The last rejection of a placement command.
  ///
  /// A rejected placement never ends the room: it only tells the player that
  /// the layout was not accepted.
  final String? placementError;

  /// The preparation countdown, as the Host last reported it.
  final Countdown? countdown;

  /// The match that started, once the preparation ended.
  final MatchStartState? match;

  /// A message the Host sent to this player.
  final String? notice;

  /// The permission-filtered state of the running match.
  final MatchSnapshot? matchSnapshot;

  /// The result of the last shot this player was involved in.
  final ShotFeedback? lastShot;

  /// The countdown of the current turn.
  final Countdown? turnCountdown;
  final bool firePending;
  final String? combatError;
  final PublicActivity? lastActivity;

  /// The final result, once the Host ended the match.
  final MatchResult? matchResult;

  /// The most recent public shots, oldest first.
  ///
  /// They carry no coordinate, so a spectator may read them (PLAN.md §5.2).
  final List<PublicActivity> activityFeed;

  /// Whether this room is a solo match against a computer opponent.
  ///
  /// A practice room lives on this device only: it has no TCP listener, no
  /// advertisement and no invitation code.
  final bool practiceMode;

  /// Whether this device hosts the room.
  bool get isHost => role == RoomRole.host;

  /// Whether this player lost their fleet and may only watch the match.
  bool get isSpectating {
    final MatchSnapshot? match = matchSnapshot;
    final String? viewer = playerId;
    if (match == null || viewer == null) return false;
    return match.playerById(viewer)?.alive == false;
  }

  /// Whether the device is a member of a room.
  bool get isInRoom => status == RoomSessionStatus.inRoom;

  /// Whether this device confirmed a complete fleet.
  bool get isPlacementReady => placement?.ready ?? false;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields use a sentinel so an explicit `null` clears the value
  /// instead of keeping the previous one.
  RoomSessionState copyWith({
    RoomRole? role,
    RoomSessionStatus? status,
    Object? snapshot = _unset,
    Object? inviteCode = _unset,
    Object? roomId = _unset,
    Object? playerId = _unset,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
    Object? hostPort = _unset,
    List<String>? hostAddresses,
    Object? placement = _unset,
    Object? readiness = _unset,
    Object? placementError = _unset,
    Object? countdown = _unset,
    Object? match = _unset,
    Object? notice = _unset,
    Object? matchSnapshot = _unset,
    Object? lastShot = _unset,
    Object? turnCountdown = _unset,
    bool? firePending,
    Object? combatError = _unset,
    Object? lastActivity = _unset,
    Object? matchResult = _unset,
    List<PublicActivity>? activityFeed,
    bool? practiceMode,
  }) => RoomSessionState(
    role: role ?? this.role,
    status: status ?? this.status,
    snapshot: identical(snapshot, _unset)
        ? this.snapshot
        : snapshot as RoomSnapshot?,
    inviteCode: identical(inviteCode, _unset)
        ? this.inviteCode
        : inviteCode as String?,
    roomId: identical(roomId, _unset) ? this.roomId : roomId as String?,
    playerId: identical(playerId, _unset) ? this.playerId : playerId as String?,
    errorCode: identical(errorCode, _unset)
        ? this.errorCode
        : errorCode as String?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    hostPort: identical(hostPort, _unset) ? this.hostPort : hostPort as int?,
    hostAddresses: hostAddresses ?? this.hostAddresses,
    placement: identical(placement, _unset)
        ? this.placement
        : placement as PlacementState?,
    readiness: identical(readiness, _unset)
        ? this.readiness
        : readiness as ReadinessState?,
    placementError: identical(placementError, _unset)
        ? this.placementError
        : placementError as String?,
    countdown: identical(countdown, _unset)
        ? this.countdown
        : countdown as Countdown?,
    match: identical(match, _unset) ? this.match : match as MatchStartState?,
    notice: identical(notice, _unset) ? this.notice : notice as String?,
    matchSnapshot: identical(matchSnapshot, _unset)
        ? this.matchSnapshot
        : matchSnapshot as MatchSnapshot?,
    lastShot: identical(lastShot, _unset)
        ? this.lastShot
        : lastShot as ShotFeedback?,
    turnCountdown: identical(turnCountdown, _unset)
        ? this.turnCountdown
        : turnCountdown as Countdown?,
    firePending: firePending ?? this.firePending,
    combatError: identical(combatError, _unset)
        ? this.combatError
        : combatError as String?,
    lastActivity: identical(lastActivity, _unset)
        ? this.lastActivity
        : lastActivity as PublicActivity?,
    matchResult: identical(matchResult, _unset)
        ? this.matchResult
        : matchResult as MatchResult?,
    activityFeed: activityFeed ?? this.activityFeed,
    practiceMode: practiceMode ?? this.practiceMode,
  );

  static const Object _unset = Object();
}

/// Drives the room lifecycle on this device.
///
/// The same controller covers both roles: as the Host it owns the
/// [HostRoomService], as a client it owns a [RoomClientSession].
class RoomSessionController extends Notifier<RoomSessionState> {
  HostRoomService? _hostService;
  RoomCoordinator? _practiceCoordinator;
  ScreenAwakeService? _screenAwake;
  RoomClientSession? _clientSession;
  StreamSubscription<RoomSnapshot>? _hostSubscription;
  StreamSubscription<RoomSnapshot>? _clientSubscription;
  StreamSubscription<RoomClientEvent>? _eventSubscription;
  StreamSubscription<PlacementState>? _hostPlacementSubscription;
  StreamSubscription<ReadinessState>? _hostReadinessSubscription;
  StreamSubscription<PlacementState>? _clientPlacementSubscription;
  StreamSubscription<ReadinessState>? _clientReadinessSubscription;
  StreamSubscription<int>? _hostCountdownSubscription;
  StreamSubscription<int>? _clientCountdownSubscription;
  StreamSubscription<MatchStartState>? _hostMatchSubscription;
  StreamSubscription<MatchStartState>? _clientMatchSubscription;
  StreamSubscription<String>? _hostNoticeSubscription;
  StreamSubscription<String>? _clientNoticeSubscription;
  StreamSubscription<MatchSnapshot>? _hostMatchSnapshotSubscription;
  StreamSubscription<MatchSnapshot>? _clientMatchSnapshotSubscription;
  StreamSubscription<MatchResult>? _hostMatchResultSubscription;
  StreamSubscription<MatchResult>? _clientMatchResultSubscription;
  StreamSubscription<ShotFeedback>? _hostShotSubscription;
  StreamSubscription<ShotFeedback>? _clientShotSubscription;
  StreamSubscription<int>? _hostTurnCountdownSubscription;
  StreamSubscription<int>? _clientTurnCountdownSubscription;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<PublicActivity>? _hostActivitySubscription;
  StreamSubscription<PublicActivity>? _clientActivitySubscription;
  (String, int)? _submittedTurn;

  // Reconnect state is kept in the underlying RoomClientSession; the
  // controller only surfaces the connection-lost event (PLAN.md §2.8).

  @override
  RoomSessionState build() {
    ref.onDispose(_dispose);
    // A Host that was suspended may have missed its deadline. The Host
    // applies the transition as soon as it comes back (PLAN.md §9.4).
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(_applyDeadlineOnResume()),
    );
    return const RoomSessionState();
  }

  Future<void> _applyDeadlineOnResume() async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator == null) return;
    await coordinator.checkPreparationDeadline();
    await coordinator.checkTurnDeadline();
  }

  /// The authority that runs the room on this device.
  ///
  /// A hosted room is served by [HostRoomService] over TCP; a practice room
  /// runs the very same [RoomCoordinator] in-process without any transport.
  RoomCoordinator? get _coordinator =>
      _hostService?.coordinator ?? _practiceCoordinator;

  // ----------------------------------------------------------------- host

  /// Creates a room on this device and starts advertising it.
  Future<void> createRoom({
    required Profile profile,
    RoomConfig? config,
    String Function(BotDifficulty difficulty)? botNameBuilder,
  }) async {
    await _teardown();

    state = const RoomSessionState().copyWith(
      role: RoomRole.host,
      status: RoomSessionStatus.working,
      errorCode: null,
      errorMessage: null,
    );

    final RoomConfig effectiveConfig = config ?? RoomConfig.defaults;
    final List<String> problems = effectiveConfig.validate();
    if (problems.isNotEmpty) {
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'INVALID_ROOM_CONFIG',
        errorMessage: problems.join(' '),
      );
      return;
    }

    final HostRoomService service = HostRoomService(
      hostService: ref.read(tcpHostServiceProvider),
      coordinator: RoomCoordinator(botNameBuilder: botNameBuilder),
      advertiser: ref.read(lanAdvertiserServiceProvider),
    );
    _hostService = service;

    try {
      final int port = await service.start(
        label: '${profile.displayName}’s room',
      );
      _bindHostCoordinator(service.coordinator);

      service.coordinator.createRoom(
        hostDisplayName: profile.displayName,
        avatarId: profile.avatarId,
        deviceId: ref.read(localPreferencesProvider).deviceId,
        config: effectiveConfig,
        tcpPort: port,
      );
      state = state.copyWith(
        status: RoomSessionStatus.inRoom,
        inviteCode: service.coordinator.inviteCode,
        roomId: service.coordinator.state?.roomId,
        playerId: service.coordinator.state?.hostPlayerId,
        hostPort: port,
        hostAddresses: await _localIpv4Addresses(),
      );
      // The Host must stay reachable: keep its screen awake while hosting.
      final ScreenAwakeService screenAwake = ref.read(
        screenAwakeServiceProvider,
      );
      _screenAwake = screenAwake;
      unawaited(screenAwake.enable());
    } on Object catch (error) {
      await service.stop();
      _hostService = null;
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'HOST_START_FAILED',
        errorMessage: 'The room could not be started. $error',
      );
    }
  }

  /// Starts a solo match against one or more computer opponents on this device.
  ///
  /// Nothing is advertised and no socket is opened: the room authority runs
  /// in-process and plays the turns of the bot itself. The preparation starts
  /// right away, so the player only has to place their own fleet.
  ///
  /// [difficulty] and [botName] describe a single opponent and are kept for
  /// backwards compatibility; [difficulties] and [botNames] allow seating
  /// several opponents of different strengths in the same match. When neither
  /// is given, [botCount] (or `config.botCount`) opponents of [difficulty]
  /// are seated.
  Future<void> startPractice({
    required Profile profile,
    BotDifficulty difficulty = BotDifficulty.medium,
    String? botName,
    int? botCount,
    List<BotDifficulty>? difficulties,
    List<String>? botNames,
    List<BotDifficulty>? botDifficulties,
    List<String>? opponentNames,
    int? opponentCount,
    RoomConfig? config,
  }) async {
    await _teardown();

    state = const RoomSessionState().copyWith(
      role: RoomRole.host,
      status: RoomSessionStatus.working,
    );

    final List<BotDifficulty> resolvedDifficulties =
        (difficulties ?? botDifficulties) ??
        (botCount != null || opponentCount != null
            ? List<BotDifficulty>.filled(
                botCount ?? opponentCount ?? 1,
                difficulty,
              )
            : (config != null && config.botCount > 0
                  ? List<BotDifficulty>.filled(config.botCount, difficulty)
                  : <BotDifficulty>[difficulty]));

    final List<BotDifficulty> opponents = resolvedDifficulties.isEmpty
        ? <BotDifficulty>[difficulty]
        : resolvedDifficulties;

    final List<String> resolvedNames =
        (botNames ?? opponentNames) ??
        List<String>.generate(
          opponents.length,
          (int index) => botName ?? 'Computer',
        );

    final RoomConfig baseConfig = config ?? RoomConfig.defaults;
    final RoomConfig requestedConfig = baseConfig.copyWith(
      botCount: opponents.length,
      botDifficulty: opponents.first,
    );
    final List<String> problems = requestedConfig.validate();
    if (problems.isNotEmpty) {
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'INVALID_ROOM_CONFIG',
        errorMessage: problems.join(' '),
      );
      return;
    }

    final RoomCoordinator coordinator = RoomCoordinator();
    _practiceCoordinator = coordinator;
    _bindHostCoordinator(coordinator);
    coordinator.createRoom(
      hostDisplayName: profile.displayName,
      avatarId: profile.avatarId,
      deviceId: ref.read(localPreferencesProvider).deviceId,
      // The computers are seated one by one below, each with its own name and
      // strength, so the room must not seat the preset opponents as well: that
      // would seat every opponent twice.
      config: requestedConfig.copyWith(botCount: 0),
      tcpPort: 0,
    );

    final List<String> setupProblems = <String>[];
    for (int index = 0; index < opponents.length; index++) {
      setupProblems.addAll(
        await coordinator.hostAddBot(
          displayName: index < resolvedNames.length
              ? resolvedNames[index]
              : 'Computer',
          difficulty: opponents[index],
        ),
      );
    }
    setupProblems.addAll(await coordinator.hostStartPlacement());
    if (setupProblems.isNotEmpty) {
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'PRACTICE_SETUP_FAILED',
        errorMessage: setupProblems.join(' '),
      );
      await _teardown();
      return;
    }

    state = state.copyWith(
      status: RoomSessionStatus.inRoom,
      roomId: coordinator.state?.roomId,
      playerId: coordinator.state?.hostPlayerId,
      inviteCode: null,
      practiceMode: true,
    );
  }

  /// Subscribes this controller to the authority that runs the room.
  ///
  /// A hosted room is served over TCP and a practice room runs the same
  /// authority in-process, so both publish the same streams and the UI never
  /// needs to know which one drives it.
  void _bindHostCoordinator(RoomCoordinator coordinator) {
    _hostSubscription = coordinator.hostSnapshots.listen((
      RoomSnapshot snapshot,
    ) {
      state = state.copyWith(snapshot: snapshot);
    });

    _hostPlacementSubscription = coordinator.hostPlacementStates.listen((
      PlacementState placement,
    ) {
      state = state.copyWith(placement: placement);
    });

    _hostReadinessSubscription = coordinator.hostReadinessStates.listen((
      ReadinessState readiness,
    ) {
      state = state.copyWith(readiness: readiness);
    });

    _hostCountdownSubscription = coordinator.hostCountdowns.listen((
      int remaining,
    ) {
      state = state.copyWith(countdown: Countdown(remainingSeconds: remaining));
    });

    _hostMatchSubscription = coordinator.hostMatchStarts.listen((
      MatchStartState match,
    ) {
      state = state.copyWith(match: match, countdown: null);
    });

    _hostNoticeSubscription = coordinator.hostNotices.listen((String notice) {
      state = state.copyWith(notice: notice);
    });

    _hostMatchSnapshotSubscription = coordinator.hostMatchSnapshots.listen(
      _acceptMatchSnapshot,
    );
    _hostMatchResultSubscription = coordinator.hostMatchResults.listen(
      _acceptMatchResult,
    );
    _hostTurnCountdownSubscription = coordinator.hostTurnCountdowns.listen(
      _acceptTurnCountdown,
    );
    _hostShotSubscription = coordinator.hostShotFeedbacks.listen(
      (ShotFeedback feedback) =>
          state = state.copyWith(lastShot: feedback, lastActivity: null),
    );
    _hostActivitySubscription = coordinator.hostPublicActivities.listen(
      _acceptPublicActivity,
    );
  }

  /// Applies new room settings. Host only.
  ///
  /// The Host runtime validates the values and broadcasts the accepted ones
  /// to every client. Returns the validation problems, or an empty list on
  /// success.
  Future<List<String>> updateConfig(RoomConfig config) async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator == null) return const <String>[];
    return coordinator.hostUpdateConfig(config);
  }

  /// Seats a computer opponent in the room. Host only.
  ///
  /// Remote clients cannot reach this: the Host runtime verifies that the
  /// command comes from the Host device. Returns the validation problems, or
  /// an empty list on success.
  Future<List<String>> addBot({
    required String displayName,
    required BotDifficulty difficulty,
  }) async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator == null) return const <String>[];
    return coordinator.hostAddBot(
      displayName: displayName,
      difficulty: difficulty,
    );
  }

  /// Sends a fleet layout to the Host.
  ///
  /// The Host validates the layout and answers with the accepted fleet, so
  /// the UI always shows the Host truth. Returns the validation problems of
  /// the local Host runtime, or an empty list when the command was sent.
  Future<List<String>> setPlacement(List<ShipPlacement> ships) async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator != null) {
      return coordinator.hostSetPlacement(ships);
    }
    _clientSession?.setPlacement(ships);
    return const <String>[];
  }

  /// Asks the Host to place the fleet automatically.
  Future<void> autoPlace() async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator != null) {
      await coordinator.hostAutoPlace();
      return;
    }
    _clientSession?.autoPlace();
  }

  /// Confirms the fleet to the Host.
  ///
  /// Returns the validation problems of the local Host runtime, or an empty
  /// list when the command was sent.
  Future<List<String>> setPlacementReady() async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator != null) {
      return coordinator.hostSetReady();
    }
    _clientSession?.setReady();
    return const <String>[];
  }

  /// Starts the preparation phase. Host only.
  ///
  /// Returns the validation problems, or an empty list on success.
  Future<List<String>> startPlacement() async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator != null) {
      return coordinator.hostStartPlacement();
    }
    _clientSession?.startPlacement();
    return const <String>[];
  }

  /// Fires at a cell of the one shared battle map.
  ///
  /// The Host resolves the shot against every living opponent, so the player
  /// never picks a target.
  Future<void> fire({required int row, required int column}) async {
    final MatchSnapshot? snapshot = state.matchSnapshot;
    if (!state.isInRoom || snapshot == null || state.firePending) return;
    if (snapshot.winnerPlayerId != null ||
        snapshot.activePlayerId != state.playerId ||
        snapshot.playerById(state.playerId ?? '')?.alive != true) {
      return;
    }
    final (String, int) turn = (snapshot.matchId, snapshot.turnNumber);
    if (_submittedTurn == turn) return;
    _submittedTurn = turn;
    state = state.copyWith(firePending: true, combatError: null);
    try {
      final RoomCoordinator? coordinator = _coordinator;
      final List<String> problems;
      if (coordinator != null) {
        problems = await coordinator.hostFire(
          matchId: snapshot.matchId,
          turnNumber: snapshot.turnNumber,
          expectedStateVersion: snapshot.stateVersion,
          row: row,
          column: column,
        );
      } else {
        problems =
            await _clientSession?.fire(
              matchId: snapshot.matchId,
              turnNumber: snapshot.turnNumber,
              expectedStateVersion: snapshot.stateVersion,
              row: row,
              column: column,
            ) ??
            <String>['The host is not connected.'];
      }
      if (!ref.mounted || state.matchSnapshot?.matchId != snapshot.matchId) {
        return;
      }
      if (problems.isNotEmpty) _submittedTurn = null;
      state = state.copyWith(
        combatError: problems.isEmpty ? null : problems.join(' '),
      );
    } on Object {
      if (ref.mounted && state.isInRoom) {
        state = state.copyWith(combatError: 'The shot could not be confirmed.');
      }
    } finally {
      if (ref.mounted) state = state.copyWith(firePending: false);
    }
  }

  void _acceptMatchSnapshot(MatchSnapshot snapshot) {
    final MatchSnapshot? current = state.matchSnapshot;
    if (current != null &&
        current.matchId == snapshot.matchId &&
        snapshot.stateVersion < current.stateVersion) {
      return;
    }
    state = state.copyWith(
      matchSnapshot: snapshot,
      turnCountdown:
          snapshot.winnerPlayerId != null ||
              snapshot.turnRemainingSeconds == null
          ? null
          : Countdown(remainingSeconds: snapshot.turnRemainingSeconds!),
    );
  }

  void _acceptTurnCountdown(int remaining) {
    if (state.matchSnapshot?.winnerPlayerId != null) return;
    state = state.copyWith(
      turnCountdown: Countdown(remainingSeconds: remaining),
    );
  }

  /// Stores the final result the Host broadcast.
  ///
  /// The ranking and the statistics are Host truth: the client renders them
  /// and never recomputes them (PLAN.md §2.10, §6.6).
  void _acceptMatchResult(MatchResult result) {
    final MatchResult? current = state.matchResult;
    if (current != null &&
        current.matchId == result.matchId &&
        result.stateVersion < current.stateVersion) {
      return;
    }
    state = state.copyWith(
      matchResult: result,
      turnCountdown: null,
      firePending: false,
    );
  }

  void _acceptPublicActivity(PublicActivity activity) {
    final List<PublicActivity> feed = <PublicActivity>[
      ...state.activityFeed,
      activity,
    ];
    state = state.copyWith(
      lastActivity: activity,
      lastShot: null,
      activityFeed: feed.length > _activityFeedLimit
          ? feed.sublist(feed.length - _activityFeedLimit)
          : feed,
    );
  }

  static const int _activityFeedLimit = 20;

  /// Removes a player from the room. Host only.
  Future<void> kick(String playerId) async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator == null) return;
    await coordinator.hostKick(playerId);
  }

  /// Closes the room for everyone. Host only.
  Future<void> closeRoom() async {
    final RoomCoordinator? coordinator = _coordinator;
    if (coordinator == null) return;
    await coordinator.closeRoom(
      reason: 'host_closed',
      message: 'The host closed the room.',
    );
    state = state.copyWith(
      status: RoomSessionStatus.closed,
      errorMessage: 'The host closed the room.',
    );
    await _teardown();
  }

  // --------------------------------------------------------------- client

  /// Joins a discovered room.
  Future<void> joinRoom({
    required DiscoveredRoom room,
    required String code,
    required Profile profile,
  }) async {
    final InternetAddress? address = room.preferredAddress;
    if (address == null) {
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'NO_RESOLVED_ADDRESS',
        errorMessage:
            'The room "${room.label}" has no usable address. Use the manual '
            'connection form instead.',
      );
      return;
    }
    await _join(
      address: address,
      port: room.port,
      code: code,
      profile: profile,
    );
  }

  /// Joins a room through a manually entered endpoint.
  Future<void> joinManually({
    required String host,
    required int port,
    required String code,
    required Profile profile,
  }) async {
    final InternetAddress? address = InternetAddress.tryParse(host.trim());
    if (address == null) {
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'INVALID_ADDRESS',
        errorMessage: 'That is not a valid IP address.',
      );
      return;
    }
    await _join(address: address, port: port, code: code, profile: profile);
  }

  Future<void> _join({
    required InternetAddress address,
    required int port,
    required String code,
    required Profile profile,
  }) async {
    await _teardown();

    state = const RoomSessionState().copyWith(
      role: RoomRole.client,
      status: RoomSessionStatus.working,
      errorCode: null,
      errorMessage: null,
    );

    final RoomClientSession session = RoomClientSession();
    _clientSession = session;

    _clientSubscription = session.snapshots.listen((RoomSnapshot snapshot) {
      state = state.copyWith(snapshot: snapshot);
    });
    _clientPlacementSubscription = session.placementStates.listen((
      PlacementState placement,
    ) {
      state = state.copyWith(placement: placement);
    });
    _clientReadinessSubscription = session.readinessStates.listen((
      ReadinessState readiness,
    ) {
      state = state.copyWith(readiness: readiness);
    });
    _clientCountdownSubscription = session.countdowns.listen((int remaining) {
      state = state.copyWith(countdown: Countdown(remainingSeconds: remaining));
    });
    _clientMatchSubscription = session.matchStarts.listen((
      MatchStartState match,
    ) {
      state = state.copyWith(match: match, countdown: null);
    });
    _clientNoticeSubscription = session.placementCancellations.listen((
      String notice,
    ) {
      state = state.copyWith(notice: notice, countdown: null);
    });
    _clientMatchSnapshotSubscription = session.matchSnapshots.listen(
      _acceptMatchSnapshot,
    );
    _clientMatchResultSubscription = session.matchResults.listen(
      _acceptMatchResult,
    );
    _clientShotSubscription = session.shotFeedbacks.listen(
      (ShotFeedback feedback) =>
          state = state.copyWith(lastShot: feedback, lastActivity: null),
    );
    _clientActivitySubscription = session.publicActivities.listen(
      _acceptPublicActivity,
    );
    _clientTurnCountdownSubscription = session.turnCountdowns.listen(
      _acceptTurnCountdown,
    );
    _eventSubscription = session.events.listen((RoomClientEvent event) {
      switch (event) {
        case RoomJoinedEvent(:final String roomId):
          state = state.copyWith(
            status: RoomSessionStatus.inRoom,
            roomId: roomId,
          );
        case RoomClosedEvent(:final String reason, :final String message):
          state = state.copyWith(
            status: RoomSessionStatus.closed,
            errorCode: reason,
            errorMessage: message,
          );
        case RoomErrorEvent(:final String code, :final String message):
          if (state.matchSnapshot != null && state.isInRoom) {
            state = state.copyWith(combatError: message, firePending: false);
            break;
          }
          if (_placementErrorCodes.contains(code)) {
            // A rejected placement only concerns the fleet: the room stays.
            state = state.copyWith(placementError: message);
            break;
          }
          state = state.copyWith(
            status: RoomSessionStatus.failed,
            errorCode: code,
            errorMessage: message,
          );
        case RoomConnectionLostEvent():
          state = state.copyWith(
            status: RoomSessionStatus.failed,
            errorCode: 'HOST_UNREACHABLE',
            errorMessage:
                'The connection to the host was lost. The match cannot '
                'continue without the host.',
          );
        case RoomPlayerDisconnectedEvent():
        case RoomPlayerReconnectedEvent():
          break;
        case RoomSnapshotEvent():
          break;
      }
    });

    try {
      await session.join(
        address: address,
        port: port,
        code: code,
        displayName: profile.displayName,
        avatarId: profile.avatarId,
        deviceId: ref.read(localPreferencesProvider).deviceId,
      );
      state = state.copyWith(playerId: session.playerId);
    } on RoomJoinException catch (error) {
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: error.code,
        errorMessage: error.message,
      );
      await _teardown();
    } on Object catch (error) {
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'HOST_UNREACHABLE',
        errorMessage:
            'Could not reach the host at $address:$port. Check that both '
            'devices are on the same Wi-Fi. ($error)',
      );
      await _teardown();
    }
  }

  /// Leaves the room. Client only.
  Future<void> leave() async {
    final RoomClientSession? session = _clientSession;
    if (session != null) {
      await session.leave();
    }
    await _teardown();
    state = const RoomSessionState();
  }

  /// Returns to the idle state, clearing any error.
  void reset() {
    state = const RoomSessionState();
  }

  // -------------------------------------------------------------- helpers

  Future<void> _teardown() async {
    await _hostSubscription?.cancel();
    _hostSubscription = null;
    await _clientSubscription?.cancel();
    _clientSubscription = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _hostPlacementSubscription?.cancel();
    _hostPlacementSubscription = null;
    await _hostReadinessSubscription?.cancel();
    _hostReadinessSubscription = null;
    await _clientPlacementSubscription?.cancel();
    _clientPlacementSubscription = null;
    await _clientReadinessSubscription?.cancel();
    _clientReadinessSubscription = null;
    await _hostCountdownSubscription?.cancel();
    _hostCountdownSubscription = null;
    await _clientCountdownSubscription?.cancel();
    _clientCountdownSubscription = null;
    await _hostMatchSubscription?.cancel();
    _hostMatchSubscription = null;
    await _clientMatchSubscription?.cancel();
    _clientMatchSubscription = null;
    await _hostNoticeSubscription?.cancel();
    _hostNoticeSubscription = null;
    await _clientNoticeSubscription?.cancel();
    _clientNoticeSubscription = null;
    await _hostMatchSnapshotSubscription?.cancel();
    _hostMatchSnapshotSubscription = null;
    await _clientMatchSnapshotSubscription?.cancel();
    _clientMatchSnapshotSubscription = null;
    await _hostMatchResultSubscription?.cancel();
    _hostMatchResultSubscription = null;
    await _clientMatchResultSubscription?.cancel();
    _clientMatchResultSubscription = null;
    await _hostShotSubscription?.cancel();
    _hostShotSubscription = null;
    await _clientShotSubscription?.cancel();
    _clientShotSubscription = null;
    await _hostTurnCountdownSubscription?.cancel();
    _hostTurnCountdownSubscription = null;
    await _clientTurnCountdownSubscription?.cancel();
    _clientTurnCountdownSubscription = null;

    await _hostActivitySubscription?.cancel();
    _hostActivitySubscription = null;
    await _clientActivitySubscription?.cancel();
    _clientActivitySubscription = null;
    _submittedTurn = null;
    final HostRoomService? service = _hostService;
    _hostService = null;
    final ScreenAwakeService? screenAwake = _screenAwake;
    _screenAwake = null;
    if (service != null) {
      // Release the screen wakelock once the Host stops hosting.
      unawaited(screenAwake?.disable());
    }
    await service?.stop();
    await service?.coordinator.dispose();

    final RoomCoordinator? practiceCoordinator = _practiceCoordinator;
    _practiceCoordinator = null;
    await practiceCoordinator?.dispose();

    final RoomClientSession? session = _clientSession;
    _clientSession = null;
    await session?.close();
  }

  void _dispose() {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    unawaited(_teardown());
  }

  Future<List<String>> _localIpv4Addresses() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces
          .expand((NetworkInterface item) => item.addresses)
          .where((InternetAddress address) => !address.isLoopback)
          .map((InternetAddress address) => address.address)
          .toList();
    } on Object {
      return const <String>[];
    }
  }
}

/// The error codes that only concern the fleet placement.
///
/// They never end the room: the player simply has to try again
/// (PLAN.md §9.1).
const Set<String> _placementErrorCodes = <String>{
  ProtocolErrorCode.invalidShipPlacement,
  ProtocolErrorCode.fleetIncomplete,
  ProtocolErrorCode.placementPhaseNotActive,
};

/// The current room session.
final roomSessionControllerProvider =
    NotifierProvider<RoomSessionController, RoomSessionState>(
      RoomSessionController.new,
    );
