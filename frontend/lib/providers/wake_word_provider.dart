import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/wake_word_config.dart';
import '../core/audio/voice_recorder.dart';
import '../core/wake/wake_word_service.dart';
import 'push_to_talk_provider.dart';
import 'voice_session_provider.dart';

abstract interface class WakeWordPreferencesStore {
  Future<bool> load();
  Future<void> save({required bool enabled});
}

class SharedPreferencesWakeWordStore implements WakeWordPreferencesStore {
  const SharedPreferencesWakeWordStore();

  static const _key = 'wake_word_enabled';

  @override
  Future<bool> load() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  @override
  Future<void> save({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(_key, enabled);
  }
}

final wakeWordPreferencesStoreProvider = Provider<WakeWordPreferencesStore>(
  (ref) => const SharedPreferencesWakeWordStore(),
);

final wakeWordEnabledProvider =
    StateNotifierProvider<WakeWordPreferencesController, bool>(
      WakeWordPreferencesController.new,
    );

class WakeWordPreferencesController extends StateNotifier<bool> {
  WakeWordPreferencesController(this._ref) : super(true) {
    unawaited(_load());
  }

  final Ref _ref;
  bool _changedLocally = false;

  Future<void> _load() async {
    try {
      final saved = await _ref.read(wakeWordPreferencesStoreProvider).load();
      if (mounted && !_changedLocally) state = saved;
    } catch (_) {
      // Wake word stays on by default; runtime prerequisites still gate it.
    }
  }

  void setEnabled({required bool enabled}) {
    _changedLocally = true;
    state = enabled;
    unawaited(_save(enabled));
  }

  Future<void> _save(bool enabled) async {
    try {
      await _ref.read(wakeWordPreferencesStoreProvider).save(enabled: enabled);
    } catch (_) {
      // Keep the in-memory choice. A later change retries persistence.
    }
  }
}

final wakeWordEngineProvider = Provider<WakeWordEngine>(
  (ref) => PorcupineWakeWordEngine(),
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
      accessKey: WakeWordConfig.accessKey,
      hasMicrophonePermission: _ref.read(voiceRecorderProvider).hasPermission,
      onWakeWord: _startVoiceLikeTheButton,
      onStatusChanged: (next) {
        if (mounted) state = next;
      },
    );
    _ref.listen<bool>(wakeWordEnabledProvider, (_, _) => _sync());
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
