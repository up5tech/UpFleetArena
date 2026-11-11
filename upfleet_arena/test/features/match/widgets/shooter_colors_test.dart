import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/match/widgets/shooter_colors.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';

void main() {
  group('shooter colours', () {
    const List<MatchPlayerView> players = <MatchPlayerView>[
      MatchPlayerView(
        playerId: 'alice',
        displayName: 'Alice',
        alive: true,
        timeouts: 0,
        shipsRemaining: 5,
      ),
      MatchPlayerView(
        playerId: 'bob',
        displayName: 'Bob',
        alive: true,
        timeouts: 0,
        shipsRemaining: 5,
      ),
    ];

    test('every player gets a colour of their own', () {
      final Map<String, Color> colors = ShooterColors.of(players);

      expect(colors.keys, containsAll(<String>['alice', 'bob']));
      expect(colors['alice'], isNot(colors['bob']));
    });

    test('the same player keeps the colour on every device', () {
      // The colours follow the turn order, which every client knows.
      expect(ShooterColors.of(players)['alice'], ShooterColors.of(players)['alice']);
    });

    test('an unknown player falls back to the accent colour', () {
      final Map<String, Color> colors = ShooterColors.of(players);

      expect(
        ShooterColors.ofPlayer(colors, 'nobody'),
        ShooterColors.palette.first,
      );
    });

    test('more players than colours still get a colour', () {
      final List<MatchPlayerView> many = <MatchPlayerView>[
        for (int index = 0; index < ShooterColors.palette.length + 2; index++)
          MatchPlayerView(
            playerId: 'player-$index',
            displayName: 'Player $index',
            alive: true,
            timeouts: 0,
            shipsRemaining: 5,
          ),
      ];

      final Map<String, Color> colors = ShooterColors.of(many);
      expect(colors, hasLength(ShooterColors.palette.length + 2));
      expect(colors.values.toSet(), hasLength(ShooterColors.palette.length));
    });
  });
}
