import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('UpFleet Arena'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'LAN only · no backend',
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
              title: 'LAN Lab',
              subtitle: 'Discovery + TCP proof of concept (Phase 0)',
              onTap: () => context.go('/lan-lab'),
            ),
            const SizedBox(height: 8),
            _PhaseEntry(
              icon: Icons.add_home_work_outlined,
              title: 'Create Room',
              subtitle: 'Host a room and share the invitation code',
              onTap: () => context.go('/create-room'),
            ),
            const SizedBox(height: 8),
            _PhaseEntry(
              icon: Icons.login_outlined,
              title: 'Join Room',
              subtitle: 'Find a nearby room and join with the code',
              onTap: () => context.go('/join-room'),
            ),
            const SizedBox(height: 8),
            _PhaseEntry(
              icon: Icons.people_outline,
              title: 'Lobby',
              subtitle: 'Phase 1 — player list, host badge, kick and close',
              enabled: false,
            ),
            const SizedBox(height: 8),
            _PhaseEntry(
              icon: Icons.grid_view_outlined,
              title: 'Ship Placement',
              subtitle: 'Phase 3 — private board and fleet placement',
              enabled: false,
            ),
            const SizedBox(height: 8),
            _PhaseEntry(
              icon: Icons.gps_fixed,
              title: 'Battle',
              subtitle: 'Phase 5 — turn-based combat',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Turn-based naval combat\nfor the same Wi-Fi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Every player places a private fleet, then takes turns firing at '
              'the others. The room host runs the whole game on their phone — '
              'no server, no account, no Internet connection required.',
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
            : const Chip(label: Text('Later')),
      ),
    );
  }
}

class _ConstraintsCard extends StatelessWidget {
  const _ConstraintsCard();

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> constraints = <(String, String)>[
      ('Network', '${AppConfig.networkMode} · ${AppConfig.topology}'),
      ('Discovery', '${AppConfig.discovery} · _upfleet._tcp'),
      ('Players', '${AppConfig.minimumPlayers}–${AppConfig.recommendedMaximumPlayers}'),
      ('Board', '${AppConfig.defaultBoardRows}×${AppConfig.defaultBoardColumns}'),
      ('Fleet', 'Standard · ${AppConfig.standardFleetShipLengths.join('-')}'),
      (
        'Timers',
        '${AppConfig.placementDurationSeconds}s placement · '
            '${AppConfig.turnDurationSeconds}s turn',
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Frozen defaults', style: Theme.of(context).textTheme.titleMedium),
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
              'Host exit ends the room for every player. There is no host '
              'migration and no Internet fallback.',
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
