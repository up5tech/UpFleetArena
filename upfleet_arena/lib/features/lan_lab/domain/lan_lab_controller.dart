import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/lan_permission_service.dart';
import '../../../shared/protocol/protocol_constants.dart';
import '../../../shared/protocol/protocol_message.dart';
import '../../lan_networking/domain/lan_discovery.dart';
import '../../lan_networking/domain/lan_networking_providers.dart';
import '../../lan_networking/services/frame_codec.dart';
import '../../lan_networking/services/tcp_client_service.dart';
import '../../lan_networking/services/tcp_host_service.dart';
import 'lan_lab_state.dart';

/// Drives the Phase 0 LAN proof of concept.
///
/// It owns the Host listener, the discovery session and the outbound client
/// connection, and records a diagnostic log that makes the transport
/// behaviour visible on a physical device.
class LanLabController extends Notifier<LanLabState> {
  static const int _maxLogEntries = 300;

  TcpClientService? _clientService;  StreamSubscription<LanHostConnection>? _hostConnectionSubscription;
  StreamSubscription<List<DiscoveredRoom>>? _roomsSubscription;
  StreamSubscription<String>? _discoveryDiagnosticsSubscription;
  StreamSubscription<String>? _advertiserDiagnosticsSubscription;
  final Map<String, StreamSubscription<ProtocolMessage>> _hostFrameSubscriptions =
      <String, StreamSubscription<ProtocolMessage>>{};
  final Map<String, DateTime> _pendingPings = <String, DateTime>{};

  @override
  LanLabState build() {
    ref.onDispose(_disposeAll);
    return const LanLabState();
  }

  // ------------------------------------------------------------- logging

  void _log(String message, [LogLevel level = LogLevel.info]) {
    final List<LogEntry> entries = <LogEntry>[
      LogEntry(time: DateTime.now(), level: level, message: message),
      ...state.log,
    ];
    if (entries.length > _maxLogEntries) {
      entries.removeRange(_maxLogEntries, entries.length);
    }
    state = state.copyWith(log: entries);
  }

  // ---------------------------------------------------------- permissions

  /// Checks and, when the platform supports it, requests local-network
  /// access.
  Future<void> checkPermission() async {
    final LanPermissionService service = ref.read(lanPermissionServiceProvider);
    LanPermissionState result = await service.currentState();
    if (result == LanPermissionState.denied) {
      result = await service.request();
    }
    state = state.copyWith(permission: result);
    _log(
      'Local network permission: ${result.name}',
      result == LanPermissionState.granted ? LogLevel.success : LogLevel.warning,
    );
  }

  // -------------------------------------------------------------- backend

  /// Switches the discovery backend and restarts any active session.
  Future<void> selectBackend(DiscoveryBackend backend) async {
    if (backend == state.backend) return;
    await _stopScanning();
    await _stopAdvertising();
    ref.read(discoveryBackendProvider.notifier).select(backend);
    _log('Switched discovery backend to ${backend.label}', LogLevel.info);
  }

  // ----------------------------------------------------------------- host

  /// Opens the TCP listener and starts advertising the room.
  Future<void> startHosting({String label = 'UpFleet Arena Host'}) async {
    if (state.isHosting) return;

    final TcpHostService service = ref.read(tcpHostServiceProvider);
    try {
      final int port = await service.start();
      final List<String> addresses = await _localIpv4Addresses();

      state = state.copyWith(
        isHosting: true,
        hostPort: port,
        hostAddresses: addresses,
        roomLabel: label,
        connectionState: ClientConnectionState.idle,
      );
      _log(
        'TCP listener bound to port $port '
        '(${addresses.isEmpty ? 'no IPv4 address' : addresses.join(', ')})',
        LogLevel.success,
      );

      _hostConnectionSubscription = service.onConnection.listen(
        _handleHostConnection,
      );
      await _startAdvertising(label, port);
    } on Object catch (error) {
      _log('Could not start the TCP listener: $error', LogLevel.error);
      state = state.copyWith(isHosting: false);
    }
  }

  Future<void> _startAdvertising(String label, int port) async {
    final LanAdvertiserService advertiser = ref.read(lanAdvertiserServiceProvider);
    _advertiserDiagnosticsSubscription = advertiser.diagnostics.listen(
      (String line) => _log(line, LogLevel.info),
    );
    try {
      await advertiser.start(
        label: label,
        port: port,
        attributes: const <String, String>{'app': 'upfleet'},
      );
    } on Object catch (error) {
      _log('Advertisement failed: $error', LogLevel.error);
    }
  }

  Future<void> _stopAdvertising() async {
    await _advertiserDiagnosticsSubscription?.cancel();
    _advertiserDiagnosticsSubscription = null;
    try {
      await ref.read(lanAdvertiserServiceProvider).stop();
    } on Object catch (error) {
      _log('Stopping the advertisement failed: $error', LogLevel.warning);
    }
  }

  /// Closes the listener and stops advertising.
  Future<void> stopHosting() async {
    await _stopAdvertising();
    await _hostConnectionSubscription?.cancel();
    _hostConnectionSubscription = null;
    for (final StreamSubscription<ProtocolMessage> subscription
        in _hostFrameSubscriptions.values) {
      await subscription.cancel();
    }
    _hostFrameSubscriptions.clear();
    _pendingPings.clear();

    await ref.read(tcpHostServiceProvider).stop();
    state = state.copyWith(
      isHosting: false,
      hostPort: null,
      clientCount: 0,
    );
    _log('TCP listener closed', LogLevel.info);
  }

  void _handleHostConnection(LanHostConnection connection) {
    state = state.copyWith(clientCount: state.clientCount + 1);
    _log(
      'Client connected: '
      '${connection.remoteAddress?.address ?? 'unknown'}:${connection.remotePort}',
      LogLevel.success,
    );

    final StreamSubscription<ProtocolMessage> subscription = connection.frames
        .listen(
          (ProtocolMessage message) =>
              _handleHostFrame(connection, message),
        );
    _hostFrameSubscriptions[connection.id] = subscription;
  }

  void _handleHostFrame(
    LanHostConnection connection,
    ProtocolMessage message,
  ) {
    state = state.copyWith(framesReceived: state.framesReceived + 1);

    switch (message.messageType) {
      case ClientMessageType.ping:
        final DateTime? sentAt = _pendingPings.remove(message.requestId);
        if (sentAt != null) {
          final Duration elapsed = DateTime.now().difference(sentAt);
          state = state.copyWith(lastRoundTrip: elapsed);
          _log(
            'Round trip of ${elapsed.inMilliseconds} ms with '
            '${connection.remoteAddress?.address ?? 'the client'}',
            LogLevel.success,
          );
        } else {
          _log(
            'Ping received from '
            '${connection.remoteAddress?.address ?? 'a client'}; answering',
            LogLevel.info,
          );
        }
        connection.send(
          ProtocolMessage(
            messageType: HostEventType.pong,
            requestId: message.requestId,
            payload: <String, dynamic>{
              'echo': message.payload['nonce'],
              'receivedAt': DateTime.now().toIso8601String(),
            },
          ),
        );
      case HostEventType.pong:
        final DateTime? sentAt = _pendingPings.remove(message.requestId);
        if (sentAt != null) {
          final Duration elapsed = DateTime.now().difference(sentAt);
          state = state.copyWith(lastRoundTrip: elapsed);
          _log(
            'Host answered the ping in ${elapsed.inMilliseconds} ms',
            LogLevel.success,
          );
        }
      case HostEventType.error:
        _log(
          'Host rejected the frame: '
          '${message.payload['code']} — ${message.payload['message']}',
          LogLevel.error,
        );
      default:
        _log(
          'Frame from the Host: ${message.messageType} '
          '(${message.payload.length} payload fields)',
          LogLevel.info,
        );
    }
  }

  // -------------------------------------------------------------- scanning

  /// Starts scanning for rooms on the local network.
  Future<void> startScanning() async {
    if (state.isScanning) return;

    final LanDiscoveryService service = ref.read(lanDiscoveryServiceProvider);
    _discoveryDiagnosticsSubscription = service.diagnostics.listen(
      (String line) => _log(line, LogLevel.info),
    );
    _roomsSubscription = service.rooms.listen((List<DiscoveredRoom> rooms) {
      state = state.copyWith(rooms: rooms);
      _log('Discovered ${rooms.length} room(s)', LogLevel.info);
    });

    try {
      await service.start();
      state = state.copyWith(isScanning: true);
      _log(
        'Scanning for ${AppProtocol.serviceType} with '
        '${state.backend.label}',
        LogLevel.info,
      );
    } on Object catch (error) {
      _log('Discovery failed to start: $error', LogLevel.error);
      state = state.copyWith(isScanning: false);
    }
  }

  Future<void> _stopScanning() async {
    await _roomsSubscription?.cancel();
    _roomsSubscription = null;
    await _discoveryDiagnosticsSubscription?.cancel();
    _discoveryDiagnosticsSubscription = null;
    try {
      await ref.read(lanDiscoveryServiceProvider).stop();
    } on Object catch (error) {
      _log('Stopping discovery failed: $error', LogLevel.warning);
    }
    state = state.copyWith(isScanning: false, rooms: const <DiscoveredRoom>[]);
  }

  /// Stops scanning.
  Future<void> stopScanning() => _stopScanning();

  // ---------------------------------------------------------------- client

  /// Connects to a discovered room and performs a ping/pong exchange.
  Future<void> connectTo(DiscoveredRoom room) async {
    await disconnect();

    final InternetAddress? address = room.preferredAddress;
    if (address == null) {
      _log(
        'The room "${room.label}" has no resolved IP address. '
        'Use the manual connection form instead.',
        LogLevel.warning,
      );
      state = state.copyWith(connectionState: ClientConnectionState.failed);
      return;
    }

    final TcpClientService service = TcpClientService();
    _clientService = service;
    state = state.copyWith(connectionState: ClientConnectionState.connecting);

    service.errors.listen((ProtocolError error) {
      _log('Client error: ${error.code} — ${error.message}', LogLevel.error);
      state = state.copyWith(connectionState: ClientConnectionState.failed);
    });
    service.frames.listen((ProtocolMessage message) {
      state = state.copyWith(framesReceived: state.framesReceived + 1);
      if (message.messageType == HostEventType.pong) {
        final DateTime? sentAt = _pendingPings.remove(message.requestId);
        if (sentAt != null) {
          final Duration elapsed = DateTime.now().difference(sentAt);
          state = state.copyWith(lastRoundTrip: elapsed);
          _log(
            'Host answered the ping in ${elapsed.inMilliseconds} ms',
            LogLevel.success,
          );
        }
      } else if (message.messageType == HostEventType.error) {
        _log(
          'Host rejected the frame: '
          '${message.payload['code']} — ${message.payload['message']}',
          LogLevel.error,
        );
      } else {
        _log('Event from the Host: ${message.messageType}', LogLevel.info);
      }
    });

    try {
      await service.connect(address, room.port);
      state = state.copyWith(connectionState: ClientConnectionState.connected);
      _log(
        'Connected to ${room.label} at ${address.address}:${room.port}',
        LogLevel.success,
      );
      await sendPing();
    } on Object catch (error) {
      _log(
        'Could not connect to ${room.label} at ${address.address}:${room.port}. '
        '$error\n'
        'Check that both devices are on the same Wi-Fi and that the router '
        'does not isolate clients.',
        LogLevel.error,
      );
      state = state.copyWith(connectionState: ClientConnectionState.failed);
    }
  }

  /// Connects to a manually entered endpoint.
  Future<void> connectManually(String host, int port) async {
    await disconnect();

    final InternetAddress? address = InternetAddress.tryParse(host);
    if (address == null) {
      _log('"$host" is not a valid IP address.', LogLevel.error);
      state = state.copyWith(connectionState: ClientConnectionState.failed);
      return;
    }

    final TcpClientService service = TcpClientService();
    _clientService = service;
    state = state.copyWith(connectionState: ClientConnectionState.connecting);

    service.errors.listen((ProtocolError error) {
      _log('Client error: ${error.code} — ${error.message}', LogLevel.error);
      state = state.copyWith(connectionState: ClientConnectionState.failed);
    });
    service.frames.listen((ProtocolMessage message) {
      state = state.copyWith(framesReceived: state.framesReceived + 1);
      if (message.messageType == HostEventType.pong) {
        final DateTime? sentAt = _pendingPings.remove(message.requestId);
        if (sentAt != null) {
          final Duration elapsed = DateTime.now().difference(sentAt);
          state = state.copyWith(lastRoundTrip: elapsed);
          _log(
            'Host answered the ping in ${elapsed.inMilliseconds} ms',
            LogLevel.success,
          );
        }
      } else if (message.messageType == HostEventType.error) {
        _log(
          'Host rejected the frame: '
          '${message.payload['code']} — ${message.payload['message']}',
          LogLevel.error,
        );
      }
    });

    try {
      await service.connect(address, port);
      state = state.copyWith(connectionState: ClientConnectionState.connected);
      _log('Connected to $host:$port', LogLevel.success);
      await sendPing();
    } on Object catch (error) {
      _log(
        'Could not connect to $host:$port. $error\n'
        'Check that both devices are on the same Wi-Fi and that the router '
        'does not isolate clients.',
        LogLevel.error,
      );
      state = state.copyWith(connectionState: ClientConnectionState.failed);
    }
  }

  /// Sends a ping and waits for the matching pong.
  Future<void> sendPing() async {
    final TcpClientService? service = _clientService;
    if (service == null || !service.isConnected) {
      _log('Not connected to a Host; nothing to ping.', LogLevel.warning);
      return;
    }
    final String requestId = 'ping-${DateTime.now().microsecondsSinceEpoch}';
    _pendingPings[requestId] = DateTime.now();
    service.send(
      ProtocolMessage(
        messageType: ClientMessageType.ping,
        requestId: requestId,
        payload: <String, dynamic>{
          'nonce': requestId,
          'sentAt': DateTime.now().toIso8601String(),
        },
      ),
    );
    state = state.copyWith(framesSent: state.framesSent + 1);
    _log('Ping sent', LogLevel.info);
  }

  /// Sends one frame split across several writes to prove that the receiver
  /// handles partial frames correctly (PLAN.md §6.4).
  Future<void> sendSplitFrame() async {
    final TcpClientService? service = _clientService;
    if (service == null || !service.isConnected) {
      _log('Not connected to a Host; nothing to send.', LogLevel.warning);
      return;
    }

    // A payload well above one TCP segment so the frame is genuinely split.
    final String filler = 'x' * 4000;
    final String requestId = 'split-${DateTime.now().microsecondsSinceEpoch}';
    final List<int> frame = FrameCodec.encode(
      ProtocolMessage(
        messageType: ClientMessageType.ping,
        requestId: requestId,
        payload: <String, dynamic>{
          'nonce': requestId,
          'filler': filler,
          'sentAt': DateTime.now().toIso8601String(),
        },
      ).toJson(),
    );

    final int third = frame.length ~/ 3;
    service.sendRaw(frame.sublist(0, third));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    service.sendRaw(frame.sublist(third, third * 2));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    service.sendRaw(frame.sublist(third * 2));

    state = state.copyWith(framesSent: state.framesSent + 1);
    _log(
      'Sent a ${frame.length}-byte frame in 3 chunks; the Host must decode '
      'exactly one complete message.',
      LogLevel.info,
    );
  }

  /// Sends a frame whose declared length exceeds the transport limit.
  ///
  /// The Host must answer with a `protocol:error` carrying
  /// `FRAME_TOO_LARGE` and close the connection.
  Future<void> sendOversizedFrame() async {
    final TcpClientService? service = _clientService;
    if (service == null || !service.isConnected) {
      _log('Not connected to a Host; nothing to send.', LogLevel.warning);
      return;
    }
    final List<int> header = <int>[
      (FrameCodec.maxPayloadBytes + 1) >> 24 & 0xFF,
      (FrameCodec.maxPayloadBytes + 1) >> 16 & 0xFF,
      (FrameCodec.maxPayloadBytes + 1) >> 8 & 0xFF,
      (FrameCodec.maxPayloadBytes + 1) & 0xFF,
    ];
    service.sendRaw(header);
    state = state.copyWith(framesSent: state.framesSent + 1);
    _log(
      'Sent a frame declaring ${FrameCodec.maxPayloadBytes + 1} bytes; '
      'expect a FRAME_TOO_LARGE error.',
      LogLevel.warning,
    );
  }

  /// Sends a frame whose payload is not valid JSON.
  Future<void> sendMalformedFrame() async {
    final TcpClientService? service = _clientService;
    if (service == null || !service.isConnected) {
      _log('Not connected to a Host; nothing to send.', LogLevel.warning);
      return;
    }
    final List<int> body = '{not-json'.codeUnits;
    final List<int> frame = <int>[
      body.length >> 24 & 0xFF,
      body.length >> 16 & 0xFF,
      body.length >> 8 & 0xFF,
      body.length & 0xFF,
      ...body,
    ];
    service.sendRaw(frame);
    state = state.copyWith(framesSent: state.framesSent + 1);
    _log('Sent a malformed frame; expect a MALFORMED_FRAME error.', LogLevel.warning);
  }

  /// Closes the outbound client connection.
  Future<void> disconnect() async {
    final TcpClientService? service = _clientService;
    _clientService = null;
    _pendingPings.clear();
    if (service != null) {
      await service.close();
      _log('Client connection closed', LogLevel.info);
    }
    state = state.copyWith(connectionState: ClientConnectionState.idle);
  }

  /// Stops everything this controller owns.
  Future<void> shutdown() async {
    await disconnect();
    await _stopScanning();
    await stopHosting();
  }

  void _disposeAll() {
    unawaited(_clientService?.close());
    _clientService = null;
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

/// The LAN Lab controller.
final lanLabControllerProvider = NotifierProvider<LanLabController, LanLabState>(
  LanLabController.new,
);
