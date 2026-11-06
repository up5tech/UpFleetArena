import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/match_models.dart';
import '../../rooms/domain/room_session_controller.dart';

/// The screen that opens when the match starts.
///
/// It shows the randomized turn order and the player who takes the first
/// turn (PLAN.md §2.6).
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkMatch());
  }

  void _checkMatch() {
    final RoomSessionState session = ref.read(roomSessionControllerProvider);
    if (!session.isInRoom && mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final MatchStartState? match = session.match;

    return Scaffold(
      appBar: AppBar(title: const Text('The match')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (match == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('The match has not started yet.'),
                ),
              )
            else ...<Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        match.activePlayerName.isEmpty
                            ? 'The match has started'
                            : '${match.activePlayerName} shoots first',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Board ${match.boardRows}×${match.boardColumns} · '
                        '${match.fleetPreset.label} fleet',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Turn order',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (int index = 0;
                          index < match.turnOrder.length;
                          index++)
                        _TurnOrderRow(
                          position: index + 1,
                          entry: match.turnOrder[index],
                          isActive:
                              match.turnOrder[index].playerId ==
                              match.activePlayerId,
                          isViewer:
                              match.turnOrder[index].playerId ==
                              session.playerId,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TurnOrderRow extends StatelessWidget {
  const _TurnOrderRow({
    required this.position,
    required this.entry,
    required this.isActive,
    required this.isViewer,
  });

  final int position;
  final TurnOrderEntry entry;
  final bool isActive;
  final bool isViewer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '$position',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(
            child: Text(
              isViewer ? '${entry.displayName} (you)' : entry.displayName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isActive ? FontWeight.w700 : null,
              ),
            ),
          ),
          if (isActive)
            const Chip(
              label: Text('First'),
              avatar: Icon(Icons.play_arrow, size: 16, color: AppTheme.accent),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
