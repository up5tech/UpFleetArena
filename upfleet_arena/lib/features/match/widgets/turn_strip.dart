import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import 'turn_warning.dart';

/// The status of the running turn: whose turn it is and the clock.
///
/// The strip is the one place of the match that carries the countdown, so
/// nothing floats over the map and nothing repeats the clock in the roster.
/// A player passes `isMyTurn: true`; a spectator always watches.
class TurnStrip extends StatelessWidget {
  const TurnStrip({
    super.key,
    required this.isMyTurn,
    required this.activePlayerName,
    required this.remaining,
    required this.turnNumber,
  });

  final bool isMyTurn;
  final String activePlayerName;
  final int? remaining;
  final int turnNumber;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool urgent = isUrgentTurn(remaining);
    final Color iconColor = urgent
        ? AppTheme.danger
        : isMyTurn
        ? AppTheme.accent
        : AppTheme.sunk;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: urgent
            ? AppTheme.danger.withValues(alpha: 0.12)
            : isMyTurn
            ? AppTheme.accent.withValues(alpha: 0.1)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: urgent
              ? AppTheme.danger.withValues(alpha: 0.6)
              : isMyTurn
              ? AppTheme.accent.withValues(alpha: 0.45)
              : AppTheme.surfaceBorder,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.14),
            ),
            child: Icon(
              urgent
                  ? Icons.timer_outlined
                  : isMyTurn
                  ? Icons.gps_fixed
                  : Icons.hourglass_empty,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isMyTurn
                      ? l10n.yourTurn
                      : l10n.playerIsShooting(activePlayerName),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: urgent ? AppTheme.danger : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining == null
                      ? l10n.turnLabel(turnNumber)
                      : l10n.turnLabelWithTime(turnNumber, remaining!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: urgent ? AppTheme.danger : AppTheme.textSecondary,
                    fontWeight: urgent ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
