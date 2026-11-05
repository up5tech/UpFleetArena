import 'package:flutter/foundation.dart';

import '../../../core/storage/local_preferences.dart';

/// The local guest profile of this device.
///
/// There are no accounts, no login and no cloud identity: a nickname and an
/// avatar, stored locally (PLAN.md §2.1, §4.1).
@immutable
class Profile {
  const Profile({required this.displayName, required this.avatarId});

  /// The nickname shown next to the player in the lobby.
  final String displayName;

  /// The avatar identifier shown next to the player in the lobby.
  final String avatarId;

  /// Whether the profile still needs a nickname.
  bool get isComplete => displayName.trim().isNotEmpty;

  /// Returns a copy with the given fields replaced.
  Profile copyWith({String? displayName, String? avatarId}) => Profile(
    displayName: displayName ?? this.displayName,
    avatarId: avatarId ?? this.avatarId,
  );

  /// Serializes the profile.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'displayName': displayName,
    'avatarId': avatarId,
  };
}

/// The avatar choices offered in the profile screen.
class Avatars {
  const Avatars._();

  /// The available avatar identifiers.
  static const List<String> all = <String>[
    '🐙',
    '🦈',
    '🐋',
    '⚓',
    '🛥️',
    '🐢',
    '🦀',
    '🐬',
    '🐳',
    '🌊',
    '🦅',
    '🚀',
  ];

  /// The avatar used when none was chosen.
  static const String fallback = '🐙';
}

/// Reads and writes the local profile.
class ProfileRepository {
  const ProfileRepository(this._preferences);

  /// The backing preference store.
  final LocalPreferences _preferences;

  /// Loads the stored profile.
  Profile load() => Profile(
    displayName: _preferences.nickname ?? '',
    avatarId: _preferences.avatarId ?? Avatars.fallback,
  );

  /// Saves the profile locally.
  Future<void> save(Profile profile) async {
    await _preferences.setNickname(profile.displayName);
    await _preferences.setAvatarId(profile.avatarId);
  }
}
