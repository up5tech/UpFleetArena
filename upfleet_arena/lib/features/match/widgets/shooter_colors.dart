import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/match_models.dart';

/// The colour of every player on the shared battle map.
///
/// The shared map shows the fire of all players at once, so every shooter
/// needs a colour of their own. The colour is derived from the position in
/// the turn order, which every client knows, so all devices paint the same
/// shooter in the same colour.
class ShooterColors {
  const ShooterColors._();

  /// The colours used for the shooters, in the order they are handed out.
  static const List<Color> palette = <Color>[
    AppTheme.accent,
    Color(0xFFFF8A5B),
    Color(0xFF9B8CFF),
    Color(0xFF7ED957),
    Color(0xFFFF6BC1),
    Color(0xFF59C2FF),
    Color(0xFFFFD166),
    Color(0xFFC0C8D6),
  ];

  /// The colours of the players of a match, keyed by player id.
  ///
  /// Players that are not part of [players] fall back to the accent colour.
  static Map<String, Color> of(List<MatchPlayerView> players) {
    final Map<String, Color> colors = <String, Color>{};
    for (int index = 0; index < players.length; index++) {
      colors[players[index].playerId] =
          palette[index % palette.length];
    }
    return colors;
  }

  /// The colour of one player, or the accent colour when it is unknown.
  static Color ofPlayer(Map<String, Color> colors, String playerId) =>
      colors[playerId] ?? AppTheme.accent;
}
