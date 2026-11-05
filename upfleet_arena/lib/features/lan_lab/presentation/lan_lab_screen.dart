import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/permissions/lan_permission_service.dart';
import '../../lan_networking/domain/lan_discovery.dart';
import '../domain/lan_lab_controller.dart';
import '../domain/lan_lab_state.dart';

/// Phase 0 proof-of-concept screen.
///
/// It proves, on real devices, that two phones can discover each other over
/// mDNS/Bonjour and exchange framed messages over a direct TCP connection
/// without any backend or Internet access (PLAN.md §15, Phase 0).
class LanLabScreen extends ConsumerStatefulWidget {
  const LanLabScreen({super.key});

  @override
  ConsumerState<LanLabScreen> createState() => _LanLabScreenState();
}

class _LanLabScreenState extends ConsumerState<LanLabScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '4040',
  );

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LanLabState state = ref.watch(lanLabControllerProvider);
    final LanLabController controller = ref.read(
      lanLabControllerProvider.notifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Lab'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Shut everything down',
            onPressed: () => controller.shutdown(),
            icon: const Icon(Icons.power_settings_new),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            _PermissionCard(state: state),
            const SizedBox(height: 12),
            _BackendCard(state: state, controller: controller),
            const SizedBox(height: 12),
            _HostCard(state: state, controller: controller),
            const SizedBox(height: 12),
            _DiscoveryCard(state: state, controller: controller),
            const SizedBox(height: 12),
            _ManualConnectCard(
              state: state,
              controller: controller,
              hostController: _hostController,
              portController: _portController,
            ),
            const SizedBox(height: 12),
            _DiagnosticsCard(state: state, controller: controller),
            const SizedBox(height: 12),
            _LogCard(state: state),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 20, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends ConsumerWidget {
  const _PermissionCard({required this.state});

  final LanLabState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LanPermissionService service = ref.read(lanPermissionServiceProvider);
    final LanPermissionState permission = state.permission;

    final Color color = switch (permission) {
      LanPermissionState.granted => AppTheme.accent,
      LanPermissionState.implicit => AppTheme.sunk,
      LanPermissionState.denied ||
      LanPermissionState.permanentlyDenied => AppTheme.danger,
      LanPermissionState.unknown => AppTheme.textSecondary,
    };

    return _SectionCard(
      title: 'Local network access',
      icon: Icons.wifi_tethering,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  permission.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            service.messageFor(permission),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(lanLabControllerProvider.notifier).checkPermission(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Check permission'),
              ),
              if (permission == LanPermissionState.permanentlyDenied)
                OutlinedButton.icon(
                  onPressed: () => service.openSettings(),
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Open settings'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'If discovery finds nothing: ${service.troubleshootingSteps.join(' ')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendCard extends ConsumerWidget {
  const _BackendCard({required this.state, required this.controller});

  final LanLabState state;
  final LanLabController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Discovery backend',
      icon: Icons.compare_arrows,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<DiscoveryBackend>(
            segments: const <ButtonSegment<DiscoveryBackend>>[
              ButtonSegment<DiscoveryBackend>(
                value: DiscoveryBackend.bonsoir,
                label: Text('Bonsoir'),
              ),
              ButtonSegment<DiscoveryBackend>(
                value: DiscoveryBackend.nsd,
                label: Text('NSD'),
              ),
            ],
            selected: <DiscoveryBackend>{state.backend},
            onSelectionChanged: (Set<DiscoveryBackend> selection) =>
                controller.selectBackend(selection.first),
          ),
          const SizedBox(height: 10),
          Text(
            'Both candidates are wired up so they can be compared on physical '
            'devices before the project commits to one. The choice is '
            'recorded in the Phase 0 ADR.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _HostCard extends ConsumerWidget {
  const _HostCard({required this.state, required this.controller});

  final LanLabState state;
  final LanLabController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Host',
      icon: Icons.router,
      trailing: state.isHosting
          ? _StatusChip(label: 'listening', color: AppTheme.accent)
          : _StatusChip(label: 'idle', color: AppTheme.textSecondary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (state.isHosting) ...<Widget>[
            _KeyValue(label: 'Port', value: '${state.hostPort}'),
            _KeyValue(
              label: 'Local IPv4',
              value: state.hostAddresses.isEmpty
                  ? 'none found'
                  : state.hostAddresses.join(', '),
            ),
            _KeyValue(label: 'Clients', value: '${state.clientCount}'),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: () => state.isHosting
                ? controller.stopHosting()
                : controller.startHosting(),
            icon: Icon(
              state.isHosting ? Icons.stop : Icons.play_arrow,
              size: 20,
            ),
            label: Text(state.isHosting ? 'Stop hosting' : 'Start hosting'),
          ),
          const SizedBox(height: 8),
          Text(
            'The Host binds an ephemeral TCP port and advertises '
            '_upfleet._tcp. The invitation code is never part of the '
            'advertisement.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryCard extends ConsumerWidget {
  const _DiscoveryCard({required this.state, required this.controller});

  final LanLabState state;
  final LanLabController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Discovered rooms',
      icon: Icons.search,
      trailing: state.isScanning
          ? _StatusChip(label: 'scanning', color: AppTheme.accent)
          : _StatusChip(label: 'stopped', color: AppTheme.textSecondary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FilledButton.icon(
            onPressed: () => state.isScanning
                ? controller.stopScanning()
                : controller.startScanning(),
            icon: Icon(
              state.isScanning ? Icons.stop : Icons.radar,
              size: 20,
            ),
            label: Text(state.isScanning ? 'Stop scanning' : 'Scan for rooms'),
          ),
          const SizedBox(height: 12),
          if (state.rooms.isEmpty)
            Text(
              state.isScanning
                  ? 'Looking for ${state.backend.label} services…'
                  : 'No rooms found yet.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final DiscoveredRoom room in state.rooms)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            room.label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            '${room.preferredAddress?.address ?? 'no address'}'
                            ':${room.port} · ${room.backend.label}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () => controller.connectTo(room),
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ManualConnectCard extends ConsumerWidget {
  const _ManualConnectCard({
    required this.state,
    required this.controller,
    required this.hostController,
    required this.portController,
  });

  final LanLabState state;
  final LanLabController controller;
  final TextEditingController hostController;
  final TextEditingController portController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Manual connection',
      icon: Icons.settings_input_component,
      trailing: _StatusChip(
        label: state.connectionState.name,
        color: switch (state.connectionState) {
          ClientConnectionState.connected => AppTheme.accent,
          ClientConnectionState.failed => AppTheme.danger,
          ClientConnectionState.connecting => AppTheme.sunk,
          ClientConnectionState.idle => AppTheme.textSecondary,
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Fallback for routers that block mDNS discovery. Enter the Host '
            'IPv4 address and the port shown on the Host device.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: hostController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Host IPv4',
                    hintText: '192.168.1.20',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              final int? port = int.tryParse(portController.text.trim());
              if (port == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('The port must be a number.')),
                );
                return;
              }
              controller.connectManually(hostController.text.trim(), port);
            },
            icon: const Icon(Icons.bolt, size: 18),
            label: const Text('Connect manually'),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsCard extends ConsumerWidget {
  const _DiagnosticsCard({required this.state, required this.controller});

  final LanLabState state;
  final LanLabController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool connected = state.connectionState == ClientConnectionState.connected;

    return _SectionCard(
      title: 'Transport diagnostics',
      icon: Icons.terminal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _KeyValue(label: 'Frames sent', value: '${state.framesSent}'),
          _KeyValue(label: 'Frames received', value: '${state.framesReceived}'),
          _KeyValue(
            label: 'Last round trip',
            value: state.lastRoundTrip == null
                ? '—'
                : '${state.lastRoundTrip!.inMilliseconds} ms',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: connected ? controller.sendPing : null,
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Ping'),
              ),
              OutlinedButton.icon(
                onPressed: connected ? controller.sendSplitFrame : null,
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('Split frame'),
              ),
              OutlinedButton.icon(
                onPressed: connected ? controller.sendOversizedFrame : null,
                icon: const Icon(Icons.report_gmailerrorred, size: 18),
                label: const Text('Oversized'),
              ),
              OutlinedButton.icon(
                onPressed: connected ? controller.sendMalformedFrame : null,
                icon: const Icon(Icons.broken_image, size: 18),
                label: const Text('Malformed'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Split frame sends one message in three writes. Oversized and '
            'malformed frames must be rejected by the Host with a stable '
            'error code instead of crashing the connection.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.state});

  final LanLabState state;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Diagnostic log',
      icon: Icons.list_alt,
      child: state.log.isEmpty
          ? Text(
              'Nothing logged yet.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: state.log.length,
                itemBuilder: (BuildContext context, int index) {
                  final LogEntry entry = state.log[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.timestamp,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.message,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _colorFor(entry.level)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  static Color _colorFor(LogLevel level) => switch (level) {
    LogLevel.info => AppTheme.textSecondary,
    LogLevel.success => AppTheme.accent,
    LogLevel.warning => AppTheme.sunk,
    LogLevel.error => AppTheme.danger,
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
