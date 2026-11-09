import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final RoomSnapshot? snapshot = session.snapshot;

    WidgetsBinding.instance.addPostFrameCallback((_) => _followPhase(session));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.lobby),
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
            if (session.notice != null) ...<Widget>[
              _NoticeCard(message: session.notice!),
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
                          l10n.players,
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
                      Text(l10n.waitingForRoomState)
                    else if (snapshot.players.isEmpty)
                      Text(l10n.nobodyInRoom)
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
            OutlinedButton.icon(
              onPressed: () => context.push('/placement'),
              icon: const Icon(Icons.grid_view_outlined, size: 18),
              label: Text(
                session.isPlacementReady
                    ? l10n.yourFleetReady
                    : l10n.prepareYourFleet,
              ),
            ),
            const SizedBox(height: 12),
            if (session.isHost)
              _HostActions(
                canStart:
                    snapshot?.status == RoomStatus.lobby &&
                    _connectedCount(snapshot) >= RoomConfig.minimumPlayers,
                onStart: () => _startPlacement(context),
                onClose: () => _closeRoom(context),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _leave(context),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l10n.leaveRoom),
              ),
            if (session.isHost) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.keepAppOpenLobby,
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

  /// The number of members that are connected right now.
  static int _connectedCount(RoomSnapshot? snapshot) {
    if (snapshot == null) return 0;
    return snapshot.players
        .where(
          (PlayerSummary player) =>
              player.status == PlayerConnectionStatus.connected,
        )
        .length;
  }

  /// Follows the phase the Host moved the room into.
  void _followPhase(RoomSessionState session) {
    if (!mounted) return;
    final RoomStatus? status = session.snapshot?.status;
    if (status == RoomStatus.active) {
      context.go('/match');
    } else if (status == RoomStatus.placement) {
      context.go('/placement');
    }
  }

  Future<void> _startPlacement(BuildContext context) async {
    final List<String> problems = await ref
        .read(roomSessionControllerProvider.notifier)
        .startPlacement();
    if (!context.mounted) return;
    if (problems.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problems.join(' '))),
    );
  }

  Future<void> _kick(BuildContext context, PlayerSummary player) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.removePlayerQuestion(player.displayName)),
        content: Text(l10n.removePlayerWarning),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(roomSessionControllerProvider.notifier).kick(player.playerId);
  }

  Future<void> _closeRoom(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.endTheRoom),
        content: Text(l10n.endRoomWarning),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.endRoom),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String code = session.inviteCode ?? '······';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.invitationCode,
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
                  tooltip: l10n.copyTheCode,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.invitationCodeCopied)),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
                Builder(
                  builder: (BuildContext buttonContext) => IconButton(
                    tooltip: l10n.shareTheInvitation,
                    onPressed: () => _share(buttonContext, code),
                    icon: const Icon(Icons.ios_share),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _KeyValue(label: l10n.port, value: '${session.hostPort ?? '—'}'),
            _KeyValue(
              label: l10n.manualAddress,
              value: session.hostAddresses.isEmpty
                  ? l10n.notAvailable
                  : '${session.hostAddresses.first}:${session.hostPort ?? ''}',
            ),
            const SizedBox(height: 8),
            Text(
              l10n.shareCodeHint,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StringBuffer text = StringBuffer()
      ..writeln(l10n.shareJoinLine)
      ..writeln(l10n.shareCodeLine(code));
    if (session.hostAddresses.isNotEmpty) {
      text.writeln(
        l10n.shareAddressLine('${session.hostAddresses.first}:${session.hostPort}'),
      );
    }
    text.write(l10n.shareWifiLine);

    final RenderObject? renderObject = context.findRenderObject();
    final Rect? origin = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text.toString(),
          subject: l10n.shareSubject,
          sharePositionOrigin: origin,
        ),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sharingNotAvailable)),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
                    l10n.roomSettings,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isHost)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(l10n.edit),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _KeyValue(label: l10n.board, value: '${config.rows}×${config.columns}'),
            _KeyValue(
              label: l10n.fleet,
              value: l10n.fleetSettingsValue(
                config.fleetPreset.label,
                config.fleetPreset.shipCount,
                config.fleetPreset.shipSummary,
              ),
            ),
            _KeyValue(
              label: l10n.capacity,
              value: l10n.capacityValue(config.maxPlayers),
            ),
            _KeyValue(
              label: l10n.timers,
              value: l10n.timersSettingsValue(
                config.placementDurationSeconds,
                config.turnDurationSeconds,
              ),
            ),
            if (!isHost) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.onlyHostChangesSettings,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
                        l10n.youSuffix,
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
                        _statusLabel(player.status, l10n),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _statusColor(player.status),
                        ),
                      ),
                    ),
                    if (player.ready) ...<Widget>[
                      const SizedBox(width: 8),
                      const Icon(Icons.check, size: 13, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Text(
                        l10n.ready,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (player.isHost)
            Chip(
              label: Text(l10n.host),
              avatar: const Icon(Icons.star, size: 16, color: AppTheme.sunk),
              visualDensity: VisualDensity.compact,
            ),
          if (canKick)
            IconButton(
              tooltip: l10n.removePlayer(player.displayName),
              onPressed: onKick,
              icon: const Icon(Icons.person_remove_outlined),
            ),
        ],
      ),
    );
  }

  static String _statusLabel(
    PlayerConnectionStatus status,
    AppLocalizations l10n,
  ) => switch (status) {
    PlayerConnectionStatus.connected => l10n.statusConnected,
    PlayerConnectionStatus.disconnected => l10n.statusDisconnected,
    PlayerConnectionStatus.left => l10n.statusLeft,
    PlayerConnectionStatus.kicked => l10n.statusKicked,
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
  const _HostActions({
    required this.canStart,
    required this.onStart,
    required this.onClose,
  });

  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: canStart ? onStart : null,
          icon: const Icon(Icons.timer_outlined),
          label: Text(l10n.startPreparation),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onClose,
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
          icon: const Icon(Icons.power_settings_new),
          label: Text(l10n.endRoom),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.preparationTimeoutHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.sunk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.sunk.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, color: AppTheme.sunk, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
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
                  child: Text(AppLocalizations.of(context).backToHome),
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
