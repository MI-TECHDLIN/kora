import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/auth/screens/sign_up_screen.dart';
import '../features/auth/screens/welcome_screen.dart';
import '../features/map/screens/map_screen.dart';
import '../features/onboarding/screens/onboarding_flow.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/summary/screens/summary_screen.dart';
import '../features/voice/screens/voice_screen.dart';
import '../mascot/mascot_display.dart';
import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import 'main_shell.dart';

/// Every route in the app is declared in this file (frontend rules).
abstract final class AppRoutes {
  /// Signed-out entry; sign-up and sign-in stack on top of it.
  static const welcome = '/welcome';
  static const _signUp = 'sign-up';
  static const _signIn = 'sign-in';
  static const signUp = '$welcome/$_signUp';
  static const signIn = '$welcome/$_signIn';

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

  // …and whenever the Supabase session changes: sign-in, sign-out, refresh.
  final auth = ref.watch(authRepositoryProvider);
  final authChanges = ValueNotifier<int>(0);
  final authSubscription = auth.changes.listen((_) => authChanges.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.voice,
    refreshListenable: Listenable.merge([onboardingChanges, authChanges]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final atOnboarding = location == AppRoutes.onboarding;
      final atAuth =
          location == AppRoutes.welcome ||
          location.startsWith('${AppRoutes.welcome}/');

      // Onboarding gate first: it introduces the app before sign-up.
      if (ref.read(onboardingProvider)) {
        return atOnboarding ? null : AppRoutes.onboarding;
      }
      // Auth gate: without a live session, only the auth screens are open.
      if (!auth.hasValidSession) return atAuth ? null : AppRoutes.welcome;
      if (atOnboarding || atAuth) return AppRoutes.voice;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        pageBuilder: (context, state) =>
            _authPage(state, const WelcomeScreen()),
        routes: [
          GoRoute(
            path: AppRoutes._signUp,
            pageBuilder: (context, state) =>
                _authPage(state, const SignUpScreen()),
          ),
          GoRoute(
            path: AppRoutes._signIn,
            pageBuilder: (context, state) =>
                _authPage(state, const SignInScreen()),
          ),
        ],
      ),
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
    authSubscription.cancel();
    authChanges.dispose();
  });
  return router;
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);

/// The signed-out screens follow straight on from onboarding, so they share
/// its holographic co-rider.
Page<void> _authPage(GoRouterState state, Widget screen) => _fadePage(
  state,
  OrbMaterialScope(material: OrbMaterial.holographic, child: screen),
);

/// Pages cross-fade over the shared gradient background instead of sliding.
/// A page also fades out while one is pushed over it (sign-in over welcome),
/// since the transparent pages would otherwise show through each other.
Page<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: VoiceOpsMotion.slow,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: FadeTransition(
              opacity: ReverseAnimation(secondaryAnimation),
              child: child,
            ),
          ),
    );
