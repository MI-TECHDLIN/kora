import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';

/// The main tab currently shown, or null outside the main shell (e.g.
/// during onboarding). Derived from go_router — read it, don't set it.
final activeTabProvider = Provider<MainTab?>((ref) {
  final router = ref.watch(routerProvider);
  final delegate = router.routerDelegate;

  void onRouteChange() => ref.invalidateSelf();
  delegate.addListener(onRouteChange);
  ref.onDispose(() => delegate.removeListener(onRouteChange));

  return MainTab.fromPath(delegate.currentConfiguration.uri.path);
});

/// Navigation from outside the widget tree (e.g. the agent's
/// `start_navigation` tool). Everything goes through go_router.
final navigationProvider = Provider<NavigationActions>(
  (ref) => NavigationActions(ref.watch(routerProvider)),
);

class NavigationActions {
  const NavigationActions(this._router);
  final GoRouter _router;

  void goTo(MainTab tab) => _router.go(tab.path);

  /// Maps an agent screen key ('voice' | 'map' | 'summary' | 'settings')
  /// to a tab; unknown keys fall back to voice.
  void navigateForAgent(String screenKey) => goTo(
    MainTab.values.firstWhere(
      (tab) => tab.name == screenKey,
      orElse: () => MainTab.voice,
    ),
  );
}
