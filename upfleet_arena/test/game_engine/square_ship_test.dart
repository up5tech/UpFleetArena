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

/// A square ship covers length × span cells instead of a single line.
void main() {
  group('square ships', () {
    test('a 2×2 ship covers four cells', () {
      const ShipPlacement square = ShipPlacement(
        shipId: 'ship-1',
        length: 2,
        span: 2,
        orientation: ShipOrientation.horizontal,
        row: 1,
        column: 1,
      );

      expect(square.cells, <CellCoord>[
        const CellCoord(1, 1),
        const CellCoord(1, 2),
        const CellCoord(2, 1),
        const CellCoord(2, 2),
      ]);
      expect(square.isSquare, isTrue);
      // A square looks the same in both directions.
      expect(square.rotated(), square);
    });

    test('a square ship sinks only when its last cell is hit', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'alice',
        ships: const <ShipPlacement>[
          ShipPlacement(
            shipId: 'square',
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
      expect(board.ships['square']!.isSunk, isTrue);
      expect(board.isEliminated, isFalse);
    });

    test('the standard preset seats a 2×2 block', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

      expect(profile.shipCount, 5);
      expect(profile.cellsOf('ship-4'), 4);
      expect(profile.totalCells, 16);
      expect(FleetPreset.standard.totalCells, 16);
      expect(FleetPreset.standard.shipSummary, '4, 3, 3, 2×2, 2');
    });

    test('a line cannot be placed as a square', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.small);

      final PlacementError? error = validateShipPlacement(
        board: const BoardSize(rows: 10, columns: 10),
        profile: profile,
        ships: const <ShipPlacement>[],
        candidate: const ShipPlacement(
          shipId: 'ship-1',
          length: 3,
          span: 3,
          orientation: ShipOrientation.horizontal,
          row: 0,
          column: 0,
        ),
      );

      expect(error?.problem, PlacementProblem.wrongShape);
    });

    test('a square ship is accepted when it fits', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

      final PlacementError? error = validateShipPlacement(
        board: const BoardSize(rows: 10, columns: 10),
        profile: profile,
        ships: const <ShipPlacement>[],
        candidate: const ShipPlacement(
          shipId: 'ship-4',
          length: 2,
          span: 2,
          orientation: ShipOrientation.horizontal,
          row: 0,
          column: 0,
        ),
      );

      expect(error, isNull);
    });

    test('automatic placement seats every block with its four cells', () {
      final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

      final List<ShipPlacement> ships = autoPlaceFleet(
        board: const BoardSize(rows: 10, columns: 10),
        profile: profile,
        random: Random(7),
      );

      expect(ships.length, profile.shipCount);
      final ShipPlacement square = ships.firstWhere(
        (ShipPlacement ship) => ship.isSquare,
      );
      expect(square.cells.length, 4);
      expect(ships.expand((ShipPlacement ship) => ship.cells).toSet().length,
          profile.totalCells);
    });

    test('the wire form keeps the span', () {
      const ShipPlacement square = ShipPlacement(
        shipId: 'ship-4',
        length: 2,
        span: 2,
        orientation: ShipOrientation.vertical,
        row: 3,
        column: 5,
      );

      final ShipLayout layout = ShipLayout.fromJson(
        ShipLayout.fromPlacement(square).toJson(),
      );

      expect(layout.span, 2);
      expect(layout.toPlacement(), square);
    });
  });
}
