import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/board/board.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../shared/models/match_models.dart';
import '../../../shared/widgets/board_canvas.dart';
import '../../rooms/domain/room_session_controller.dart';
import '../widgets/battle_board.dart';

/// The screen of a running match.
///
/// It shows whose turn it is, the board of the selected opponent and the
/// action that fires at a cell (PLAN.md §5.2).
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  String? _selectedTargetId;
  CellCoord? _selectedCell;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final MatchSnapshot? snapshot = session.matchSnapshot;

    if (!session.isInRoom) {
      return Scaffold(
        appBar: AppBar(title: const Text('Match ended')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(session.errorMessage ?? 'The room has closed.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _exit(session), child: const Text('Back to home')),
          ]),
        )),
      );
    }
    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('The match')),
        body: const Center(child: Text('The match has not started yet.')),
      );
    }

    ref.listen(roomSessionControllerProvider, (previous, next) {
      if (previous?.matchSnapshot?.turnNumber != next.matchSnapshot?.turnNumber ||
          previous?.matchSnapshot?.matchId != next.matchSnapshot?.matchId ||
          next.matchSnapshot?.targetById(_selectedTargetId ?? '')?.alive == false) {
        setState(() => _selectedCell = null);
      }
    });
    final bool isMyTurn = session.isInRoom && snapshot.winnerPlayerId == null &&
        snapshot.activePlayerId == session.playerId &&
        snapshot.playerById(session.playerId ?? '')?.alive == true;
    final int? remaining = session.turnCountdown?.remaining;

    final List<TargetBoardView> living = snapshot.livingTargets;
    final String? targetId = living.any((target) => target.playerId == _selectedTargetId)
        ? _selectedTargetId : living.firstOrNull?.playerId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('The match'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'Battle'),
            Tab(text: 'Your board'),
            Tab(text: 'Players'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: <Widget>[
            _BattleTab(
              snapshot: snapshot,
              session: session,
              isMyTurn: isMyTurn,
              remaining: remaining,
              selectedTargetId: targetId,
              selectedCell: _selectedCell,
              onTargetSelected: (String targetId) {
                setState(() {
                  _selectedTargetId = targetId;
                  _selectedCell = null;
                });
              },
              onCellTapped: (CellCoord cell) {
                setState(() => _selectedCell = cell);
              },
              onFire: () { if (targetId != null) unawaited(_fire(targetId)); },
            ),
            _OwnBoardTab(snapshot: snapshot, session: session),
            _PlayersTab(snapshot: snapshot, session: session),
          ],
        ),
      ),
    );
  }

  Future<void> _exit(RoomSessionState session) async {
    if (session.isInRoom) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(session.isHost ? 'End the room?' : 'Leave the match?'),
          content: Text(
            session.isHost
                ? 'This ends the match for every player.'
                : 'You will leave this match.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final RoomSessionController controller = ref.read(
      roomSessionControllerProvider.notifier,
    );
    if (session.isHost) {
      await controller.closeRoom();
    } else {
      await controller.leave();
    }
    if (mounted) context.go('/');
  }

  Future<void> _fire(String targetId) async {
    final CellCoord? cell = _selectedCell;
    if (cell == null) return;

    setState(() => _selectedCell = null);
    await ref
        .read(roomSessionControllerProvider.notifier)
        .fire(
          targetPlayerId: targetId,
          row: cell.row,
          column: cell.column,
        );
  }
}

class _BattleTab extends StatelessWidget {
  const _BattleTab({
    required this.snapshot,
    required this.session,
    required this.isMyTurn,
    required this.remaining,
    required this.selectedTargetId,
    required this.selectedCell,
    required this.onTargetSelected,
    required this.onCellTapped,
    required this.onFire,
  });

  final MatchSnapshot snapshot;
  final RoomSessionState session;
  final bool isMyTurn;
  final int? remaining;
  final String? selectedTargetId;
  final CellCoord? selectedCell;
  final ValueChanged<String> onTargetSelected;
  final ValueChanged<CellCoord> onCellTapped;
  final VoidCallback onFire;

  @override
  Widget build(BuildContext context) {
    final List<TargetBoardView> targets = snapshot.livingTargets;
    final TargetBoardView? target = selectedTargetId == null
        ? null
        : snapshot.targetById(selectedTargetId!);

    final bool alreadyFired = target != null &&
        selectedCell != null &&
        target.shots.any(
          (ShotView shot) =>
              shot.row == selectedCell!.row &&
              shot.column == selectedCell!.column,
        );
    final bool canInteract = isMyTurn && !session.firePending && remaining != 0;
    final bool canFire = canInteract && target?.alive == true &&
        selectedCell != null && !alreadyFired;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        if (snapshot.winnerPlayerId != null) ...<Widget>[
          _WinnerCard(
            winnerPlayerId: snapshot.winnerPlayerId!,
            viewerPlayerId: session.playerId ?? '',
          ),
          const SizedBox(height: 12),
        ],
        if (session.combatError != null) ...[
          Text(session.combatError!, style: const TextStyle(color: AppTheme.danger)),
          const SizedBox(height: 12),
        ],
        if (session.lastActivity case final PublicActivity activity) ...[
          Text('${snapshot.playerById(activity.attackerPlayerId)?.displayName ?? 'A player'} '
              '${switch (activity.result) { ShotResult.miss => 'missed', ShotResult.hit => 'hit', ShotResult.shipSunk => 'sank a ship belonging to' }} '
              '${snapshot.playerById(activity.targetPlayerId)?.displayName ?? 'another player'}.'),
          const SizedBox(height: 12),
        ],
        if (snapshot.winnerPlayerId == null) _TurnCard(
          isMyTurn: isMyTurn,
          activePlayerName:
              snapshot.playerById(snapshot.activePlayerId)?.displayName ?? '',
          remaining: remaining,
          turnNumber: snapshot.turnNumber,
        ),
        if (session.lastShot != null) ...<Widget>[
          const SizedBox(height: 12),
          _FeedbackCard(
            feedback: session.lastShot!,
            viewerPlayerId: session.playerId,
          ),
        ],
        const SizedBox(height: 16),
        Text('Target', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (targets.isEmpty)
          const Text('There is nobody left to shoot at.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final TargetBoardView opponent in targets)
                ChoiceChip(
                  label: Text(opponent.displayName),
                  selected: opponent.playerId == selectedTargetId,
                  onSelected: canInteract ? (_) => onTargetSelected(opponent.playerId) : null,
                ),
            ],
          ),
        const SizedBox(height: 16),
        if (target != null)
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              final int rows = session.snapshot?.config.rows ?? 10;
              final int columns = session.snapshot?.config.columns ?? 10;
              return SizedBox(
                width: width,
                height: width * rows / columns,
                child: BattleBoard(
                  rows: rows,
                  columns: columns,
                  shots: target.shots,
                  selectedCell: selectedCell,
                  enabled: canInteract,
                  onCellTapped: onCellTapped,
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        const Text('Dot: miss · Cross: hit · Ring: sunk'),
        if (selectedCell != null)
          Text('Selected: ${String.fromCharCode(65 + selectedCell!.column)}${selectedCell!.row + 1}'
              '${alreadyFired ? ' — already fired here' : ''}'),
        const SizedBox(height: 16),
        if (snapshot.winnerPlayerId == null) FilledButton.icon(
          onPressed: canFire ? onFire : null,
          icon: const Icon(Icons.local_fire_department),
          label: Text(
            session.firePending ? 'Waiting for host…' :
                isMyTurn ? 'Fire at this cell' : 'Wait for your turn',
          ),
        ),
      ],
    );
  }
}

class _OwnBoardTab extends StatelessWidget {
  const _OwnBoardTab({required this.snapshot, required this.session});

  final MatchSnapshot snapshot;
  final RoomSessionState session;

  @override
  Widget build(BuildContext context) {
    final OwnBoardView? board = snapshot.ownBoard;
    final int rows = session.snapshot?.config.rows ?? 10;
    final int columns = session.snapshot?.config.columns ?? 10;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text('Your fleet', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (board == null)
          const Text('Your board is not available.')
        else ...<Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              return SizedBox(
                width: width,
                height: width * rows / columns,
                child: BoardCanvas(
                  rows: rows,
                  columns: columns,
                  ships: board.ships
                      .map(
                        (ShipView ship) => ShipPlacement(
                          shipId: ship.shipId,
                          length: ship.length,
                          orientation: ship.orientation,
                          row: ship.row,
                          column: ship.column,
                        ),
                      )
                      .toList(),
                  sunkShips: board.ships
                      .where((ShipView ship) => ship.sunk)
                      .map((ShipView ship) => ship.shipId)
                      .toSet(),
                  shots: board.ships.expand((ShipView ship) => ship.hitCells).toList(),
                  misses: board.shotsReceived
                      .where((CellCoord cell) => !board.ships.any((ShipView ship) => ship.hitCells.contains(cell)))
                      .toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'The red cells are the hits on your fleet. Only you and the host '
            'see this board.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ],
    );
  }
}

class _PlayersTab extends StatelessWidget {
  const _PlayersTab({required this.snapshot, required this.session});

  final MatchSnapshot snapshot;
  final RoomSessionState session;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text('Turn order', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final MatchPlayerView player in snapshot.players)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    player.playerId == session.playerId
                        ? '${player.displayName} (you)'
                        : player.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: player.playerId == snapshot.activePlayerId
                          ? FontWeight.w700
                          : null,
                    ),
                  ),
                ),
                if (player.timeouts > 0)
                  Text(
                    '${player.timeouts} timeouts',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                const SizedBox(width: 8),
                Icon(
                  player.alive ? Icons.circle : Icons.person_off,
                  size: 14,
                  color: player.alive ? AppTheme.accent : AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  player.alive ? 'In the match' : 'Eliminated',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: player.alive
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.winnerPlayerId, required this.viewerPlayerId});

  final String winnerPlayerId;
  final String? viewerPlayerId;

  @override
  Widget build(BuildContext context) {
    final bool isWinner = winnerPlayerId == viewerPlayerId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.emoji_events, color: AppTheme.accent, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isWinner ? 'You won the match.' : 'The match is over.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnCard extends StatelessWidget {
  const _TurnCard({
    required this.isMyTurn,
    required this.activePlayerName,
    required this.remaining,
    required this.turnNumber,
  });

  final bool isMyTurn;
  final String activePlayerName;
  final int? remaining;
  final int turnNumber;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(
              isMyTurn ? Icons.gps_fixed : Icons.hourglass_empty,
              color: isMyTurn ? AppTheme.accent : AppTheme.sunk,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isMyTurn
                        ? 'Your turn'
                        : '$activePlayerName is shooting',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Turn $turnNumber'
                    '${remaining == null ? '' : ' · ${remaining}s left'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback, required this.viewerPlayerId});

  final ShotFeedback feedback;
  final String? viewerPlayerId;

  @override
  Widget build(BuildContext context) {
    final bool isAttacker = feedback.attackerPlayerId == viewerPlayerId;
    final bool isTarget = feedback.targetPlayerId == viewerPlayerId;

    final String text;
    final Color color;
    if (isAttacker) {
      switch (feedback.result) {
        case ShotResult.miss:
          text = 'Your shot missed.';
          color = AppTheme.miss;
        case ShotResult.hit:
          text = 'Your shot hit a ship.';
          color = AppTheme.hit;
        case ShotResult.shipSunk:
          text = 'Your shot sank a ship.';
          color = AppTheme.sunk;
      }
    } else if (isTarget) {
      switch (feedback.result) {
        case ShotResult.miss:
          text = 'A shot missed your board.';
          color = AppTheme.miss;
        case ShotResult.hit:
          text = 'A shot hit one of your ships.';
          color = AppTheme.hit;
        case ShotResult.shipSunk:
          text = 'One of your ships was sunk.';
          color = AppTheme.sunk;
      }
    } else {
      text = 'The other players are shooting at each other.';
      color = AppTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            feedback.result == ShotResult.miss
                ? Icons.block
                : Icons.local_fire_department,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
