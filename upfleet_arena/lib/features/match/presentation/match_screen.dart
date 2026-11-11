import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/match_feedback.dart';
import '../../../game_engine/board/board.dart';
import '../../../game_engine/combat/combat.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../shared/models/match_models.dart';
import '../../../shared/widgets/board_canvas.dart';
import '../../rooms/domain/room_session_controller.dart';
import '../widgets/battle_board.dart';
import '../widgets/match_panel.dart';
import '../widgets/shooter_colors.dart';
import '../widgets/shooter_dot.dart';
import '../widgets/spectator_view.dart';
import '../widgets/turn_strip.dart';
import '../widgets/turn_warning.dart';

/// From this width the match uses side-by-side columns instead of tabs.
const double _wideLayoutWidth = 720;

/// The screen of a running match.
///
/// It shows whose turn it is, the board of the selected opponent and the
/// action that fires at a cell (PLAN.md §5.2).
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  CellCoord? _selectedCell;
  Timer? _ticker;

  /// The turn that already played its warning, so it plays once per turn.
  String? _warnedTurn;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!mounted) return;
      setState(() {});
      _warnIfTurnEnding();
    });
  }

  /// Whether the eliminated player already answered the sunk notice.
  bool _sunkNoticeSeen = false;

  @override
  void dispose() {
    _ticker?.cancel();
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
          previous?.matchSnapshot?.matchId != next.matchSnapshot?.matchId) {
        setState(() {
          _selectedCell = null;
          // A new match starts with a fresh sunk notice.
          _sunkNoticeSeen = false;
        });
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

    // The match no longer uses tabs: the player list is always part of the
    // same scroll (beside the boards on wide screens, below them on narrow
    // ones), so it stays reachable without switching views.
    final bool isMyTurn =
        session.isInRoom &&
        snapshot.winnerPlayerId == null &&
        snapshot.activePlayerId == session.playerId &&
        snapshot.playerById(session.playerId ?? '')?.alive == true;
    final int? remaining = session.turnCountdown?.remaining;

    final bool spectating = session.isSpectating;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followPhase(session);
      // A screen opened late may already be inside the last seconds.
      _warnIfTurnEnding();
    });

    final Widget ownFleet = _OwnFleetSection(
      snapshot: snapshot,
      session: session,
    );
    final Widget players = _PlayersSection(
      snapshot: snapshot,
      session: session,
    );
    final Widget mainView = spectating
        ? SpectatorView(
            snapshot: snapshot,
            session: session,
            footer: ownFleet,
            showSunkNotice: !_sunkNoticeSeen,
            onKeepWatching: () => setState(() => _sunkNoticeSeen = true),
            onLeave: () => unawaited(_exit(session)),
          )
        : _BattleTab(
            snapshot: snapshot,
            session: session,
            isMyTurn: isMyTurn,
            remaining: remaining,
            selectedCell: _selectedCell,
            sidePanel: players,
            onCellTapped: (CellCoord cell) {
              setState(() => _selectedCell = cell);
            },
            onCellDoubleTapped: (CellCoord cell) {
              unawaited(_fireAt(cell));
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.theMatch),
        actions: <Widget>[
          if (session.isInRoom)
            IconButton(
              tooltip: l10n.closeMatch,
              onPressed: () => _exit(session),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: SafeArea(child: mainView),
    );
  }

  /// Plays the short warning once, when the local player's turn is nearly over.
  ///
  /// Only the player who has to act hears it: other turns and spectators stay
  /// silent, so the sound always means "you are about to lose your turn".
  void _warnIfTurnEnding() {
    if (!mounted) return;
    final RoomSessionState session = ref.read(roomSessionControllerProvider);
    final MatchSnapshot? match = session.matchSnapshot;
    if (match == null || match.winnerPlayerId != null) return;
    if (match.activePlayerId != session.playerId) return;
    if (!isUrgentTurn(session.turnCountdown?.remaining)) return;

    final String turn = '${match.matchId}:${match.turnNumber}';
    if (_warnedTurn == turn) return;
    _warnedTurn = turn;
    ref.read(matchFeedbackProvider).turnEnding();
  }

  /// Opens the fleet review once the Host broadcast the final result.
  ///
  /// The fleets always come first: the result screen is reached only after
  /// the players acknowledge what was hit and sunk.
  void _followPhase(RoomSessionState session) {
    if (!mounted) return;
    if (session.matchResult != null) context.go('/match/result/fleets');
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

  Future<void> _fireAt(CellCoord cell) async {
    ref.read(matchFeedbackProvider).fire();
    setState(() => _selectedCell = null);
    await ref
        .read(roomSessionControllerProvider.notifier)
        .fire(row: cell.row, column: cell.column);
  }
}

class _BattleTab extends StatelessWidget {
  const _BattleTab({
    required this.snapshot,
    required this.session,
    required this.isMyTurn,
    required this.remaining,
    required this.selectedCell,
    this.sidePanel,
    required this.onCellTapped,
    required this.onCellDoubleTapped,
  });

  final MatchSnapshot snapshot;
  final RoomSessionState session;
  final bool isMyTurn;
  final int? remaining;
  final CellCoord? selectedCell;

  /// Extra column shown next to the map, e.g. the player list.
  final Widget? sidePanel;

  final ValueChanged<CellCoord> onCellTapped;
  final ValueChanged<CellCoord> onCellDoubleTapped;

  /// Whether the viewer already fired at [cell] on the shared map.
  bool _firedAt(String viewerId, CellCoord cell) => snapshot.mapShots.any(
    (ShotView shot) =>
        shot.attackerPlayerId == viewerId &&
        shot.row == cell.row &&
        shot.column == cell.column,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool canInteract = isMyTurn && !session.firePending && remaining != 0;
    final Map<String, Color> shooterColors = ShooterColors.of(snapshot.players);
    final String viewerId = session.playerId ?? '';
    final bool hasOpponents = snapshot.players.any(
      (MatchPlayerView player) => player.playerId != viewerId && player.alive,
    );

    final bool alreadyFired =
        selectedCell != null && _firedAt(viewerId, selectedCell!);
    // A miss by another player leaves no mark on the map: the room does not
    // need it, and hiding it keeps the hits readable. Only the shooter keeps
    // their own misses, as a reminder of the cells they already fired at.
    final List<ShotView> marks = snapshot.mapShots
        .where(
          (ShotView shot) =>
              shot.result != ShotResult.miss ||
              shot.attackerPlayerId == viewerId,
        )
        .toList();

    final bool finished = snapshot.winnerPlayerId != null;
    // The hint teaches the double-tap, so it is a first-time note: it stays
    // until the viewer's first shot of the match and never comes back. The
    // turn strip already carries the timing after that.
    final bool viewerFired = snapshot.mapShots.any(
      (ShotView shot) => shot.attackerPlayerId == viewerId,
    );

    // Whose turn it is, with the clock: a single strip above the map, so
    // nothing floats over the board or hides the player list.
    final Widget? status = finished
        ? null
        : TurnStrip(
            isMyTurn: isMyTurn,
            activePlayerName:
                snapshot.playerById(snapshot.activePlayerId)?.displayName ?? '',
            remaining: remaining,
            turnNumber: snapshot.turnNumber,
          );

    final Widget map = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.grid_on, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              l10n.sharedMapTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!hasOpponents)
          Text(l10n.noTargetsLeft)
        else ...<Widget>[
          MatchPanel(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double width = constraints.maxWidth;
                    final int rows = session.snapshot?.config.rows ?? 10;
                    final int columns =
                        session.snapshot?.config.columns ?? 10;
                    final OwnBoardView? own = snapshot.ownBoard;
                    return SizedBox(
                      width: width,
                      height: width * rows / columns,
                      child: BattleBoard(
                        rows: rows,
                        columns: columns,
                        // The own fleet and every shot share this one map.
                        ships: <ShipPlacement>[
                          for (final ShipView ship
                              in own?.ships ?? const <ShipView>[])
                            ShipPlacement(
                              shipId: ship.shipId,
                              length: ship.length,
                              span: ship.span,
                              orientation: ship.orientation,
                              row: ship.row,
                              column: ship.column,
                            ),
                        ],
                        sunkShips: <String>{
                          for (final ShipView ship
                              in own?.ships ?? const <ShipView>[])
                            if (ship.sunk) ship.shipId,
                        },
                        // The own sunk hulls are already drawn above, so only
                        // the fleet of an opponent is outlined here.
                        sunkOpponentShips: <SunkShipView>[
                          for (final SunkShipView sunk in snapshot.sunkShips)
                            if (sunk.ownerPlayerId != viewerId) sunk,
                        ],
                        shots: marks,
                        shooterColors: shooterColors,
                        selectedCell: selectedCell,
                        enabled: canInteract,
                        onCellTapped: onCellTapped,
                        onCellDoubleTapped: (CellCoord cell) {
                          if (canInteract && !_firedAt(viewerId, cell)) {
                            onCellDoubleTapped(cell);
                          }
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                const _MapLegend(),
              ],
            ),
          ),
          if (!finished &&
              (session.firePending ||
                  (isMyTurn && !viewerFired))) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  session.firePending
                      ? Icons.hourglass_empty
                      : Icons.touch_app_outlined,
                  size: 15,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    session.firePending
                        ? l10n.waitingForHost
                        : l10n.doubleTapToFire,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (selectedCell != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              alreadyFired
                  ? l10n.selectedCellAlreadyFired(
                      '${String.fromCharCode(65 + selectedCell!.column)}${selectedCell!.row + 1}',
                    )
                  : l10n.selectedCell(
                      '${String.fromCharCode(65 + selectedCell!.column)}${selectedCell!.row + 1}',
                    ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: alreadyFired ? AppTheme.sunk : AppTheme.textPrimary,
              ),
            ),
          ],
        ],
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Wide screens put the player list next to the board.
        final bool sideBySide = constraints.maxWidth >= _wideLayoutWidth;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (status case final Widget strip) ...<Widget>[
              strip,
              const SizedBox(height: 12),
            ],
            if (finished) ...<Widget>[
              _WinnerCard(
                winnerPlayerId: snapshot.winnerPlayerId!,
                viewerPlayerId: viewerId,
              ),
              const SizedBox(height: 12),
            ],
            if (session.combatError != null) ...<Widget>[
              Text(
                session.combatError!,
                style: const TextStyle(color: AppTheme.danger),
              ),
              const SizedBox(height: 12),
            ],
            if (session.lastActivity case final PublicActivity activity) ...<Widget>[
              Text(
                _activityText(activity, l10n),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (sideBySide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // The map is the focus of the match, so it takes the larger
                  // share of a wide screen.
                  Expanded(flex: 3, child: map),
                  if (sidePanel case final Widget panel) ...<Widget>[
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: panel),
                  ],
                ],
              )
            else ...<Widget>[
              map,
              if (sidePanel case final Widget panel) ...<Widget>[
                const SizedBox(height: 16),
                panel,
              ],
            ],
          ],
        );
      },
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

/// What the marks of the map mean, as three short glyphs.
///
/// The colour of a mark belongs to its shooter, and every player already
/// carries that colour in the roster, so the legend needs no names.
class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _LegendItem(glyph: _MarkGlyph.hit, label: l10n.legendHit),
        _LegendItem(glyph: _MarkGlyph.sunk, label: l10n.legendSunk),
        _LegendItem(glyph: _MarkGlyph.miss, label: l10n.legendMiss),
      ],
    );
  }
}

/// One glyph of the map legend with its label.
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.glyph, required this.label});

  final _MarkGlyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _MarkGlyphPainter(glyph: glyph),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// The shapes the shared map uses for a hit, a sunk ship and a miss.
enum _MarkGlyph { hit, sunk, miss }

/// Draws one legend glyph in the neutral text colour, so the legend never
/// pretends to be a player colour.
class _MarkGlyphPainter extends StatelessWidget {
  const _MarkGlyphPainter({required this.glyph});

  final _MarkGlyph glyph;

  @override
  Widget build(BuildContext context) {
    const double size = 12;
    final Color colour = AppTheme.textSecondary;
    return SizedBox(
      width: size,
      height: size,
      child: switch (glyph) {
        _MarkGlyph.hit => DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
        ),
        _MarkGlyph.sunk => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colour, width: 2.5),
          ),
          child: Center(
            child: Container(
              width: 3.5,
              height: 3.5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surface,
              ),
            ),
          ),
        ),
        _MarkGlyph.miss => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colour, width: 1.5),
          ),
        ),
      },
    );
  }
}

/// The viewer's own fleet, shown to a player who already lost.
class _OwnFleetSection extends StatelessWidget {
  const _OwnFleetSection({required this.snapshot, required this.session});

  final MatchSnapshot snapshot;
  final RoomSessionState session;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OwnBoardView? board = snapshot.ownBoard;
    final int rows = session.snapshot?.config.rows ?? 10;
    final int columns = session.snapshot?.config.columns ?? 10;
    final Map<String, Color> shooterColors = ShooterColors.of(snapshot.players);

    // The own board shows the hits in the colour of the player who fired
    // them, so the fleet reads like the shared map.
    final Map<CellCoord, Color> hitColors = <CellCoord, Color>{};
    for (final ShotView shot in board?.receivedShots ?? const <ShotView>[]) {
      if (shot.result == ShotResult.miss) continue;
      hitColors[shot.cell] = ShooterColors.ofPlayer(
        shooterColors,
        shot.attackerPlayerId,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.directions_boat_outlined,
              size: 16,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(l10n.yourFleet, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        MatchPanel(
          padding: const EdgeInsets.all(10),
          child: board == null
              ? Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(l10n.yourBoardUnavailable),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
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
                                        span: ship.span,
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
                                shotColors: hitColors,
                                misses: board.shotsReceived
                                    .where(
                                      (CellCoord cell) => !board.ships.any(
                                        (ShipView ship) =>
                                            ship.hitCells.contains(cell),
                                      ),
                                    )
                                    .toList(),
                              ),
                            );
                          },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.ownBoardHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The turn order and the state of every player.
///
/// One line per player keeps the list short enough to sit next to the boards
/// on a wide screen.
class _PlayersSection extends StatelessWidget {
  const _PlayersSection({required this.snapshot, required this.session});

  final MatchSnapshot snapshot;
  final RoomSessionState session;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final Map<String, Color> colours = ShooterColors.of(snapshot.players);
    return MatchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.turnOrder, style: text.titleMedium),
          const SizedBox(height: 8),
          for (final MatchPlayerView player in snapshot.players)
            _PlayerRow(
              player: player,
              colour: ShooterColors.ofPlayer(colours, player.playerId),
              isViewer: player.playerId == session.playerId,
              isActive: player.playerId == snapshot.activePlayerId,
            ),
        ],
      ),
    );
  }
}

/// One compact line of the player list.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.colour,
    required this.isViewer,
    required this.isActive,
  });

  final MatchPlayerView player;

  /// The colour this player's marks carry on the shared map.
  final Color colour;
  final bool isViewer;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final Color status = player.alive ? AppTheme.accent : AppTheme.textSecondary;
    final bool narrow = MediaQuery.sizeOf(context).width < _wideLayoutWidth;
    // The clock lives in the turn strip above the map, so a row only carries
    // the state that belongs to the player itself.
    final Widget meta = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: <Widget>[
        Text(
          l10n.shipsLeftCount(player.shipsRemaining),
          style: text.labelSmall?.copyWith(color: status),
        ),
        if (player.timeouts > 0)
          Text(
            l10n.timeoutsCount(player.timeouts),
            style: text.labelSmall?.copyWith(color: AppTheme.sunk),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.accent.withValues(alpha: 0.08)
            : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          // The dot carries the colour of the player's marks on the shared
          // map, so the roster doubles as the colour legend. The tooltip
          // keeps the alive state readable without another icon.
          Tooltip(
            message: player.alive ? l10n.inTheMatch : l10n.eliminated,
            child: ShooterDot(colour: colour, alive: player.alive),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isViewer
                  ? l10n.playerNameYou(player.displayName)
                  : player.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                fontWeight: isActive ? FontWeight.w700 : null,
                color: player.alive ? null : AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          narrow
              // In the tabbed layout the row shares 288 px with the name, so
              // the clock, ships and timeouts move to a second line instead
              // of pushing the row past the edge.
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: meta,
                )
              : meta,
        ],
      ),
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
        borderRadius: BorderRadius.circular(16),
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
