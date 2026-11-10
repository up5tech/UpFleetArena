import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

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
    this.footer,
  });

  final MatchSnapshot snapshot;
  final RoomSessionState session;

  /// Extra content appended below the feed, e.g. the player's own fleet.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
                      l10n.yourFleetWasSunk,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.spectatorWatching,
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
                          l10n.playerIsShooting(
                            snapshot.playerById(snapshot.activePlayerId)?.displayName ??
                                l10n.aPlayer,
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          remaining == null
                              ? l10n.turnLabel(snapshot.turnNumber)
                              : l10n.turnLabelWithTime(snapshot.turnNumber, remaining),
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
          l10n.stillInTheMatch,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (living.isEmpty)
          Text(l10n.nobodyIsLeft)
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
                    l10n.shipsLeftCount(player.shipsRemaining),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        const SizedBox(height: 20),
        Text(l10n.publicActivity, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (feed.isEmpty)
          Text(l10n.noPublicShots)
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
                      _describe(l10n, activity),
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
          l10n.spectatorHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
        ),
        if (footer case final Widget extra) ...<Widget>[
          const SizedBox(height: 24),
          extra,
        ],
      ],
    );
  }

  String _describe(AppLocalizations l10n, PublicActivity activity) {
    final String attacker =
        snapshot.playerById(activity.attackerPlayerId)?.displayName ?? l10n.aPlayer;
    final String target =
        snapshot.playerById(activity.targetPlayerId)?.displayName ?? l10n.anotherPlayer;
    return switch (activity.result) {
      ShotResult.miss => l10n.activityMissed(attacker, target),
      ShotResult.hit => l10n.activityHit(attacker, target),
      ShotResult.shipSunk => l10n.activitySunk(attacker, target),
    };
  }
}