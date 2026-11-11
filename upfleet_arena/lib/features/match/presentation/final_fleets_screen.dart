import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/board/board.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../shared/models/match_models.dart';
import '../../../shared/widgets/board_canvas.dart';
import '../../rooms/domain/room_session_controller.dart';
import '../widgets/match_panel.dart';
import '../widgets/shooter_colors.dart';
import '../widgets/shooter_dot.dart';

/// Every fleet of a finished match, revealed for review.
///
/// While the match runs a fleet only reaches its owner. Once a winner is
/// declared the result may show every hull, so the players can look back at
/// where each ship was and how it went down (GAME_RULES.md §2).
class FinalFleetsScreen extends ConsumerWidget {
  const FinalFleetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final MatchResult? result = session.matchResult;

    if (result == null || result.fleets.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.allFleets)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  result == null
                      ? l10n.matchNotFinished
                      : l10n.fleetsUnavailable,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: Text(l10n.backToHome),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final int rows = session.snapshot?.config.rows ?? 10;
    final int columns = session.snapshot?.config.columns ?? 10;
    final String? viewerPlayerId = session.playerId;
    // The same colours the shared map used, so a fleet reads the same way.
    // The snapshot keeps the turn order of the match; a result that outlived
    // it falls back to the ranking so no player loses their colour.
    final Map<String, Color> shooterColors = ShooterColors.of(
      session.matchSnapshot?.players ??
          <MatchPlayerView>[
            for (final PlayerResultView entry in result.ranking)
              MatchPlayerView(
                playerId: entry.playerId,
                displayName: entry.displayName,
                alive: true,
                timeouts: entry.timeouts,
                shipsRemaining: 0,
              ),
          ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.allFleets)),
      // The result screen waits behind this button, so nobody skips the
      // review by accident.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => context.go('/match/result'),
              child: Text(l10n.ok),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            Text(
              l10n.allFleetsHint,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 12),
            _ShooterLegend(
              ranking: result.ranking,
              colours: shooterColors,
              viewerPlayerId: viewerPlayerId,
            ),
            const SizedBox(height: 16),
            for (final PlayerResultView entry in result.ranking) ...<Widget>[
              _FleetCard(
                entry: entry,
                fleet: result.fleetOf(entry.playerId),
                rows: rows,
                columns: columns,
                shooterColors: shooterColors,
                isViewer: entry.playerId == viewerPlayerId,
                isWinner: entry.playerId == result.winnerPlayerId,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which player fired in which colour.
///
/// The boards of the review paint every hit in the colour of its shooter, so
/// the top of the screen names the colours once instead of on every board.
class _ShooterLegend extends StatelessWidget {
  const _ShooterLegend({
    required this.ranking,
    required this.colours,
    required this.viewerPlayerId,
  });

  final List<PlayerResultView> ranking;
  final Map<String, Color> colours;
  final String? viewerPlayerId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return MatchPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.shootersLegend, style: text.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: <Widget>[
              for (final PlayerResultView entry in ranking)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ShooterDot(
                      colour: ShooterColors.ofPlayer(colours, entry.playerId),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.playerId == viewerPlayerId
                          ? l10n.playerNameYou(entry.displayName)
                          : entry.displayName,
                      style: text.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The revealed fleet of one player with every shot it received.
class _FleetCard extends StatelessWidget {
  const _FleetCard({
    required this.entry,
    required this.fleet,
    required this.rows,
    required this.columns,
    required this.shooterColors,
    required this.isViewer,
    required this.isWinner,
  });

  final PlayerResultView entry;
  final FinalFleetView? fleet;
  final int rows;
  final int columns;

  /// The colour of every player, keyed by player id.
  final Map<String, Color> shooterColors;
  final bool isViewer;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final FinalFleetView? revealed = fleet;

    return MatchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isWinner ? Icons.emoji_events : Icons.directions_boat_outlined,
                size: 18,
                color: isWinner ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isViewer
                      ? l10n.playerNameYou(entry.displayName)
                      : entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          if (revealed == null) ...<Widget>[
            const SizedBox(height: 8),
            Text(l10n.fleetsUnavailable, style: text.bodySmall),
          ] else ...<Widget>[
            const SizedBox(height: 2),
            Text(
              l10n.fleetReviewSummary(
                revealed.ships.length,
                revealed.sunkCount,
              ),
              style: text.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;
                // Every hit carries the colour of the player who fired it, so
                // the review reads like the shared map of the match.
                final Map<CellCoord, Color> hitColors = <CellCoord, Color>{};
                for (final ShotView shot in revealed.receivedShots) {
                  if (shot.result == ShotResult.miss) continue;
                  hitColors[shot.cell] = ShooterColors.ofPlayer(
                    shooterColors,
                    shot.attackerPlayerId,
                  );
                }
                return SizedBox(
                  width: width,
                  height: width * rows / columns,
                  child: BoardCanvas(
                    rows: rows,
                    columns: columns,
                    ships: <ShipPlacement>[
                      for (final ShipView ship in revealed.ships)
                        ShipPlacement(
                          shipId: ship.shipId,
                          length: ship.length,
                          span: ship.span,
                          orientation: ship.orientation,
                          row: ship.row,
                          column: ship.column,
                        ),
                    ],
                    sunkShips: <String>{
                      for (final ShipView ship in revealed.ships)
                        if (ship.sunk) ship.shipId,
                    },
                    shots: <CellCoord>{
                      for (final ShipView ship in revealed.ships)
                        ...ship.hitCells,
                      for (final ShotView shot in revealed.receivedShots)
                        if (shot.result != ShotResult.miss) shot.cell,
                    }.toList(),
                    shotColors: hitColors,
                    misses: <CellCoord>{
                      for (final ShotView shot in revealed.receivedShots)
                        if (shot.result == ShotResult.miss) shot.cell,
                    }.toList(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
