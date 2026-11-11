import 'package:flutter/material.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/room_models.dart';

/// Picks the size of the board of a new room or practice match.
///
/// The limits are the ones the Host runtime enforces, so a value that reaches
/// this widget is always one the room accepts (PLAN.md §13.3).
class BoardSizeSteppers extends StatelessWidget {
  const BoardSizeSteppers({
    super.key,
    required this.rows,
    required this.columns,
    required this.onRowsChanged,
    required this.onColumnsChanged,
    this.enabled = true,
  });

  /// The chosen number of rows.
  final int rows;

  /// The chosen number of columns.
  final int columns;

  /// Called with a row count inside the supported range.
  final ValueChanged<int> onRowsChanged;

  /// Called with a column count inside the supported range.
  final ValueChanged<int> onColumnsChanged;

  /// Whether the controls accept input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Stepper(
          label: l10n.rows,
          value: rows,
          enabled: enabled,
          onChanged: onRowsChanged,
        ),
        _Stepper(
          label: l10n.columns,
          value: columns,
          enabled: enabled,
          onChanged: onColumnsChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l10n.boardSizeHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        IconButton(
          tooltip: l10n.decreaseLabel(label),
          onPressed: enabled && value > RoomConfig.minimumDimension
              ? () => onChanged(value - 1)
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
          onPressed: enabled && value < RoomConfig.maximumDimension
              ? () => onChanged(value + 1)
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
