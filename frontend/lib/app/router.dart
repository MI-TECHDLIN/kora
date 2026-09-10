import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../features/map/screens/map_screen.dart';
import '../features/onboarding/screens/onboarding_flow.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/summary/screens/summary_screen.dart';
import '../features/voice/screens/voice_screen.dart';
import '../mascot/mascot_display.dart';
import '../providers/onboarding_provider.dart';
import 'main_shell.dart';

/// Every route in the app is declared in this file (frontend rules).
abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const voice = '/voice';
  static const map = '/map';
  static const summary = '/summary';
  static const settings = '/settings';
}

/// The four main tabs, in bottom-nav order. Index = shell branch index.
enum MainTab {
  voice(AppRoutes.voice),
  map(AppRoutes.map),
  summary(AppRoutes.summary),
  settings(AppRoutes.settings);

  const MainTab(this.path);
  final String path;

  static MainTab? fromPath(String path) {
    for (final tab in values) {
      if (path == tab.path || path.startsWith('${tab.path}/')) return tab;
    }
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever onboarding completes or resets.
  final onboardingChanges = ValueNotifier<bool>(ref.read(onboardingProvider));
  ref.listen<bool>(
    onboardingProvider,
    (_, next) => onboardingChanges.value = next,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.voice,
    refreshListenable: onboardingChanges,
    redirect: (context, state) {
      final needsOnboarding = ref.read(onboardingProvider);
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (needsOnboarding && !atOnboarding) return AppRoutes.onboarding;
      if (!needsOnboarding && atOnboarding) return AppRoutes.voice;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => _fadePage(
          state,
          const OrbMaterialScope(
            material: OrbMaterial.holographic,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: OnboardingFlow(),
            ),
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => _fadePage(
          state,
          OrbMaterialScope(
            material: OrbMaterial.chrome,
            child: MainShell(navigationShell: navigationShell),
          ),
        ),
        branches: [
          _branch(AppRoutes.voice, const VoiceScreen()),
          _branch(AppRoutes.map, const MapScreen()),
          _branch(AppRoutes.summary, const SummaryScreen()),
          _branch(AppRoutes.settings, const SettingsScreen()),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    onboardingChanges.dispose();
  });
  return router;
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);

/// Pages cross-fade over the shared gradient background instead of sliding.
Page<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: VoiceOpsMotion.slow,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
