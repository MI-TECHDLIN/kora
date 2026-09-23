import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/wake/sherpa_wake_word_engine.dart';
import 'package:voiceops/core/wake/wake_word_service.dart';

void main() {
  WakeWordService service({
    required FakeWakeWordEngine engine,
    required FakeWakeWordAssets assets,
    bool permission = true,
    Future<void> Function()? onWakeWord,
  }) => WakeWordService(
    engine: engine,
    assets: assets,
    platform: WakeWordPlatform.android,
    hasMicrophonePermission: () async => permission,
    onWakeWord: onWakeWord ?? () async {},
    log: (_) {},
  );

  test('loads only enabled entries with tokenized phrases', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: FakeWakeWordAssets(
        manifest: manifest([
          phrase('ready', enabled: true, sensitivity: 0.7),
          phrase('disabled', enabled: false),
          phrase('missing', enabled: true),
        ]),
        keywords: keywordTokens(['ready']),
      ),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    expect(engine.config!.keywords, hasLength(1));
    expect(engine.config!.keywords.single.id, 'ready');
    expect(engine.config!.keywords.single.tokens, 'R EH1 D IY0');
    expect(engine.config!.keywords.single.sensitivity, 0.7);
    expect(wake.status, WakeWordStatus.listening);
  });

  test('an enabled entry without tokens is skipped silently', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: FakeWakeWordAssets(
        manifest: manifest([phrase('present'), phrase('not_bundled')]),
        keywords: keywordTokens(['present']),
      ),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    expect(engine.config!.keywords.map((keyword) => keyword.id), ['present']);
  });

  test('several enabled keywords start in one engine', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: FakeWakeWordAssets(
        manifest: manifest([
          phrase('hey_kora'),
          phrase('okay_kora', sensitivity: 0.65),
          phrase('kora'),
        ], defaultSensitivity: 0.4),
        keywords: keywordTokens(['hey_kora', 'okay_kora', 'kora']),
      ),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    expect(engine.config!.keywords, hasLength(3));
    expect(engine.config!.keywords.map((keyword) => keyword.sensitivity), [
      0.4,
      0.65,
      0.4,
    ]);
  });

  test('an empty manifest disables wake-word detection', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: FakeWakeWordAssets(manifest: manifest([])),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    expect(engine.config, isNull);
    expect(engine.starts, 0);
    expect(wake.status, WakeWordStatus.unavailable);
  });

  test('detection stops sherpa then starts the voice action', () async {
    final engine = FakeWakeWordEngine();
    var voiceStarts = 0;
    final wake = service(
      engine: engine,
      assets: oneKeywordAssets(),
      onWakeWord: () async => voiceStarts++,
    );
    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    engine.detect(0);
    await Future<void>.delayed(Duration.zero);

    expect(engine.stops, greaterThanOrEqualTo(1));
    expect(voiceStarts, 1);
  });

  test('disabled preference never starts or responds to detection', () async {
    final engine = FakeWakeWordEngine();
    var voiceStarts = 0;
    final wake = service(
      engine: engine,
      assets: oneKeywordAssets(),
      onWakeWord: () async => voiceStarts++,
    );

    await wake.sync(enabled: false, sessionActive: false, foreground: true);

    expect(engine.config, isNull);
    expect(engine.starts, 0);
    expect(voiceStarts, 0);
    expect(wake.status, WakeWordStatus.disabled);
  });

  test(
    'active voice session stops listening and resume starts it again',
    () async {
      final engine = FakeWakeWordEngine();
      final wake = service(engine: engine, assets: oneKeywordAssets());
      await wake.sync(enabled: true, sessionActive: false, foreground: true);

      await wake.sync(enabled: true, sessionActive: true, foreground: true);
      expect(engine.stops, 1);
      expect(wake.status, WakeWordStatus.paused);

      await wake.sync(enabled: true, sessionActive: false, foreground: true);
      expect(engine.starts, 2);
      expect(wake.status, WakeWordStatus.listening);
    },
  );

  test('backgrounding stops capture and dispose releases the engine', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(engine: engine, assets: oneKeywordAssets());
    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    await wake.sync(enabled: true, sessionActive: false, foreground: false);
    expect(engine.stops, 1);
    expect(wake.status, WakeWordStatus.paused);

    await wake.dispose();
    expect(engine.disposals, 1);
    expect(wake.status, WakeWordStatus.disabled);
  });

  test('missing permission or tokenized keyword fails closed', () async {
    for (final setup in [
      (permission: false, keywords: keywordTokens(['kora'])),
      (permission: true, keywords: ''),
    ]) {
      final engine = FakeWakeWordEngine();
      final wake = service(
        engine: engine,
        assets: FakeWakeWordAssets(
          manifest: manifest([phrase('kora')]),
          keywords: setup.keywords,
        ),
        permission: setup.permission,
      );

      await wake.sync(enabled: true, sessionActive: false, foreground: true);

      expect(engine.starts, 0);
      expect(wake.status, WakeWordStatus.unavailable);
    }
  });

  test(
    'engine startup failure leaves the app-facing service available',
    () async {
      final engine = FakeWakeWordEngine()..startError = StateError('mic busy');
      final wake = service(engine: engine, assets: oneKeywordAssets());

      await wake.sync(enabled: true, sessionActive: false, foreground: true);

      expect(wake.status, WakeWordStatus.unavailable);
    },
  );

  test('parses sherpa keyword labels and strips tuning modifiers', () {
    final parsed = parseTokenizedWakeKeywords('''
// generated file
HH EY1 K AO1 R AH0 :2.0 #0.25 @hey_kora
OW2 K EY1 K AO1 R AH0 @okay_kora
''');

    expect(parsed, {
      'hey_kora': 'HH EY1 K AO1 R AH0',
      'okay_kora': 'OW2 K EY1 K AO1 R AH0',
    });
    expect(
      () => parseTokenizedWakeKeywords('HH EY1 K AO1 R AH0'),
      throwsFormatException,
    );
  });

  test('maps sensitivity to sherpa score and threshold', () {
    final low = SherpaKeywordTuning.fromSensitivity(0);
    final standard = SherpaKeywordTuning.fromSensitivity(0.5);
    final high = SherpaKeywordTuning.fromSensitivity(1);

    expect(low.score, 1.0);
    expect(low.threshold, closeTo(0.35, 0.0001));
    expect(standard.score, 2.0);
    expect(standard.threshold, closeTo(0.25, 0.0001));
    expect(high.score, 3.0);
    expect(high.threshold, closeTo(0.15, 0.0001));
  });
}

Map<String, Object?> phrase(
  String id, {
  bool enabled = true,
  double? sensitivity,
}) => {
  'id': id,
  'phrase': id.replaceAll('_', ' '),
  'enabled': enabled,
  'sensitivity': ?sensitivity,
};

String manifest(
  List<Map<String, Object?>> phrases, {
  double defaultSensitivity = 0.5,
}) =>
    jsonEncode({'sensitivity_default': defaultSensitivity, 'phrases': phrases});

FakeWakeWordAssets oneKeywordAssets() => FakeWakeWordAssets(
  manifest: manifest([phrase('kora')]),
  keywords: keywordTokens(['kora']),
);

String keywordTokens(List<String> ids) =>
    ids.map((id) => 'R EH1 D IY0 @$id').join('\n');

class FakeWakeWordAssets implements WakeWordAssetSource {
  FakeWakeWordAssets({required this.manifest, this.keywords = ''});

  final String manifest;
  final String keywords;

  @override
  Future<String> loadTokenizedKeywords() async => keywords;

  @override
  Future<String> loadManifest() async => manifest;
}

class FakeWakeWordEngine implements WakeWordEngine {
  WakeWordEngineConfig? config;
  Object? configureError;
  Object? startError;
  int starts = 0;
  int stops = 0;
  int disposals = 0;

  @override
  Future<void> configure(WakeWordEngineConfig config) async {
    if (configureError case final error?) throw error;
    this.config = config;
  }

  void detect(int index) => config?.onDetected(index);

  @override
  Future<void> start() async {
    if (startError case final error?) throw error;
    starts++;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposals++;
}
