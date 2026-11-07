import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../storage/local_preferences.dart';

/// Device-local sound, haptics and motion preferences (PLAN.md §5.5, §7.2).
///
/// The toggles are independent: a player may keep sound but silence haptics,
/// or force reduced motion regardless of the OS setting.
@immutable
class FeedbackSettings {
  const FeedbackSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.reducedMotion = false,
  });

  /// Loads the persisted values, applying the defaults for a fresh install.
  factory FeedbackSettings.fromPreferences(LocalPreferences preferences) =>
      FeedbackSettings(
        soundEnabled: preferences.soundEnabled,
        hapticsEnabled: preferences.hapticsEnabled,
        reducedMotion: preferences.reducedMotion,
      );

  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool reducedMotion;

  /// Returns a copy with the given fields replaced.
  FeedbackSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? reducedMotion,
  }) => FeedbackSettings(
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    reducedMotion: reducedMotion ?? this.reducedMotion,
  );
}

/// Reads and persists the feedback preferences.
class FeedbackSettingsController extends Notifier<FeedbackSettings> {
  @override
  FeedbackSettings build() => FeedbackSettings.fromPreferences(
    ref.read(localPreferencesProvider),
  );

  /// Turns sound effects on or off.
  Future<void> setSoundEnabled(bool value) async {
    state = state.copyWith(soundEnabled: value);
    await ref.read(localPreferencesProvider).setSoundEnabled(value);
  }

  /// Turns haptic feedback on or off.
  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    await ref.read(localPreferencesProvider).setHapticsEnabled(value);
  }

  /// Forces reduced motion on or off.
  Future<void> setReducedMotion(bool value) async {
    state = state.copyWith(reducedMotion: value);
    await ref.read(localPreferencesProvider).setReducedMotion(value);
  }
}

/// The current feedback preferences.
final feedbackSettingsProvider =
    NotifierProvider<FeedbackSettingsController, FeedbackSettings>(
      FeedbackSettingsController.new,
    );

/// Whether animations should be shortened or disabled.
///
/// Combines the player's explicit toggle with the OS accessibility setting,
/// so either one is enough to reduce motion (PLAN.md §5.5).
bool useReducedMotion(BuildContext context, FeedbackSettings settings) =>
    settings.reducedMotion || MediaQuery.disableAnimationsOf(context);