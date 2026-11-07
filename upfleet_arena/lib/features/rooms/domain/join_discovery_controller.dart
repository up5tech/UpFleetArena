import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/lan_permission_service.dart';
import '../../lan_networking/domain/lan_discovery.dart';
import '../../lan_networking/domain/lan_networking_providers.dart';

/// The result of a discovery scan.
@immutable
class JoinDiscoveryState {
  const JoinDiscoveryState({
    this.isScanning = false,
    this.rooms = const <DiscoveredRoom>[],
    this.errorMessage,
    this.permission = LanPermissionState.unknown,
  });

  /// Whether the scan is running.
  final bool isScanning;

  /// The rooms currently visible on the network.
  final List<DiscoveredRoom> rooms;

  /// Why the scan failed, when it did.
  final String? errorMessage;

  /// The local-network permission state observed for this scan.
  final LanPermissionState permission;

  /// Returns a copy with the given fields replaced.
  JoinDiscoveryState copyWith({
    bool? isScanning,
    List<DiscoveredRoom>? rooms,
    String? errorMessage,
    LanPermissionState? permission,
  }) => JoinDiscoveryState(
    isScanning: isScanning ?? this.isScanning,
    rooms: rooms ?? this.rooms,
    errorMessage: errorMessage ?? this.errorMessage,
    permission: permission ?? this.permission,
  );
}

/// Scans the local network for UpFleet rooms.
class JoinDiscoveryController extends Notifier<JoinDiscoveryState> {
  StreamSubscription<List<DiscoveredRoom>>? _roomsSubscription;
  StreamSubscription<String>? _diagnosticsSubscription;

  @override
  JoinDiscoveryState build() {
    ref.onDispose(() {
      unawaited(_roomsSubscription?.cancel());
      unawaited(_diagnosticsSubscription?.cancel());
    });
    return const JoinDiscoveryState();
  }

  /// Starts scanning.
  ///
  /// The local-network permission is checked (and requested when the platform
  /// supports an explicit request) before any discovery call, so a denied
  /// permission surfaces as a readable state instead of a silent failure
  /// (PLAN.md §11, §5.4).
  Future<void> start() async {
    if (state.isScanning) return;

    final LanPermissionService permissionService = ref.read(
      lanPermissionServiceProvider,
    );
    LanPermissionState permission = await permissionService.currentState();
    if (permission == LanPermissionState.denied) {
      permission = await permissionService.request();
    }
    state = state.copyWith(permission: permission);

    if (permission == LanPermissionState.denied ||
        permission == LanPermissionState.permanentlyDenied) {
      state = state.copyWith(
        isScanning: false,
        rooms: const <DiscoveredRoom>[],
        errorMessage: permissionService.messageFor(permission),
      );
      return;
    }

    final LanDiscoveryService service = ref.read(lanDiscoveryServiceProvider);

    _roomsSubscription = service.rooms.listen((List<DiscoveredRoom> rooms) {
      state = state.copyWith(rooms: rooms);
    });
    _diagnosticsSubscription = service.diagnostics.listen((String _) {
      // Diagnostics are intentionally not surfaced in the join flow; the LAN
      // Lab shows them.
    });

    try {
      await service.start();
      state = state.copyWith(isScanning: true, errorMessage: null);
    } on Object catch (error) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Discovery could not start. $error',
      );
    }
  }

  /// Stops scanning.
  Future<void> stop() async {
    await _roomsSubscription?.cancel();
    _roomsSubscription = null;
    await _diagnosticsSubscription?.cancel();
    _diagnosticsSubscription = null;

    try {
      await ref.read(lanDiscoveryServiceProvider).stop();
    } on Object catch (error) {
      state = state.copyWith(errorMessage: 'Discovery could not stop. $error');
    }
    state = state.copyWith(isScanning: false, rooms: const <DiscoveredRoom>[]);
  }
}

/// The discovery scan used by the join flow.
final joinDiscoveryControllerProvider =
    NotifierProvider<JoinDiscoveryController, JoinDiscoveryState>(
      JoinDiscoveryController.new,
    );
