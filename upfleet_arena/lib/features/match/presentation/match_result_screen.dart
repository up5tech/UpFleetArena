import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/match_models.dart';
import '../../rooms/domain/room_session_controller.dart';

/// The final result of a finished match.
///
/// It shows the winner, the elimination ranking and the statistics the Host
/// computed, and returns the player home (PLAN.md §2.10, §5.2).
class MatchResultScreen extends ConsumerWidget {
  const MatchResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final MatchResult? result = session.matchResult;

    if (result == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.matchResult)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  session.isInRoom
                      ? l10n.matchNotFinished
                      : l10n.roomHasClosed,
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

    final String? viewerPlayerId = session.playerId;
    final PlayerResultView? own = viewerPlayerId == null
        ? null
        : result.standingOf(viewerPlayerId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.matchResult),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            _WinnerCard(result: result, viewerPlayerId: viewerPlayerId),
            if (result.winnerPlayerId != null && result.fleets.isNotEmpty) ...<
              Widget
            >[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/match/result/fleets'),
                icon: const Icon(Icons.directions_boat_outlined),
                label: Text(l10n.reviewAllFleets),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              own == null
                  ? l10n.lastedDuration(_duration(result.durationSeconds))
                  : l10n.lastedDurationWithRank(
                      _duration(result.durationSeconds),
                      own.rank,
                    ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 20),
            Text(l10n.finalRanking, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final PlayerResultView entry in result.ranking) ...<Widget>[
              _RankingRow(
                entry: entry,
                isViewer: entry.playerId == viewerPlayerId,
                isWinner: entry.playerId == result.winnerPlayerId,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.rankingHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _returnHome(context, ref, session),
              icon: const Icon(Icons.home_outlined),
              label: Text(
                session.isHost && session.isInRoom
                    ? l10n.endRoomAndReturnHome
                    : l10n.returnHome,
              ),
            ),
            if (session.isHost && session.isInRoom) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.matchOverClosesRoom,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _returnHome(
    BuildContext context,
    WidgetRef ref,
    RoomSessionState session,
  ) async {
    final RoomSessionController controller = ref.read(
      roomSessionControllerProvider.notifier,
    );
    if (session.isInRoom) {
      if (session.isHost) {
        await controller.closeRoom();
      } else {
        await controller.leave();
      }
    }
    if (context.mounted) context.go('/');
  }
}

String _duration(int seconds) {
  final int minutes = seconds ~/ 60;
  final int rest = seconds % 60;
  return minutes == 0 ? '${rest}s' : '${minutes}m ${rest}s';
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.result, required this.viewerPlayerId});

  final MatchResult result;
  final String? viewerPlayerId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isWinner =
        result.winnerPlayerId != null && result.winnerPlayerId == viewerPlayerId;
    final String title = switch (result.winnerPlayerId) {
      null => l10n.nobodySurvived,
      _ when isWinner => l10n.youWonMatch,
      _ => l10n.playerWonMatch(result.winnerDisplayName ?? l10n.aPlayer),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.emoji_events, color: AppTheme.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.entry,
    required this.isViewer,
    required this.isWinner,
  });

  final PlayerResultView entry;
  final bool isViewer;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color badge = isWinner ? AppTheme.accent : AppTheme.surfaceBorder;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badge.withValues(alpha: isWinner ? 0.2 : 0.6),
                shape: BoxShape.circle,
                border: Border.all(color: badge),
              ),
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  color: isWinner ? AppTheme.accent : AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isViewer ? l10n.playerNameYou(entry.displayName) : entry.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.rankingStats(
                      entry.shots,
                      entry.hits,
                      entry.misses,
                      entry.shipsSunk,
                      entry.timeouts,
                    ),
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
    );
  }
}