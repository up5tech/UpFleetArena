import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/bot/bot_brain.dart';
import 'bot_labels.dart';

/// Asks which strength a new computer opponent should have.
///
/// Returns `null` when the Host cancelled the dialog.
Future<BotDifficulty?> showAddBotDialog(BuildContext context) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  BotDifficulty difficulty = BotDifficulty.medium;

  return showDialog<BotDifficulty>(
    context: context,
    builder: (BuildContext dialogContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
        // Leaves more room for the hint text on narrow phones.
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Text(l10n.addComputerTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.chooseDifficulty,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.35),
              ),
              const SizedBox(height: 4),
              for (final BotDifficulty option in BotDifficulty.values)
                _DifficultyChoice(
                  label: botDifficultyLabel(l10n, option),
                  hint: botDifficultyHint(l10n, option),
                  selected: difficulty == option,
                  onTap: () => setDialogState(() => difficulty = option),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(difficulty),
            child: Text(l10n.addComputer),
          ),
        ],
      ),
    ),
  );
}

/// One strength option: the radio marker plus the label and its explanation.
///
/// A plain row rather than a [ListTile], so the explanation gets the full
/// dialog width instead of being squeezed between leading and trailing icons.
class _DifficultyChoice extends StatelessWidget {
  const _DifficultyChoice({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppTheme.accent : AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
