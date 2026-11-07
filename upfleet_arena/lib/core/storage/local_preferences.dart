import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Local, non-sensitive preferences stored on this device only.
///
/// Nothing here ever leaves the device, and there is no cloud synchronization
/// (PLAN.md §7.2, §18).
class LocalPreferences {
  LocalPreferences(this._preferences);

  /// Opens the local preference store.
  static Future<LocalPreferences> open() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return LocalPreferences(preferences);
  }

  /// Builds a store around an existing instance. Used by tests.
  LocalPreferences.withInstance(SharedPreferences preferences)
    : _preferences = preferences;

  final SharedPreferences _preferences;

  static const String _nicknameKey = 'profile.nickname';
  static const String _avatarKey = 'profile.avatarId';
  static const String _deviceIdKey = 'device.id';
  static const String _lastRoomKey = 'room.last';
  static const String _soundKey = 'settings.soundEnabled';
  static const String _hapticsKey = 'settings.hapticsEnabled';
  static const String _reducedMotionKey = 'settings.reducedMotion';

  /// The saved nickname, or `null` when the player has not chosen one.
  String? get nickname => _preferences.getString(_nicknameKey);

  /// Saves the nickname.
  Future<void> setNickname(String value) =>
      _preferences.setString(_nicknameKey, value);

  /// The saved avatar identifier, or `null`.
  String? get avatarId => _preferences.getString(_avatarKey);

  /// Saves the avatar identifier.
  Future<void> setAvatarId(String value) =>
      _preferences.setString(_avatarKey, value);

  /// A stable, locally generated identifier for this device.
  ///
  /// Used by the Host to reject a second active connection from the same
  /// device. It is not an account, not a cloud identity and never leaves the
  /// LAN (PLAN.md §7.3).
  String get deviceId {
    final String? existing = _preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final String generated = _generateId();
    // Fire and forget: the value is regenerated on the next call if the
    // write has not landed yet, which is harmless for its purpose.
    unawaited(_preferences.setString(_deviceIdKey, generated));
    return generated;
  }

  /// The last room this device joined, for a "rejoin" shortcut.
  Map<String, dynamic>? get lastRoom {
    final String? raw = _preferences.getString(_lastRoomKey);
    if (raw == null || raw.isEmpty) return null;
    final List<String> parts = raw.split('|');
    if (parts.length != 4) return null;
    return <String, dynamic>{
      'roomId': parts[0],
      'code': parts[1],
      'host': parts[2],
      'port': int.tryParse(parts[3]) ?? 0,
    };
  }

  /// Stores the last joined room.
  Future<void> setLastRoom({
    required String roomId,
    required String code,
    required String host,
    required int port,
  }) => _preferences.setString(_lastRoomKey, '$roomId|$code|$host|$port');

  /// Forgets the last joined room.
  Future<void> clearLastRoom() => _preferences.remove(_lastRoomKey);

  /// Whether shot and result sound effects play. On by default.
  bool get soundEnabled => _preferences.getBool(_soundKey) ?? true;

  /// Persists the sound-effects preference.
  Future<void> setSoundEnabled(bool value) =>
      _preferences.setBool(_soundKey, value);

  /// Whether haptic feedback plays. On by default.
  bool get hapticsEnabled => _preferences.getBool(_hapticsKey) ?? true;

  /// Persists the haptics preference.
  Future<void> setHapticsEnabled(bool value) =>
      _preferences.setBool(_hapticsKey, value);

  /// Whether the player asked for reduced motion. Off by default; the OS
  /// accessibility setting is honored on top of it (PLAN.md §5.5).
  bool get reducedMotion => _preferences.getBool(_reducedMotionKey) ?? false;

  /// Persists the reduced-motion preference.
  Future<void> setReducedMotion(bool value) =>
      _preferences.setBool(_reducedMotionKey, value);

  /// The chosen language tag (`en`, `vi`), or `null` to follow the system.
  String? get localeTag => _preferences.getString(_localeKey);

  /// Persists the language choice; `null` restores system-following.
  Future<void> setLocaleTag(String? value) => value == null
      ? _preferences.remove(_localeKey)
      : _preferences.setString(_localeKey, value);

  static const String _localeKey = 'settings.locale';

  static final Random _random = Random.secure();

  /// Generates a random identifier.
  static String _generateId() {
    const String alphabet =
        'abcdefghijklmnopqrstuvwxyz0123456789';
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 24; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }
}
