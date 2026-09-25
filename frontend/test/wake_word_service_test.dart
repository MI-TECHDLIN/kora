import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/wake/sherpa_wake_word_engine.dart';
import 'package:voiceops/core/wake/wake_tuning.dart';
import 'package:voiceops/core/wake/wake_word_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WakeWordService service({
    required FakeWakeWordEngine engine,
    required WakeWordAssetSource assets,
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

  test('bundled manifest enables bare Kora with conservative tuning', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: const BundleWakeWordAssetSource(),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    final keyword = engine.config!.keywords.singleWhere(
      (entry) => entry.id == 'kora',
    );
    expect(keyword.phrase, 'Kora');
    expect(keyword.score, 1.0);
    expect(keyword.threshold, 0.30);
  });

  test(
    'bundled manifest wakes on Kora and Cora forms, not bare greetings',
    () async {
      final engine = FakeWakeWordEngine();
      final wake = service(
        engine: engine,
        assets: const BundleWakeWordAssetSource(),
      );

      await wake.sync(enabled: true, sessionActive: false, foreground: true);

      final phrases = engine.config!.keywords.map((k) => k.phrase).toList();
      expect(
        phrases,
        containsAll([
          'Kora',
          'Hey Kora',
          'Okay Kora',
          'Hi Kora',
          'Hello Kora',
          'Cora',
          'Hey Cora',
          'Hi Cora',
          'Okay Cora',
        ]),
      );
      for (final bare in ['Hi', 'Hey', 'Hello']) {
        expect(phrases, isNot(contains(bare)));
      }
      final ids = engine.config!.keywords.map((k) => k.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    },
  );

  test('wake on greetings adds the bare greetings and reconfigures', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: const BundleWakeWordAssetSource(),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);
    expect(engine.configures, 1);

    await wake.sync(
      enabled: true,
      sessionActive: false,
      foreground: true,
      settings: const WakeWordSettings(wakeOnGreetings: true),
    );

    expect(engine.configures, 2);
    final phrases = engine.config!.keywords.map((k) => k.phrase).toList();
    expect(phrases, containsAll(['Hi', 'Hey', 'Hello', 'Kora']));

    // An unchanged setting must not reload the model.
    await wake.sync(
      enabled: true,
      sessionActive: false,
      foreground: true,
      settings: const WakeWordSettings(wakeOnGreetings: true),
    );
    expect(engine.configures, 2);
  });

  test('sensitivity change reconfigures the engine with its tuning', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(engine: engine, assets: oneKeywordAssets());

    await wake.sync(enabled: true, sessionActive: false, foreground: true);
    expect(engine.config!.tuning, WakeTuning.normal);

    await wake.sync(
      enabled: true,
      sessionActive: false,
      foreground: true,
      settings: const WakeWordSettings(sensitivity: WakeSensitivity.high),
    );

    expect(engine.configures, 2);
    expect(engine.config!.tuning, WakeTuning.high);
    expect(wake.status, WakeWordStatus.listening);
  });

  test('bundled keywords tokenise Cora exactly like Kora', () {
    final tokens = parseTokenizedWakeKeywords(
      File('assets/wake/keywords.txt').readAsStringSync(),
    );

    expect(tokens['cora'], tokens['kora']);
    expect(tokens['hey_cora'], tokens['hey_kora']);
    expect(tokens['hi_cora'], tokens['hi_kora']);
    expect(tokens['okay_cora'], tokens['okay_kora']);
    expect(tokens['hello_cora'], tokens['hello_kora']);
    expect(tokens['greeting_hi'], 'HH AY1');
    expect(tokens['greeting_hey'], 'HH EY1');
    expect(tokens['greeting_hello'], 'HH AH0 L OW1');
  });

  test('every enabled manifest phrase has generated tokens', () {
    final manifest =
        jsonDecode(File('assets/wake/wake_phrases.json').readAsStringSync())
            as Map<String, dynamic>;
    final tokens = parseTokenizedWakeKeywords(
      File('assets/wake/keywords.txt').readAsStringSync(),
    );
    final enabled = [
      for (final p in manifest['phrases'] as List)
        if ((p as Map)['enabled'] == true) p['id'] as String,
    ];

    expect(enabled.toSet(), hasLength(enabled.length));
    expect(tokens.keys, containsAll(enabled));
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

  test('keyword buffer sends one line per token sequence', () {
    final buffer = buildSherpaKeywordBuffer(const [
      WakeWordKeyword(
        id: 'kora',
        phrase: 'Kora',
        tokens: 'K AO1 R AH0',
        sensitivity: 0.5,
        score: 1.0,
        threshold: 0.30,
      ),
      WakeWordKeyword(
        id: 'cora',
        phrase: 'Cora',
        tokens: 'K AO1 R AH0',
        sensitivity: 0.5,
      ),
      WakeWordKeyword(
        id: 'hey_kora',
        phrase: 'Hey Kora',
        tokens: 'HH EY1 K AO1 R AH0',
        sensitivity: 0.5,
      ),
    ]);

    expect(
      buffer,
      'K AO1 R AH0 :1.00 #0.30 @kora\n'
      'HH EY1 K AO1 R AH0 :2.00 #0.25 @hey_kora\n',
    );
  });

  test('High shifts every phrase towards accepting more', () {
    const keywords = [
      WakeWordKeyword(
        id: 'kora',
        phrase: 'Kora',
        tokens: 'K AO1 R AH0',
        sensitivity: 0.5,
        score: 1.0,
        threshold: 0.30,
      ),
    ];
    final normal = buildSherpaKeywordBuffer(keywords);
    final high = buildSherpaKeywordBuffer(keywords, tuning: WakeTuning.high);

    expect(normal, contains(':1.00 #0.30'));
    expect(
      high,
      contains(
        ':${WakeTuning.high.adjustScore(1.0).toStringAsFixed(2)} '
        '#${WakeTuning.high.adjustThreshold(0.30).toStringAsFixed(2)}',
      ),
    );
    expect(WakeTuning.high.adjustScore(1.0), greaterThan(1.0));
    expect(WakeTuning.high.adjustThreshold(0.30), lessThan(0.30));
    expect(
      WakeTuning.high.gain.idleGainDb,
      greaterThan(WakeTuning.normal.gain.idleGainDb),
    );
    expect(
      WakeTuning.high.gain.maxGainDb,
      greaterThan(WakeTuning.normal.gain.maxGainDb),
    );
  });

  test('tuning clamps to sherpa-safe ranges', () {
    expect(WakeTuning.high.adjustScore(4), 4.0);
    expect(
      const WakeTuning(
        gain: WakeGainTuning(targetRmsDb: -24, maxGainDb: 24, idleGainDb: 12),
        thresholdDelta: -1,
      ).adjustThreshold(0.2),
      0.05,
    );
  });

  test('sensitivity names round-trip and unknown falls back to Normal', () {
    for (final value in WakeSensitivity.values) {
      expect(WakeSensitivity.fromName(value.name), value);
    }
    expect(WakeSensitivity.fromName(null), WakeSensitivity.normal);
    expect(WakeSensitivity.fromName('loud'), WakeSensitivity.normal);
    expect(const WakeWordSettings().wakeOnGreetings, isFalse);
    expect(const WakeWordSettings().sensitivity, WakeSensitivity.normal);
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
  double? score,
  double? threshold,
}) => {
  'id': id,
  'phrase': id.replaceAll('_', ' '),
  'enabled': enabled,
  'sensitivity': ?sensitivity,
  'score': ?score,
  'threshold': ?threshold,
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
  int configures = 0;
  int stops = 0;
  int disposals = 0;

  @override
  Future<void> configure(WakeWordEngineConfig config) async {
    if (configureError case final error?) throw error;
    this.config = config;
    configures++;
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
