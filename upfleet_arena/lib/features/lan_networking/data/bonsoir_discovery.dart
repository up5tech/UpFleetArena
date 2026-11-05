import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

import '../../../shared/protocol/protocol_constants.dart';
import '../domain/lan_discovery.dart';

/// Bonsoir-backed mDNS/Bonjour discovery and advertisement.
///
/// Bonsoir normalizes the service type and attributes per RFC 6335, which
/// keeps the advertisement compatible with iOS, Android and desktop
/// resolvers.
class BonsoirDiscoveryService implements LanDiscoveryService {
  BonsoirDiscoveryService();

  final StreamController<List<DiscoveredRoom>> _roomsController =
      StreamController<List<DiscoveredRoom>>.broadcast();
  final StreamController<String> _diagnosticsController =
      StreamController<String>.broadcast();

  final Map<String, DiscoveredRoom> _rooms = <String, DiscoveredRoom>{};
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySubscription;

  @override
  Stream<List<DiscoveredRoom>> get rooms => _roomsController.stream;

  @override
  Stream<String> get diagnostics => _diagnosticsController.stream;

  @override
  Future<void> start() async {
    if (_discovery != null) return;

    final discovery = BonsoirDiscovery(type: AppProtocol.serviceType);
    _discovery = discovery;
    await discovery.initialize();
    await discovery.start();

    _diagnosticsController.add(
      'Bonsoir discovery started for ${AppProtocol.serviceType}',
    );

    _discoverySubscription = discovery.eventStream?.listen(
      _handleEvent,
      onError: (Object error) =>
          _diagnosticsController.add('Bonsoir discovery error: $error'),
    );
  }

  void _handleEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        _diagnosticsController.add('Bonsoir found: ${event.service.name}');
        _upsert(event.service);
      case BonsoirDiscoveryServiceResolvedEvent():
        _diagnosticsController.add(
          'Bonsoir resolved: ${event.service.name} '
          '@ ${event.service.hostAddresses.join(', ')}',
        );
        _upsert(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        _upsert(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        _diagnosticsController.add('Bonsoir lost: ${event.service.name}');
        _remove(event.service);
      case BonsoirDiscoveryStartedEvent():
      case BonsoirDiscoveryServiceResolveFailedEvent():
      case BonsoirDiscoveryStoppedEvent():
      case BonsoirDiscoveryUnknownEvent():
        break;
    }
  }

  void _upsert(BonsoirService service) {
    final room = _toRoom(service);
    _rooms[room.id] = room;
    _emitRooms();
  }

  void _remove(BonsoirService service) {
    final id = _keyOf(service);
    _rooms.remove(id);
    _emitRooms();
  }

  void _emitRooms() {
    if (_roomsController.isClosed) return;
    final List<DiscoveredRoom> sorted = _rooms.values.toList()
      ..sort((DiscoveredRoom a, DiscoveredRoom b) =>
          a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    _roomsController.add(sorted);
  }

  @override
  Future<void> stop() async {
    final subscription = _discoverySubscription;
    _discoverySubscription = null;
    await subscription?.cancel();

    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      await discovery.stop();
    }
    _rooms.clear();
    _emitRooms();
    _diagnosticsController.add('Bonsoir discovery stopped');
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _roomsController.close();
    await _diagnosticsController.close();
  }
}

/// Bonsoir-backed advertisement of the local Host room.
class BonsoirAdvertiserService implements LanAdvertiserService {
  BonsoirAdvertiserService();

  final StreamController<String> _diagnosticsController =
      StreamController<String>.broadcast();

  BonsoirBroadcast? _broadcast;
  StreamSubscription<BonsoirBroadcastEvent>? _subscription;

  @override
  Stream<String> get diagnostics => _diagnosticsController.stream;

  @override
  Future<void> start({
    required String label,
    required int port,
    Map<String, String> attributes = const <String, String>{},
  }) async {
    if (_broadcast != null) {
      throw StateError('Bonsoir advertisement is already running.');
    }

    final service = BonsoirService(
      name: label,
      type: AppProtocol.serviceType,
      port: port,
      attributes: <String, String>{
        ...attributes,
        'v': AppProtocol.version.toString(),
      },
    );

    final broadcast = BonsoirBroadcast(service: service);
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();

    _subscription = broadcast.eventStream?.listen(
      (BonsoirBroadcastEvent event) {
        if (event is BonsoirBroadcastStartedEvent) {
          _diagnosticsController.add(
            'Bonsoir advertising "${service.name}" as ${service.type} '
            'on port $port',
          );
        } else if (event is BonsoirBroadcastNameAlreadyExistsEvent) {
          _diagnosticsController.add(
            'Bonsoir name conflict for "${service.name}"; the OS renamed it.',
          );
        }
      },
      onError: (Object error) =>
          _diagnosticsController.add('Bonsoir advertisement error: $error'),
    );
  }

  @override
  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast != null) {
      await broadcast.stop();
    }
    _diagnosticsController.add('Bonsoir advertisement stopped');
  }
}

/// Converts a Bonsoir service into the internal room model.
DiscoveredRoom _toRoom(BonsoirService service) {
  final List<InternetAddress> addresses = <InternetAddress>[];
  for (final String raw in service.hostAddresses) {
    final InternetAddress? parsed = InternetAddress.tryParse(raw);
    if (parsed != null) addresses.add(parsed);
  }
  return DiscoveredRoom(
    id: 'bonsoir:${_keyOf(service)}',
    label: service.name,
    host: service.hostname ?? '',
    port: service.port,
    addresses: addresses,
    attributes: service.attributes,
    backend: DiscoveryBackend.bonsoir,
  );
}

String _keyOf(BonsoirService service) => '${service.name}|${service.type}';
