import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../game_engine/bot/bot_brain.dart';
import '../../../shared/models/room_models.dart';
import '../../profile/domain/profile.dart';
import '../../profile/domain/profile_controller.dart';
import '../../rooms/domain/room_session_controller.dart';

/// Picks the strength of the computer opponent and starts a solo match.
///
/// Practice needs no Wi-Fi, no room and no invitation code: the room authority
/// runs on this device and the bot is seated next to the player.
class BotSetupScreen extends ConsumerStatefulWidget {
  const BotSetupScreen({super.key});

  @override
  ConsumerState<BotSetupScreen> createState() => _BotSetupScreenState();
}

class _BotSetupScreenState extends ConsumerState<BotSetupScreen> {
  BotDifficulty _difficulty = BotDifficulty.medium;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Profile profile = ref.watch(profileProvider);
    final RoomSessionState session = ref.watch(roomSessionControllerProvider);
    final bool busy = session.status == RoomSessionStatus.working;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.playVsComputer)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
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
                            '${l10n.board} · '
                            '${RoomConfig.defaults.rows}×'
                            '${RoomConfig.defaults.columns}',
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
                      l10n.chooseDifficulty,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final BotDifficulty difficulty in BotDifficulty.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DifficultyTile(
                          icon: _iconFor(difficulty),
                          title: _labelOf(l10n, difficulty),
                          hint: _hintOf(l10n, difficulty),
                          selected: _difficulty == difficulty,
                          onTap: () => setState(() => _difficulty = difficulty),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.practiceHint,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppTheme.textSecondary, height: 1.35),
            ),
            if (session.errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                session.errorMessage!,
                style: const TextStyle(color: AppTheme.danger),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || !profile.isComplete
                  ? null
                  : () => _start(profile),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.smart_toy_outlined),
              label: Text(busy ? l10n.startingPractice : l10n.startPractice),
            ),
            if (!profile.isComplete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.pickNicknameFirst,
                  style: const TextStyle(color: AppTheme.sunk),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(Profile profile) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String botName = l10n.botDisplayName(_labelOf(l10n, _difficulty));
    await ref
        .read(roomSessionControllerProvider.notifier)
        .startPractice(
          profile: profile,
          difficulty: _difficulty,
          botName: botName,
        );
    if (!mounted) return;
    final RoomSessionState session = ref.read(roomSessionControllerProvider);
    if (session.isInRoom) {
      context.go('/placement');
      return;
    }
    if (session.errorMessage != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(session.errorMessage!)));
    }
  }

  IconData _iconFor(BotDifficulty difficulty) => switch (difficulty) {
    BotDifficulty.easy => Icons.sentiment_satisfied_alt_outlined,
    BotDifficulty.medium => Icons.smart_toy_outlined,
    BotDifficulty.hard => Icons.local_fire_department_outlined,
  };

  String _labelOf(AppLocalizations l10n, BotDifficulty difficulty) =>
      switch (difficulty) {
        BotDifficulty.easy => l10n.difficultyEasy,
        BotDifficulty.medium => l10n.difficultyMedium,
        BotDifficulty.hard => l10n.difficultyHard,
      };

  String _hintOf(AppLocalizations l10n, BotDifficulty difficulty) =>
      switch (difficulty) {
        BotDifficulty.easy => l10n.difficultyEasyHint,
        BotDifficulty.medium => l10n.difficultyMediumHint,
        BotDifficulty.hard => l10n.difficultyHardHint,
      };
}

class _DifficultyTile extends StatelessWidget {
  const _DifficultyTile({
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
