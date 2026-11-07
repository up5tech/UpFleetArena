import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../shared/models/match_models.dart';
import '../../rooms/domain/room_session_controller.dart';

/// The read-only view of a player whose fleet was sunk.
///
/// A spectator sees the match status, the remaining players and the public
/// activity — never a coordinate and never another player's fleet
/// (PLAN.md §5.2, §6.6).
class SpectatorView extends StatelessWidget {
  const SpectatorView({
    super.key,
    required this.snapshot,
    required this.session,
  });

  final MatchSnapshot snapshot;
  final RoomSessionState session;

  @override
  Widget build(BuildContext context) {
    final List<MatchPlayerView> living = snapshot.players
        .where((MatchPlayerView player) => player.alive)
        .toList();
    final List<PublicActivity> feed = session.activityFeed.reversed.toList();
    final int? remaining = session.turnCountdown?.remaining;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.sunk.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.sunk.withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.visibility_outlined, color: AppTheme.sunk, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Your fleet was sunk.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You are watching the rest of the match. You cannot fire.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (snapshot.winnerPlayerId == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.hourglass_empty, color: AppTheme.miss, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${snapshot.playerById(snapshot.activePlayerId)?.displayName ?? 'A player'} is shooting',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Turn ${snapshot.turnNumber}'
                          '${remaining == null ? '' : ' · ${remaining}s left'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Still in the match',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (living.isEmpty)
          const Text('Nobody is left.')
        else
          for (final MatchPlayerView player in living)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.circle, size: 12, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(player.displayName),
                  ),
                  Text(
                    '${player.shipsRemaining} ships left',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        const SizedBox(height: 20),
        Text('Public activity', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (feed.isEmpty)
          const Text('No public shots yet.')
        else
          for (final PublicActivity activity in feed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    switch (activity.result) {
                      ShotResult.miss => Icons.block,
                      ShotResult.hit => Icons.gps_fixed,
                      ShotResult.shipSunk => Icons.local_fire_department,
                    },
                    size: 14,
                    color: switch (activity.result) {
                      ShotResult.miss => AppTheme.miss,
                      ShotResult.hit => AppTheme.hit,
                      ShotResult.shipSunk => AppTheme.sunk,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _describe(activity),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 16),
        Text(
          'Spectators see no coordinates and no enemy fleet. Your own board '
          'stays available in the next tab.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
        ),
      ],
    );
  }

  String _describe(PublicActivity activity) {
    final String attacker =
        snapshot.playerById(activity.attackerPlayerId)?.displayName ?? 'A player';
    final String target =
        snapshot.playerById(activity.targetPlayerId)?.displayName ?? 'another player';
    return switch (activity.result) {
      ShotResult.miss => '$attacker missed $target.',
      ShotResult.hit => '$attacker hit $target.',
      ShotResult.shipSunk => '$attacker sank a ship of $target.',
    };
  }
}