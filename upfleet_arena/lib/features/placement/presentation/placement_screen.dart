import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/board/board.dart';
import '../../../game_engine/fleet/fleet_profile.dart';
import '../../../game_engine/placement/placement.dart';
import '../../../game_engine/placement/placement_validator.dart';
import '../../../shared/models/match_models.dart';
import '../../../shared/models/placement_models.dart';
import '../../../shared/models/room_models.dart';
import '../../rooms/domain/room_session_controller.dart';
import '../../../shared/widgets/board_canvas.dart';

/// Sizes an action button to its content so its label stays on one line.
final ButtonStyle _actionButtonStyle = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 48),
  padding: const EdgeInsets.symmetric(horizontal: 12),
);

/// The screen where a player prepares their own fleet.
///
/// Every placement is confirmed by the Host before it is shown, so the board
/// always shows the Host truth (PLAN.md §10.1).
class PlacementScreen extends ConsumerStatefulWidget {
  const PlacementScreen({super.key});

  @override
  ConsumerState<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends ConsumerState<PlacementScreen> {
  String? _selectedShipId;

  /// The cell under the finger during a drag.
  ///
  /// A [ValueNotifier] keeps the ghost cheap: only the board listens to it, so
  /// a pointer move never rebuilds the inventory, the hints or the readiness
  /// list below the board.
  final ValueNotifier<CellCoord?> _previewCell = ValueNotifier<CellCoord?>(
    null,
  );
  String? _hint;

  /// The cell of the ship that stays under the finger while dragging.
  ///
  /// A ship grabbed by its second cell keeps that cell under the finger, so
  /// the hull does not jump to the touched cell.
  int _grabRowOffset = 0;
  int _grabColumnOffset = 0;

  /// The last touch, used to recognize a second tap without making the board
  /// wait for the double-tap timeout.
  DateTime? _lastTapAt;
  CellCoord? _lastTapCell;

  /// Whether the current touch was a double tap that already rotated a ship.
  bool _doubleTapHandled = false;

  /// The cell where the current press and hold started.
  CellCoord? _longPressCell;

  /// How close together two taps must be to count as a double tap.
  static const Duration _doubleTapWindow = Duration(milliseconds: 320);
  final Map<String, ShipOrientation> _pendingOrientation =
      <String, ShipOrientation>{};

  /// Whether the player picked the square shape for a ship not placed yet.
  final Map<String, bool> _pendingSquare = <String, bool>{};
  final List<List<ShipPlacement>> _undoStack = <List<ShipPlacement>>[];

  /// The layout the player just dropped, shown while the Host answers.
  ///
  /// The Host is still the only truth: a new placement state replaces this
  /// overlay immediately, and a short timeout removes it if the Host never
  /// answers. Without it the hull snapped back to its old cell on every drop.
  List<ShipPlacement>? _pendingLayout;
  PlacementState? _pendingBase;
  Timer? _pendingTimer;

  /// Guards the post-frame phase check so a rebuild cannot queue a pile of
  /// navigation callbacks while the finger is moving.
  bool _phaseCheckScheduled = false;

  /// Cache of the Host layout: the getters below are called several times per
  /// build, and converting the wire state allocates a fresh list each time.
  PlacementState? _cachedPlacement;
  List<ShipPlacement> _cachedShips = const <ShipPlacement>[];

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _previewCell.dispose();
    super.dispose();
  }

  RoomSessionState get _session => ref.read(roomSessionControllerProvider);

  /// Follows the phase the Host moved the room into.
  ///
  /// Only one check is queued at a time: the old code queued one callback per
  /// build, which piled up while the board was being dragged. A closed room
  /// ends the preparation: the notice is shown once on Home and the stale
  /// session is cleared, so it cannot follow the player into the next room.
  void _schedulePhaseCheck() {
    if (_phaseCheckScheduled) return;
    _phaseCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phaseCheckScheduled = false;
      if (!mounted) return;
      final RoomSessionState session = ref.read(roomSessionControllerProvider);
      if (session.status == RoomSessionStatus.closed) {
        final String? message = session.errorMessage;
        if (message != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
        ref
            .read(roomSessionControllerProvider.notifier)
            .acknowledgeClosedRoom();
        context.go('/');
        return;
      }
      if (session.snapshot?.status == RoomStatus.active) context.go('/match');
    });
  }

  /// Leaves the preparation.
  ///
  /// A practice room has no lobby behind it, so leaving really ends it
  /// instead of letting a match run on in the background.
  Future<void> _leave(BuildContext context, RoomSessionState session) async {
    if (!session.practiceMode) {
      context.pop();
      return;
    }
    await ref.read(roomSessionControllerProvider.notifier).closeRoom();
    if (context.mounted) context.go('/');
  }

  FleetProfile get _profile => FleetProfile.fromPreset(
    _session.snapshot?.config.fleetPreset ?? FleetPreset.standard,
  );

  BoardSize get _board => BoardSize(
    rows: _session.snapshot?.config.rows ?? 10,
    columns: _session.snapshot?.config.columns ?? 10,
  );

  /// The fleet the Host has confirmed, cached until the next Host update.
  List<ShipPlacement> get _ships {
    final PlacementState? placement = _session.placement;
    if (!identical(placement, _cachedPlacement)) {
      _cachedPlacement = placement;
      _cachedShips = placement?.toPlacements() ?? const <ShipPlacement>[];
    }
    return _cachedShips;
  }

  /// The fleet the player sees: a just-dropped layout is shown while the Host
  /// answers, so the hull never jumps back to its old cell on release.
  List<ShipPlacement> get _displayedShips => _pendingLayout ?? _ships;

  void _clearPendingLayout() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingLayout = null;
    _pendingBase = null;
  }

  /// Sends a layout to the Host and keeps it on screen until the Host answers.
  void _sendPlacement(List<ShipPlacement> next) {
    _pendingTimer?.cancel();
    _pendingBase = _session.placement;
    _pendingLayout = next;
    _pendingTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(_clearPendingLayout);
    });
    ref.read(roomSessionControllerProvider.notifier).setPlacement(next);
  }

  ShipPlacement? _placedShip(String shipId) {
    for (final ShipPlacement ship in _displayedShips) {
      if (ship.shipId == shipId) return ship;
    }
    return null;
  }

  ShipOrientation _orientationOf(String shipId) {
    final ShipPlacement? placed = _placedShip(shipId);
    if (placed != null) return placed.orientation;
    return _pendingOrientation[shipId] ?? ShipOrientation.horizontal;
  }

  /// Whether the ship is, or is about to be, a square block.
  bool _isSquare(String shipId) {
    final ShipPlacement? placed = _placedShip(shipId);
    if (placed != null) return placed.isSquare;
    return _pendingSquare[shipId] ?? false;
  }

  /// The footprint the ship has, or is about to get, on the board.
  int? _lengthOf(String shipId) {
    final ShipPlacement? placed = _placedShip(shipId);
    if (placed != null) return placed.length;
    final int? side = _profile.squareSideOf(shipId);
    if (side != null && _isSquare(shipId)) return side;
    return _profile.lengthOf(shipId);
  }

  /// The cells the ship covers across its direction.
  int? _spanOf(String shipId) {
    final ShipPlacement? placed = _placedShip(shipId);
    if (placed != null) return placed.span;
    final int? side = _profile.squareSideOf(shipId);
    if (side != null && _isSquare(shipId)) return side;
    return _profile.spanOf(shipId);
  }

  /// The ghost of the held ship at [cell], if any.
  ShipPlacement? _previewFor(CellCoord? cell) {
    final String? shipId = _selectedShipId;
    if (shipId == null || cell == null) return null;
    final int? length = _lengthOf(shipId);
    final int? span = _spanOf(shipId);
    if (length == null || span == null) return null;
    return ShipPlacement(
      shipId: shipId,
      length: length,
      span: span,
      orientation: _orientationOf(shipId),
      row: cell.row - _grabRowOffset,
      column: cell.column - _grabColumnOffset,
    );
  }

  bool _previewIsValid(ShipPlacement? preview) {
    if (preview == null) return true;
    return validateShipPlacement(
          board: _board,
          profile: _profile,
          ships: _displayedShips,
          candidate: preview,
        ) ==
        null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final RoomSnapshot? snapshot = session.snapshot;

    // The closed-room check must run even when the room data is already gone.
    _schedulePhaseCheck();

    if (session.status == RoomSessionStatus.closed || snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.prepareYourFleet)),
        body: Center(child: Text(l10n.roomNoLongerOpen)),
      );
    }

    // Any new Host state wins over the layout we showed optimistically.
    if (_pendingLayout != null && !identical(session.placement, _pendingBase)) {
      _clearPendingLayout();
    }

    final FleetProfile profile = _profile;
    final List<ShipPlacement> ships = _displayedShips;
    // Ready stays gated on the Host truth, never on a layout that is still in
    // flight: otherwise the Host could reject a premature Ready command.
    final bool complete = isFleetComplete(profile, _ships);
    final bool ready = session.isPlacementReady;
    final Countdown? countdown = session.countdown;
    // A confirmed fleet is locked for the rest of the preparation phase.
    final bool locked = snapshot.status == RoomStatus.placement && ready;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.prepareYourFleet),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _leave(context, session),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (countdown != null) ...<Widget>[
              _CountdownCard(countdown: countdown),
              const SizedBox(height: 12),
            ],
            // Only the board listens to the moving ghost: the rest of the
            // page stays untouched while the finger crosses the grid.
            ValueListenableBuilder<CellCoord?>(
              valueListenable: _previewCell,
              builder: (BuildContext context, CellCoord? cell, Widget? _) {
                final ShipPlacement? preview = _previewFor(cell);
                return _BoardSection(
                  rows: snapshot.config.rows,
                  columns: snapshot.config.columns,
                  ships: ships,
                  selectedShipId: _selectedShipId,
                  preview: preview,
                  previewIsValid: _previewIsValid(preview),
                  onCellPreview: _handlePreview,
                  onPreviewCleared: _handlePreviewCleared,
                  onCellCommit: _handleCommit,
                  onPointerDown: _handlePointerDown,
                  onLongPressStart: _handleLongPressStart,
                  onLongPressMove: _handleLongPressMove,
                  onLongPressEnd: _handleLongPressEnd,
                  onDragEnd: _handleDragEnd,
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              l10n.yourFleet,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _ShipInventory(
              profile: profile,
              ships: ships,
              selectedShipId: _selectedShipId,
              enabled: !locked,
              onSelect: _selectShip,
              lengthOf: _lengthOf,
              spanOf: _spanOf,
            ),
            if (profile.shipIds.any(
              (String shipId) => profile.squareSideOf(shipId) != null,
            )) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.squareHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // A Wrap keeps every label on one line: with fixed thirds the
            // longer Vietnamese labels ("Hoàn tác", "Tự động") broke
            // mid-word on a 393 pt phone.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  style: _actionButtonStyle,
                  onPressed: _selectedShipId == null || locked ? null : _rotate,
                  icon: const Icon(Icons.rotate_right, size: 18),
                  label: Text(l10n.rotate),
                ),
                OutlinedButton.icon(
                  style: _actionButtonStyle,
                  onPressed: _undoStack.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(l10n.undo),
                ),
                OutlinedButton.icon(
                  style: _actionButtonStyle,
                  onPressed: locked ? null : _autoPlace,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(l10n.auto),
                ),
              ],
            ),
            if (_hint != null || session.placementError != null) ...<Widget>[
              const SizedBox(height: 12),
              _HintCard(message: _hint ?? session.placementError!),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: complete && !ready ? _confirmReady : null,
              icon: Icon(ready ? Icons.check_circle : Icons.flag),
              label: Text(
                ready
                    ? l10n.youAreReady
                    : complete
                    ? l10n.iAmReady
                    : l10n.placeEveryShipFirst,
              ),
            ),
            const SizedBox(height: 16),
            _ReadinessCard(readiness: session.readiness),
          ],
        ),
      ),
    );
  }

  /// Hides the ghost without rebuilding the rest of the page.
  void _clearPreview() {
    if (_previewCell.value != null) _previewCell.value = null;
  }

  void _selectShip(String shipId) {
    _clearPreview();
    setState(() {
      _selectedShipId = _selectedShipId == shipId ? null : shipId;
      _grabRowOffset = 0;
      _grabColumnOffset = 0;
      _hint = null;
    });
  }

  void _handlePreview(CellCoord cell) {
    if (_selectedShipId == null) return;
    if (_previewCell.value == cell) return;
    _previewCell.value = cell;
  }

  void _handlePreviewCleared() => _clearPreview();

  /// Picks up the ship under the finger.
  ///
  /// Auto Place fills the whole fleet, but the player may still move any ship.
  /// The grabbed cell stays under the finger, so the hull does not jump one
  /// cell when it is picked up by its middle.
  void _handlePointerDown(CellCoord cell) {
    // A second tap on the same cell rotates the ship there, so a placed fleet
    // can be turned without reaching for the action row.
    final DateTime now = DateTime.now();
    final bool doubleTap =
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < _doubleTapWindow &&
        _lastTapCell == cell;
    _lastTapAt = now;
    _lastTapCell = cell;
    // A stale double-tap flag must never swallow the next ordinary tap.
    _doubleTapHandled = false;
    if (doubleTap) {
      _rotateTapped(cell);
      return;
    }

    if (_selectedShipId != null) return;
    final ShipPlacement? ship = _shipAt(cell);
    if (ship == null) return;
    _grabShip(ship, cell);
  }

  /// Grabs the ship under the finger when a press and hold starts.
  void _handleLongPressStart(CellCoord cell) {
    if (_selectedShipId == null) {
      final ShipPlacement? ship = _shipAt(cell);
      if (ship == null) return;
      _grabShip(ship, cell);
    }
    _longPressCell = cell;
  }

  /// Rotates the held ship when the finger swishes sideways.
  ///
  /// A vertical swish does nothing, and every full cell of horizontal travel
  /// rotates once more, so all shapes stay reachable without lifting the
  /// finger.
  void _handleLongPressMove(CellCoord cell) {
    final CellCoord? start = _longPressCell;
    if (start == null) return;
    final int dColumn = cell.column - start.column;
    final int dRow = cell.row - start.row;
    if (dColumn.abs() <= dRow.abs()) return;
    _longPressCell = cell;
    _rotate();
  }

  void _handleLongPressEnd() => _longPressCell = null;

  /// Rotates the ship under the finger, selecting it first when it is not the
  /// ship that is currently picked up.
  void _rotateTapped(CellCoord cell) {
    final ShipPlacement? tapped = _shipAt(cell);
    final String? shipId = tapped?.shipId ?? _selectedShipId;
    if (shipId == null) return;
    if (tapped != null && tapped.shipId != _selectedShipId) {
      _grabShip(tapped, cell);
    }
    // The tap that ended the double tap must not place or move the ship.
    _doubleTapHandled = true;
    _rotate();
  }

  /// Selects a ship that is already on the board, keeping the touched cell as
  /// the grab point.
  void _grabShip(ShipPlacement ship, CellCoord cell) {
    _clearPreview();
    setState(() {
      _selectedShipId = ship.shipId;
      _hint = null;
      _grabRowOffset = cell.row - ship.row;
      _grabColumnOffset = cell.column - ship.column;
    });
  }

  /// The ship of the own fleet that lies on [cell], if any.
  ShipPlacement? _shipAt(CellCoord cell) {
    for (final ShipPlacement ship in _displayedShips) {
      if (ship.cells.contains(cell)) return ship;
    }
    return null;
  }

  void _handleDragEnd() {
    final CellCoord? cell = _previewCell.value;
    if (cell == null) return;
    _commit(cell);
  }

  void _handleCommit(CellCoord cell) {
    if (_doubleTapHandled) {
      _doubleTapHandled = false;
      _clearPreview();
      return;
    }
    final String? shipId = _selectedShipId;
    final ShipPlacement? tapped = _shipAt(cell);
    // Tapping a ship that is already on the board selects it, so a fleet can
    // be edited on the board without going back to the inventory.
    if (tapped != null && tapped.shipId != shipId) {
      _grabShip(tapped, cell);
      return;
    }
    if (shipId == null) return;
    _commit(cell);
  }

  void _commit(CellCoord cell) {
    final String? shipId = _selectedShipId;
    if (shipId == null) return;

    // The grabbed cell stays under the finger, so the hull does not jump one
    // cell when it was picked up by its middle.
    final int row = cell.row - _grabRowOffset;
    final int column = cell.column - _grabColumnOffset;
    _grabRowOffset = 0;
    _grabColumnOffset = 0;

    final int? length = _lengthOf(shipId);
    final int? span = _spanOf(shipId);
    if (length == null || span == null) return;

    final ShipPlacement candidate = ShipPlacement(
      shipId: shipId,
      length: length,
      span: span,
      orientation: _orientationOf(shipId),
      row: row,
      column: column,
    );

    // Tapping a ship without moving it only selects it.
    final ShipPlacement? current = _placedShip(shipId);
    if (current == candidate) {
      _clearPreview();
      setState(() => _hint = null);
      return;
    }

    final List<ShipPlacement> next =
        _displayedShips
            .where((ShipPlacement ship) => ship.shipId != shipId)
            .toList()
          ..add(candidate);

    final PlacementError? error = validateFleetLayout(
      board: _board,
      profile: _profile,
      ships: next,
    );
    if (error != null) {
      _clearPreview();
      setState(() => _hint = error.message);
      return;
    }

    _pushUndo();
    _clearPreview();
    setState(() => _hint = null);
    _sendPlacement(next);
  }

  /// Cycles the shape of the selected ship.
  ///
  /// A ship goes through its two line forms and, when its cells form a square,
  /// through the block as well: horizontal, vertical, block, horizontal.
  void _rotate() {
    final String? shipId = _selectedShipId;
    if (shipId == null) return;

    final bool square = _isSquare(shipId);
    final ShipOrientation orientation = _orientationOf(shipId);
    final int? side = _profile.squareSideOf(shipId);
    final bool toSquare =
        side != null && !square && orientation == ShipOrientation.vertical;

    final ShipPlacement? placed = _placedShip(shipId);
    if (placed == null) {
      _clearPreview();
      setState(() {
        _pendingSquare[shipId] = toSquare;
        _pendingOrientation[shipId] = square || toSquare
            ? ShipOrientation.horizontal
            : orientation.flipped;
        _hint = null;
      });
      return;
    }

    final ShipPlacement rotated;
    if (square) {
      // The block goes back to a horizontal line of its cell count.
      rotated = placed.copyWith(
        length: _profile.lengthOf(shipId) ?? placed.length,
        span: _profile.spanOf(shipId) ?? 1,
        orientation: ShipOrientation.horizontal,
      );
    } else if (toSquare) {
      rotated = placed.copyWith(
        length: side,
        span: side,
        orientation: ShipOrientation.horizontal,
      );
    } else {
      rotated = placed.rotated();
    }
    final List<ShipPlacement> next =
        _displayedShips
            .where((ShipPlacement ship) => ship.shipId != shipId)
            .toList()
          ..add(rotated);

    final PlacementError? error = validateFleetLayout(
      board: _board,
      profile: _profile,
      ships: next,
    );
    if (error != null) {
      _clearPreview();
      setState(() => _hint = error.message);
      return;
    }
    _pushUndo();
    _clearPreview();
    setState(() => _hint = null);
    _sendPlacement(next);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final List<ShipPlacement> previous = _undoStack.removeLast();
    _clearPreview();
    setState(() {
      _hint = null;
      _selectedShipId = null;
    });
    _sendPlacement(previous);
  }

  void _autoPlace() {
    _pushUndo();
    // The new layout is the Host's to decide, so there is nothing to show
    // optimistically here.
    _clearPendingLayout();
    _clearPreview();
    setState(() => _hint = null);
    ref.read(roomSessionControllerProvider.notifier).autoPlace();
  }

  void _pushUndo() {
    _undoStack.add(List<ShipPlacement>.from(_displayedShips));
    if (_undoStack.length > 20) _undoStack.removeAt(0);
  }

  Future<void> _confirmReady() async {
    final List<String> problems = await ref
        .read(roomSessionControllerProvider.notifier)
        .setPlacementReady();
    if (!mounted) return;
    if (problems.isEmpty) return;
    setState(() => _hint = problems.join(' '));
  }
}

class _BoardSection extends StatelessWidget {
  const _BoardSection({
    required this.rows,
    required this.columns,
    required this.ships,
    required this.selectedShipId,
    required this.preview,
    required this.previewIsValid,
    required this.onCellPreview,
    required this.onPreviewCleared,
    required this.onCellCommit,
    required this.onPointerDown,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onDragEnd,
  });

  final int rows;
  final int columns;
  final List<ShipPlacement> ships;
  final String? selectedShipId;
  final ShipPlacement? preview;
  final bool previewIsValid;
  final void Function(CellCoord cell) onCellPreview;
  final VoidCallback onPreviewCleared;
  final void Function(CellCoord cell) onCellCommit;
  final void Function(CellCoord cell) onPointerDown;
  final void Function(CellCoord cell) onLongPressStart;
  final void Function(CellCoord cell) onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return SizedBox(
          width: width,
          height: width * rows / columns,
          child: BoardCanvas(
            rows: rows,
            columns: columns,
            ships: ships,
            selectedShipId: selectedShipId,
            preview: preview,
            previewIsValid: previewIsValid,
            onCellPreview: onCellPreview,
            onPreviewCleared: onPreviewCleared,
            onCellCommit: onCellCommit,
            onPointerDown: onPointerDown,
            onLongPressStart: onLongPressStart,
            onLongPressMove: onLongPressMove,
            onLongPressEnd: onLongPressEnd,
            onDragEnd: onDragEnd,
          ),
        );
      },
    );
  }
}

class _ShipInventory extends StatelessWidget {
  const _ShipInventory({
    required this.profile,
    required this.ships,
    required this.selectedShipId,
    required this.enabled,
    required this.onSelect,
    required this.lengthOf,
    required this.spanOf,
  });

  final FleetProfile profile;
  final List<ShipPlacement> ships;
  final String? selectedShipId;
  final bool enabled;
  final ValueChanged<String> onSelect;

  /// The footprint each ship has on the board right now.
  final int? Function(String shipId) lengthOf;
  final int? Function(String shipId) spanOf;

  @override
  Widget build(BuildContext context) {
    final Set<String> placed = ships
        .map((ShipPlacement ship) => ship.shipId)
        .toSet();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String shipId in profile.shipIds)
          _ShipChip(
            shipId: shipId,
            length: lengthOf(shipId) ?? 0,
            span: spanOf(shipId) ?? 1,
            placed: placed.contains(shipId),
            selected: selectedShipId == shipId,
            onTap: enabled ? () => onSelect(shipId) : null,
          ),
      ],
    );
  }
}

class _ShipChip extends StatelessWidget {
  const _ShipChip({
    required this.shipId,
    required this.length,
    required this.span,
    required this.placed,
    required this.selected,
    required this.onTap,
  });

  final String shipId;
  final int length;

  /// `1` for a line, the length itself for a square ship.
  final int span;
  final bool placed;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              placed ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: placed ? AppTheme.accent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              span == 1
                  ? AppLocalizations.of(context).cellsCount(length)
                  : AppLocalizations.of(context).shipSize(length, span),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ticks on its own so the one-second clock never rebuilds the board.
class _CountdownCard extends StatefulWidget {
  const _CountdownCard({required this.countdown});

  final Countdown countdown;

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int remaining = widget.countdown.remaining;
    final int minutes = remaining ~/ 60;
    final int seconds = remaining % 60;
    final String clock = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.timer_outlined, color: AppTheme.sunk, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.preparationEndsIn(clock),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.autoPlaceHint,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.35),
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

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness});

  final ReadinessState? readiness;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<PlayerReadiness> players = readiness?.players ?? const [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.players, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (players.isEmpty)
              Text(l10n.nobodyInRoom)
            else
              for (final PlayerReadiness player in players)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          player.displayName,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Icon(
                        player.ready
                            ? Icons.check_circle
                            : Icons.hourglass_empty,
                        size: 16,
                        color: player.ready
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        player.ready ? l10n.ready : l10n.placing,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: player.ready
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                        ),
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

class _HintCard extends StatelessWidget {
  const _HintCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
