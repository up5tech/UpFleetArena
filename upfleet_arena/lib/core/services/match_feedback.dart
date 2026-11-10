import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game_engine/combat/combat.dart';
import '../../shared/models/match_models.dart';
import '../settings/feedback_settings.dart';

/// The short sound effects shipped with the app.
enum GameSound {
  fire('sounds/fire.wav'),
  hit('sounds/hit.wav'),
  miss('sounds/miss.wav'),
  sunk('sounds/sunk.wav'),
  win('sounds/win.wav'),
  lose('sounds/lose.wav'),
  warning('sounds/warning.wav');

  const GameSound(this.asset);

  /// The bundled asset path.
  final String asset;
}

/// Plays the bundled sound effects.
///
/// Abstracted so tests can record what would play without touching the audio
/// platform channels.
abstract class SoundPlayer {
  /// Plays [sound], replacing any effect still playing.
  Future<void> play(GameSound sound);

  /// Releases the underlying player.
  Future<void> dispose();
}

/// Production sound player backed by `audioplayers`.
class AssetSoundPlayer implements SoundPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(GameSound sound) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(sound.asset), volume: 0.9);
    } on Object {
      // Audio is a best-effort enhancement; a failure must never interrupt
      // the match (PLAN.md §10.2).
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}

/// The haptic strengths used by the game.
enum HapticPulse { light, medium, heavy, selection }

/// Emits haptic feedback. Injected so tests can record pulses.
typedef HapticsEmitter = void Function(HapticPulse pulse);

/// Haptics backed by the platform vibration APIs.
void systemHaptics(HapticPulse pulse) {
  switch (pulse) {
    case HapticPulse.light:
      HapticFeedback.lightImpact();
    case HapticPulse.medium:
      HapticFeedback.mediumImpact();
    case HapticPulse.heavy:
      HapticFeedback.heavyImpact();
    case HapticPulse.selection:
      HapticFeedback.selectionClick();
  }
}

/// Coordinates sound and haptic feedback for match events.
///
/// Every effect respects the player's independent sound and haptics toggles
/// (PLAN.md §5.5, §15 Phase 8). Feedback is personal: it fires for the player
/// who shot or was shot at, not for spectators reading the public feed.
class MatchFeedback {
  MatchFeedback(this._sounds, this._settings, [this._haptics = systemHaptics]);

  final SoundPlayer _sounds;
  final FeedbackSettings Function() _settings;
  final HapticsEmitter _haptics;

  void _sound(GameSound sound) {
    if (_settings().soundEnabled) {
      // Fire and forget: the UI never waits on the audio backend.
      _sounds.play(sound);
    }
  }

  void _haptic(HapticPulse pulse) {
    if (_settings().hapticsEnabled) _haptics(pulse);
  }

  /// The local player pressed Fire.
  void fire() {
    _sound(GameSound.fire);
    _haptic(HapticPulse.light);
  }

  /// A shot the local player was involved in resolved.
  ///
  /// [viewerPlayerId] is this device's player. Nothing is played when the
  /// viewer is neither the attacker nor the target (a spectator).
  void shotResolved(ShotFeedback feedback, String viewerPlayerId) {
    final bool involved =
        feedback.attackerPlayerId == viewerPlayerId ||
        feedback.targetPlayerId == viewerPlayerId;
    if (!involved) return;

    switch (feedback.result) {
      case ShotResult.miss:
        _sound(GameSound.miss);
        _haptic(HapticPulse.selection);
      case ShotResult.hit:
        _sound(GameSound.hit);
        _haptic(HapticPulse.medium);
      case ShotResult.shipSunk:
        _sound(GameSound.sunk);
        _haptic(HapticPulse.heavy);
    }
  }

  /// The turn is about to run out.
  ///
  /// Sound only: the clock is shared by the whole room, so buzzing every
  /// device's motors would be noise rather than help.
  void turnEnding() {
    _sound(GameSound.warning);
  }

  /// The match ended; [won] tells whether the local player won.
  void matchFinished({required bool won}) {
    _sound(won ? GameSound.win : GameSound.lose);
    _haptic(won ? HapticPulse.heavy : HapticPulse.medium);
  }
}

/// The bundled sound player owned by the app.
final soundPlayerProvider = Provider<SoundPlayer>((Ref ref) {
  final SoundPlayer player = AssetSoundPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// The match feedback coordinator, reading the live settings on every event.
final matchFeedbackProvider = Provider<MatchFeedback>((Ref ref) {
  return MatchFeedback(
    ref.watch(soundPlayerProvider),
    () => ref.read(feedbackSettingsProvider),
  );
});