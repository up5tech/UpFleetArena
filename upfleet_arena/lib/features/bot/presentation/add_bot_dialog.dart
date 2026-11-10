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
        title: Text(l10n.addComputerTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.chooseDifficulty,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final BotDifficulty option in BotDifficulty.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    botDifficultyIcon(option),
                    color: difficulty == option
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                  ),
                  title: Text(botDifficultyLabel(l10n, option)),
                  subtitle: Text(botDifficultyHint(l10n, option)),
                  trailing: Icon(
                    difficulty == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: difficulty == option
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                    size: 18,
                  ),
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
