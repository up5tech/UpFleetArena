import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/local_preferences.dart';

/// Entry point.
///
/// The app is fully offline: no bootstrap request, no telemetry, no remote
/// configuration (PLAN.md §10.2).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final LocalPreferences preferences = await LocalPreferences.open();

  runApp(
    ProviderScope(
      overrides: [
        localPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const UpFleetArenaApp(),
    ),
  );
}
