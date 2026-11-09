import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';

/// Entry screen of the app.
///
/// Phase 0 ships the LAN proof of concept only. The remaining entries are
/// visible but disabled, each labelled with the phase that implements it, so
/// the intended product flow stays discoverable (PLAN.md §15).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            _HeroCard(),
            const SizedBox(height: 16),
            _PhaseEntry(
              icon: Icons.lan_outlined,
              title: l10n.lanLab,
              subtitle: l10n.lanLabSubtitle,
              onTap: () => context.go('/lan-lab'),
            ),
            const SizedBox(height: 8),
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
              enabled: false,
            ),
            const SizedBox(height: 8),
            _PhaseEntry(
              icon: Icons.grid_view_outlined,
              title: l10n.shipPlacement,
              subtitle: l10n.shipPlacementSubtitle,
              enabled: false,
            ),
            const SizedBox(height: 8),
            _PhaseEntry(
              icon: Icons.gps_fixed,
              title: l10n.battle,
              subtitle: l10n.battleSubtitle,
              enabled: false,
            ),
            const SizedBox(height: 24),
            const _ConstraintsCard(),
          ],
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
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
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color foreground = enabled
        ? AppTheme.textPrimary
        : AppTheme.textSecondary.withValues(alpha: 0.6);

    return Card(
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: Icon(icon, color: enabled ? AppTheme.accent : foreground),
        title: Text(
          title,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: enabled
            ? const Icon(Icons.chevron_right, color: AppTheme.textSecondary)
            : Chip(label: Text(AppLocalizations.of(context).later)),
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
      (l10n.players, '${AppConfig.minimumPlayers}–${AppConfig.recommendedMaximumPlayers}'),
      (l10n.board, '${AppConfig.defaultBoardRows}×${AppConfig.defaultBoardColumns}'),
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
            Text(l10n.frozenDefaults, style: Theme.of(context).textTheme.titleMedium),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
