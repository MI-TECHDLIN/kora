import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

/// The mic, as the voice socket needs it: PCM16 little-endian, mono, 24 kHz
/// (docs/contracts/interface.md §1). Tests override [voiceRecorderProvider].
abstract interface class VoiceRecorder {
  /// Asks for mic permission if needed; false when the driver refuses.
  Future<bool> ensurePermission();

  /// Starts capturing. The stream ends when [stop] is called.
  Future<Stream<Uint8List>> start();

  Future<void> stop();
  Future<void> dispose();
}

/// The contract's fixed audio format.
const voiceSampleRate = 24000;

/// ~50 ms of PCM16 mono at 24 kHz: the contract's frame size.
const voiceFrameBytes = voiceSampleRate * 2 ~/ 20;

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = RecordVoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

class RecordVoiceRecorder implements VoiceRecorder {
  // Created on first use: the plugin touches platform channels, and most
  // app sessions (and every test) never press the mic.
  AudioRecorder? _recorder;
  AudioRecorder get _mic => _recorder ??= AudioRecorder();

  @override
  Future<bool> ensurePermission() => _mic.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _mic.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: voiceSampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder?.stop();
  }

  @override
  Future<void> dispose() async {
    await _recorder?.dispose();
  }
}
