import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/protocol/protocol_constants.dart';

/// Outcome of a local-network permission check.
enum LanPermissionState {
  /// Access is granted; discovery and sockets may be used.
  granted,

  /// The user denied access but may be asked again.
  denied,

  /// The user denied access permanently; only system settings can change it.
  permanentlyDenied,

  /// The platform does not expose an explicit runtime permission.
  ///
  /// iOS grants local-network access implicitly: the system shows its own
  /// prompt the first time a Bonjour or socket API is used. Nothing can be
  /// requested up front (PLAN.md §11.2).
  implicit,

  /// The platform exposes a permission but the plugin could not answer.
  unknown,
}

/// Reads and requests the local-network permission.
///
/// Platform behaviour (PLAN.md §11):
///
/// * **Android 16 and below** — no runtime permission exists; access is
///   granted at install time. Android 17 (API 37) blocks LAN access by
///   default for apps targeting that level unless `ACCESS_LOCAL_NETWORK` is
///   declared and requested.
/// * **iOS 14+** — access is implicit. The system prompt appears on the
///   first Bonjour/socket call, so the request must be triggered from a clear
///   user action such as *Find Rooms* or *Create Room*.
class LanPermissionService {
  const LanPermissionService();

  /// Returns the current permission state without prompting.
  Future<LanPermissionState> currentState() async {
    if (kIsWeb) return LanPermissionState.implicit;
    if (Platform.isIOS) return LanPermissionState.implicit;
    try {
      final PermissionStatus status =
          await Permission.accessLocalNetwork.status;
      return _map(status);
    } on Object catch (error) {
      debugPrint('LAN permission status unavailable: $error');
      return LanPermissionState.unknown;
    }
  }

  /// Requests local-network access when the platform supports an explicit
  /// runtime request.
  ///
  /// On iOS this is a no-op that returns [LanPermissionState.implicit]: the
  /// system prompt is triggered by the first real discovery or socket call.
  Future<LanPermissionState> request() async {
    if (kIsWeb) return LanPermissionState.implicit;
    if (Platform.isIOS) return LanPermissionState.implicit;

    try {
      final PermissionStatus status =
          await Permission.accessLocalNetwork.request();
      return _map(status);
    } on Object catch (error) {
      debugPrint('LAN permission request failed: $error');
      return LanPermissionState.unknown;
    }
  }

  /// A user-facing explanation for a non-granted state.
  ///
  /// The message never mentions an "offline" mode: LAN play is expected to
  /// work without Internet (PLAN.md §5.4).
  String messageFor(LanPermissionState state) {
    switch (state) {
      case LanPermissionState.granted:
        return 'Local network access is granted.';
      case LanPermissionState.denied:
        return 'Local network access was denied. UpFleet Arena needs it to '
            'find and connect to nearby rooms on the same Wi-Fi.';
      case LanPermissionState.permanentlyDenied:
        return 'Local network access is blocked. Open the system settings '
            'for UpFleet Arena and allow local network access, then try '
            'again.';
      case LanPermissionState.implicit:
        return 'Your system asks for local network access the first time '
            'UpFleet Arena scans for nearby rooms.';
      case LanPermissionState.unknown:
        return 'Local network access could not be verified. You can still '
            'try to connect manually.';
    }
  }

  /// Opens the app's system settings page so a permanently denied permission
  /// can be re-enabled.
  Future<bool> openSettings() => openAppSettings();

  /// A short troubleshooting checklist for LAN failures.
  ///
  /// Shown when discovery returns nothing or a direct connection fails
  /// (PLAN.md §5.4, §11.3).
  List<String> get troubleshootingSteps => const <String>[
    'Make sure every device is on the same Wi-Fi network.',
    'Turn off guest Wi-Fi or AP / client isolation on the router.',
    'Disconnect any VPN that routes local traffic.',
    'Keep the Host app open and in the foreground while hosting.',
    'Try the manual IP / port connection if discovery is blocked.',
  ];

  LanPermissionState _map(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
      case PermissionStatus.limited:
        return LanPermissionState.granted;
      case PermissionStatus.denied:
        return LanPermissionState.denied;
      case PermissionStatus.permanentlyDenied:
        return LanPermissionState.permanentlyDenied;
      case PermissionStatus.restricted:
        return LanPermissionState.permanentlyDenied;
      case PermissionStatus.provisional:
        return LanPermissionState.granted;
    }
  }
}

/// Stable error code used when local-network access is missing.
const String lanPermissionDeniedCode = ProtocolErrorCode.lanPermissionDenied;
