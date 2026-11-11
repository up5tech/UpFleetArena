import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/fleet/fleet_profile.dart';
import 'package:upfleet_arena/game_engine/placement/auto_placement.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/game_engine/placement/placement_validator.dart';
import 'package:upfleet_arena/shared/models/placement_models.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

/// A ship whose cells form a square may be placed as a block instead of a line.
void main() {
  group('square ships', () {
    const BoardSize board = BoardSize(rows: 10, columns: 10);

    test('a 2×2 block covers four cells', () {
      const ShipPlacement block = ShipPlacement(
        shipId: 'ship-1',
        length: 2,
        span: 2,
        orientation: ShipOrientation.horizontal,
        row: 1,
        column: 1,
      );

      expect(block.cells, <CellCoord>[
        const CellCoord(1, 1),
        const CellCoord(1, 2),
        const CellCoord(2, 1),
        const CellCoord(2, 2),
      ]);
      expect(block.isSquare, isTrue);
      // A block looks the same in both directions.
      expect(block.rotated(), block);
    });

    test('a block sinks only when its last cell is hit', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'alice',
        ships: const <ShipPlacement>[
          ShipPlacement(
            shipId: 'block',
            length: 2,
            span: 2,
            orientation: ShipOrientation.horizontal,
            row: 0,
            column: 0,
          ),
          ShipPlacement(
            shipId: 'line',
            length: 3,
            orientation: ShipOrientation.horizontal,
            row: 4,
            column: 0,
          ),
        ],
      );

      expect(resolveShot(board, const CellCoord(0, 0)).result, ShotResult.hit);
      expect(resolveShot(board, const CellCoord(0, 1)).result, ShotResult.hit);
      expect(resolveShot(board, const CellCoord(1, 0)).result, ShotResult.hit);
      // The fourth cell is what sinks the block, not its length.
      expect(
        resolveShot(board, const CellCoord(1, 1)).result,
        ShotResult.shipSunk,
      );
      expect(board.ships['block']!.isSunk, isTrue);
      expect(board.isEliminated, isFalse);
    });

    test('only perfect squares can be drawn as a block', () {
      expect(FleetProfile.squareSideFor(4), 2);
      expect(FleetProfile.squareSideFor(9), 3);
      expect(FleetProfile.squareSideFor(16), 4);
      expect(FleetProfile.squareSideFor(8), isNull);
      expect(FleetProfile.squareSideFor(1), isNull);
    });

    test('a preset states the cells, not the shape', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

      expect(FleetPreset.standard.totalCells, 14);
      expect(FleetPreset.standard.shipSummary, '4, 3, 3, 2, 2');
      // The four-cell ship can be a 2×2 block, the three-cell ones cannot.
      expect(profile.cellsOf('ship-1'), 4);
      expect(profile.squareSideOf('ship-1'), 2);
      expect(profile.squareSideOf('ship-2'), isNull);
    });

    test('a four-cell ship is accepted as a line or as a block', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

      expect(
        validateShipPlacement(
          board: board,
          profile: profile,
          ships: const <ShipPlacement>[],
          candidate: const ShipPlacement(
            shipId: 'ship-1',
            length: 4,
            orientation: ShipOrientation.horizontal,
            row: 0,
            column: 0,
          ),
        ),
        isNull,
      );
      expect(
        validateShipPlacement(
          board: board,
          profile: profile,
          ships: const <ShipPlacement>[],
          candidate: const ShipPlacement(
            shipId: 'ship-1',
            length: 2,
            span: 2,
            orientation: ShipOrientation.horizontal,
            row: 6,
            column: 0,
          ),
        ),
        isNull,
      );
    });

    test('a block that changes the cell count is rejected', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

      final PlacementError? error = validateShipPlacement(
        board: board,
        profile: profile,
        ships: const <ShipPlacement>[],
        candidate: const ShipPlacement(
          shipId: 'ship-1',
          length: 3,
          span: 2,
          orientation: ShipOrientation.horizontal,
          row: 0,
          column: 0,
        ),
      );

      expect(error?.problem, PlacementProblem.wrongLength);
    });

    test('a three-cell ship cannot be a block', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

      final PlacementError? error = validateShipPlacement(
        board: board,
        profile: profile,
        ships: const <ShipPlacement>[],
        candidate: const ShipPlacement(
          shipId: 'ship-2',
          length: 1,
          span: 3,
          orientation: ShipOrientation.horizontal,
          row: 0,
          column: 0,
        ),
      );

      expect(error?.problem, PlacementProblem.wrongShape);
    });

    test('a nine-cell ship can be a 3×3 block', () {
      const FleetProfile profile = FleetProfile(<int>[9, 3]);

      expect(profile.squareSideOf('ship-1'), 3);
      expect(
        validateShipPlacement(
          board: board,
          profile: profile,
          ships: const <ShipPlacement>[],
          candidate: const ShipPlacement(
            shipId: 'ship-1',
            length: 3,
            span: 3,
            orientation: ShipOrientation.horizontal,
            row: 2,
            column: 2,
          ),
        ),
        isNull,
      );
    });

    test('automatic placement sometimes seats a four-cell ship as a block', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);
      final Set<bool> blockSeen = <bool>{};

      for (int seed = 0; seed < 12; seed++) {
        final List<ShipPlacement> ships = autoPlaceFleet(
          board: board,
          profile: profile,
          random: Random(seed),
        );

        expect(ships, hasLength(profile.shipCount));
        expect(
          validateFleetLayout(board: board, profile: profile, ships: ships),
          isNull,
        );
        // A block keeps the cells of its ship: the layout still fills the
        // whole fleet without overlapping.
        expect(
          ships.expand((ShipPlacement ship) => ship.cells).toSet().length,
          profile.totalCells,
        );
        blockSeen.add(ships.any((ShipPlacement ship) => ship.isSquare));
      }

      expect(blockSeen, <bool>{true, false});
    });

    test('the wire form keeps the block', () {
      const ShipPlacement block = ShipPlacement(
        shipId: 'ship-1',
        length: 2,
        span: 2,
        orientation: ShipOrientation.vertical,
        row: 3,
        column: 5,
      );

      final ShipLayout layout = ShipLayout.fromJson(
        ShipLayout.fromPlacement(block).toJson(),
      );

      expect(layout.span, 2);
      expect(layout.toPlacement(), block);
    });
  });
}
