import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/core/services/match_feedback.dart';
import 'package:upfleet_arena/core/settings/feedback_settings.dart';
import 'package:upfleet_arena/game_engine/combat/combat.dart';
import 'package:upfleet_arena/shared/models/match_models.dart';

/// Records the sounds that would play, without any audio backend.
class RecordingSoundPlayer implements SoundPlayer {
  final List<GameSound> played = <GameSound>[];
  bool disposed = false;

  @override
  Future<void> play(GameSound sound) async => played.add(sound);

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late RecordingSoundPlayer sounds;
  late List<HapticPulse> pulses;
  late FeedbackSettings settings;
  late MatchFeedback feedback;

  setUp(() {
    sounds = RecordingSoundPlayer();
    pulses = <HapticPulse>[];
    settings = const FeedbackSettings();
    feedback = MatchFeedback(
      sounds,
      () => settings,
      (HapticPulse pulse) => pulses.add(pulse),
    );
  });

  ShotFeedback shot(ShotResult result) => ShotFeedback(
    attackerPlayerId: 'attacker',
    targetPlayerId: 'target',
    row: 0,
    column: 0,
    result: result,
  );

  test('fire plays the fire sound and a light pulse', () {
    feedback.fire();
    expect(sounds.played, <GameSound>[GameSound.fire]);
    expect(pulses, <HapticPulse>[HapticPulse.light]);
  });

  test('sound off silences effects but keeps haptics', () {
    settings = settings.copyWith(soundEnabled: false);
    feedback.fire();
    feedback.shotResolved(shot(ShotResult.hit), 'attacker');
    expect(sounds.played, isEmpty);
    expect(pulses, <HapticPulse>[HapticPulse.light, HapticPulse.medium]);
  });

  test('haptics off keeps sound but emits no pulse', () {
    settings = settings.copyWith(hapticsEnabled: false);
    feedback.fire();
    feedback.shotResolved(shot(ShotResult.shipSunk), 'target');
    expect(sounds.played, <GameSound>[GameSound.fire, GameSound.sunk]);
    expect(pulses, isEmpty);
  });

  test('both off produces no feedback at all', () {
    settings = settings.copyWith(soundEnabled: false, hapticsEnabled: false);
    feedback.fire();
    feedback.shotResolved(shot(ShotResult.hit), 'attacker');
    feedback.matchFinished(won: true);
    expect(sounds.played, isEmpty);
    expect(pulses, isEmpty);
  });

  test('each shot result maps to its own sound and pulse for the attacker', () {
    feedback.shotResolved(shot(ShotResult.miss), 'attacker');
    feedback.shotResolved(shot(ShotResult.hit), 'attacker');
    feedback.shotResolved(shot(ShotResult.shipSunk), 'attacker');
    expect(sounds.played, <GameSound>[
      GameSound.miss,
      GameSound.hit,
      GameSound.sunk,
    ]);
    expect(pulses, <HapticPulse>[
      HapticPulse.selection,
      HapticPulse.medium,
      HapticPulse.heavy,
    ]);
  });

  test('the target also hears the shot that hit them', () {
    feedback.shotResolved(shot(ShotResult.hit), 'target');
    expect(sounds.played, <GameSound>[GameSound.hit]);
    expect(pulses, <HapticPulse>[HapticPulse.medium]);
  });

  test('a spectator receives no personal feedback', () {
    feedback.shotResolved(shot(ShotResult.shipSunk), 'someone-else');
    expect(sounds.played, isEmpty);
    expect(pulses, isEmpty);
  });

  test('winning and losing play distinct endings', () {
    feedback.matchFinished(won: true);
    feedback.matchFinished(won: false);
    expect(sounds.played, <GameSound>[GameSound.win, GameSound.lose]);
    expect(pulses, <HapticPulse>[HapticPulse.heavy, HapticPulse.medium]);
  });
}