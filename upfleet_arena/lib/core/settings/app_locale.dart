import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// The language the UI is shown in.
///
/// `null` means "follow the system locale"; an explicit tag pins the choice.
/// The value is stored on this device only (PLAN.md §7.2, §15 Phase 8).
class AppLocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    final String? tag = ref.read(localPreferencesProvider).localeTag;
    return tag == null ? null : Locale(tag);
  }

  /// Pins the language, or passes `null` to follow the system again.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await ref.read(localPreferencesProvider).setLocaleTag(locale?.languageCode);
  }
}

/// The current UI locale override, or `null` to follow the system.
final appLocaleProvider = NotifierProvider<AppLocaleController, Locale?>(
  AppLocaleController.new,
);

/// The languages shipped with the app.
const List<Locale> supportedAppLocales = <Locale>[
  Locale('en'),
  Locale('vi'),
];