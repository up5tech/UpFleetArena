import '../../shared/models/room_models.dart';
import 'room_state.dart';

/// Builds the per-recipient view of the room.
///
/// The Host never serializes one internal state and broadcasts it to
/// everyone. Each recipient gets its own projection, so a field that only
/// makes sense for one viewer can never leak to the others (PLAN.md §6.6).
class ProjectionBuilder {
  const ProjectionBuilder();

  /// Builds the snapshot visible to [viewerPlayerId].
  ///
  /// Pass `null` for a view that is not bound to a player, such as a
  /// pre-join preview.
  RoomSnapshot buildFor(HostRoomState state, String? viewerPlayerId) {
    final List<PlayerSummary> players = state.orderedPlayers
        .map(
          (HostPlayer player) => player.toSummary().copyWith(
            ready: state.placements[player.playerId]?.ready ?? false,
          ),
        )
        .toList();

    return RoomSnapshot(
      roomId: state.roomId,
      status: state.status,
      config: state.config,
      players: players,
      viewerPlayerId: viewerPlayerId,
      viewerIsHost:
          viewerPlayerId != null && viewerPlayerId == state.hostPlayerId,
      stateVersion: state.stateVersion,
    );
  }
}
