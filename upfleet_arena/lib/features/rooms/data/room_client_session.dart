import 'dart:async';
import 'dart:io';

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

  StreamSubscription<ProtocolMessage>? _frameSubscription;
  StreamSubscription<ProtocolError>? _errorSubscription;
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  DateTime _lastFrameAt = DateTime.now();

  String? _playerId;
  String? _roomId;
  String? _resumeToken;
  bool _closed = false;

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
      case HostEventType.stateSnapshot:
      case HostEventType.configUpdated:
        final Object? rawSnapshot = message.payload['snapshot'];
        if (rawSnapshot is Map<String, dynamic>) {
          _snapshots.add(RoomSnapshot.fromJson(rawSnapshot));
        }
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
