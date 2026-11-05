import 'dart:async';
import 'dart:io';

import '../features/lan_networking/domain/lan_discovery.dart';
import '../features/lan_networking/services/tcp_host_service.dart';
import '../shared/protocol/protocol_constants.dart';
import '../shared/protocol/protocol_message.dart';
import 'client_connection_registry.dart';
import 'room_coordinator.dart';
import 'room_state.dart';

/// Runs the Host side of a room: the TCP listener, the advertisement and the
/// routing of inbound frames into the [RoomCoordinator].
///
/// The Host phone runs this in-process. It is not a separately deployed
/// backend (PLAN.md §1.2, §6.1).
class HostRoomService implements RoomTransport {
  HostRoomService({
    required this.hostService,
    required this.coordinator,
    this.advertiser,
  }) {
    coordinator.attach(this, onRoomClosed: _handleRoomClosed);
  }

  /// The TCP listener the room is served from.
  final TcpHostService hostService;

  /// The room authority.
  final RoomCoordinator coordinator;

  /// The mDNS/Bonjour advertiser, when the backend provides one.
  final LanAdvertiserService? advertiser;

  final Map<String, ClientSession> _sessions = <String, ClientSession>{};
  final Map<String, LanHostConnection> _connections =
      <String, LanHostConnection>{};
  final Map<String, StreamSubscription<ProtocolMessage>> _frameSubscriptions =
      <String, StreamSubscription<ProtocolMessage>>{};

  StreamSubscription<LanHostConnection>? _connectionSubscription;
  Timer? _heartbeatTimer;
  bool _stopping = false;

  /// The port the Host is listening on.
  int? get port => hostService.port;

  /// Diagnostics emitted by the advertiser.
  Stream<String> get advertiserDiagnostics =>
      advertiser?.diagnostics ?? const Stream<String>.empty();

  /// Opens the listener and starts advertising the room.
  ///
  /// [label] is the non-secret room label shown in the discovery list. The
  /// invitation code is never part of it (PLAN.md §6.3).
  Future<int> start({
    required String label,
    Map<String, String> attributes = const <String, String>{},
    int port = 0,
    InternetAddress? address,
  }) async {
    _stopping = false;
    final int boundPort = await hostService.start(
      port: port,
      address: address,
    );

    _connectionSubscription = hostService.onConnection.listen(_accept);
    _startHeartbeat();

    final LanAdvertiserService? service = advertiser;
    if (service != null) {
      await service.start(
        label: label,
        port: boundPort,
        attributes: <String, String>{'app': 'upfleet', ...attributes},
      );
    }
    return boundPort;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      AppProtocol.hostHeartbeatInterval,
      (Timer _) => _broadcastHeartbeat(),
    );
  }

  /// Tells every client that the Host is still alive.
  ///
  /// Clients use this to detect an abrupt Host loss. It carries the current
  /// state version so a client can notice a missed change (PLAN.md §9.5).
  Future<void> _broadcastHeartbeat() async {
    final HostRoomState? room = coordinator.state;
    if (room == null) return;
    for (final ClientSession session
        in coordinator.registry.admittedSessions.toList()) {
      await send(
        session.connectionId,
        ProtocolMessage(
          messageType: HostEventType.heartbeat,
          payload: <String, dynamic>{'stateVersion': room.stateVersion},
        ),
      );
    }
  }

  void _accept(LanHostConnection connection) {
    // The session reuses the connection identifier so that the coordinator
    // can address the socket it belongs to.
    final ClientSession session = ClientSession(
      connectionId: connection.id,
      connectedAt: DateTime.now(),
    );
    _sessions[connection.id] = session;
    _connections[connection.id] = connection;
    coordinator.registry.add(session);

    _frameSubscriptions[connection.id] = connection.frames.listen(
      (ProtocolMessage message) {
        unawaited(coordinator.handleMessage(session, message));
      },
      onDone: () => _handleConnectionClosed(connection.id, session),
      onError: (Object _) => _handleConnectionClosed(connection.id, session),
    );

    // The socket may already be gone when the connection is handed over.
    connection.socket.done.then((_) {
      if (!_stopping) _handleConnectionClosed(connection.id, session);
    }).catchError((Object _) {});
  }

  void _handleConnectionClosed(String connectionId, ClientSession session) {
    final StreamSubscription<ProtocolMessage>? subscription =
        _frameSubscriptions.remove(connectionId);
    unawaited(subscription?.cancel());
    _sessions.remove(connectionId);
    _connections.remove(connectionId);
    session.closed = true;
    coordinator.registry.remove(connectionId);
    coordinator.handleConnectionLost(session);
  }

  void _handleRoomClosed() {
    unawaited(_stopAdvertising());
  }

  // ------------------------------------------------------- RoomTransport

  @override
  Future<void> send(String connectionId, ProtocolMessage message) async {
    _connections[connectionId]?.send(message);
  }

  @override
  Future<void> closeConnection(String connectionId) async {
    final LanHostConnection? connection = _connections[connectionId];
    await connection?.close();

    final ClientSession? session = _sessions[connectionId];
    if (session != null) {
      _handleConnectionClosed(connectionId, session);
    }
  }

  @override
  Future<void> closeAll() async {
    for (final LanHostConnection connection in List.of(
      hostService.connections,
    )) {
      await connection.close();
    }
  }

  // ------------------------------------------------------------ lifecycle

  Future<void> _stopAdvertising() async {
    try {
      await advertiser?.stop();
    } on Object {
      // Advertising is best effort; the room is closing either way.
    }
  }

  /// Stops the advertisement, closes every socket and shuts the listener.
  ///
  /// Called when the Host leaves the room: no client may be left with a
  /// half-open socket and no service may stay advertised (PLAN.md §9.5).
  Future<void> stop() async {
    _stopping = true;
    await _stopAdvertising();

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    for (final StreamSubscription<ProtocolMessage> subscription
        in _frameSubscriptions.values) {
      await subscription.cancel();
    }
    _frameSubscriptions.clear();
    _sessions.clear();
    _connections.clear();
    coordinator.registry.clear();

    await hostService.stop();
  }
}
