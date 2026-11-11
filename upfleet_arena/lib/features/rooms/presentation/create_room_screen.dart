import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/bot/bot_brain.dart';
import '../../../shared/models/room_models.dart';
import '../../bot/presentation/bot_labels.dart';
import '../../profile/domain/profile.dart';
import '../../profile/domain/profile_controller.dart';
import '../domain/room_session_controller.dart';
import 'board_size_steppers.dart';

/// Creates a room on this device.
///
/// The Host phone becomes the room authority: it opens the TCP listener,
/// advertises the room and holds the invitation code
/// (PLAN.md §1.5, §6.3).
class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  int _rows = RoomConfig.defaults.rows;
  int _columns = RoomConfig.defaults.columns;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Profile profile = ref.watch(profileProvider);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final bool busy = session.status == RoomSessionStatus.working;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createRoomScreenTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          profile.avatarId.isEmpty
                              ? Avatars.fallback
                              : profile.avatarId,
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                profile.displayName.isEmpty
                                    ? l10n.noNicknameYet
                                    : profile.displayName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                l10n.youWillHost,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/profile'),
                          child: Text(l10n.edit),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _SettingRow(
                      label: l10n.players,
                      value: '${RoomConfig.minimumPlayers}–'
                          '${RoomConfig.maximumPlayers}',
                    ),
                    _SettingRow(
                      label: l10n.board,
                      value: '$_rows×$_columns',
                    ),
                    _SettingRow(
                      label: l10n.fleet,
                      value: RoomConfig.defaults.fleetPreset.wire,
                    ),
                    _SettingRow(
                      label: l10n.timers,
                      value:
                          '${RoomConfig.defaults.placementDurationSeconds}s / '
                          '${RoomConfig.defaults.turnDurationSeconds}s',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.defaultSettingsHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
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
                      l10n.board,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    BoardSizeSteppers(
                      rows: _rows,
                      columns: _columns,
                      enabled: !busy,
                      onRowsChanged: (int value) =>
                          setState(() => _rows = value),
                      onColumnsChanged: (int value) =>
                          setState(() => _columns = value),
                    ),
                  ],
                ),
              ),
            ),
            if (session.errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorCard(
                message: session.errorMessage!,
                code: session.errorCode,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || profile.displayName.trim().isEmpty
                  ? null
                  : () async {
                      final RoomSessionController controller = ref.read(
                        roomSessionControllerProvider.notifier,
                      );
                      await controller.createRoom(
                        profile: profile,
                        config: RoomConfig.defaults.copyWith(
                          rows: _rows,
                          columns: _columns,
                        ),
                        botNameBuilder: (BotDifficulty difficulty) =>
                            botDisplayName(l10n, difficulty),
                      );
                      if (!context.mounted) return;
                      if (ref.read(roomSessionControllerProvider).isInRoom) {
                        context.go('/lobby');
                      }
                    },
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_home_work),
              label: Text(busy ? l10n.creating : l10n.createRoomScreenTitle),
            ),
            if (profile.displayName.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.pickNicknameFirst,
                  style: const TextStyle(color: AppTheme.sunk),
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
                      l10n.whileYouHost,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.keepAppOpenHost,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.sunk,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.code});

  final String message;
  final String? code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                if (code != null)
                  Text(
                    code!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
