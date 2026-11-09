import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:upfleet_arena/l10n/generated/app_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/settings/app_locale.dart';
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
      SnackBar(content: Text(AppLocalizations.of(context).profileSaved)),
    );
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Profile profile = ref.watch(profileProvider);
    final Locale? currentLocale = ref.watch(appLocaleProvider);
    final FeedbackSettings feedback = ref.watch(feedbackSettingsProvider);
    final FeedbackSettingsController feedbackController = ref.read(
      feedbackSettingsProvider.notifier,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.yourProfile)),
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
                      l10n.nickname,
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
                      decoration: InputDecoration(
                        hintText: l10n.nicknameHint,
                        prefixIcon: const Icon(Icons.badge_outlined),
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
                      l10n.nicknamePrivacy,
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
                      l10n.avatar,
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
                      l10n.soundAndEffects,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.soundEffects),
                      subtitle: Text(l10n.soundEffectsSubtitle),
                      value: feedback.soundEnabled,
                      onChanged: (bool value) =>
                          feedbackController.setSoundEnabled(value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.hapticFeedback),
                      subtitle: Text(l10n.hapticFeedbackSubtitle),
                      value: feedback.hapticsEnabled,
                      onChanged: (bool value) =>
                          feedbackController.setHapticsEnabled(value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.reduceMotion),
                      subtitle: Text(l10n.reduceMotionSubtitle),
                      value: feedback.reducedMotion,
                      onChanged: (bool value) =>
                          feedbackController.setReducedMotion(value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.language,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.languageSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: currentLocale?.languageCode ?? 'system',
                      isExpanded: true,
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'system',
                          child: Text(l10n.followSystem),
                        ),
                        DropdownMenuItem<String>(
                          value: 'en',
                          child: Text(l10n.english),
                        ),
                        DropdownMenuItem<String>(
                          value: 'vi',
                          child: Text(l10n.vietnamese),
                        ),
                      ],
                      onChanged: (String? value) {
                        final Locale? locale = value == null || value == 'system'
                            ? null
                            : Locale(value);
                        ref.read(appLocaleProvider.notifier).setLocale(locale);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: Text(l10n.saveProfile)),
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
    return Semantics(
      label: '${AppLocalizations.of(context).avatar} $avatar',
      selected: selected,
      button: true,
      child: InkWell(
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
          child: ExcludeSemantics(
            child: Text(avatar, style: const TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }
}
