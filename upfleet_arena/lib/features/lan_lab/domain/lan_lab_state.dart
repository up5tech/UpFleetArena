import 'package:flutter/foundation.dart';

import '../../lan_networking/domain/lan_discovery.dart';
import '../../../core/permissions/lan_permission_service.dart';

/// Severity of a diagnostic line in the LAN Lab log.
enum LogLevel { info, success, warning, error }

/// A single diagnostic line.
@immutable
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
  });

  /// Wall-clock time the entry was recorded.
  final DateTime time;

  /// Severity.
  final LogLevel level;

  /// Message shown in the log.
  final String message;

  /// `HH:MM:SS` representation used by the log list.
  String get timestamp =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

/// Immutable snapshot of the LAN Lab proof-of-concept state.
@immutable
class LanLabState {
  const LanLabState({
    this.backend = DiscoveryBackend.bonsoir,
    this.permission = LanPermissionState.unknown,
    this.isHosting = false,
    this.hostPort,
    this.hostAddresses = const <String>[],
    this.roomLabel = '',
    this.isScanning = false,
    this.rooms = const <DiscoveredRoom>[],
    this.clientCount = 0,
    this.lastRoundTrip,
    this.framesSent = 0,
    this.framesReceived = 0,
    this.connectionState = ClientConnectionState.idle,
    this.log = const <LogEntry>[],
  });

  /// Which discovery implementation is currently active.
  final DiscoveryBackend backend;

  /// Result of the last local-network permission check.
  final LanPermissionState permission;

  /// Whether the TCP listener is running.
  final bool isHosting;

  /// Port the Host is listening on.
  final int? hostPort;

  /// Local IPv4 addresses, shown so a tester can connect manually.
  final List<String> hostAddresses;

  /// Label advertised to other devices.
  final String roomLabel;

  /// Whether discovery is running.
  final bool isScanning;

  /// Rooms currently visible on the network.
  final List<DiscoveredRoom> rooms;

  /// Number of clients connected to the Host listener.
  final int clientCount;

  /// Round-trip time of the last ping/pong exchange.
  final Duration? lastRoundTrip;

  /// Number of frames sent by this device.
  final int framesSent;

  /// Number of frames received by this device.
  final int framesReceived;

  /// State of the outbound client connection.
  final ClientConnectionState connectionState;

  /// Diagnostic log, newest first.
  final List<LogEntry> log;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields use a sentinel so an explicit `null` clears the value
  /// instead of keeping the previous one.
  LanLabState copyWith({
    DiscoveryBackend? backend,
    LanPermissionState? permission,
    bool? isHosting,
    Object? hostPort = _unset,
    List<String>? hostAddresses,
    String? roomLabel,
    bool? isScanning,
    List<DiscoveredRoom>? rooms,
    int? clientCount,
    Object? lastRoundTrip = _unset,
    int? framesSent,
    int? framesReceived,
    ClientConnectionState? connectionState,
    List<LogEntry>? log,
  }) => LanLabState(
    backend: backend ?? this.backend,
    permission: permission ?? this.permission,
    isHosting: isHosting ?? this.isHosting,
    hostPort: identical(hostPort, _unset) ? this.hostPort : hostPort as int?,
    hostAddresses: hostAddresses ?? this.hostAddresses,
    roomLabel: roomLabel ?? this.roomLabel,
    isScanning: isScanning ?? this.isScanning,
    rooms: rooms ?? this.rooms,
    clientCount: clientCount ?? this.clientCount,
    lastRoundTrip: identical(lastRoundTrip, _unset)
        ? this.lastRoundTrip
        : lastRoundTrip as Duration?,
    framesSent: framesSent ?? this.framesSent,
    framesReceived: framesReceived ?? this.framesReceived,
    connectionState: connectionState ?? this.connectionState,
    log: log ?? this.log,
  );

  static const Object _unset = Object();
}

/// State of the outbound client connection in the proof of concept.
enum ClientConnectionState {
  /// No client connection has been opened.
  idle,

  /// A connection attempt is in progress.
  connecting,

  /// Connected to a Host.
  connected,

  /// The connection failed or was lost.
  failed,
}
