import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage/local_preferences.dart';

/// The local preference store.
///
/// Overridden at startup with the real instance, because opening it is
/// asynchronous.
final localPreferencesProvider = Provider<LocalPreferences>((Ref ref) {
  throw StateError(
    'localPreferencesProvider must be overridden with a real instance in '
    'main().',
  );
});
