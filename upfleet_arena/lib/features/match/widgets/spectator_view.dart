import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../shared/models/match_models.dart';
import '../../rooms/domain/room_session_controller.dart';
import 'match_panel.dart';
import 'shooter_colors.dart';
import 'shooter_dot.dart';
import 'turn_strip.dart';

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
    final Map<String, Color> colours = ShooterColors.of(snapshot.players);

    return Center(
      // The same parts as the playing view, stacked in one readable column.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.sunk.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.sunk.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.sunk.withValues(alpha: 0.14),
                    ),
                    child: const Icon(
                      Icons.visibility_outlined,
                      color: AppTheme.sunk,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.yourFleetWasSunk,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.spectatorWatching,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (snapshot.winnerPlayerId == null) ...<Widget>[
              const SizedBox(height: 12),
              // The same strip the players read, with the spectator's own
              // "not your turn" wording.
              TurnStrip(
                isMyTurn: false,
                activePlayerName:
                    snapshot.playerById(snapshot.activePlayerId)?.displayName ??
                    l10n.aPlayer,
                remaining: remaining,
                turnNumber: snapshot.turnNumber,
              ),
            ],
            const SizedBox(height: 16),
            MatchPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.stillInTheMatch,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (living.isEmpty)
                    Text(
                      l10n.nobodyIsLeft,
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    for (final MatchPlayerView player in living)
                      _LivingRow(
                        player: player,
                        colour: ShooterColors.ofPlayer(colours, player.playerId),
                        isActive: player.playerId == snapshot.activePlayerId,
                      ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MatchPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.publicActivity,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (feed.isEmpty)
                    Text(
                      l10n.noPublicShots,
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    // The dot is the colour of the shooter, exactly as the
                    // map paints their marks, so a line names a player twice:
                    // once by colour and once by name.
                    for (final PublicActivity activity in feed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: ShooterDot(
                                colour: ShooterColors.ofPlayer(
                                  colours,
                                  activity.attackerPlayerId,
                                ),
                                size: 8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _describe(l10n, activity),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.spectatorHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
            if (footer case final Widget extra) ...<Widget>[
              const SizedBox(height: 20),
              extra,
            ],
          ],
        ),
      ),
    );
  }

  String _describe(AppLocalizations l10n, PublicActivity activity) {
    final String attacker =
        snapshot.playerById(activity.attackerPlayerId)?.displayName ??
        l10n.aPlayer;
    final String target =
        snapshot.playerById(activity.targetPlayerId)?.displayName ??
        l10n.anotherPlayer;
    return switch (activity.result) {
      ShotResult.miss => l10n.activityMissed(attacker, target),
      ShotResult.hit => l10n.activityHit(attacker, target),
      ShotResult.shipSunk => l10n.activitySunk(attacker, target),
    };
  }
}

/// One player still fighting, with the colour of their marks on the map.
class _LivingRow extends StatelessWidget {
  const _LivingRow({
    required this.player,
    required this.colour,
    required this.isActive,
  });

  final MatchPlayerView player;
  final Color colour;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.accent.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          ShooterDot(colour: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              player.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                fontWeight: isActive ? FontWeight.w700 : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.shipsLeftCount(player.shipsRemaining),
            style: text.labelSmall?.copyWith(color: AppTheme.accent),
          ),
        ],
      ),
    );
  }
}
