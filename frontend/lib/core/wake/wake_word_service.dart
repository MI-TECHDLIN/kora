import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';

enum WakeWordPlatform {
  android,
  ios;

  static WakeWordPlatform? get current => switch (defaultTargetPlatform) {
    TargetPlatform.android => WakeWordPlatform.android,
    TargetPlatform.iOS => WakeWordPlatform.ios,
    _ => null,
  };
}

enum WakeWordStatus { disabled, unavailable, paused, listening }

class WakeWordKeyword {
  const WakeWordKeyword({
    required this.id,
    required this.phrase,
    required this.assetPath,
    required this.sensitivity,
  });

  final String id;
  final String phrase;
  final String assetPath;
  final double sensitivity;
}

class WakeWordEngineConfig {
  const WakeWordEngineConfig({
    required this.accessKey,
    required this.keywords,
    required this.onDetected,
    required this.onError,
  });

  final String accessKey;
  final List<WakeWordKeyword> keywords;
  final ValueChanged<int> onDetected;
  final ValueChanged<Object> onError;
}

abstract interface class WakeWordEngine {
  Future<void> configure(WakeWordEngineConfig config);
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// The real Porcupine engine. [PorcupineManager] owns the microphone while it
/// is running, so the service always stops it before voice capture begins.
class PorcupineWakeWordEngine implements WakeWordEngine {
  PorcupineManager? _manager;
  bool _running = false;

  @override
  Future<void> configure(WakeWordEngineConfig config) async {
    await dispose();
    _manager = await PorcupineManager.fromKeywordPaths(
      config.accessKey,
      config.keywords.map((keyword) => keyword.assetPath).toList(),
      config.onDetected,
      sensitivities: config.keywords
          .map((keyword) => keyword.sensitivity)
          .toList(),
      errorCallback: config.onError,
    );
  }

  @override
  Future<void> start() async {
    if (_running) return;
    final manager = _manager;
    if (manager == null) throw StateError('Porcupine is not configured.');
    await manager.start();
    _running = true;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _manager?.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _manager?.delete();
    _manager = null;
  }
}

abstract interface class WakeWordAssetSource {
  Future<String> loadManifest();
  Future<Set<String>> bundledAssets();
}

class BundleWakeWordAssetSource implements WakeWordAssetSource {
  const BundleWakeWordAssetSource();

  static const manifestPath = 'assets/wake/wake_phrases.json';

  @override
  Future<String> loadManifest() => rootBundle.loadString(manifestPath);

  @override
  Future<Set<String>> bundledAssets() async =>
      (await AssetManifest.loadFromAssetBundle(
        rootBundle,
      )).listAssets().toSet();
}

typedef WakeWordLog = void Function(String message);

/// Coordinates manifest loading, microphone ownership and graceful fallback.
///
/// Calls to [sync] are serialized so rapid lifecycle/session changes cannot
/// leave Porcupine and the voice recorder holding the microphone together.
class WakeWordService {
  WakeWordService({
    required WakeWordEngine engine,
    required WakeWordAssetSource assets,
    required WakeWordPlatform? platform,
    required String accessKey,
    required Future<bool> Function() hasMicrophonePermission,
    required Future<void> Function() onWakeWord,
    ValueChanged<WakeWordStatus>? onStatusChanged,
    WakeWordLog? log,
  }) : _engine = engine,
       _assets = assets,
       _platform = platform,
       _accessKey = accessKey.trim(),
       _hasMicrophonePermission = hasMicrophonePermission,
       _onWakeWord = onWakeWord,
       _onStatusChanged = onStatusChanged,
       _log = log ?? debugPrint;

  final WakeWordEngine _engine;
  final WakeWordAssetSource _assets;
  final WakeWordPlatform? _platform;
  final String _accessKey;
  final Future<bool> Function() _hasMicrophonePermission;
  final Future<void> Function() _onWakeWord;
  final ValueChanged<WakeWordStatus>? _onStatusChanged;
  final WakeWordLog _log;

  WakeWordStatus _status = WakeWordStatus.disabled;
  WakeWordStatus get status => _status;

  bool _enabled = true;
  bool _sessionActive = false;
  bool _foreground = true;
  bool _configured = false;
  bool _disposed = false;
  bool _wakeInProgress = false;
  Future<void> _pending = Future<void>.value();

  Future<void> sync({
    required bool enabled,
    required bool sessionActive,
    required bool foreground,
  }) {
    _enabled = enabled;
    _sessionActive = sessionActive;
    _foreground = foreground;
    _pending = _pending.then((_) => _apply()).catchError((Object error) {
      _log('Wake word disabled after an unexpected error: $error');
      _setStatus(WakeWordStatus.unavailable);
    });
    return _pending;
  }

  bool get _shouldListen =>
      !_disposed &&
      _enabled &&
      !_sessionActive &&
      _foreground &&
      !_wakeInProgress;

  Future<void> _apply() async {
    if (_disposed) return;
    if (!_shouldListen) {
      await _engine.stop();
      _setStatus(!_enabled ? WakeWordStatus.disabled : WakeWordStatus.paused);
      return;
    }

    if (_accessKey.isEmpty) {
      _log(
        'Wake word unavailable: PORCUPINE_ACCESS_KEY was not supplied at build time.',
      );
      _setStatus(WakeWordStatus.unavailable);
      return;
    }
    if (_platform == null) {
      _log('Wake word unavailable: this platform is not supported.');
      _setStatus(WakeWordStatus.unavailable);
      return;
    }

    final permitted = await _hasMicrophonePermission();
    if (!permitted) {
      _log('Wake word unavailable: microphone permission is not granted.');
      _setStatus(WakeWordStatus.unavailable);
      return;
    }
    if (!_shouldListen) return;

    if (!_configured) {
      try {
        final keywords = await _loadKeywords(_platform);
        if (keywords.isEmpty) {
          _log(
            'Wake word unavailable: no enabled keyword files are bundled for ${_platform.name}.',
          );
          _setStatus(WakeWordStatus.unavailable);
          return;
        }
        if (!_shouldListen) return;
        await _engine.configure(
          WakeWordEngineConfig(
            accessKey: _accessKey,
            keywords: keywords,
            onDetected: _onDetected,
            onError: (error) =>
                _log('Wake word engine reported an error: $error'),
          ),
        );
        _configured = true;
      } catch (error) {
        _log('Wake word engine could not be configured: $error');
        _setStatus(WakeWordStatus.unavailable);
        return;
      }
    }
    if (!_shouldListen) return;

    try {
      await _engine.start();
      _setStatus(WakeWordStatus.listening);
    } catch (error) {
      _log('Wake word engine could not start: $error');
      _setStatus(WakeWordStatus.unavailable);
    }
  }

  Future<List<WakeWordKeyword>> _loadKeywords(WakeWordPlatform platform) async {
    final manifest = jsonDecode(await _assets.loadManifest());
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('wake phrase manifest is not an object');
    }
    final defaultSensitivity = _sensitivity(
      manifest['sensitivity_default'],
      fallback: 0.5,
    );
    final phrases = manifest['phrases'];
    if (phrases is! List) return const [];
    final bundled = await _assets.bundledAssets();
    final loaded = <WakeWordKeyword>[];
    for (final value in phrases) {
      if (value is! Map || value['enabled'] != true) continue;
      final id = value['id'];
      final phrase = value['phrase'];
      final ppn = value['ppn'];
      if (id is! String || phrase is! String || ppn is! String) continue;
      if (id.trim().isEmpty || phrase.trim().isEmpty || ppn.trim().isEmpty) {
        continue;
      }
      final path = 'assets/wake/${platform.name}/${ppn.trim()}';
      if (!bundled.contains(path)) continue;
      loaded.add(
        WakeWordKeyword(
          id: id,
          phrase: phrase,
          assetPath: path,
          sensitivity: _sensitivity(
            value['sensitivity'],
            fallback: defaultSensitivity,
          ),
        ),
      );
    }
    return loaded;
  }

  static double _sensitivity(Object? value, {required double fallback}) {
    if (value is! num) return fallback;
    final sensitivity = value.toDouble();
    return sensitivity >= 0 && sensitivity <= 1 ? sensitivity : fallback;
  }

  void _onDetected(int keywordIndex) {
    if (_status != WakeWordStatus.listening || _wakeInProgress) return;
    _wakeInProgress = true;
    unawaited(_handleDetection(keywordIndex));
  }

  Future<void> _handleDetection(int keywordIndex) async {
    try {
      await _engine.stop();
      _setStatus(WakeWordStatus.paused);
      await _onWakeWord();
    } catch (error) {
      _log('Wake word detection could not start voice: $error');
    } finally {
      _wakeInProgress = false;
      await _apply();
    }
  }

  void _setStatus(WakeWordStatus next) {
    if (_status == next) return;
    _status = next;
    _onStatusChanged?.call(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _pending;
    await _engine.dispose();
    _setStatus(WakeWordStatus.disabled);
  }
}
