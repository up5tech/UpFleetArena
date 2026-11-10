import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/match_feedback.dart';
import '../../../core/settings/feedback_settings.dart';
import '../../../game_engine/board/board.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../shared/models/match_models.dart';
import '../../../shared/widgets/board_canvas.dart';
import '../../rooms/domain/room_session_controller.dart';
import '../widgets/battle_board.dart';
import '../widgets/spectator_view.dart';

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
  TabController? _tabs;
  bool? _tabsReducedMotion;
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
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final MatchSnapshot? snapshot = session.matchSnapshot;

    if (!session.isInRoom) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.matchEnded)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.errorMessage ?? l10n.roomHasClosed),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _exit(session),
                  child: Text(l10n.backToHome),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.theMatch)),
        body: Center(child: Text(l10n.matchNotStarted)),
      );
    }

    ref.listen(roomSessionControllerProvider, (previous, next) {
      if (previous?.matchSnapshot?.turnNumber !=
              next.matchSnapshot?.turnNumber ||
          previous?.matchSnapshot?.matchId != next.matchSnapshot?.matchId ||
          next.matchSnapshot?.targetById(_selectedTargetId ?? '')?.alive ==
              false) {
        setState(() => _selectedCell = null);
      }

      final MatchFeedback feedback = ref.read(matchFeedbackProvider);
      final String viewer = next.playerId ?? '';
      // A fresh shot the local player was involved in.
      if (next.lastShot != null &&
          !identical(previous?.lastShot, next.lastShot)) {
        feedback.shotResolved(next.lastShot!, viewer);
      }
      // The Host broadcast the final result for the first time.
      if (next.matchResult != null && previous?.matchResult == null) {
        feedback.matchFinished(won: next.matchResult!.winnerPlayerId == viewer);
      }
    });

    // Reduced motion shortens the tab transition to zero (PLAN.md §5.5).
    final FeedbackSettings settings = ref.watch(feedbackSettingsProvider);
    final bool reducedMotion = useReducedMotion(context, settings);
    if (_tabs == null || _tabsReducedMotion != reducedMotion) {
      final int index = _tabs?.index ?? 0;
      _tabs?.dispose();
      _tabs = TabController(
        length: 3,
        vsync: this,
        initialIndex: index,
        animationDuration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
      _tabsReducedMotion = reducedMotion;
    }
    final TabController tabs = _tabs!;
    final bool isMyTurn =
        session.isInRoom &&
        snapshot.winnerPlayerId == null &&
        snapshot.activePlayerId == session.playerId &&
        snapshot.playerById(session.playerId ?? '')?.alive == true;
    final int? remaining = session.turnCountdown?.remaining;

    final List<TargetBoardView> living = snapshot.livingTargets;
    final String? targetId =
        living.any((target) => target.playerId == _selectedTargetId)
        ? _selectedTargetId
        : living.firstOrNull?.playerId;
    final bool spectating = session.isSpectating;

    WidgetsBinding.instance.addPostFrameCallback((_) => _followPhase(session));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.theMatch),
        bottom: TabBar(
          controller: tabs,
          tabs: <Widget>[
            Tab(text: spectating ? l10n.spectating : l10n.battle),
            Tab(text: l10n.yourBoard),
            Tab(text: l10n.players),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: tabs,
          children: <Widget>[
            if (spectating)
              SpectatorView(snapshot: snapshot, session: session)
            else
              _BattleTab(
                snapshot: snapshot,
                session: session,
                isMyTurn: isMyTurn,
                remaining: remaining,
                selectedTargetId: targetId,
                selectedCell: _selectedCell,
                reducedMotion: reducedMotion,
                onTargetSelected: (String targetId) {
                  setState(() {
                    _selectedTargetId = targetId;
                    _selectedCell = null;
                  });
                },
                onCellTapped: (CellCoord cell) {
                  setState(() => _selectedCell = cell);
                },
                onFire: () {
                  if (targetId != null) unawaited(_fire(targetId));
                },
              ),
            _OwnBoardTab(snapshot: snapshot, session: session),
            _PlayersTab(snapshot: snapshot, session: session),
          ],
        ),
      ),
    );
  }

  /// Opens the result screen once the Host broadcast the final result.
  void _followPhase(RoomSessionState session) {
    if (!mounted) return;
    if (session.matchResult != null) context.go('/match/result');
  }

  Future<void> _exit(RoomSessionState session) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (session.isInRoom) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(session.isHost ? l10n.endTheRoom : l10n.leaveTheMatch),
          content: Text(
            session.isHost ? l10n.endMatchForEveryone : l10n.youWillLeaveMatch,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.leave),
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

    ref.read(matchFeedbackProvider).fire();
    setState(() => _selectedCell = null);
    await ref
        .read(roomSessionControllerProvider.notifier)
        .fire(targetPlayerId: targetId, row: cell.row, column: cell.column);
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
    required this.reducedMotion,
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
  final bool reducedMotion;
  final ValueChanged<String> onTargetSelected;
  final ValueChanged<CellCoord> onCellTapped;
  final VoidCallback onFire;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<TargetBoardView> targets = snapshot.livingTargets;
    final TargetBoardView? target = selectedTargetId == null
        ? null
        : snapshot.targetById(selectedTargetId!);

    final bool alreadyFired =
        target != null &&
        selectedCell != null &&
        target.shots.any(
          (ShotView shot) =>
              shot.row == selectedCell!.row &&
              shot.column == selectedCell!.column,
        );
    final bool canInteract = isMyTurn && !session.firePending && remaining != 0;
    final bool canFire =
        canInteract &&
        target?.alive == true &&
        selectedCell != null &&
        !alreadyFired;

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
          Text(
            session.combatError!,
            style: const TextStyle(color: AppTheme.danger),
          ),
          const SizedBox(height: 12),
        ],
        if (session.lastActivity case final PublicActivity activity) ...[
          Text(_activityText(activity, l10n)),
          const SizedBox(height: 12),
        ],
        if (snapshot.winnerPlayerId == null)
          _TurnCard(
            isMyTurn: isMyTurn,
            activePlayerName:
                snapshot.playerById(snapshot.activePlayerId)?.displayName ?? '',
            remaining: remaining,
            turnNumber: snapshot.turnNumber,
          ),
        AnimatedSwitcher(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: session.lastShot == null
              ? const SizedBox.shrink(key: ValueKey<String>('no-shot'))
              : Padding(
                  key: ValueKey<ShotFeedback>(session.lastShot!),
                  padding: const EdgeInsets.only(top: 12),
                  child: _FeedbackCard(
                    feedback: session.lastShot!,
                    viewerPlayerId: session.playerId,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Text(l10n.target, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (targets.isEmpty)
          Text(l10n.noTargetsLeft)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final TargetBoardView opponent in targets)
                ChoiceChip(
                  label: Text(opponent.displayName),
                  // The chip theme forces light labels, which is unreadable on
                  // the amber selected background.
                  labelStyle: opponent.playerId == selectedTargetId
                      ? TextStyle(
                          color: Theme.of(context).colorScheme.onSecondary,
                        )
                      : null,
                  selected: opponent.playerId == selectedTargetId,
                  onSelected: canInteract
                      ? (_) => onTargetSelected(opponent.playerId)
                      : null,
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
        Text(l10n.boardLegend),
        if (selectedCell != null)
          Text(
            alreadyFired
                ? l10n.selectedCellAlreadyFired(
                    '${String.fromCharCode(65 + selectedCell!.column)}${selectedCell!.row + 1}',
                  )
                : l10n.selectedCell(
                    '${String.fromCharCode(65 + selectedCell!.column)}${selectedCell!.row + 1}',
                  ),
          ),
        const SizedBox(height: 16),
        if (snapshot.winnerPlayerId == null)
          FilledButton.icon(
            onPressed: canFire ? onFire : null,
            icon: const Icon(Icons.local_fire_department),
            label: Text(
              session.firePending
                  ? l10n.waitingForHost
                  : isMyTurn
                  ? l10n.fireAtThisCell
                  : l10n.waitForYourTurn,
            ),
          ),
      ],
    );
  }

  /// Describes a public shot without revealing any coordinate.
  String _activityText(PublicActivity activity, AppLocalizations l10n) {
    final String attacker =
        snapshot.playerById(activity.attackerPlayerId)?.displayName ??
        l10n.aPlayer;
    final String target =
        snapshot.playerById(activity.targetPlayerId)?.displayName ??
        l10n.anotherPlayer;
    return switch (activity.result) {
      ShotResult.miss => l10n.activityMissed(attacker, target),
      ShotResult.hit => l10n.activityHit(attacker, target),
      ShotResult.shipSunk => l10n.battleActivitySunk(attacker, target),
    };
  }
}

class _OwnBoardTab extends StatelessWidget {
  const _OwnBoardTab({required this.snapshot, required this.session});

  final MatchSnapshot snapshot;
  final RoomSessionState session;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OwnBoardView? board = snapshot.ownBoard;
    final int rows = session.snapshot?.config.rows ?? 10;
    final int columns = session.snapshot?.config.columns ?? 10;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text(l10n.yourFleet, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (board == null)
          Text(l10n.yourBoardUnavailable)
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
                  shots: board.ships
                      .expand((ShipView ship) => ship.hitCells)
                      .toList(),
                  misses: board.shotsReceived
                      .where(
                        (CellCoord cell) => !board.ships.any(
                          (ShipView ship) => ship.hitCells.contains(cell),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            l10n.ownBoardHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(height: 1.35),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text(l10n.turnOrder, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final MatchPlayerView player in snapshot.players)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        player.playerId == session.playerId
                            ? l10n.playerNameYou(player.displayName)
                            : player.displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: player.playerId == snapshot.activePlayerId
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                      Text(
                        l10n.shipsLeftCount(player.shipsRemaining),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                if (player.timeouts > 0)
                  Text(
                    l10n.timeoutsCount(player.timeouts),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                const SizedBox(width: 8),
                Icon(
                  player.alive ? Icons.circle : Icons.person_off,
                  size: 14,
                  color: player.alive
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  player.alive ? l10n.inTheMatch : l10n.eliminated,
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
  const _WinnerCard({
    required this.winnerPlayerId,
    required this.viewerPlayerId,
  });

  final String winnerPlayerId;
  final String? viewerPlayerId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
              isWinner ? l10n.youWonMatch : l10n.matchIsOver,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
                        ? l10n.yourTurn
                        : l10n.playerIsShooting(activePlayerName),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    remaining == null
                        ? l10n.turnLabel(turnNumber)
                        : l10n.turnLabelWithTime(turnNumber, remaining!),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isAttacker = feedback.attackerPlayerId == viewerPlayerId;
    final bool isTarget = feedback.targetPlayerId == viewerPlayerId;

    final String text;
    final Color color;
    if (isAttacker) {
      switch (feedback.result) {
        case ShotResult.miss:
          text = l10n.feedbackYouMissed;
          color = AppTheme.miss;
        case ShotResult.hit:
          text = l10n.feedbackYouHit;
          color = AppTheme.hit;
        case ShotResult.shipSunk:
          text = l10n.feedbackYouSunk;
          color = AppTheme.sunk;
      }
    } else if (isTarget) {
      switch (feedback.result) {
        case ShotResult.miss:
          text = l10n.feedbackTargetMissed;
          color = AppTheme.miss;
        case ShotResult.hit:
          text = l10n.feedbackTargetHit;
          color = AppTheme.hit;
        case ShotResult.shipSunk:
          text = l10n.feedbackTargetSunk;
          color = AppTheme.sunk;
      }
    } else {
      text = l10n.feedbackOthers;
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
