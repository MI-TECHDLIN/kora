import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/voice_recorder.dart';
import '../core/wake/sherpa_wake_word_engine.dart';
import '../core/wake/wake_tuning.dart';
import '../core/wake/wake_word_service.dart';
import 'push_to_talk_provider.dart';
import 'voice_session_provider.dart';

abstract interface class WakeWordPreferencesStore {
  Future<bool> load();
  Future<void> save({required bool enabled});
  Future<WakeSensitivity> loadSensitivity();
  Future<void> saveSensitivity(WakeSensitivity sensitivity);
  Future<bool> loadGreetings();
  Future<void> saveGreetings({required bool enabled});
}

class SharedPreferencesWakeWordStore implements WakeWordPreferencesStore {
  const SharedPreferencesWakeWordStore();

  static const _key = 'wake_word_enabled';
  static const _sensitivityKey = 'wake_word_sensitivity';
  static const _greetingsKey = 'wake_word_greetings';

  @override
  Future<bool> load() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  @override
  Future<void> save({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(_key, enabled);
  }

  @override
  Future<WakeSensitivity> loadSensitivity() async => WakeSensitivity.fromName(
    (await SharedPreferences.getInstance()).getString(_sensitivityKey),
  );

  @override
  Future<void> saveSensitivity(WakeSensitivity sensitivity) async {
    await (await SharedPreferences.getInstance()).setString(
      _sensitivityKey,
      sensitivity.name,
    );
  }

  @override
  Future<bool> loadGreetings() async =>
      (await SharedPreferences.getInstance()).getBool(_greetingsKey) ?? false;

  @override
  Future<void> saveGreetings({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(
      _greetingsKey,
      enabled,
    );
  }
}

final wakeWordPreferencesStoreProvider = Provider<WakeWordPreferencesStore>(
  (ref) => const SharedPreferencesWakeWordStore(),
);

/// One persisted Settings choice. It shows the default at once, swaps in the
/// saved value when it loads (unless the driver already changed it), and keeps
/// the in-memory choice if saving fails.
abstract class _PersistedWakePreference<T> extends StateNotifier<T> {
  _PersistedWakePreference(this._ref, super.initial) {
    unawaited(_restore());
  }

  final Ref _ref;
  bool _changedLocally = false;

  WakeWordPreferencesStore get store =>
      _ref.read(wakeWordPreferencesStoreProvider);

  Future<T> load();
  Future<void> persist(T value);

  Future<void> _restore() async {
    try {
      final saved = await load();
      if (mounted && !_changedLocally) state = saved;
    } catch (_) {
      // The default stays; runtime prerequisites still gate wake listening.
    }
  }

  void _set(T value) {
    _changedLocally = true;
    state = value;
    unawaited(_save(value));
  }

  Future<void> _save(T value) async {
    try {
      await persist(value);
    } catch (_) {
      // Keep the in-memory choice. A later change retries persistence.
    }
  }
}

final wakeWordEnabledProvider =
    StateNotifierProvider<WakeWordPreferencesController, bool>(
      WakeWordPreferencesController.new,
    );

class WakeWordPreferencesController extends _PersistedWakePreference<bool> {
  WakeWordPreferencesController(Ref ref) : super(ref, true);

  @override
  Future<bool> load() => store.load();

  @override
  Future<void> persist(bool value) => store.save(enabled: value);

  void setEnabled({required bool enabled}) => _set(enabled);
}

/// "Wake sensitivity" in Settings. Normal is the default; High raises the
/// input gain and loosens the detector for a phone mounted far from the driver.
final wakeSensitivityProvider =
    StateNotifierProvider<WakeSensitivityController, WakeSensitivity>(
      WakeSensitivityController.new,
    );

class WakeSensitivityController
    extends _PersistedWakePreference<WakeSensitivity> {
  WakeSensitivityController(Ref ref) : super(ref, WakeSensitivity.normal);

  @override
  Future<WakeSensitivity> load() => store.loadSensitivity();

  @override
  Future<void> persist(WakeSensitivity value) => store.saveSensitivity(value);

  void setSensitivity(WakeSensitivity sensitivity) => _set(sensitivity);
}

/// "Wake on greetings" in Settings, off by default: a bare "hi", "hey" or
/// "hello" is easily said in ordinary conversation.
final wakeOnGreetingsProvider =
    StateNotifierProvider<WakeOnGreetingsController, bool>(
      WakeOnGreetingsController.new,
    );

class WakeOnGreetingsController extends _PersistedWakePreference<bool> {
  WakeOnGreetingsController(Ref ref) : super(ref, false);

  @override
  Future<bool> load() => store.loadGreetings();

  @override
  Future<void> persist(bool value) => store.saveGreetings(enabled: value);

  void setEnabled({required bool enabled}) => _set(enabled);
}

final wakeWordEngineProvider = Provider<WakeWordEngine>(
  (ref) => SherpaWakeWordEngine(),
);

final wakeWordAssetSourceProvider = Provider<WakeWordAssetSource>(
  (ref) => const BundleWakeWordAssetSource(),
);

final wakeWordPlatformProvider = Provider<WakeWordPlatform?>(
  (ref) => WakeWordPlatform.current,
);

final wakeWordControllerProvider =
    StateNotifierProvider.autoDispose<WakeWordController, WakeWordStatus>(
      WakeWordController.new,
    );

class WakeWordController extends StateNotifier<WakeWordStatus> {
  WakeWordController(this._ref) : super(WakeWordStatus.disabled) {
    _service = WakeWordService(
      engine: _ref.read(wakeWordEngineProvider),
      assets: _ref.read(wakeWordAssetSourceProvider),
      platform: _ref.read(wakeWordPlatformProvider),
      hasMicrophonePermission: _ref.read(voiceRecorderProvider).hasPermission,
      onWakeWord: _startVoiceLikeTheButton,
      onStatusChanged: (next) {
        if (mounted) state = next;
      },
    );
    _ref.listen<bool>(wakeWordEnabledProvider, (_, _) => _sync());
    _ref.listen<WakeSensitivity>(wakeSensitivityProvider, (_, _) => _sync());
    _ref.listen<bool>(wakeOnGreetingsProvider, (_, _) => _sync());
    _ref.listen<PushToTalkState>(pushToTalkProvider, (_, _) => _sync());
    _ref.listen<bool>(micLiveProvider, (_, _) => _sync());
    unawaited(_sync());
  }

  final Ref _ref;
  late final WakeWordService _service;
  bool _foreground = true;

  Future<void> _startVoiceLikeTheButton() async {
    if (_ref.read(pushToTalkProvider) != PushToTalkState.idle) return;
    await _ref.read(voiceSessionProvider.notifier).onPushToTalk();
  }

  Future<void> _sync() => _service.sync(
    enabled: _ref.read(wakeWordEnabledProvider),
    sessionActive:
        _ref.read(micLiveProvider) ||
        _ref.read(pushToTalkProvider) != PushToTalkState.idle,
    foreground: _foreground,
    settings: WakeWordSettings(
      sensitivity: _ref.read(wakeSensitivityProvider),
      wakeOnGreetings: _ref.read(wakeOnGreetingsProvider),
    ),
  );

  void setForeground({required bool foreground}) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    unawaited(_sync());
  }

  @override
  void dispose() {
    unawaited(_service.dispose());
    super.dispose();
  }
}
