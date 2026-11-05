import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/lan_permission_service.dart';
import '../data/bonsoir_discovery.dart';
import '../data/nsd_discovery.dart';
import '../services/tcp_host_service.dart';
import 'lan_discovery.dart';

/// Selects the discovery implementation under evaluation.
///
/// Phase 0 keeps both candidates alive so they can be compared on physical
/// devices. The final choice is recorded in
/// `docs/adr/ADR-001-lan-discovery-and-tcp-framing.md`.
class DiscoveryBackendController extends Notifier<DiscoveryBackend> {
  @override
  DiscoveryBackend build() => DiscoveryBackend.bonsoir;

  /// Switches the active backend.
  void select(DiscoveryBackend backend) => state = backend;
}

/// The discovery backend used by the app.
final discoveryBackendProvider =
    NotifierProvider<DiscoveryBackendController, DiscoveryBackend>(
      DiscoveryBackendController.new,
    );

/// Local-network permission service.
final lanPermissionServiceProvider = Provider<LanPermissionService>(
  (Ref ref) => const LanPermissionService(),
);

/// Discovery service bound to the selected backend.
final lanDiscoveryServiceProvider = Provider<LanDiscoveryService>((Ref ref) {
  final DiscoveryBackend backend = ref.watch(discoveryBackendProvider);
  final LanDiscoveryService service = switch (backend) {
    DiscoveryBackend.bonsoir => BonsoirDiscoveryService(),
    DiscoveryBackend.nsd => NsdDiscoveryService(),
  };
  ref.onDispose(service.dispose);
  return service;
});

/// Advertiser bound to the selected backend.
final lanAdvertiserServiceProvider = Provider<LanAdvertiserService>((Ref ref) {
  final DiscoveryBackend backend = ref.watch(discoveryBackendProvider);
  final LanAdvertiserService service = switch (backend) {
    DiscoveryBackend.bonsoir => BonsoirAdvertiserService(),
    DiscoveryBackend.nsd => NsdAdvertiserService(),
  };
  ref.onDispose(() => service.stop());
  return service;
});

/// The TCP listener owned by the Host.
final tcpHostServiceProvider = Provider<TcpHostService>((Ref ref) {
  final TcpHostService service = TcpHostService();
  ref.onDispose(() => service.dispose());
  return service;
});
