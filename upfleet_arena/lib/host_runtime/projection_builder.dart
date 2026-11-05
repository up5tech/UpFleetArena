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
    final List<HostPlayer> ordered = state.players.values.toList()
      ..sort((HostPlayer a, HostPlayer b) {
        // The Host always comes first, then by join order.
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        final int byTime = a.joinedAt.compareTo(b.joinedAt);
        if (byTime != 0) return byTime;
        return a.playerId.compareTo(b.playerId);
      });

    final List<PlayerSummary> players = ordered
        .map((HostPlayer player) => player.toSummary())
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
