import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
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
  final PlacementCountdown? countdown;

  /// The match that started, once the preparation ended.
  final MatchStartState? match;

  /// A message the Host sent to this player.
  final String? notice;

  /// Whether this device hosts the room.
  bool get isHost => role == RoomRole.host;

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
  }) => RoomSessionState(
    role: role ?? this.role,
    status: status ?? this.status,
    snapshot: identical(snapshot, _unset) ? this.snapshot : snapshot as RoomSnapshot?,
    inviteCode: identical(inviteCode, _unset) ? this.inviteCode : inviteCode as String?,
    roomId: identical(roomId, _unset) ? this.roomId : roomId as String?,
    playerId: identical(playerId, _unset) ? this.playerId : playerId as String?,
    errorCode: identical(errorCode, _unset) ? this.errorCode : errorCode as String?,
    errorMessage:
        identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
    hostPort: identical(hostPort, _unset) ? this.hostPort : hostPort as int?,
    hostAddresses: hostAddresses ?? this.hostAddresses,
    placement: identical(placement, _unset) ? this.placement : placement as PlacementState?,
    readiness: identical(readiness, _unset) ? this.readiness : readiness as ReadinessState?,
    placementError: identical(placementError, _unset)
        ? this.placementError
        : placementError as String?,
    countdown: identical(countdown, _unset)
        ? this.countdown
        : countdown as PlacementCountdown?,
    match: identical(match, _unset) ? this.match : match as MatchStartState?,
    notice: identical(notice, _unset) ? this.notice : notice as String?,
  );

  static const Object _unset = Object();
}

/// Drives the room lifecycle on this device.
///
/// The same controller covers both roles: as the Host it owns the
/// [HostRoomService], as a client it owns a [RoomClientSession].
class RoomSessionController extends Notifier<RoomSessionState> {
  HostRoomService? _hostService;
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
  AppLifecycleListener? _lifecycleListener;

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
    final HostRoomService? service = _hostService;
    if (service == null) return;
    await service.coordinator.checkPreparationDeadline();
  }

  // ----------------------------------------------------------------- host

  /// Creates a room on this device and starts advertising it.
  Future<void> createRoom({
    required Profile profile,
    RoomConfig? config,
  }) async {
    await _teardown();

    state = state.copyWith(
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
      coordinator: RoomCoordinator(),
      advertiser: ref.read(lanAdvertiserServiceProvider),
    );
    _hostService = service;

    try {
      final int port = await service.start(
        label: '${profile.displayName}’s room',
      );
      service.coordinator.createRoom(
        hostDisplayName: profile.displayName,
        avatarId: profile.avatarId,
        deviceId: ref.read(localPreferencesProvider).deviceId,
        config: effectiveConfig,
        tcpPort: port,
      );

      _hostSubscription = service.coordinator.hostSnapshots.listen(
        (RoomSnapshot snapshot) {
          state = state.copyWith(snapshot: snapshot);
        },
      );

      _hostPlacementSubscription = service.coordinator.hostPlacementStates
          .listen((PlacementState placement) {
            state = state.copyWith(placement: placement);
          });

      _hostReadinessSubscription = service.coordinator.hostReadinessStates
          .listen((ReadinessState readiness) {
            state = state.copyWith(readiness: readiness);
          });

      _hostCountdownSubscription = service.coordinator.hostCountdowns.listen(
        (int remaining) {
          state = state.copyWith(
            countdown: PlacementCountdown(
              remainingSeconds: remaining,
              syncedAt: DateTime.now(),
            ),
          );
        },
      );

      _hostMatchSubscription = service.coordinator.hostMatchStarts.listen(
        (MatchStartState match) {
          state = state.copyWith(match: match, countdown: null);
        },
      );

      _hostNoticeSubscription = service.coordinator.hostNotices.listen(
        (String notice) {
          state = state.copyWith(notice: notice);
        },
      );

      state = state.copyWith(
        status: RoomSessionStatus.inRoom,
        inviteCode: service.coordinator.inviteCode,
        roomId: service.coordinator.state?.roomId,
        playerId: service.coordinator.state?.hostPlayerId,
        hostPort: port,
        hostAddresses: await _localIpv4Addresses(),
      );
    } on Object catch (error) {
      await service.stop();
      _hostService = null;
      state = state.copyWith(
        status: RoomSessionStatus.failed,
        errorCode: 'HOST_START_FAILED',
        errorMessage:
            'The room could not be started. $error',
      );
    }
  }

  /// Applies new room settings. Host only.
  ///
  /// The Host runtime validates the values and broadcasts the accepted ones
  /// to every client. Returns the validation problems, or an empty list on
  /// success.
  Future<List<String>> updateConfig(RoomConfig config) async {
    final HostRoomService? service = _hostService;
    if (service == null) return const <String>[];
    return service.coordinator.hostUpdateConfig(config);
  }

  /// Sends a fleet layout to the Host.
  ///
  /// The Host validates the layout and answers with the accepted fleet, so
  /// the UI always shows the Host truth. Returns the validation problems of
  /// the local Host runtime, or an empty list when the command was sent.
  Future<List<String>> setPlacement(List<ShipPlacement> ships) async {
    final HostRoomService? service = _hostService;
    if (service != null) {
      return service.coordinator.hostSetPlacement(ships);
    }
    _clientSession?.setPlacement(ships);
    return const <String>[];
  }

  /// Asks the Host to place the fleet automatically.
  Future<void> autoPlace() async {
    final HostRoomService? service = _hostService;
    if (service != null) {
      await service.coordinator.hostAutoPlace();
      return;
    }
    _clientSession?.autoPlace();
  }

  /// Confirms the fleet to the Host.
  ///
  /// Returns the validation problems of the local Host runtime, or an empty
  /// list when the command was sent.
  Future<List<String>> setPlacementReady() async {
    final HostRoomService? service = _hostService;
    if (service != null) {
      return service.coordinator.hostSetReady();
    }
    _clientSession?.setReady();
    return const <String>[];
  }

  /// Starts the preparation phase. Host only.
  ///
  /// Returns the validation problems, or an empty list on success.
  Future<List<String>> startPlacement() async {
    final HostRoomService? service = _hostService;
    if (service != null) {
      return service.coordinator.hostStartPlacement();
    }
    _clientSession?.startPlacement();
    return const <String>[];
  }

  /// Removes a player from the room. Host only.
  Future<void> kick(String playerId) async {
    final HostRoomService? service = _hostService;
    if (service == null) return;
    await service.coordinator.hostKick(playerId);
  }

  /// Closes the room for everyone. Host only.
  Future<void> closeRoom() async {
    final HostRoomService? service = _hostService;
    if (service == null) return;
    await service.coordinator.closeRoom(
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
    await _join(
      address: address,
      port: port,
      code: code,
      profile: profile,
    );
  }

  Future<void> _join({
    required InternetAddress address,
    required int port,
    required String code,
    required Profile profile,
  }) async {
    await _teardown();

    state = state.copyWith(
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
    _clientPlacementSubscription = session.placementStates.listen(
      (PlacementState placement) {
        state = state.copyWith(placement: placement);
      },
    );
    _clientReadinessSubscription = session.readinessStates.listen(
      (ReadinessState readiness) {
        state = state.copyWith(readiness: readiness);
      },
    );
    _clientCountdownSubscription = session.countdowns.listen((int remaining) {
      state = state.copyWith(
        countdown: PlacementCountdown(
          remainingSeconds: remaining,
          syncedAt: DateTime.now(),
        ),
      );
    });
    _clientMatchSubscription = session.matchStarts.listen(
      (MatchStartState match) {
        state = state.copyWith(match: match, countdown: null);
      },
    );
    _clientNoticeSubscription = session.placementCancellations.listen(
      (String notice) {
        state = state.copyWith(notice: notice, countdown: null);
      },
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

    final HostRoomService? service = _hostService;
    _hostService = null;
    await service?.stop();

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