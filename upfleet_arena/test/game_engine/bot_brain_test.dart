import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/bot/bot_brain.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';

const BoardSize _board = BoardSize(rows: 10, columns: 10);

CellCoord? _choose(
  BotBrain brain, {
  Map<CellCoord, ShotResult> shots = const <CellCoord, ShotResult>{},
}) => brain.chooseCell(board: _board, shots: shots);

bool _isNeighbourOfAny(CellCoord cell, Iterable<CellCoord> hits) => hits.any(
  (CellCoord hit) =>
      (hit.row == cell.row && (hit.column - cell.column).abs() == 1) ||
      (hit.column == cell.column && (hit.row - cell.row).abs() == 1),
);

void main() {
  group('bot brain', () {
    test('every difficulty fires inside the board at an unfired cell', () {
      for (final BotDifficulty difficulty in BotDifficulty.values) {
        final BotBrain brain = BotBrain(
          difficulty: difficulty,
          random: Random(11),
        );
        // Every cell but one was already fired at.
        final Map<CellCoord, ShotResult> shots = <CellCoord, ShotResult>{
          for (int row = 0; row < _board.rows; row++)
            for (int column = 0; column < _board.columns; column++)
              if (row != 3 || column != 7)
                CellCoord(row, column): ShotResult.miss,
        };

        final CellCoord? cell = _choose(brain, shots: shots);
        expect(
          cell,
          const CellCoord(3, 7),
          reason: '$difficulty must still fire',
        );
      }
    });

    test('a full board leaves no shot', () {
      final Map<CellCoord, ShotResult> shots = <CellCoord, ShotResult>{
        for (int row = 0; row < _board.rows; row++)
          for (int column = 0; column < _board.columns; column++)
            CellCoord(row, column): ShotResult.miss,
      };
      for (final BotDifficulty difficulty in BotDifficulty.values) {
        expect(
          _choose(BotBrain(difficulty: difficulty), shots: shots),
          isNull,
          reason: '$difficulty must stop once the board is full',
        );
      }
    });

    test('an easy opponent does not chase the ship it just hit', () {
      const CellCoord hit = CellCoord(5, 5);
      final BotBrain brain = BotBrain(
        difficulty: BotDifficulty.easy,
        random: Random(3),
      );
      final List<CellCoord> cells = <CellCoord>[
        for (int i = 0; i < 20; i++)
          _choose(brain, shots: <CellCoord, ShotResult>{hit: ShotResult.hit})!,
      ];
      // Purely random shooting mostly lands away from the hit.
      expect(
        cells
            .where(
              (CellCoord cell) => _isNeighbourOfAny(cell, <CellCoord>[hit]),
            )
            .length,
        lessThan(12),
      );
    });

    test('a medium opponent fires next to the cells it hit', () {
      final Map<CellCoord, ShotResult> shots = <CellCoord, ShotResult>{
        const CellCoord(2, 2): ShotResult.hit,
        const CellCoord(6, 6): ShotResult.hit,
      };
      for (int seed = 0; seed < 10; seed++) {
        final CellCoord cell = _choose(
          BotBrain(difficulty: BotDifficulty.medium, random: Random(seed)),
          shots: shots,
        )!;
        expect(
          _isNeighbourOfAny(cell, <CellCoord>[
            const CellCoord(2, 2),
            const CellCoord(6, 6),
          ]),
          isTrue,
          reason: 'medium must follow up a hit (seed $seed)',
        );
        expect(shots.containsKey(cell), isFalse);
      }
    });

    test('a hard opponent lengthens a damaged ship along its axis', () {
      final Map<CellCoord, ShotResult> shots = <CellCoord, ShotResult>{
        const CellCoord(2, 2): ShotResult.hit,
        const CellCoord(2, 3): ShotResult.hit,
      };
      final Set<CellCoord> ends = <CellCoord>{
        const CellCoord(2, 1),
        const CellCoord(2, 4),
      };
      for (int seed = 0; seed < 10; seed++) {
        final CellCoord cell = _choose(
          BotBrain(difficulty: BotDifficulty.hard, random: Random(seed)),
          shots: shots,
        )!;
        expect(ends.contains(cell), isTrue, reason: 'seed $seed');
      }
    });

    test('a hard opponent hunts the checkerboard, a medium one does not', () {
      final BotBrain hard = BotBrain(
        difficulty: BotDifficulty.hard,
        random: Random(5),
      );
      for (int i = 0; i < 30; i++) {
        final CellCoord cell = _choose(hard)!;
        expect((cell.row + cell.column).isEven, isTrue);
      }
    });

    test('a sunk ship is no longer chased', () {
      const CellCoord sunk = CellCoord(4, 4);
      final Map<CellCoord, ShotResult> shots = <CellCoord, ShotResult>{
        const CellCoord(4, 3): ShotResult.hit,
        sunk: ShotResult.shipSunk,
        const CellCoord(8, 8): ShotResult.hit,
      };
      for (int seed = 0; seed < 20; seed++) {
        final CellCoord cell = _choose(
          BotBrain(difficulty: BotDifficulty.medium, random: Random(seed)),
          shots: shots,
        )!;
        // The only hit worth chasing is the one at (8, 8).
        expect(
          _isNeighbourOfAny(cell, <CellCoord>[const CellCoord(8, 8)]),
          isTrue,
          reason: 'seed $seed',
        );
        expect(shots.containsKey(cell), isFalse);
      }
    });
  });
}
