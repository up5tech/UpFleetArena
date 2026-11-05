import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/lan_lab/presentation/lan_lab_screen.dart';

/// Application router.
///
/// Phase 0 exposes the home screen and the LAN Lab. Later phases add the
/// lobby, placement, battle and result routes without changing the shell
/// (PLAN.md §10).
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
        path: '/lan-lab',
        name: 'lan-lab',
        builder: (BuildContext context, GoRouterState state) =>
            const LanLabScreen(),
      ),
    ],
  );
}
