import 'dart:async';
import 'dart:io';

import '../../../game_engine/placement/placement.dart';
import '../../../shared/models/match_models.dart';
import '../../../shared/models/placement_models.dart';
import '../../../shared/models/room_models.dart';
import '../../../shared/protocol/protocol_constants.dart';
import '../../../shared/protocol/protocol_message.dart';
import '../../lan_networking/services/tcp_client_service.dart';

/// Events emitted by a [RoomClientSession] to the UI.
sealed class RoomClientEvent {
  const RoomClientEvent();
}

/// The join was accepted; the client is now a member of the room.
class RoomJoinedEvent extends RoomClientEvent {
  const RoomJoinedEvent({
    required this.playerId,
    required this.roomId,
    required this.resumeToken,
  });

  /// The player ID assigned by the Host.
  final String playerId;

  /// The room identifier.
  final String roomId;

  /// The resume token, used to reclaim the seat after a disconnection.
  final String resumeToken;
}

/// A new room state arrived.
class RoomSnapshotEvent extends RoomClientEvent {
  const RoomSnapshotEvent(this.snapshot);

  /// The permission-filtered room state.
  final RoomSnapshot snapshot;
}

/// The room is over for this client.
class RoomClosedEvent extends RoomClientEvent {
  const RoomClosedEvent({required this.reason, required this.message});

  /// Why the room ended, e.g. `host_closed` or `kicked`.
  final String reason;

  /// A user-safe explanation.
  final String message;
}

/// The Host rejected a command.
class RoomErrorEvent extends RoomClientEvent {
  const RoomErrorEvent({required this.code, required this.message});

  /// Stable machine-readable error code.
  final String code;

  /// User-safe explanation.
  final String message;
}

/// The connection to the Host was lost.
class RoomConnectionLostEvent extends RoomClientEvent {
  const RoomConnectionLostEvent();
}

/// The client side of a room session.
///
/// It opens one long-lived TCP connection to the Host, performs the join
/// handshake and reduces the Host events into a [RoomSnapshot] stream
/// (PLAN.md §6.4, §10.1).
class RoomClientSession {
  RoomClientSession({TcpClientService? transport})
    : _transport = transport ?? TcpClientService();

  final TcpClientService _transport;
  final StreamController<RoomSnapshot> _snapshots =
      StreamController<RoomSnapshot>.broadcast();
  final StreamController<RoomClientEvent> _events =
      StreamController<RoomClientEvent>.broadcast();
  final StreamController<PlacementState> _placementStates =
      StreamController<PlacementState>.broadcast();
  final StreamController<ReadinessState> _readinessStates =
      StreamController<ReadinessState>.broadcast();
  final StreamController<int> _countdowns = StreamController<int>.broadcast();
  final StreamController<MatchStartState> _matchStarts =
      StreamController<MatchStartState>.broadcast();
  final StreamController<String> _placementCancellations =
      StreamController<String>.broadcast();
  final StreamController<MatchSnapshot> _matchSnapshots =
      StreamController<MatchSnapshot>.broadcast();
  final StreamController<ShotFeedback> _shotFeedbacks =
      StreamController<ShotFeedback>.broadcast();
  final StreamController<PublicActivity> _publicActivities =
      StreamController<PublicActivity>.broadcast();
  final StreamController<int> _turnCountdowns =
      StreamController<int>.broadcast();

  StreamSubscription<ProtocolMessage>? _frameSubscription;
  StreamSubscription<ProtocolError>? _errorSubscription;
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  DateTime _lastFrameAt = DateTime.now();

  String? _playerId;
  String? _roomId;
  String? _resumeToken;
  bool _closed = false;
  String? _pendingFireId;
  Completer<List<String>>? _pendingFire;
  int _fireSequence = 0;

  /// The player ID assigned by the Host.
  String? get playerId => _playerId;

  /// The room identifier.
  String? get roomId => _roomId;

  /// The resume token issued at join time.
  String? get resumeToken => _resumeToken;

  /// Whether the connection is open.
  bool get isConnected => _transport.isConnected && !_closed;

  /// The latest room state.
  Stream<RoomSnapshot> get snapshots => _snapshots.stream;

  /// Session events.
  Stream<RoomClientEvent> get events => _events.stream;

  /// The exact fleet layout of this client, sent by the Host.
  Stream<PlacementState> get placementStates => _placementStates.stream;

  /// The readiness of every member.
  Stream<ReadinessState> get readinessStates => _readinessStates.stream;

  /// The seconds that are left before the preparation ends.
  ///
  /// The Host owns the deadline and resends the remaining time with every
  /// heartbeat, so a client only renders it (PLAN.md §9.4).
  Stream<int> get countdowns => _countdowns.stream;

  /// The match that just started.
  Stream<MatchStartState> get matchStarts => _matchStarts.stream;

  /// The reasons the preparation was cancelled.
  Stream<String> get placementCancellations => _placementCancellations.stream;

  /// The permission-filtered state of the match.
  Stream<MatchSnapshot> get matchSnapshots => _matchSnapshots.stream;

  /// The result of a shot this client is involved in.
  Stream<ShotFeedback> get shotFeedbacks => _shotFeedbacks.stream;

  /// The shots of the other players, without any coordinate.
  Stream<PublicActivity> get publicActivities => _publicActivities.stream;

  /// The seconds that are left before the current turn ends.
  Stream<int> get turnCountdowns => _turnCountdowns.stream;

  /// Connects to the Host and performs the join handshake.
  ///
  /// Returns the accepted player identity. Throws [RoomJoinException] when
  /// the Host rejects the join.
  Future<String> join({
    required InternetAddress address,
    required int port,
    required String code,
    required String displayName,
    required String avatarId,
    required String deviceId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _transport.connect(address, port, timeout: timeout);

    _errorSubscription = _transport.errors.listen((ProtocolError error) {
      if (_closed) return;
      _events.add(
        RoomErrorEvent(code: error.code, message: error.message),
      );
    });

    _frameSubscription = _transport.frames.listen(_handleFrame);

    final Completer<String> completer = Completer<String>();
    final String requestId = 'join-${DateTime.now().microsecondsSinceEpoch}';

    _pendingJoin = completer;

    _transport.send(
      ProtocolMessage(
        messageType: ClientMessageType.join,
        requestId: requestId,
        payload: <String, dynamic>{
          'code': code.trim().toUpperCase(),
          'displayName': displayName,
          'avatarId': avatarId,
          'deviceId': deviceId,
        },
      ),
    );

    _startHeartbeat();
    _startWatchdog();

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw const RoomJoinException(
          ProtocolErrorCode.hostUnreachable,
          'The host did not answer in time.',
        ),
      );
    } finally {
      _pendingJoin = null;
    }
  }

  Completer<String>? _pendingJoin;

  void _handleFrame(ProtocolMessage message) {
    _lastFrameAt = DateTime.now();
    switch (message.messageType) {
      case HostEventType.joined:
        final Map<String, dynamic> payload = message.payload;
        final String playerId = payload['playerId'] as String? ?? '';
        _playerId = playerId;
        _roomId = payload['roomId'] as String?;
        _resumeToken = payload['resumeToken'] as String?;

        final Object? rawSnapshot = payload['snapshot'];
        if (rawSnapshot is Map<String, dynamic>) {
          _snapshots.add(RoomSnapshot.fromJson(rawSnapshot));
        }
        _events.add(
          RoomJoinedEvent(
            playerId: playerId,
            roomId: _roomId ?? '',
            resumeToken: _resumeToken ?? '',
          ),
        );
        _pendingJoin?.complete(playerId);
      case HostEventType.roomState:
      case HostEventType.configUpdated:
        final Object? rawSnapshot = message.payload['snapshot'];
        if (rawSnapshot is Map<String, dynamic>) {
          _snapshots.add(RoomSnapshot.fromJson(rawSnapshot));
        }
      case HostEventType.stateSnapshot:
        final Object? rawMatch = message.payload['snapshot'];
        if (rawMatch is Map<String, dynamic>) {
          _matchSnapshots.add(MatchSnapshot.fromJson(rawMatch));
        }
      case HostEventType.shotResult:
        _shotFeedbacks.add(ShotFeedback.fromJson(message.payload));
        if (message.requestId == _pendingFireId && _pendingFire?.isCompleted == false) {
          _pendingFire!.complete(const <String>[]);
        }
      case HostEventType.publicActivity:
        _publicActivities.add(PublicActivity.fromJson(message.payload));
      case HostEventType.turnStarted:
        final Object? remaining = message.payload['remainingSeconds'];
        if (remaining is int) _turnCountdowns.add(remaining);
      case HostEventType.placementState:
        _placementStates.add(PlacementState.fromJson(message.payload));
      case HostEventType.placementReadyState:
        _readinessStates.add(ReadinessState.fromJson(message.payload));
      case HostEventType.placementStarted:
        _countdowns.add(message.payload['remainingSeconds'] as int? ?? 0);
      case HostEventType.placementCancelled:
        _placementCancellations.add(
          message.payload['reason'] as String? ??
              'The preparation was cancelled.',
        );
      case HostEventType.started:
        _matchStarts.add(MatchStartState.fromJson(message.payload));
      case HostEventType.heartbeat:
        final Object? remaining = message.payload['placementRemainingSeconds'];
        if (remaining is int) _countdowns.add(remaining);
        final Object? turnRemaining =
            message.payload['turnRemainingSeconds'];
        if (turnRemaining is int) _turnCountdowns.add(turnRemaining);
      case HostEventType.closed:
        _events.add(
          RoomClosedEvent(
            reason: message.payload['reason'] as String? ?? 'host_closed',
            message:
                message.payload['message'] as String? ??
                'The host closed the room.',
          ),
        );
        _pendingJoin?.completeError(
          const RoomJoinException(
            ProtocolErrorCode.roomNotFound,
            'The room closed before you could join.',
          ),
        );
      case HostEventType.error:
        final String code = message.payload['code'] as String? ?? 'UNKNOWN';
        final String text =
            message.payload['message'] as String? ?? 'Something went wrong.';
        if (message.requestId == _pendingFireId && _pendingFire?.isCompleted == false) {
          _pendingFire!.complete(<String>[text]);
          requestSnapshot();
          break;
        }
        _events.add(RoomErrorEvent(code: code, message: text));
        if (_pendingJoin != null) {
          _pendingJoin!.completeError(RoomJoinException(code, text));
        }
      default:
        break;
    }
  }

  /// Asks the Host to remove this client from the room.
  Future<void> leave() async {
    if (!isConnected) {
      await close();
      return;
    }
    _transport.send(
      ProtocolMessage(messageType: ClientMessageType.leave),
    );
    await close();
  }

  /// Sends the fleet layout to the Host.
  ///
  /// The Host validates the whole layout and answers with the accepted fleet
  /// in a `placement:state` event.
  void setPlacement(List<ShipPlacement> ships) {
    if (!isConnected) return;
    _transport.send(
      ProtocolMessage(
        messageType: ClientMessageType.placementSet,
        payload: <String, dynamic>{
          'ships': ships
              .map(
                (ShipPlacement ship) =>
                    ShipLayout.fromPlacement(ship).toJson(),
              )
              .toList(),
        },
      ),
    );
  }

  /// Asks the Host to place the fleet automatically.
  void autoPlace() {
    if (!isConnected) return;
    _transport.send(
      ProtocolMessage(messageType: ClientMessageType.placementAuto),
    );
  }

  /// Confirms the fleet to the Host.
  void setReady() {
    if (!isConnected) return;
    _transport.send(
      ProtocolMessage(messageType: ClientMessageType.placementReady),
    );
  }

  /// Fires at a cell of an opponent's board and waits for the Host to
  /// confirm the shot.
  ///
  /// The answer arrives as `game:shot-result` carrying this request id, so a
  /// client never has to guess whether its shot was accepted.
  Future<List<String>> fire({
    required String matchId,
    required int turnNumber,
    required int expectedStateVersion,
    required String targetPlayerId,
    required int row,
    required int column,
  }) async {
    if (!isConnected) return <String>['The host is not connected.'];
    if (_pendingFire != null) return <String>['A shot is awaiting confirmation.'];
    final String requestId = 'fire-${++_fireSequence}';
    final Completer<List<String>> pending = Completer<List<String>>();
    _pendingFireId = requestId;
    _pendingFire = pending;
    try {
      _transport.send(
        ProtocolMessage(
          messageType: ClientMessageType.fire,
          roomId: _roomId,
          requestId: requestId,
          expectedStateVersion: expectedStateVersion,
          payload: <String, dynamic>{
            'matchId': matchId,
            'turnNumber': turnNumber,
            'targetPlayerId': targetPlayerId,
            'row': row,
            'column': column,
          },
        ),
      );
      return await pending.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          requestSnapshot();
          return <String>[
            'The host did not confirm the shot. The match state was refreshed.',
          ];
        },
      );
    } finally {
      _pendingFire = null;
      _pendingFireId = null;
    }
  }

  /// Asks the Host for the current authorized state.
  void requestSnapshot() {
    if (!isConnected) return;
    _transport.send(
      ProtocolMessage(messageType: ClientMessageType.requestSnapshot),
    );
  }

  /// Asks the Host to start the preparation phase.
  void startPlacement() {
    if (!isConnected) return;
    _transport.send(
      ProtocolMessage(messageType: ClientMessageType.startPlacement),
    );
  }

  /// Sends a heartbeat to the Host.
  void sendHeartbeat() {
    if (!isConnected) return;
    _transport.send(ProtocolMessage(messageType: ClientMessageType.heartbeat));
  }

  /// Detects an abrupt Host loss.
  ///
  /// The Host sends a heartbeat about every three seconds. When nothing
  /// arrives for the configured timeout, the room cannot continue and the
  /// client is told to return Home (PLAN.md §2.9, §9.5).
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (_closed) return;
      if (DateTime.now().difference(_lastFrameAt) >
          AppProtocol.hostLostTimeout) {
        _events.add(const RoomConnectionLostEvent());
        unawaited(close());
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      AppProtocol.hostHeartbeatInterval,
      (Timer _) => sendHeartbeat(),
    );
  }

  /// Closes the connection and releases every resource.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_pendingFire?.isCompleted == false) {
      _pendingFire!.complete(<String>['The connection to the host was closed.']);
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await _frameSubscription?.cancel();
    await _errorSubscription?.cancel();
    _frameSubscription = null;
    _errorSubscription = null;
    await _transport.close();
    await _snapshots.close();
    await _events.close();
    await _placementStates.close();
    await _readinessStates.close();
    await _countdowns.close();
    await _matchStarts.close();
    await _placementCancellations.close();
    await _matchSnapshots.close();
    await _shotFeedbacks.close();
    await _publicActivities.close();
    await _turnCountdowns.close();
  }
}

/// Raised when the Host rejects a join attempt.
class RoomJoinException implements Exception {
  const RoomJoinException(this.code, this.message);

  /// Stable machine-readable error code.
  final String code;

  /// User-safe explanation.
  final String message;

  @override
  String toString() => 'RoomJoinException($code): $message';
}
