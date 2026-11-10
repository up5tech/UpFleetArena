import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../game_engine/bot/bot_brain.dart';

/// The localized name of a difficulty level.
String botDifficultyLabel(AppLocalizations l10n, BotDifficulty difficulty) =>
    switch (difficulty) {
      BotDifficulty.easy => l10n.difficultyEasy,
      BotDifficulty.medium => l10n.difficultyMedium,
      BotDifficulty.hard => l10n.difficultyHard,
    };

/// A one-line description of how a difficulty level plays.
String botDifficultyHint(AppLocalizations l10n, BotDifficulty difficulty) =>
    switch (difficulty) {
      BotDifficulty.easy => l10n.difficultyEasyHint,
      BotDifficulty.medium => l10n.difficultyMediumHint,
      BotDifficulty.hard => l10n.difficultyHardHint,
    };

/// An icon that stands for a difficulty level.
IconData botDifficultyIcon(BotDifficulty difficulty) => switch (difficulty) {
  BotDifficulty.easy => Icons.sentiment_satisfied_alt_outlined,
  BotDifficulty.medium => Icons.smart_toy_outlined,
  BotDifficulty.hard => Icons.local_fire_department_outlined,
};

/// The display name a computer opponent of this strength is seated with.
String botDisplayName(AppLocalizations l10n, BotDifficulty difficulty) =>
    l10n.botDisplayName(botDifficultyLabel(l10n, difficulty));
