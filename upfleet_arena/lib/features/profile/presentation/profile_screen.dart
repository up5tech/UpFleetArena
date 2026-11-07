import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/settings/feedback_settings.dart';
import '../../../shared/models/room_models.dart';
import '../domain/profile.dart';
import '../domain/profile_controller.dart';

/// Lets the player pick a nickname and an avatar.
///
/// There is no account and no registration: the profile lives on this device
/// only (PLAN.md §2.1).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.onSaved});

  /// Called after the profile was saved.
  final VoidCallback? onSaved;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Profile profile = ref.read(profileProvider);
    _nameController = TextEditingController(text: profile.displayName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ProfileController controller = ref.read(profileProvider.notifier);
    final String value = _nameController.text;

    final String? problem = DisplayNames.validate(value);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    controller.setDisplayName(DisplayNames.normalize(value));
    await controller.save();
    if (!mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved on this device.')),
    );
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final Profile profile = ref.watch(profileProvider);
    final FeedbackSettings feedback = ref.watch(feedbackSettingsProvider);
    final FeedbackSettingsController feedbackController = ref.read(
      feedbackSettingsProvider.notifier,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
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
                    Text(
                      'Nickname',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      maxLength: DisplayNames.maximumLength,
                      textInputAction: TextInputAction.done,
                      onChanged: (String _) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (String _) => _save(),
                      decoration: const InputDecoration(
                        hintText: 'How should other players see you?',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppTheme.danger),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Your nickname is stored on this device and is shared '
                      'only with the players in the room you join.',
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
                      'Avatar',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String avatar in Avatars.all)
                          _AvatarOption(
                            avatar: avatar,
                            selected: avatar == profile.avatarId,
                            onTap: () => ref
                                .read(profileProvider.notifier)
                                .setAvatarId(avatar),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Sound & effects',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sound effects'),
                      subtitle: const Text('Shot, hit and result sounds'),
                      value: feedback.soundEnabled,
                      onChanged: (bool value) =>
                          feedbackController.setSoundEnabled(value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Haptic feedback'),
                      subtitle: const Text('Vibration on shots and results'),
                      value: feedback.hapticsEnabled,
                      onChanged: (bool value) =>
                          feedbackController.setHapticsEnabled(value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Reduce motion'),
                      subtitle: const Text(
                        'Shorten animations; the system setting is also honored',
                      ),
                      value: feedback.reducedMotion,
                      onChanged: (bool value) =>
                          feedbackController.setReducedMotion(value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save profile')),
          ],
        ),
      ),
    );
  }
}

class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  final String avatar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.18)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(avatar, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
