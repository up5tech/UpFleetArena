import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart';

import '../../../shared/protocol/protocol_constants.dart';
import '../domain/lan_discovery.dart';

/// NSD-backed mDNS/Bonjour discovery and advertisement.
///
/// This is the alternative candidate to Bonsoir. Phase 0 keeps both so the
/// team can compare discovery reliability, startup latency and permission
/// behaviour on physical Android and iOS devices before committing to one
/// implementation (PLAN.md §15, Phase 0).
class NsdDiscoveryService implements LanDiscoveryService {
  NsdDiscoveryService();

  final StreamController<List<DiscoveredRoom>> _roomsController =
      StreamController<List<DiscoveredRoom>>.broadcast();
  final StreamController<String> _diagnosticsController =
      StreamController<String>.broadcast();

  Discovery? _discovery;
  bool _disposed = false;

  @override
  Stream<List<DiscoveredRoom>> get rooms => _roomsController.stream;

  @override
  Stream<String> get diagnostics => _diagnosticsController.stream;

  @override
  Future<void> start() async {
    if (_discovery != null) return;

    // `autoResolve` gives us the resolved addresses and port without a
    // second round trip; `IpLookupType.any` returns IPv4 and IPv6 so the
    // client can pick the reachable one (PLAN.md §11.3).
    final discovery = await startDiscovery(
      AppProtocol.serviceType,
      autoResolve: true,
      ipLookupType: IpLookupType.any,
    );
    _discovery = discovery;

    _diagnosticsController.add(
      'NSD discovery started for ${AppProtocol.serviceType}',
    );

    discovery.addListener(() => _emitRooms(discovery.services));
    _emitRooms(discovery.services);
  }

  void _emitRooms(List<Service> services) {
    if (_disposed || _roomsController.isClosed) return;

    final List<DiscoveredRoom> rooms = <DiscoveredRoom>[];
    for (final Service service in services) {
      rooms.add(
        DiscoveredRoom(
          id: 'nsd:${service.name}|${service.type}',
          label: service.name ?? 'Unknown room',
          host: service.host ?? '',
          port: service.port ?? 0,
          addresses: service.addresses ?? const <InternetAddress>[],
          attributes: _attributesOf(service),
          backend: DiscoveryBackend.nsd,
        ),
      );
    }
    rooms.sort(
      (DiscoveredRoom a, DiscoveredRoom b) =>
          a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    _roomsController.add(rooms);
  }

  @override
  Future<void> stop() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      await stopDiscovery(discovery);
    }
    _diagnosticsController.add('NSD discovery stopped');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _roomsController.close();
    await _diagnosticsController.close();
  }
}

/// NSD-backed advertisement of the local Host room.
class NsdAdvertiserService implements LanAdvertiserService {
  NsdAdvertiserService();

  final StreamController<String> _diagnosticsController =
      StreamController<String>.broadcast();

  Registration? _registration;

  @override
  Stream<String> get diagnostics => _diagnosticsController.stream;

  @override
  Future<void> start({
    required String label,
    required int port,
    Map<String, String> attributes = const <String, String>{},
  }) async {
    if (_registration != null) {
      throw StateError('NSD advertisement is already running.');
    }

    final service = Service(
      name: label,
      type: AppProtocol.serviceType,
      port: port,
      txt: _txtOf(attributes),
    );

    final registration = await register(service);
    _registration = registration;
    _diagnosticsController.add(
      'NSD advertising "$label" as ${AppProtocol.serviceType} on port $port',
    );
  }

  @override
  Future<void> stop() async {
    final registration = _registration;
    _registration = null;
    if (registration != null) {
      await unregister(registration);
    }
    _diagnosticsController.add('NSD advertisement stopped');
  }
}

/// Converts plain attributes into the DNS-SD TXT record map used by nsd.
///
/// Keys are limited to nine printable ASCII characters and values are raw
/// bytes, per RFC 6763.
Map<String, Uint8List?> _txtOf(Map<String, String> attributes) {
  final Map<String, Uint8List?> txt = <String, Uint8List?>{};
  for (final MapEntry<String, String> entry in attributes.entries) {
    final String key = entry.key.length <= 9 ? entry.key : entry.key.substring(0, 9);
    txt[key] = Uint8List.fromList(entry.value.codeUnits);
  }
  txt['v'] = Uint8List.fromList(AppProtocol.version.toString().codeUnits);
  return txt;
}

/// Converts a TXT record map back into plain attributes.
Map<String, String> _attributesOf(Service service) {
  final Map<String, String> attributes = <String, String>{};
  final Map<String, Uint8List?>? txt = service.txt;
  if (txt == null) return attributes;
  for (final MapEntry<String, Uint8List?> entry in txt.entries) {
    final Uint8List? value = entry.value;
    if (value == null) {
      attributes[entry.key] = '';
      continue;
    }
    attributes[entry.key] = String.fromCharCodes(value);
  }
  return attributes;
}
