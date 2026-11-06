import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/game_engine/board/board.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/game_engine/placement/placement.dart';

void main() {
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

  group('shot resolution', () {
    test('a shot into the water misses', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'player-1',
        ships: <ShipPlacement>[ship(shipId: 'ship-1', length: 3)],
      );

      var resolution = resolveShot(
        board,
        const CellCoord(5, 5),
      );

      expect(resolution, isNotNull);
      expect(resolution.result, ShotResult.miss);
      expect(resolution.shipId, isNull);
    });

    test('a shot on a ship hits', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'player-1',
        ships: <ShipPlacement>[ship(shipId: 'ship-1', length: 3)],
      );

      var resolution = resolveShot(
        board,
        const CellCoord(0, 1),
      );

      expect(resolution.result, ShotResult.hit);
      expect(resolution.shipId, 'ship-1');
      expect(board.ships['ship-1']!.hitCells, hasLength(1));
      expect(board.ships['ship-1']!.isSunk, isFalse);
    });

    test('the last cell of a ship sinks it', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'player-1',
        ships: <ShipPlacement>[ship(shipId: 'ship-1', length: 2)],
      );

      resolveShot(board, const CellCoord(0, 0));
      final ShotResolution resolution = resolveShot(board, const CellCoord(0, 1));

      expect(resolution.result, ShotResult.shipSunk);
      expect(board.ships['ship-1']!.isSunk, isTrue);
      expect(resolveShot(board, const CellCoord(0, 1)).result, ShotResult.hit);
      expect(resolveShot(board, const CellCoord(0, 0)).result, ShotResult.hit);
      expect(board.sunkCount, 1);
      expect(board.remainingCells, 0);
      expect(board.ships['ship-1']!.hitCells, hasLength(2));
    });

    test('repeated cells resolve without applying damage twice', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'player-1',
        ships: <ShipPlacement>[ship(shipId: 'ship-1', length: 3)],
      );

      expect(resolveShot(board, const CellCoord(0, 0)).result, ShotResult.hit);
      expect(resolveShot(board, const CellCoord(0, 0)).result, ShotResult.hit);
      expect(board.shotsReceived, hasLength(1));
      expect(board.ships['ship-1']!.hitCells, hasLength(1));
      expect(board.remainingCells, 2);
      expect(resolveShot(board, const CellCoord(9, 9)).result, ShotResult.miss);
      expect(resolveShot(board, const CellCoord(9, 9)).result, ShotResult.miss);
      expect(board.shotsReceived, hasLength(2));
    });

    test('a player is eliminated when every ship was sunk', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'player-1',
        ships: <ShipPlacement>[
          ship(shipId: 'ship-1', length: 2),
          ship(shipId: 'ship-2', length: 2, row: 4),
        ],
      );

      expect(isPlayerEliminated(board), isFalse);

      resolveShot(board, const CellCoord(0, 0));
      resolveShot(board, const CellCoord(0, 1));
      expect(isPlayerEliminated(board), isFalse);

      resolveShot(board, const CellCoord(4, 0));
      resolveShot(board, const CellCoord(4, 1));
      expect(isPlayerEliminated(board), isTrue);
    });

    test('the sunk ships are counted', () {
      final PlayerBoard board = PlayerBoard(
        playerId: 'player-1',
        ships: <ShipPlacement>[
          ship(shipId: 'ship-1', length: 2),
          ship(shipId: 'ship-2', length: 2, row: 4),
        ],
      );

      resolveShot(board, const CellCoord(0, 0));
      resolveShot(board, const CellCoord(0, 1));

      expect(board.sunkCount, 1);
      expect(board.remainingCells, 2);
    });
  });

  group('turn order', () {
    bool alive(String playerId) => playerId != 'player-2';

    test('the next living player follows the current one', () {
      expect(
        getNextLivingPlayer(
          turnOrder: <String>['player-1', 'player-2', 'player-3'],
          currentPlayerId: 'player-1',
          isAlive: alive,
        ),
        'player-3',
      );
    });

    test('the order wraps around', () {
      expect(
        getNextLivingPlayer(
          turnOrder: <String>['player-1', 'player-2'],
          currentPlayerId: 'player-2',
          isAlive: alive,
        ),
        'player-1',
      );
    });

    test('there is no next player when everybody is gone', () {
      expect(
        getNextLivingPlayer(
          turnOrder: <String>['player-1', 'player-2'],
          currentPlayerId: 'player-1',
          isAlive: (String playerId) => false,
        ),
        isNull,
      );
    });

    test('the match ends when one player is left', () {
      expect(isMatchFinished(1), isTrue);
      expect(isMatchFinished(2), isFalse);
    });
  });
}
