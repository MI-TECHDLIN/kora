import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'auth_provider.dart';

/// Remembers whether the post-sign-up co-rider voice step has already run
/// on this device (same storage pattern as [SharedPreferencesOnboardingStore]
/// in `onboarding_provider.dart` and [SharedPreferencesCoRiderVoiceStore] in
/// `co_rider_voice_provider.dart`).
abstract interface class VoiceOnboardingStore {
  /// Whether the step has already shown on this device.
  Future<bool> load();

  Future<void> save({required bool shown});
}

class SharedPreferencesVoiceOnboardingStore implements VoiceOnboardingStore {
  const SharedPreferencesVoiceOnboardingStore();

  static const _key = 'has_shown_voice_onboarding';

  @override
  Future<bool> load() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> save({required bool shown}) async {
    final prefs = await SharedPreferences.getInstance();
    shown ? await prefs.setBool(_key, true) : await prefs.remove(_key);
  }
}

final voiceOnboardingStoreProvider = Provider<VoiceOnboardingStore>(
  (ref) => const SharedPreferencesVoiceOnboardingStore(),
);

/// True while the post-sign-up voice step should show. Unlike
/// `onboardingProvider` (`onboarding_provider.dart`), which starts true on
/// a fresh install, this starts **false**: the step never shows just
/// because a session exists. It only turns on when the sign-up screen calls
/// [VoiceOnboardingNotifier.showIfNeverShown] right after a successful
/// sign-up, so a returning driver signing in never sees it.
final voiceOnboardingProvider =
    StateNotifierProvider<VoiceOnboardingNotifier, bool>(
      (ref) => VoiceOnboardingNotifier(
        ref.watch(voiceOnboardingStoreProvider),
        ref.watch(authRepositoryProvider).changes,
      ),
    );

class VoiceOnboardingNotifier extends StateNotifier<bool> {
  VoiceOnboardingNotifier(this._store, Stream<AuthChangeEvent> authChanges)
    : super(false) {
    // A driver who signs out before tapping Continue (the flag never
    // persisted) must not carry a dangling `true` into whoever signs in
    // next during the same app run — that would show the step on a plain
    // sign-in, which it must never do.
    _authSubscription = authChanges
        .where((event) => event == AuthChangeEvent.signedOut)
        .listen((_) => state = false);
  }

  final VoiceOnboardingStore _store;
  late final StreamSubscription<AuthChangeEvent> _authSubscription;

  /// Call right after a sign-up succeeds. Shows the step only if this
  /// device has never shown it before.
  Future<void> showIfNeverShown() async {
    bool shown;
    try {
      shown = await _store.load();
    } catch (_) {
      shown = false;
    }
    if (!shown && mounted) state = true;
  }

  /// The driver continued past the step (with or without changing the
  /// default voice): never show it again on this device.
  void complete() {
    state = false;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await _store.save(shown: true);
    } catch (_) {
      // Keep the state for this run; a later app run may show it again if
      // this failed, which is safe since the step is skippable.
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
