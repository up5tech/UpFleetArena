import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/fleet/fleet_profile.dart';
import 'package:upfleet_arena/game_engine/placement/auto_placement.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';
import 'package:upfleet_arena/game_engine/placement/placement_validator.dart';
import 'package:upfleet_arena/shared/models/room_models.dart';

void main() {
  const BoardSize board = BoardSize(rows: 10, columns: 10);
  final FleetProfile profile = FleetProfile.fromPreset(FleetPreset.standard);

  ShipPlacement ship({
    required String shipId,
    required int length,
    int row = 0,
    int column = 0,
    ShipOrientation orientation = ShipOrientation.horizontal,
  }) => ShipPlacement(
    shipId: shipId,
    length: length,
    orientation: orientation,
    row: row,
    column: column,
  );

  group('ship cells', () {
    test('a horizontal ship grows to the right', () {
      expect(
        getShipCells(
          row: 2,
          column: 3,
          orientation: ShipOrientation.horizontal,
          length: 3,
        ),
        <CellCoord>[const CellCoord(2, 3), const CellCoord(2, 4), const CellCoord(2, 5)],
      );
    });

    test('a vertical ship grows downwards', () {
      expect(
        getShipCells(
          row: 2,
          column: 3,
          orientation: ShipOrientation.vertical,
          length: 2,
        ),
        <CellCoord>[const CellCoord(2, 3), const CellCoord(3, 3)],
      );
    });

    test('a rotated ship keeps its anchor cell', () {
      final ShipPlacement placed = ship(shipId: 'ship-1', length: 3);
      expect(placed.rotated().cells.first, const CellCoord(0, 0));
      expect(placed.rotated().orientation, ShipOrientation.vertical);
    });
  });

  group('placement validation', () {
    test('a ship outside the board is rejected', () {
      final PlacementError? error = validateShipPlacement(
        board: board,
        profile: profile,
        ships: const <ShipPlacement>[],
        candidate: ship(shipId: 'ship-1', length: 4, row: 9, column: 8),
      );

      expect(error, isNotNull);
      expect(error!.problem, PlacementProblem.outOfBounds);
    });

    test('an overlapping ship is rejected', () {
      final List<ShipPlacement> placed = <ShipPlacement>[
        ship(shipId: 'ship-1', length: 4, row: 2, column: 2),
      ];

      final PlacementError? error = validateShipPlacement(
        board: board,
        profile: profile,
        ships: placed,
        candidate: ship(shipId: 'ship-2', length: 3, row: 2, column: 4),
      );

      expect(error, isNotNull);
      expect(error!.problem, PlacementProblem.overlapping);
    });

    test('ships may touch each other', () {
      final List<ShipPlacement> placed = <ShipPlacement>[
        ship(shipId: 'ship-1', length: 4, row: 2, column: 2),
      ];

      final PlacementError? error = validateShipPlacement(
        board: board,
        profile: profile,
        ships: placed,
        candidate: ship(shipId: 'ship-2', length: 3, row: 2, column: 6),
      );

      expect(error, isNull);
    });

    test('a ship that is not part of the fleet is rejected', () {
      final PlacementError? error = validateShipPlacement(
        board: board,
        profile: profile,
        ships: const <ShipPlacement>[],
        candidate: ship(shipId: 'ship-9', length: 4),
      );

      expect(error, isNotNull);
      expect(error!.problem, PlacementProblem.unknownShip);
    });

    test('a ship with the wrong length is rejected', () {
      final PlacementError? error = validateShipPlacement(
        board: board,
        profile: profile,
        ships: const <ShipPlacement>[],
        candidate: ship(shipId: 'ship-1', length: 2),
      );

      expect(error, isNotNull);
      expect(error!.problem, PlacementProblem.wrongLength);
    });

    test('a legal layout passes the validation', () {
      final List<ShipPlacement> ships = <ShipPlacement>[
        ship(shipId: 'ship-1', length: 4, row: 0, column: 0),
        ship(shipId: 'ship-2', length: 3, row: 2, column: 0),
        ship(shipId: 'ship-3', length: 3, row: 4, column: 0),
        ship(shipId: 'ship-4', length: 2, row: 6, column: 0),
        ship(shipId: 'ship-5', length: 2, row: 8, column: 0),
      ];

      expect(
        validateFleetLayout(
          board: board,
          profile: profile,
          ships: ships,
        ),
        isNull,
      );
      expect(isFleetComplete(profile, ships), isTrue);
    });

    test('the same ship may not be sent twice', () {
      final List<ShipPlacement> ships = <ShipPlacement>[
        ship(shipId: 'ship-1', length: 4, row: 0, column: 0),
        ship(shipId: 'ship-1', length: 4, row: 5, column: 5),
      ];

      final PlacementError? error = validateFleetLayout(
        board: board,
        profile: profile,
        ships: ships,
      );

      expect(error, isNotNull);
      expect(error!.problem, PlacementProblem.unknownShip);
    });

    test('an incomplete fleet is not complete', () {
      final List<ShipPlacement> ships = <ShipPlacement>[
        ship(shipId: 'ship-1', length: 4, row: 0, column: 0),
      ];

      expect(isFleetComplete(profile, ships), isFalse);
    });
  });

  group('fleet profile', () {
    test('the ship identifiers are stable', () {
      expect(profile.shipIds, <String>['ship-1', 'ship-2', 'ship-3', 'ship-4', 'ship-5']);
      expect(profile.lengthOf('ship-1'), 4);
      expect(profile.lengthOf('ship-5'), 2);
      expect(profile.lengthOf('ship-9'), isNull);
    });

    test('a fleet that does not fit is reported', () {
      final FleetProfile large = FleetProfile.fromPreset(FleetPreset.large);
      expect(validateFleetProfile(large, 2, 2), isNotEmpty);
      expect(validateFleetProfile(profile, 10, 10), isEmpty);
    });
  });

  group('auto placement', () {
    test('every ship is placed inside the board without overlaps', () {
      final List<ShipPlacement> ships = autoPlaceFleet(
        board: board,
        profile: profile,
        random: Random(7),
      );

      expect(ships, hasLength(profile.shipCount));
      expect(
        validateFleetLayout(board: board, profile: profile, ships: ships),
        isNull,
      );
      expect(isFleetComplete(profile, ships), isTrue);
    });

    test('the same seed produces the same layout', () {
      final List<ShipPlacement> first = autoPlaceFleet(
        board: board,
        profile: profile,
        random: Random(42),
      );
      final List<ShipPlacement> second = autoPlaceFleet(
        board: board,
        profile: profile,
        random: Random(42),
      );

      expect(first, second);
    });

    test('a rectangular board is handled', () {
      const BoardSize narrow = BoardSize(rows: 14, columns: 8);
      final List<ShipPlacement> ships = autoPlaceFleet(
        board: narrow,
        profile: profile,
        random: Random(3),
      );

      expect(
        validateFleetLayout(board: narrow, profile: profile, ships: ships),
        isNull,
      );
    });
  });
}
