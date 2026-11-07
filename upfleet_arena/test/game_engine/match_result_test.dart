import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/combat/match_result.dart';

void main() {
  group('player statistics', () {
    test('a miss counts as a shot and a miss only', () {
      final PlayerMatchStats stats = PlayerMatchStats()
        ..recordShot(ShotResult.miss);

      expect(stats.shots, 1);
      expect(stats.misses, 1);
      expect(stats.hits, 0);
      expect(stats.shipsSunk, 0);
    });

    test('a hit counts as a shot and a hit', () {
      final PlayerMatchStats stats = PlayerMatchStats()
        ..recordShot(ShotResult.hit);

      expect(stats.shots, 1);
      expect(stats.hits, 1);
      expect(stats.misses, 0);
      expect(stats.shipsSunk, 0);
    });

    test('a sinking shot is a hit and a sunk ship at the same time', () {
      final PlayerMatchStats stats = PlayerMatchStats()
        ..recordShot(ShotResult.shipSunk);

      expect(stats.shots, 1);
      expect(stats.hits, 1);
      expect(stats.shipsSunk, 1);
      expect(stats.misses, 0);
    });

    test('shots always equal hits plus misses over a whole match', () {
      final PlayerMatchStats stats = PlayerMatchStats();
      for (final ShotResult result in <ShotResult>[
        ShotResult.miss,
        ShotResult.hit,
        ShotResult.shipSunk,
        ShotResult.miss,
        ShotResult.hit,
        ShotResult.shipSunk,
        ShotResult.shipSunk,
      ]) {
        stats.recordShot(result);
      }

      expect(stats.shots, 7);
      expect(stats.hits, 5);
      expect(stats.misses, 2);
      expect(stats.shipsSunk, 3);
      expect(stats.shots, stats.hits + stats.misses);
    });

    test('a player that never fired keeps empty statistics', () {
      final PlayerMatchStats stats = PlayerMatchStats();

      expect(stats.shots, 0);
      expect(stats.hits, 0);
      expect(stats.misses, 0);
      expect(stats.shipsSunk, 0);
    });
  });

  group('final ranking', () {
    test('the winner is first and the last fleet to sink is second', () {
      final List<PlayerStanding> ranking = buildRanking(
        turnOrder: <String>['alice', 'bob', 'carol'],
        eliminationOrder: <String>['alice', 'bob'],
        winnerPlayerId: 'carol',
      );

      expect(
        ranking.map((PlayerStanding s) => (s.rank, s.playerId)).toList(),
        <(int, String)>[(1, 'carol'), (2, 'bob'), (3, 'alice')],
      );
    });

    test('every player appears exactly once even though the winner is in the turn order', () {
      final List<PlayerStanding> ranking = buildRanking(
        turnOrder: <String>['alice', 'bob', 'carol', 'dave'],
        eliminationOrder: <String>['bob', 'alice', 'dave'],
        winnerPlayerId: 'carol',
      );

      expect(ranking.length, 4);
      expect(ranking.map((PlayerStanding s) => s.playerId).toSet().length, 4);
      expect(
        ranking.map((PlayerStanding s) => s.rank).toList(),
        <int>[1, 2, 3, 4],
      );
      expect(ranking.first.playerId, 'carol');
      expect(ranking[1].playerId, 'dave');
      expect(ranking[2].playerId, 'alice');
      expect(ranking[3].playerId, 'bob');
    });

    test('a two player match ranks the winner above the only eliminated player', () {
      final List<PlayerStanding> ranking = buildRanking(
        turnOrder: <String>['alice', 'bob'],
        eliminationOrder: <String>['bob'],
        winnerPlayerId: 'alice',
      );

      expect(ranking.length, 2);
      expect(ranking.first.playerId, 'alice');
      expect(ranking.first.rank, 1);
      expect(ranking.last.playerId, 'bob');
      expect(ranking.last.rank, 2);
    });

    test('without a winner the order falls back to eliminations then turn order', () {
      final List<PlayerStanding> ranking = buildRanking(
        turnOrder: <String>['alice', 'bob', 'carol', 'dave'],
        eliminationOrder: <String>['bob'],
        winnerPlayerId: null,
      );

      expect(
        ranking.map((PlayerStanding s) => s.playerId).toList(),
        <String>['bob', 'alice', 'carol', 'dave'],
      );
    });

    test('an empty match produces an empty ranking', () {
      expect(
        buildRanking(
          turnOrder: const <String>[],
          eliminationOrder: const <String>[],
          winnerPlayerId: null,
        ),
        isEmpty,
      );
    });
  });
}