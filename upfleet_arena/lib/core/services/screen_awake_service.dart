import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the Host screen awake while it is hosting a room.
///
/// Mobile operating systems suspend background work and dim the screen; a
/// sleeping Host would drop every client. The wakelock is held only for the
/// hosting role and released as soon as the room tears down (PLAN.md §2.9).
abstract class ScreenAwakeService {
  /// Prevents the screen from sleeping.
  Future<void> enable();

  /// Allows the screen to sleep again.
  Future<void> disable();
}

/// Production implementation backed by `wakelock_plus`.
class WakelockScreenAwakeService implements ScreenAwakeService {
  const WakelockScreenAwakeService();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// The screen-awake service used by the app.
///
/// Overridden in tests with a recording fake.
final screenAwakeServiceProvider = Provider<ScreenAwakeService>(
  (Ref ref) => const WakelockScreenAwakeService(),
);