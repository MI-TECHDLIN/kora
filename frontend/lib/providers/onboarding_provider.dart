import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that the driver finished onboarding, so it only shows once.
abstract interface class OnboardingStore {
  /// Whether onboarding was completed on an earlier launch.
  Future<bool> load();

  Future<void> save({required bool completed});
}

class SharedPreferencesOnboardingStore implements OnboardingStore {
  const SharedPreferencesOnboardingStore();

  static const _key = 'has_completed_onboarding';

  @override
  Future<bool> load() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> save({required bool completed}) async {
    final prefs = await SharedPreferences.getInstance();
    completed ? await prefs.setBool(_key, true) : await prefs.remove(_key);
  }
}

final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => const SharedPreferencesOnboardingStore(),
);

/// Whether onboarding was already completed when the app launched.
/// main.dart reads it with [loadOnboardingCompleted] before the first frame
/// and overrides this, so the router's first redirect is already right and
/// onboarding never flashes up on a returning driver. The default, false,
/// is a first launch.
final onboardingCompletedAtLaunchProvider = Provider<bool>((ref) => false);

/// The saved flag from [store], or false (show onboarding) when it can't be
/// read.
Future<bool> loadOnboardingCompleted(OnboardingStore store) async {
  try {
    return await store.load();
  } catch (_) {
    return false;
  }
}

/// True while onboarding should show. The router gates on it first.
final onboardingProvider = StateNotifierProvider<OnboardingNotifier, bool>(
  (ref) => OnboardingNotifier(
    ref.watch(onboardingStoreProvider),
    completed: ref.watch(onboardingCompletedAtLaunchProvider),
  ),
);

class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier(this._store, {required bool completed})
    : super(!completed);

  final OnboardingStore _store;

  void complete() {
    state = false;
    unawaited(_save(completed: true));
  }

  /// Shows onboarding again, on this launch and the next.
  void reset() {
    state = true;
    unawaited(_save(completed: false));
  }

  Future<void> _save({required bool completed}) async {
    try {
      await _store.save(completed: completed);
    } catch (_) {
      // Keep the state for this run; onboarding shows again next launch.
    }
  }
}
