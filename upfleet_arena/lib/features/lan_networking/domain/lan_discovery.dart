import 'dart:io';

/// Which mDNS/Bonjour implementation backs a discovery service.
///
/// Phase 0 keeps both candidates alive so they can be compared on physical
/// Android and iOS devices before the project commits to one
/// (PLAN.md §15, Phase 0).
enum DiscoveryBackend {
  /// `bonsoir` package.
  bonsoir('Bonsoir'),

  /// `nsd` package.
  nsd('NSD');

  const DiscoveryBackend(this.label);

  /// Display name used in the diagnostics UI.
  final String label;
}

/// A room advertised by a Host on the local network.
///
/// The invitation code is intentionally absent: it travels only inside the
/// TCP handshake, never through discovery metadata, because every device on
/// the LAN can inspect mDNS announcements (PLAN.md §6.3 step 4).
class DiscoveredRoom {
  DiscoveredRoom({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.addresses,
    required this.attributes,
    required this.backend,
  });

  /// Stable key used to deduplicate rooms across discovery events.
  final String id;

  /// Human-readable room or Host label shown in the room list.
  final String label;

  /// Resolved hostname, usually `*.local`. May be empty.
  final String host;

  /// TCP port the Host is listening on.
  final int port;

  /// Resolved IP addresses. Prefer IPv4 for the first release (PLAN.md §11.3).
  final List<InternetAddress> addresses;

  /// DNS-SD TXT attributes.
  final Map<String, String> attributes;

  /// Which backend produced this entry.
  final DiscoveryBackend backend;

  /// Returns the first IPv4 address, or `null` when none was resolved.
  InternetAddress? get ipv4 {
    for (final InternetAddress address in addresses) {
      if (address.type == InternetAddressType.IPv4) return address;
    }
    return null;
  }

  /// Returns the first usable address, preferring IPv4.
  InternetAddress? get preferredAddress => ipv4 ??
      (addresses.isEmpty ? null : addresses.first);

  @override
  String toString() =>
      'DiscoveredRoom($label @ ${host.isEmpty ? '?' : host}:$port, '
      '${addresses.length} addr)';
}

/// Discovers UpFleet rooms advertised on the local network.
abstract class LanDiscoveryService {
  /// Emits the full list of currently visible rooms whenever it changes.
  Stream<List<DiscoveredRoom>> get rooms;

  /// Emits human-readable diagnostic lines for the debug panel.
  Stream<String> get diagnostics;

  /// Starts scanning. Safe to call when already running.
  Future<void> start();

  /// Stops scanning but keeps the service reusable.
  Future<void> stop();

  /// Releases every resource held by the service.
  Future<void> dispose();
}

/// Advertises the local Host room on the local network.
abstract class LanAdvertiserService {
  /// Emits human-readable diagnostic lines for the debug panel.
  Stream<String> get diagnostics;

  /// Starts advertising [label] on [port].
  ///
  /// [attributes] must never contain the invitation code or any other secret
  /// (PLAN.md §6.3 step 4).
  Future<void> start({
    required String label,
    required int port,
    Map<String, String> attributes = const <String, String>{},
  });

  /// Stops advertising and releases the registration.
  Future<void> stop();
}
