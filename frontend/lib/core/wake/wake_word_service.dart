import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wake_tuning.dart';

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
    required this.tokens,
    required this.sensitivity,
    this.score,
    this.threshold,
  });

  final String id;
  final String phrase;
  final String tokens;
  final double sensitivity;

  /// Optional per-phrase sherpa overrides. Keeping the short bare-name phrase
  /// conservative avoids silently applying the broad sensitivity curve used
  /// by the safer multi-word phrases.
  final double? score;
  final double? threshold;
}

class WakeWordEngineConfig {
  const WakeWordEngineConfig({
    required this.keywords,
    required this.onDetected,
    required this.onError,
    this.tuning = WakeTuning.normal,
  });

  final List<WakeWordKeyword> keywords;
  final WakeTuning tuning;
  final ValueChanged<int> onDetected;
  final ValueChanged<Object> onError;
}

abstract interface class WakeWordEngine {
  Future<void> configure(WakeWordEngineConfig config);
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class WakeWordAssetSource {
  Future<String> loadManifest();
  Future<String> loadTokenizedKeywords();
}

class BundleWakeWordAssetSource implements WakeWordAssetSource {
  const BundleWakeWordAssetSource();

  static const manifestPath = 'assets/wake/wake_phrases.json';
  static const keywordsPath = 'assets/wake/keywords.txt';

  @override
  Future<String> loadManifest() => rootBundle.loadString(manifestPath);

  @override
  Future<String> loadTokenizedKeywords() => rootBundle.loadString(keywordsPath);
}

/// Parses sherpa's pre-tokenized keyword format into `id -> phone tokens`.
///
/// Lines may include sherpa score (`:`) and threshold (`#`) modifiers. The
/// final `@id` label is required because detections are routed by manifest id.
Map<String, String> parseTokenizedWakeKeywords(String source) {
  final result = <String, String>{};
  for (final rawLine in const LineSplitter().convert(source)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('//')) continue;
    final parts = line.split(RegExp(r'\s+'));
    final labelIndex = parts.lastIndexWhere((part) => part.startsWith('@'));
    if (labelIndex < 1 || labelIndex != parts.length - 1) {
      throw FormatException('Invalid tokenized wake keyword: $line');
    }
    final id = parts[labelIndex].substring(1).trim();
    final tokens = parts
        .take(labelIndex)
        .where((part) => !part.startsWith(':') && !part.startsWith('#'))
        .join(' ')
        .trim();
    if (id.isEmpty || tokens.isEmpty || result.containsKey(id)) {
      throw FormatException('Invalid tokenized wake keyword: $line');
    }
    result[id] = tokens;
  }
  return result;
}

/// Manifest `requires` value that gates a phrase on the "Wake on greetings"
/// Settings option.
const wakeOnGreetingsRequirement = 'wake_on_greetings';

typedef WakeWordLog = void Function(String message);

/// Coordinates manifest loading, microphone ownership and graceful fallback.
///
/// Calls to [sync] are serialized so rapid lifecycle/session changes cannot
/// leave the wake engine and voice recorder holding the microphone together.
class WakeWordService {
  WakeWordService({
    required WakeWordEngine engine,
    required WakeWordAssetSource assets,
    required WakeWordPlatform? platform,
    required Future<bool> Function() hasMicrophonePermission,
    required Future<void> Function() onWakeWord,
    ValueChanged<WakeWordStatus>? onStatusChanged,
    WakeWordLog? log,
  }) : _engine = engine,
       _assets = assets,
       _platform = platform,
       _hasMicrophonePermission = hasMicrophonePermission,
       _onWakeWord = onWakeWord,
       _onStatusChanged = onStatusChanged,
       _log = log ?? debugPrint;

  final WakeWordEngine _engine;
  final WakeWordAssetSource _assets;
  final WakeWordPlatform? _platform;
  final Future<bool> Function() _hasMicrophonePermission;
  final Future<void> Function() _onWakeWord;
  final ValueChanged<WakeWordStatus>? _onStatusChanged;
  final WakeWordLog _log;

  WakeWordStatus _status = WakeWordStatus.disabled;
  WakeWordStatus get status => _status;

  bool _enabled = true;
  bool _sessionActive = false;
  bool _foreground = true;
  WakeWordSettings _settings = const WakeWordSettings();
  WakeWordSettings? _configuredFor;
  bool _disposed = false;
  bool _wakeInProgress = false;
  Future<void> _pending = Future<void>.value();

  Future<void> sync({
    required bool enabled,
    required bool sessionActive,
    required bool foreground,
    WakeWordSettings settings = const WakeWordSettings(),
  }) {
    _settings = settings;
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

    if (_configuredFor != _settings) {
      final settings = _settings;
      try {
        // A settings change (sensitivity, greetings) rebuilds the keyword list
        // and gain, which the engine only reads while configuring. Configure
        // stops the engine first, so the microphone is released.
        final keywords = await _loadKeywords(settings);
        if (keywords.isEmpty) {
          _log('Wake word unavailable: no enabled tokenized keywords exist.');
          _setStatus(WakeWordStatus.unavailable);
          return;
        }
        if (!_shouldListen) return;
        await _engine.configure(
          WakeWordEngineConfig(
            keywords: keywords,
            onDetected: _onDetected,
            onError: (error) =>
                _log('Wake word engine reported an error: $error'),
            tuning: settings.tuning,
          ),
        );
        _configuredFor = settings;
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

  Future<List<WakeWordKeyword>> _loadKeywords(WakeWordSettings settings) async {
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
    final tokenized = parseTokenizedWakeKeywords(
      await _assets.loadTokenizedKeywords(),
    );
    final loaded = <WakeWordKeyword>[];
    for (final value in phrases) {
      if (value is! Map || value['enabled'] != true) continue;
      // Bare greetings ("hi", "hey", "hello") are only listened for when the
      // driver opted in; they are common in ordinary conversation.
      if (value['requires'] == wakeOnGreetingsRequirement &&
          !settings.wakeOnGreetings) {
        continue;
      }
      final id = value['id'];
      final phrase = value['phrase'];
      if (id is! String || phrase is! String) continue;
      final cleanId = id.trim();
      if (cleanId.isEmpty || phrase.trim().isEmpty) continue;
      final tokens = tokenized[cleanId];
      if (tokens == null) continue;
      loaded.add(
        WakeWordKeyword(
          id: cleanId,
          phrase: phrase,
          tokens: tokens,
          sensitivity: _sensitivity(
            value['sensitivity'],
            fallback: defaultSensitivity,
          ),
          score: _score(value['score']),
          threshold: _threshold(value['threshold']),
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

  static double? _score(Object? value) {
    if (value is! num) return null;
    final score = value.toDouble();
    return score > 0 && score <= 4 ? score : null;
  }

  static double? _threshold(Object? value) {
    if (value is! num) return null;
    final threshold = value.toDouble();
    return threshold > 0 && threshold <= 1 ? threshold : null;
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
