import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/room_models.dart';
import '../../rooms/domain/room_session_controller.dart';

/// The room lobby.
///
/// It shows the member list with the Host badge, the shared room settings and
/// offers the actions the current role allows: kick and close for the Host,
/// leave for everybody else (PLAN.md §3.1, §3.2).
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  void _checkSession() {
    final RoomSessionState state = ref.read(roomSessionControllerProvider);
    if (!state.isInRoom && mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final RoomSnapshot? snapshot = session.snapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _leave(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (session.errorMessage != null &&
                session.status == RoomSessionStatus.closed) ...<Widget>[
              _ClosedBanner(message: session.errorMessage!),
              const SizedBox(height: 12),
            ],
            if (session.isHost) ...<Widget>[
              _InviteCard(session: session),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          'Players',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${snapshot?.players.length ?? 0}'
                          '/${snapshot?.config.maxPlayers ?? 0}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (snapshot == null)
                      const Text('Waiting for the room state…')
                    else if (snapshot.players.isEmpty)
                      const Text('Nobody is in the room yet.')
                    else
                      for (final PlayerSummary player in snapshot.players)
                        _PlayerRow(
                          player: player,
                          isViewer: player.playerId == session.playerId,
                          canKick:
                              session.isHost &&
                              !player.isHost &&
                              player.status ==
                                  PlayerConnectionStatus.connected,
                          onKick: () => _kick(context, player),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (snapshot != null)
              _SettingsCard(
                config: snapshot.config,
                isHost: session.isHost,
                onEdit: () => context.push('/lobby/settings'),
              ),
            const SizedBox(height: 12),
            if (session.isHost)
              _HostActions(
                onClose: () => _closeRoom(context),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _leave(context),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Leave room'),
              ),
            if (session.isHost) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Keep this app open and in the foreground. Closing it ends '
                    'the room for every player.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.sunk,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _kick(BuildContext context, PlayerSummary player) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Remove ${player.displayName}?'),
        content: const Text(
          'They are removed from the room and cannot rejoin with this '
          'invitation code.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(roomSessionControllerProvider.notifier).kick(player.playerId);
  }

  Future<void> _closeRoom(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('End the room?'),
        content: const Text(
          'Every player is disconnected and returns to the home screen. The '
          'room cannot be reopened.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End room'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(roomSessionControllerProvider.notifier).closeRoom();
    if (context.mounted) context.go('/');
  }

  Future<void> _leave(BuildContext context) async {
    await ref.read(roomSessionControllerProvider.notifier).leave();
    if (context.mounted) context.go('/');
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.session});

  final RoomSessionState session;

  @override
  Widget build(BuildContext context) {
    final String code = session.inviteCode ?? '······';
    return Card(
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy the code',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation code copied.')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
                Builder(
                  builder: (BuildContext buttonContext) => IconButton(
                    tooltip: 'Share the invitation',
                    onPressed: () => _share(buttonContext, code),
                    icon: const Icon(Icons.ios_share),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _KeyValue(label: 'Port', value: '${session.hostPort ?? '—'}'),
            _KeyValue(
              label: 'Manual address',
              value: session.hostAddresses.isEmpty
                  ? 'not available'
                  : '${session.hostAddresses.first}:${session.hostPort ?? ''}',
            ),
            const SizedBox(height: 8),
            Text(
              'Share the code with players on the same Wi-Fi. The code is not '
              'part of the network announcement, so only the players you tell '
              'can join.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the system share sheet with the invitation details.
  Future<void> _share(BuildContext context, String code) async {
    final StringBuffer text = StringBuffer()
      ..writeln('Join my UpFleet Arena room.')
      ..writeln('Invitation code: $code');
    if (session.hostAddresses.isNotEmpty) {
      text.writeln(
        'Manual address: ${session.hostAddresses.first}:${session.hostPort}',
      );
    }
    text.write('Every player must be on the same Wi-Fi network.');

    final RenderObject? renderObject = context.findRenderObject();
    final Rect? origin = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text.toString(),
          subject: 'UpFleet Arena invitation',
          sharePositionOrigin: origin,
        ),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sharing is not available here.')),
      );
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.config,
    required this.isHost,
    required this.onEdit,
  });

  final RoomConfig config;
  final bool isHost;
  final VoidCallback onEdit;

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
                Expanded(
                  child: Text(
                    'Room settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isHost)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _KeyValue(label: 'Board', value: '${config.rows}×${config.columns}'),
            _KeyValue(
              label: 'Fleet',
              value:
                  '${config.fleetPreset.label} · ${config.fleetPreset.shipCount} '
                  'ships (${config.fleetPreset.shipSummary})',
            ),
            _KeyValue(
              label: 'Capacity',
              value: 'up to ${config.maxPlayers} players',
            ),
            _KeyValue(
              label: 'Timers',
              value:
                  '${config.placementDurationSeconds} s preparation · '
                  '${config.turnDurationSeconds} s per turn',
            ),
            if (!isHost) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Only the host can change these settings.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.sunk,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.isViewer,
    required this.canKick,
    required this.onKick,
  });

  final PlayerSummary player;
  final bool isViewer;
  final bool canKick;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Text(
            player.avatarId.isEmpty ? '🙂' : player.avatarId,
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        player.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (isViewer)
                      Text(
                        '  (you)',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    Icon(
                      _statusIcon(player.status),
                      size: 13,
                      color: _statusColor(player.status),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _statusLabel(player.status),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _statusColor(player.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (player.isHost)
            const Chip(
              label: Text('Host'),
              avatar: Icon(Icons.star, size: 16, color: AppTheme.sunk),
              visualDensity: VisualDensity.compact,
            ),
          if (canKick)
            IconButton(
              tooltip: 'Remove ${player.displayName}',
              onPressed: onKick,
              icon: const Icon(Icons.person_remove_outlined),
            ),
        ],
      ),
    );
  }

  static String _statusLabel(PlayerConnectionStatus status) => switch (status) {
    PlayerConnectionStatus.connected => 'Connected',
    PlayerConnectionStatus.disconnected => 'Disconnected — may rejoin',
    PlayerConnectionStatus.left => 'Left the room',
    PlayerConnectionStatus.kicked => 'Removed by the host',
  };

  static Color _statusColor(PlayerConnectionStatus status) => switch (status) {
    PlayerConnectionStatus.connected => AppTheme.accent,
    PlayerConnectionStatus.disconnected => AppTheme.sunk,
    PlayerConnectionStatus.left => AppTheme.textSecondary,
    PlayerConnectionStatus.kicked => AppTheme.danger,
  };

  static IconData _statusIcon(PlayerConnectionStatus status) =>
      switch (status) {
        PlayerConnectionStatus.connected => Icons.circle,
        PlayerConnectionStatus.disconnected => Icons.link_off,
        PlayerConnectionStatus.left => Icons.logout,
        PlayerConnectionStatus.kicked => Icons.person_remove,
      };
}

class _HostActions extends StatelessWidget {
  const _HostActions({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onClose,
      icon: const Icon(Icons.power_settings_new),
      label: const Text('End room'),
    );
  }
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, color: AppTheme.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ],
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
            width: 118,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
