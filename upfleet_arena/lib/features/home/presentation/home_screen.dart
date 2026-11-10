import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../rooms/domain/room_session_controller.dart';

/// Entry screen of the app.
///
/// Every implemented flow is reachable from here: the profile and settings,
/// creating and joining a room, and the in-room screens (lobby, placement,
/// battle). The LAN Lab is a developer tool and is only listed in debug
/// builds (PLAN.md §15).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final bool inRoom = session.isInRoom;
    final bool matchRunning = session.matchSnapshot != null;

    void openRoomScreen(String route, {bool available = true}) {
      // The in-room screens read the active session: without one they would
      // only show an empty shell, so point the player at the real entry paths.
      final String? problem = !inRoom
          ? l10n.inRoomOnly
          : (available ? null : l10n.matchNotStarted);
      if (problem == null) {
        context.go(route);
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                l10n.lanOnlyNoBackend,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        // Keeps the launcher readable on tablets and in landscape instead of
        // stretching every row across the full width (PLAN.md §5).
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                _HeroCard(),
                const SizedBox(height: 16),
                _PhaseEntry(
                  icon: Icons.add_home_work_outlined,
                  title: l10n.createRoom,
                  subtitle: l10n.createRoomSubtitle,
                  onTap: () => context.go('/create-room'),
                ),
                const SizedBox(height: 8),
                _PhaseEntry(
                  icon: Icons.login_outlined,
                  title: l10n.joinRoom,
                  subtitle: l10n.joinRoomSubtitle,
                  onTap: () => context.go('/join-room'),
                ),
                const SizedBox(height: 8),
                _PhaseEntry(
                  icon: Icons.people_outline,
                  title: l10n.lobby,
                  subtitle: l10n.lobbySubtitle,
                  onTap: () => openRoomScreen('/lobby'),
                ),
                const SizedBox(height: 8),
                _PhaseEntry(
                  icon: Icons.grid_view_outlined,
                  title: l10n.shipPlacement,
                  subtitle: l10n.shipPlacementSubtitle,
                  onTap: () => openRoomScreen('/placement'),
                ),
                const SizedBox(height: 8),
                _PhaseEntry(
                  icon: Icons.gps_fixed,
                  title: l10n.battle,
                  subtitle: l10n.battleSubtitle,
                  onTap: () =>
                      openRoomScreen('/match', available: matchRunning),
                ),
                const SizedBox(height: 8),
                _PhaseEntry(
                  icon: Icons.person_outline,
                  title: l10n.profileAndSettings,
                  subtitle: l10n.profileAndSettingsSubtitle,
                  onTap: () => context.push('/profile'),
                ),
                if (kDebugMode) ...<Widget>[
                  const SizedBox(height: 8),
                  _PhaseEntry(
                    icon: Icons.lan_outlined,
                    title: l10n.lanLab,
                    subtitle: l10n.lanLabSubtitle,
                    onTap: () => context.go('/lan-lab'),
                  ),
                ],
                const SizedBox(height: 24),
                const _ConstraintsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.heroTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.heroBody,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseEntry extends StatelessWidget {
  const _PhaseEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: AppTheme.accent),
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _ConstraintsCard extends StatelessWidget {
  const _ConstraintsCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<(String, String)> constraints = <(String, String)>[
      (l10n.network, '${AppConfig.networkMode} · ${AppConfig.topology}'),
      (l10n.discovery, '${AppConfig.discovery} · _upfleet._tcp'),
      (
        l10n.players,
        '${AppConfig.minimumPlayers}–${AppConfig.recommendedMaximumPlayers}',
      ),
      (
        l10n.board,
        '${AppConfig.defaultBoardRows}×${AppConfig.defaultBoardColumns}',
      ),
      (
        l10n.fleet,
        l10n.fleetConstraintValue(AppConfig.standardFleetShipLengths.join('-')),
      ),
      (
        l10n.timers,
        l10n.timersConstraintValue(
          AppConfig.placementDurationSeconds,
          AppConfig.turnDurationSeconds,
        ),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.frozenDefaults,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final (String label, String value) in constraints)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 92,
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              l10n.hostExitWarning,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppTheme.textSecondary, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
