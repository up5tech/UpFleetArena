import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/fleet_preset_label.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/room_models.dart';
import '../../rooms/domain/room_session_controller.dart';

/// The Host-only room settings screen.
///
/// It edits a local draft of [RoomConfig] and hands it to the Host runtime,
/// which validates it and broadcasts the accepted values to every client
/// (PLAN.md §3.1, §15 Phase 2).
class HostSettingsScreen extends ConsumerStatefulWidget {
  const HostSettingsScreen({super.key});

  @override
  ConsumerState<HostSettingsScreen> createState() => _HostSettingsScreenState();
}

class _HostSettingsScreenState extends ConsumerState<HostSettingsScreen> {
  late RoomConfig _draft;
  List<String> _problems = const <String>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final RoomSessionState session = ref.read(roomSessionControllerProvider);
    _draft = session.snapshot?.config ?? RoomConfig.defaults;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final bool isHost = session.isHost;
    final int seated =
        session.snapshot?.players
            .where(
              (PlayerSummary player) =>
                  player.status == PlayerConnectionStatus.connected ||
                  player.status == PlayerConnectionStatus.disconnected,
            )
            .length ??
        0;

    final List<String> liveProblems = _draft.validate();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.roomSettings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (!isHost) ...<Widget>[
              _NoticeCard(
                icon: Icons.lock_outline,
                message: l10n.hostOnlySettingsNotice,
              ),
              const SizedBox(height: 12),
            ],
            _SectionCard(
              title: l10n.board,
              children: <Widget>[
                _StepperRow(
                  label: l10n.rows,
                  value: _draft.rows,
                  min: RoomConfig.minimumDimension,
                  max: RoomConfig.maximumDimension,
                  enabled: isHost,
                  onChanged: (int value) => _edit(_draft.copyWith(rows: value)),
                ),
                _StepperRow(
                  label: l10n.columns,
                  value: _draft.columns,
                  min: RoomConfig.minimumDimension,
                  max: RoomConfig.maximumDimension,
                  enabled: isHost,
                  onChanged: (int value) =>
                      _edit(_draft.copyWith(columns: value)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.fleet,
              children: <Widget>[
                for (final FleetPreset preset in FleetPreset.values)
                  _FleetOption(
                    preset: preset,
                    selected: _draft.fleetPreset == preset,
                    enabled: isHost,
                    onTap: () => _edit(_draft.copyWith(fleetPreset: preset)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.players,
              children: <Widget>[
                _StepperRow(
                  label: l10n.capacity,
                  value: _draft.maxPlayers,
                  min: seated > RoomConfig.minimumPlayers
                      ? seated
                      : RoomConfig.minimumPlayers,
                  max: RoomConfig.maximumPlayers,
                  enabled: isHost,
                  onChanged: (int value) =>
                      _edit(_draft.copyWith(maxPlayers: value)),
                ),
                if (seated > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.seatedPlayers(seated),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.timers,
              children: <Widget>[
                _TimerSlider(
                  label: l10n.preparation,
                  value: _draft.placementDurationSeconds,
                  min: RoomConfig.minimumPlacementSeconds,
                  max: RoomConfig.maximumPlacementSeconds,
                  step: 15,
                  enabled: isHost,
                  onChanged: (int value) =>
                      _edit(_draft.copyWith(placementDurationSeconds: value)),
                ),
                _TimerSlider(
                  label: l10n.eachTurn,
                  value: _draft.turnDurationSeconds,
                  min: RoomConfig.minimumTurnSeconds,
                  max: RoomConfig.maximumTurnSeconds,
                  step: 5,
                  enabled: isHost,
                  onChanged: (int value) =>
                      _edit(_draft.copyWith(turnDurationSeconds: value)),
                ),
              ],
            ),
            if (liveProblems.isNotEmpty || _problems.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _NoticeCard(
                icon: Icons.error_outline,
                message: (_problems.isNotEmpty ? _problems : liveProblems).join(
                  ' ',
                ),
                isError: true,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: !isHost || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? l10n.saving : l10n.saveSettings),
            ),
            if (isHost) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => _edit(RoomConfig.defaults),
                child: Text(l10n.resetToDefaults),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _edit(RoomConfig next) {
    setState(() {
      _draft = next;
      _problems = const <String>[];
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _problems = const <String>[];
    });

    final List<String> problems = await ref
        .read(roomSessionControllerProvider.notifier)
        .updateConfig(_draft);

    if (!mounted) return;
    if (problems.isEmpty) {
      context.pop();
      return;
    }
    setState(() {
      _saving = false;
      _problems = problems;
    });
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int current = value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          IconButton(
            tooltip: l10n.decreaseLabel(label),
            onPressed: enabled && current > min
                ? () => onChanged(current - 1)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: l10n.increaseLabel(label),
            onPressed: enabled && current < max
                ? () => onChanged(current + 1)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _FleetOption extends StatelessWidget {
  const _FleetOption({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final FleetPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.fleetOptionLabel(
                      preset.localizedLabel(l10n),
                      preset.shipCount,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    l10n.fleetLengths(preset.shipSummary),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              l10n.cellsCount(preset.totalCells),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerSlider extends StatelessWidget {
  const _TimerSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final int divisions = (max - min) ~/ step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                '$value s',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            label: '$value s',
            onChanged: enabled
                ? (double next) => onChanged(_nearestStep(next))
                : null,
          ),
        ],
      ),
    );
  }

  int _nearestStep(double raw) {
    final int steps = ((raw - min) / step).round();
    return min + steps * step;
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final Color color = isError ? AppTheme.danger : AppTheme.sunk;
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
          Icon(icon, color: color, size: 20),
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
