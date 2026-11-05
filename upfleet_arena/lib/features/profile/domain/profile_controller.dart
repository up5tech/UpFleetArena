import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'profile.dart';

/// Reads and writes the local profile.
final profileRepositoryProvider = Provider<ProfileRepository>((Ref ref) {
  return ProfileRepository(ref.watch(localPreferencesProvider));
});

/// The local guest profile of this device.
class ProfileController extends Notifier<Profile> {
  @override
  Profile build() => ref.read(profileRepositoryProvider).load();

  /// Updates the nickname locally.
  void setDisplayName(String value) {
    state = state.copyWith(displayName: value);
    unawaitedSave();
  }

  /// Updates the avatar locally.
  void setAvatarId(String value) {
    state = state.copyWith(avatarId: value);
    unawaitedSave();
  }

  /// Persists the profile.
  Future<void> save() => ref.read(profileRepositoryProvider).save(state);

  void unawaitedSave() {
    // The profile is a local convenience; a failed write is not worth
    // interrupting the UI for.
    save().catchError((Object _) {});
  }
}

/// The current profile.
final profileProvider = NotifierProvider<ProfileController, Profile>(
  ProfileController.new,
);
