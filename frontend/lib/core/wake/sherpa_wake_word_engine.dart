import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'wake_word_service.dart';

@immutable
class SherpaKeywordTuning {
  const SherpaKeywordTuning({required this.score, required this.threshold});

  /// Maps the existing 0..1 user-facing sensitivity to the range exercised by
  /// the Kora model spike. Higher sensitivity boosts the keyword and lowers
  /// its trigger threshold.
  factory SherpaKeywordTuning.fromSensitivity(double sensitivity) {
    final normalized = sensitivity.clamp(0.0, 1.0);
    return SherpaKeywordTuning(
      score: 1.0 + (2.0 * normalized),
      threshold: 0.35 - (0.20 * normalized),
    );
  }

  final double score;
  final double threshold;
}

/// Capture and decoder settings kept together so sensitivity changes remain
/// deliberate and reviewable.
abstract final class SherpaWakeWordDefaults {
  static const sampleRate = 16000;
  static const streamBufferSize = sampleRate * 2 ~/ 10; // 100 ms PCM16 mono
  static const keywordsScore = 1.0;
  static const keywordsThreshold = 0.25;
  static const numTrailingBlanks = 1;
  static const maxActivePaths = 4;
}

/// Android's voice-recognition source avoids the device-selected processing
/// used by the default source. Sherpa receives the same raw mono PCM shape as its
/// reference microphone example; its feature extractor handles level
/// normalization.
const wakeWordRecordConfig = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: SherpaWakeWordDefaults.sampleRate,
  numChannels: 1,
  autoGain: false,
  echoCancel: false,
  noiseSuppress: false,
  streamBufferSize: SherpaWakeWordDefaults.streamBufferSize,
  audioInterruption: AudioInterruptionMode.none,
  androidConfig: AndroidRecordConfig(
    audioSource: AndroidAudioSource.voiceRecognition,
  ),
);

@visibleForTesting
String buildSherpaKeywordBuffer(List<WakeWordKeyword> keywords) =>
    '${keywords.map((keyword) {
      final fallback = SherpaKeywordTuning.fromSensitivity(keyword.sensitivity);
      final score = keyword.score ?? fallback.score;
      final threshold = keyword.threshold ?? fallback.threshold;
      return '${keyword.tokens} '
          ':${score.toStringAsFixed(2)} '
          '#${threshold.toStringAsFixed(2)} '
          '@${keyword.id}';
    }).join('\n')}\n';

/// Foreground-only sherpa-onnx wake-word engine.
///
/// Audio capture stays on the root isolate because `record` is a Flutter
/// plugin. PCM conversion and every sherpa FFI call run in a worker isolate.
class SherpaWakeWordEngine implements WakeWordEngine {
  static const sampleRate = SherpaWakeWordDefaults.sampleRate;
  static const _modelDirectory =
      'sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20';
  static const _assetRoot = 'assets/wake/model';
  static const _encoder = 'encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx';
  static const _decoder = 'decoder-epoch-13-avg-2-chunk-16-left-64.onnx';
  static const _joiner = 'joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx';
  static const _tokens = 'tokens.txt';
  static const _modelFiles = [_encoder, _decoder, _joiner, _tokens];

  AudioRecorder? _recorder;
  AudioRecorder get _mic => _recorder ??= AudioRecorder();

  WakeWordEngineConfig? _config;
  Isolate? _worker;
  SendPort? _workerCommands;
  ReceivePort? _workerEvents;
  StreamSubscription<Object?>? _workerEventSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _workerReady;
  Completer<void>? _workerStopped;
  bool _running = false;
  bool _detectionPending = false;

  @override
  Future<void> configure(WakeWordEngineConfig config) async {
    await stop();
    await _releaseWorker();
    _config = config;

    final paths = await _copyModelAssets();
    final keywordBuffer = buildSherpaKeywordBuffer(config.keywords);

    final events = ReceivePort();
    _workerEvents = events;
    _workerReady = Completer<void>();
    _workerStopped = Completer<void>();
    _workerEventSubscription = events.listen(_handleWorkerEvent);
    _worker = await Isolate.spawn<Map<String, Object?>>(_sherpaWorkerMain, {
      'replyPort': events.sendPort,
      'encoder': paths[_encoder]!,
      'decoder': paths[_decoder]!,
      'joiner': paths[_joiner]!,
      'tokens': paths[_tokens]!,
      'keywords': keywordBuffer,
    }, debugName: 'kora-sherpa-kws');

    try {
      await _workerReady!.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      await _releaseWorker();
      rethrow;
    }
  }

  @override
  Future<void> start() async {
    if (_running) return;
    if (_workerCommands == null || _config == null) {
      throw StateError('Sherpa wake-word engine is not configured.');
    }

    _detectionPending = false;
    _workerCommands!.send(const {'type': 'reset'});
    try {
      final audio = await _mic.startStream(wakeWordRecordConfig);
      _running = true;
      _audioSubscription = audio.listen(
        _sendAudio,
        onError: (Object error) => _config?.onError(error),
      );
    } catch (_) {
      await _recorder?.stop();
      rethrow;
    }
  }

  void _sendAudio(Uint8List bytes) {
    if (!_running || bytes.isEmpty) return;
    _workerCommands?.send({
      'type': 'audio',
      'data': TransferableTypedData.fromList([bytes]),
    });
  }

  void _handleWorkerEvent(Object? event) {
    if (event is SendPort) {
      _workerCommands = event;
      return;
    }
    if (event is! Map) return;
    switch (event['type']) {
      case 'ready':
        final ready = _workerReady;
        if (ready != null && !ready.isCompleted) ready.complete();
      case 'detected':
        if (!_running || _detectionPending) return;
        final id = event['id'];
        final config = _config;
        if (id is! String || config == null) return;
        final index = config.keywords.indexWhere((keyword) => keyword.id == id);
        if (index < 0) {
          config.onError(StateError('Sherpa returned unknown keyword "$id".'));
          return;
        }
        _detectionPending = true;
        config.onDetected(index);
      case 'error':
        final error = StateError('${event['error']}');
        final ready = _workerReady;
        if (ready != null && !ready.isCompleted) {
          ready.completeError(error);
        } else {
          _config?.onError(error);
        }
      case 'stopped':
        final stopped = _workerStopped;
        if (stopped != null && !stopped.isCompleted) stopped.complete();
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    final subscription = _audioSubscription;
    _audioSubscription = null;
    try {
      // Awaiting this is the microphone handoff boundary. Voice capture must
      // not start until record has released the native audio session.
      await _recorder?.stop();
    } finally {
      await subscription?.cancel();
    }
    _workerCommands?.send(const {'type': 'reset'});
    _detectionPending = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder?.dispose();
    _recorder = null;
    await _releaseWorker();
    _config = null;
  }

  Future<Map<String, String>> _copyModelAssets() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/wake/$_modelDirectory');
    await directory.create(recursive: true);
    final paths = <String, String>{};
    for (final name in _modelFiles) {
      final data = await rootBundle.load('$_assetRoot/$name');
      final target = File('${directory.path}/$name');
      if (!await target.exists() ||
          await target.length() != data.lengthInBytes) {
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      paths[name] = target.path;
    }
    return paths;
  }

  Future<void> _releaseWorker() async {
    final worker = _worker;
    if (worker == null) return;
    _workerCommands?.send(const {'type': 'dispose'});
    try {
      await _workerStopped?.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      worker.kill(priority: Isolate.immediate);
    }
    await _workerEventSubscription?.cancel();
    _workerEvents?.close();
    _worker = null;
    _workerCommands = null;
    _workerEvents = null;
    _workerEventSubscription = null;
    _workerReady = null;
    _workerStopped = null;
  }
}

void _sherpaWorkerMain(Map<String, Object?> setup) {
  final replyPort = setup['replyPort']! as SendPort;
  final commands = ReceivePort();
  replyPort.send(commands.sendPort);
  unawaited(_runSherpaWorker(setup, commands, replyPort));
}

Future<void> _runSherpaWorker(
  Map<String, Object?> setup,
  ReceivePort commands,
  SendPort replyPort,
) async {
  sherpa.KeywordSpotter? spotter;
  sherpa.OnlineStream? stream;
  int? trailingByte;
  try {
    sherpa.initBindings();
    final keywords = setup['keywords']! as String;
    spotter = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: setup['encoder']! as String,
            decoder: setup['decoder']! as String,
            joiner: setup['joiner']! as String,
          ),
          tokens: setup['tokens']! as String,
          numThreads: 1,
          provider: 'cpu',
          debug: false,
        ),
        keywordsBuf: keywords,
        keywordsBufSize: utf8.encode(keywords).length,
        maxActivePaths: SherpaWakeWordDefaults.maxActivePaths,
        numTrailingBlanks: SherpaWakeWordDefaults.numTrailingBlanks,
        keywordsScore: SherpaWakeWordDefaults.keywordsScore,
        keywordsThreshold: SherpaWakeWordDefaults.keywordsThreshold,
      ),
    );
    stream = spotter.createStream();
    replyPort.send(const {'type': 'ready'});

    await for (final command in commands) {
      if (command is! Map) continue;
      final type = command['type'];
      if (type == 'dispose') break;
      if (type == 'reset') {
        spotter.reset(stream);
        trailingByte = null;
        continue;
      }
      if (type != 'audio' || command['data'] is! TransferableTypedData) {
        continue;
      }

      final bytes = (command['data']! as TransferableTypedData)
          .materialize()
          .asUint8List();
      final converted = convertWakePcm16leToFloat32(bytes, trailingByte);
      trailingByte = converted.trailingByte;
      if (converted.samples.isEmpty) continue;
      stream.acceptWaveform(
        samples: converted.samples,
        sampleRate: SherpaWakeWordEngine.sampleRate,
      );
      while (spotter.isReady(stream)) {
        spotter.decode(stream);
        final result = spotter.getResult(stream);
        if (result.keyword.isEmpty) continue;
        // Reset immediately so a hit never leaks decoder state into the next
        // listening session, even while the root isolate releases the mic.
        spotter.reset(stream);
        trailingByte = null;
        replyPort.send({'type': 'detected', 'id': result.keyword});
        break;
      }
    }
  } catch (error, stackTrace) {
    replyPort.send({'type': 'error', 'error': '$error\n$stackTrace'});
  } finally {
    stream?.free();
    spotter?.free();
    commands.close();
    replyPort.send(const {'type': 'stopped'});
  }
}

@visibleForTesting
({Float32List samples, int? trailingByte}) convertWakePcm16leToFloat32(
  Uint8List chunk,
  int? priorTrailingByte,
) {
  var bytes = chunk;
  if (priorTrailingByte != null) {
    final joined = Uint8List(chunk.length + 1)..[0] = priorTrailingByte;
    joined.setRange(1, joined.length, chunk);
    bytes = joined;
  }
  final sampleCount = bytes.length ~/ 2;
  final samples = Float32List(sampleCount);
  final values = ByteData.sublistView(bytes, 0, sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    samples[index] = values.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return (
    samples: samples,
    trailingByte: bytes.length.isOdd ? bytes.last : null,
  );
}
