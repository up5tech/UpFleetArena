import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/bot/presentation/bot_setup_screen.dart';
import '../features/lan_lab/presentation/lan_lab_screen.dart';
import '../features/lobby/presentation/host_settings_screen.dart';
import '../features/lobby/presentation/lobby_screen.dart';
import '../features/match/presentation/final_fleets_screen.dart';
import '../features/match/presentation/match_result_screen.dart';
import '../features/match/presentation/match_screen.dart';
import '../features/placement/presentation/placement_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/rooms/presentation/create_room_screen.dart';
import '../features/rooms/presentation/join_room_screen.dart';

/// Application router.
///
/// Every implemented screen is routable. The LAN Lab is a developer tool and
/// is only registered in debug builds (PLAN.md §15).
class AppRouter {
  const AppRouter._();

  /// The router instance used by the app.
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'home',
        builder: (BuildContext context, GoRouterState state) =>
            const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileScreen(),
      ),
      GoRoute(
        path: '/play-bot',
        name: 'play-bot',
        builder: (BuildContext context, GoRouterState state) =>
            const BotSetupScreen(),
      ),
      GoRoute(
        path: '/create-room',
        name: 'create-room',
        builder: (BuildContext context, GoRouterState state) =>
            const CreateRoomScreen(),
      ),
      GoRoute(
        path: '/join-room',
        name: 'join-room',
        builder: (BuildContext context, GoRouterState state) =>
            const JoinRoomScreen(),
      ),
      GoRoute(
        path: '/lobby',
        name: 'lobby',
        builder: (BuildContext context, GoRouterState state) =>
            const LobbyScreen(),
      ),
      GoRoute(
        path: '/lobby/settings',
        name: 'host-settings',
        builder: (BuildContext context, GoRouterState state) =>
            const HostSettingsScreen(),
      ),
      GoRoute(
        path: '/placement',
        name: 'placement',
        builder: (BuildContext context, GoRouterState state) =>
            const PlacementScreen(),
      ),
      GoRoute(
        path: '/match',
        name: 'match',
        builder: (BuildContext context, GoRouterState state) =>
            const MatchScreen(),
      ),
      GoRoute(
        path: '/match/result',
        name: 'match-result',
        builder: (BuildContext context, GoRouterState state) =>
            const MatchResultScreen(),
      ),
      GoRoute(
        path: '/match/result/fleets',
        name: 'match-result-fleets',
        builder: (BuildContext context, GoRouterState state) =>
            const FinalFleetsScreen(),
      ),
      if (kDebugMode)
        GoRoute(
          path: '/lan-lab',
          name: 'lan-lab',
          builder: (BuildContext context, GoRouterState state) =>
              const LanLabScreen(),
        ),
    ],
  );
}
