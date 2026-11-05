import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/permissions/lan_permission_service.dart';
import '../../lan_networking/domain/lan_discovery.dart';
import '../../lan_networking/domain/lan_networking_providers.dart';
import '../../profile/domain/profile.dart';
import '../../profile/domain/profile_controller.dart';
import '../domain/join_discovery_controller.dart';
import '../domain/room_session_controller.dart';

/// Finds a room on the local network and joins it with the invitation code.
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  DiscoveredRoom? _selectedRoom;
  bool _showManual = false;

  @override
  void dispose() {
    _codeController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _joinSelected() async {
    final DiscoveredRoom? room = _selectedRoom;
    if (room == null) return;

    await _join(() {
      final RoomSessionController controller = ref.read(
        roomSessionControllerProvider.notifier,
      );
      return controller.joinRoom(
        room: room,
        code: _codeController.text,
        profile: ref.read(profileProvider),
      );
    });
  }

  Future<void> _joinManual() async {
    final int? port = int.tryParse(_portController.text.trim());
    if (port == null) {
      _showMessage('The port must be a number.');
      return;
    }
    await _join(() {
      final RoomSessionController controller = ref.read(
        roomSessionControllerProvider.notifier,
      );
      return controller.joinManually(
        host: _hostController.text,
        port: port,
        code: _codeController.text,
        profile: ref.read(profileProvider),
      );
    });
  }

  Future<void> _join(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    final RoomSessionState state = ref.read(roomSessionControllerProvider);
    if (state.isInRoom) {
      context.go('/lobby');
    } else if (state.errorMessage != null) {
      _showMessage(state.errorMessage!);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Profile profile = ref.watch(profileProvider);
    final JoinDiscoveryState discovery = ref.watch(
      joinDiscoveryControllerProvider,
    );
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final bool busy = session.status == RoomSessionStatus.working;

    return Scaffold(
      appBar: AppBar(title: const Text('Join room')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Text(
                      profile.avatarId.isEmpty
                          ? Avatars.fallback
                          : profile.avatarId,
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        profile.displayName.isEmpty
                            ? 'No nickname yet'
                            : profile.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/profile'),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Invitation code',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 8,
                      decoration: const InputDecoration(
                        hintText: 'ABC234',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The host shares this code. It is checked by the host '
                      'device over the direct connection, never over the '
                      'network announcement.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.radar, size: 20, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Nearby rooms',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final JoinDiscoveryController controller = ref.read(
                              joinDiscoveryControllerProvider.notifier,
                            );
                            if (discovery.isScanning) {
                              controller.stop();
                            } else {
                              controller.start();
                            }
                          },
                          child: Text(
                            discovery.isScanning ? 'Stop' : 'Scan',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (discovery.rooms.isEmpty)
                      Text(
                        discovery.isScanning
                            ? 'Looking for rooms on this Wi-Fi…'
                            : 'No rooms found yet. Tap Scan, or use the '
                                  'manual connection below.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      )
                    else
                      for (final DiscoveredRoom room in discovery.rooms)
                        ListTile(
                          onTap: () => setState(() => _selectedRoom = room),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _selectedRoom == room
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: _selectedRoom == room
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                          ),
                          title: Text(room.label),
                          subtitle: Text(
                            '${room.preferredAddress?.address ?? 'no address'}'
                            ':${room.port}',
                          ),
                        ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: busy ||
                              _selectedRoom == null ||
                              _codeController.text.trim().isEmpty
                          ? null
                          : _joinSelected,
                      icon: const Icon(Icons.login),
                      label: const Text('Join selected room'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.settings_input_component,
                          size: 20,
                          color: AppTheme.sunk,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Manual connection',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _showManual = !_showManual),
                          child: Text(_showManual ? 'Hide' : 'Show'),
                        ),
                      ],
                    ),
                    if (_showManual) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        'Use this when the router blocks discovery. Enter the '
                        'IPv4 address and the port shown on the host device.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _hostController,
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
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _joinManual,
                        icon: const Icon(Icons.bolt, size: 18),
                        label: const Text('Connect manually'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _TroubleshootingCard(),
          ],
        ),
      ),
    );
  }
}

class _TroubleshootingCard extends ConsumerWidget {
  const _TroubleshootingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LanPermissionService service = ref.read(lanPermissionServiceProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Nothing found?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final String step in service.troubleshootingSteps)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('• '),
                    Expanded(
                      child: Text(
                        step,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'The router may isolate clients from each other. The manual '
              'connection above uses a direct TCP link, so it sometimes works '
              'when discovery is filtered.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.sunk,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
