import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/wake/wake_word_service.dart';

void main() {
  WakeWordService service({
    required FakeWakeWordEngine engine,
    required FakeWakeWordAssets assets,
    String accessKey = 'test-access-key',
    bool permission = true,
    Future<void> Function()? onWakeWord,
  }) => WakeWordService(
    engine: engine,
    assets: assets,
    platform: WakeWordPlatform.android,
    accessKey: accessKey,
    hasMicrophonePermission: () async => permission,
    onWakeWord: onWakeWord ?? () async {},
    log: (_) {},
  );

  test('loads only enabled entries whose platform files exist', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: FakeWakeWordAssets(
        manifest: manifest([
          phrase('ready', enabled: true, sensitivity: 0.7),
          phrase('disabled', enabled: false),
          phrase('missing', enabled: true),
        ]),
        bundled: {'assets/wake/android/ready.ppn'},
      ),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    expect(engine.config!.keywords, hasLength(1));
    expect(engine.config!.keywords.single.id, 'ready');
    expect(engine.config!.keywords.single.sensitivity, 0.7);
    expect(wake.status, WakeWordStatus.listening);
  });

  test('an enabled entry without a file is skipped silently', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: FakeWakeWordAssets(
        manifest: manifest([phrase('present'), phrase('not_bundled')]),
        bundled: {'assets/wake/android/present.ppn'},
      ),
    );

    await wake.sync(enabled: true, sessionActive: false, foreground: true);

    expect(engine.config!.keywords.map((keyword) => keyword.id), ['present']);
  });

  test('several enabled platform keywords start in one engine', () async {
    final engine = FakeWakeWordEngine();
    final wake = service(
      engine: engine,
      assets: FakeWakeWordAssets(
        manifest: manifest([
          phrase('hey_kora'),
          phrase('okay_kora', sensitivity: 0.65),
          phrase('kora'),
        ], defaultSensitivity: 0.4),
        bundled: {
          'assets/wake/android/hey_kora.ppn',
          'assets/wake/android/okay_kora.ppn',
          'assets/wake/android/kora.ppn',
        },
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

  test('detection stops Porcupine then starts the voice action', () async {
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

  test('missing key, permission or keyword file fails closed', () async {
    for (final setup in [
      (key: '', permission: true, files: <String>{}),
      (key: 'key', permission: false, files: <String>{}),
      (key: 'key', permission: true, files: <String>{}),
    ]) {
      final engine = FakeWakeWordEngine();
      final wake = service(
        engine: engine,
        assets: FakeWakeWordAssets(
          manifest: manifest([phrase('kora')]),
          bundled: setup.files,
        ),
        accessKey: setup.key,
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
}

Map<String, Object?> phrase(
  String id, {
  bool enabled = true,
  double? sensitivity,
}) => {
  'id': id,
  'phrase': id.replaceAll('_', ' '),
  'enabled': enabled,
  'ppn': '$id.ppn',
  'sensitivity': ?sensitivity,
};

String manifest(
  List<Map<String, Object?>> phrases, {
  double defaultSensitivity = 0.5,
}) =>
    jsonEncode({'sensitivity_default': defaultSensitivity, 'phrases': phrases});

FakeWakeWordAssets oneKeywordAssets() => FakeWakeWordAssets(
  manifest: manifest([phrase('kora')]),
  bundled: {'assets/wake/android/kora.ppn'},
);

class FakeWakeWordAssets implements WakeWordAssetSource {
  FakeWakeWordAssets({required this.manifest, this.bundled = const {}});

  final String manifest;
  final Set<String> bundled;

  @override
  Future<Set<String>> bundledAssets() async => bundled;

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
