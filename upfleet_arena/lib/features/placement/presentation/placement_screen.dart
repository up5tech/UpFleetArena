import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  CellCoord? _previewCell;
  String? _hint;
  final Map<String, ShipOrientation> _pendingOrientation =
      <String, ShipOrientation>{};
  final List<List<ShipPlacement>> _undoStack = <List<ShipPlacement>>[];
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

  RoomSessionState get _session => ref.read(roomSessionControllerProvider);

  /// The seconds that are left before the preparation ends.
  int? get _remaining {
    final Countdown? countdown = _session.countdown;
    if (countdown == null) return null;
    return countdown.remaining;
  }

  /// Follows the phase the Host moved the room into.
  void _followPhase(RoomSessionState session) {
    if (!mounted) return;
    if (session.snapshot?.status == RoomStatus.active) {
      context.go('/match');
    }
  }

  FleetProfile get _profile => FleetProfile.fromPreset(
    _session.snapshot?.config.fleetPreset ?? FleetPreset.standard,
  );

  BoardSize get _board => BoardSize(
    rows: _session.snapshot?.config.rows ?? 10,
    columns: _session.snapshot?.config.columns ?? 10,
  );

  List<ShipPlacement> get _ships =>
      _session.placement?.toPlacements() ?? const <ShipPlacement>[];

  ShipPlacement? _placedShip(String shipId) {
    for (final ShipPlacement ship in _ships) {
      if (ship.shipId == shipId) return ship;
    }
    return null;
  }

  ShipOrientation _orientationOf(String shipId) {
    final ShipPlacement? placed = _placedShip(shipId);
    if (placed != null) return placed.orientation;
    return _pendingOrientation[shipId] ?? ShipOrientation.horizontal;
  }

  ShipPlacement? get _preview {
    final String? shipId = _selectedShipId;
    final CellCoord? cell = _previewCell;
    if (shipId == null || cell == null) return null;
    final int? length = _profile.lengthOf(shipId);
    if (length == null) return null;
    return ShipPlacement(
      shipId: shipId,
      length: length,
      orientation: _orientationOf(shipId),
      row: cell.row,
      column: cell.column,
    );
  }

  bool get _previewIsValid {
    final ShipPlacement? preview = _preview;
    if (preview == null) return true;
    return validateShipPlacement(
      board: _board,
      profile: _profile,
      ships: _ships,
      candidate: preview,
    ) ==
        null;
  }

  @override
  Widget build(BuildContext context) {
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final RoomSnapshot? snapshot = session.snapshot;

    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prepare your fleet')),
        body: const Center(child: Text('The room is no longer open.')),
      );
    }

    final FleetProfile profile = _profile;
    final List<ShipPlacement> ships = _ships;
    final bool complete = isFleetComplete(profile, ships);
    final bool ready = session.isPlacementReady;
    final int? remaining = _remaining;
    // A confirmed fleet is locked for the rest of the preparation phase.
    final bool locked =
        snapshot.status == RoomStatus.placement && ready;

    WidgetsBinding.instance.addPostFrameCallback((_) => _followPhase(session));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prepare your fleet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (remaining != null) ...<Widget>[
              _CountdownCard(remaining: remaining),
              const SizedBox(height: 12),
            ],
            _BoardSection(
              rows: snapshot.config.rows,
              columns: snapshot.config.columns,
              ships: ships,
              preview: _preview,
              previewIsValid: _previewIsValid,
              onCellPreview: _handlePreview,
              onCellCommit: _handleCommit,
              onDragEnd: _handleDragEnd,
            ),
            const SizedBox(height: 16),
            Text(
              'Your fleet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _ShipInventory(
              profile: profile,
              ships: ships,
              selectedShipId: _selectedShipId,
              enabled: !locked,
              onSelect: _selectShip,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedShipId == null || locked
                        ? null
                        : _rotate,
                    icon: const Icon(Icons.rotate_right, size: 18),
                    label: const Text('Rotate'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _undoStack.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Undo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: locked ? null : _autoPlace,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Auto'),
                  ),
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
                    ? 'You are ready'
                    : complete
                    ? 'I am ready'
                    : 'Place every ship first',
              ),
            ),
            const SizedBox(height: 16),
            _ReadinessCard(readiness: session.readiness),
          ],
        ),
      ),
    );
  }

  void _selectShip(String shipId) {
    setState(() {
      _selectedShipId = _selectedShipId == shipId ? null : shipId;
      _previewCell = null;
      _hint = null;
    });
  }

  void _handlePreview(CellCoord cell) {
    if (_selectedShipId == null) return;
    setState(() => _previewCell = cell);
  }

  void _handleDragEnd() {
    final CellCoord? cell = _previewCell;
    if (cell == null) return;
    _commit(cell);
  }

  void _handleCommit(CellCoord cell) {
    final String? shipId = _selectedShipId;
    if (shipId == null) {
      _selectShipAt(cell);
      return;
    }
    _commit(cell);
  }

  void _commit(CellCoord cell) {
    final String? shipId = _selectedShipId;
    if (shipId == null) return;

    final int? length = _profile.lengthOf(shipId);
    if (length == null) return;

    final ShipPlacement candidate = ShipPlacement(
      shipId: shipId,
      length: length,
      orientation: _orientationOf(shipId),
      row: cell.row,
      column: cell.column,
    );

    final List<ShipPlacement> next = _ships
        .where((ShipPlacement ship) => ship.shipId != shipId)
        .toList()
      ..add(candidate);

    final PlacementError? error = validateFleetLayout(
      board: _board,
      profile: _profile,
      ships: next,
    );
    if (error != null) {
      setState(() => _hint = error.message);
      return;
    }

    _pushUndo();
    setState(() {
      _hint = null;
      _previewCell = null;
    });
    ref.read(roomSessionControllerProvider.notifier).setPlacement(next);
  }

  /// Selects the ship that lies on the tapped cell.
  void _selectShipAt(CellCoord cell) {
    for (final ShipPlacement ship in _ships) {
      if (ship.cells.contains(cell)) {
        _selectShip(ship.shipId);
        return;
      }
    }
  }

  void _rotate() {
    final String? shipId = _selectedShipId;
    if (shipId == null) return;

    final ShipPlacement? placed = _placedShip(shipId);
    if (placed == null) {
      setState(() {
        _pendingOrientation[shipId] = _orientationOf(shipId).flipped;
        _hint = null;
      });
      return;
    }

    final ShipPlacement rotated = placed.rotated();
    final List<ShipPlacement> next = _ships
        .where((ShipPlacement ship) => ship.shipId != shipId)
        .toList()
      ..add(rotated);

    final PlacementError? error = validateFleetLayout(
      board: _board,
      profile: _profile,
      ships: next,
    );
    if (error != null) {
      setState(() => _hint = error.message);
      return;
    }

    _pushUndo();
    setState(() {
      _hint = null;
      _previewCell = null;
    });
    ref.read(roomSessionControllerProvider.notifier).setPlacement(next);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final List<ShipPlacement> previous = _undoStack.removeLast();
    setState(() {
      _hint = null;
      _previewCell = null;
      _selectedShipId = null;
    });
    ref.read(roomSessionControllerProvider.notifier).setPlacement(previous);
  }

  void _autoPlace() {
    _pushUndo();
    setState(() {
      _hint = null;
      _previewCell = null;
    });
    ref.read(roomSessionControllerProvider.notifier).autoPlace();
  }

  void _pushUndo() {
    _undoStack.add(List<ShipPlacement>.from(_ships));
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
    required this.preview,
    required this.previewIsValid,
    required this.onCellPreview,
    required this.onCellCommit,
    required this.onDragEnd,
  });

  final int rows;
  final int columns;
  final List<ShipPlacement> ships;
  final ShipPlacement? preview;
  final bool previewIsValid;
  final void Function(CellCoord cell) onCellPreview;
  final void Function(CellCoord cell) onCellCommit;
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
            preview: preview,
            previewIsValid: previewIsValid,
            onCellPreview: onCellPreview,
            onCellCommit: onCellCommit,
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
  });

  final FleetProfile profile;
  final List<ShipPlacement> ships;
  final String? selectedShipId;
  final bool enabled;
  final ValueChanged<String> onSelect;

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
            length: profile.lengthOf(shipId) ?? 0,
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
    required this.placed,
    required this.selected,
    required this.onTap,
  });

  final String shipId;
  final int length;
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
              '$length cells',
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

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final int minutes = remaining ~/ 60;
    final int seconds = remaining % 60;
    final String clock =
        '$minutes:${seconds.toString().padLeft(2, '0')}';

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
                    'The preparation ends in $clock',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A fleet that is not finished in time is placed '
                    'automatically.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.35,
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

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness});

  final ReadinessState? readiness;

  @override
  Widget build(BuildContext context) {
    final List<PlayerReadiness> players = readiness?.players ?? const [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Players',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (players.isEmpty)
              const Text('Nobody is in the room yet.')
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
                        player.ready ? Icons.check_circle : Icons.hourglass_empty,
                        size: 16,
                        color: player.ready
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        player.ready ? 'Ready' : 'Placing',
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
