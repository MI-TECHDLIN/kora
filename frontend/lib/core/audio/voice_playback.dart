// just_audio marks its in-memory source API (StreamAudioSource) experimental.
// It is the only way to play bytes without a file or URL; the version is
// pinned in pubspec.yaml, so a breaking change shows up as an upgrade.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'voice_recorder.dart' show voiceSampleRate;

/// The co-rider's voice: PCM16 mono 24 kHz chunks off the voice socket
/// (docs/contracts/interface.md §1). Tests override [voicePlaybackProvider].
abstract interface class VoicePlayback {
  /// Queues one chunk of the current reply.
  void add(Uint8List pcm);

  /// The reply's audio is complete: play whatever is still buffered.
  Future<void> flush();

  /// Stops at once and drops anything queued (barge-in, session end).
  Future<void> stop();

  Future<void> dispose();
}

final voicePlaybackProvider = Provider<VoicePlayback>((ref) {
  final playback = JustAudioPlayback();
  ref.onDispose(playback.dispose);
  return playback;
});

/// Plays the reply as it streams in: chunks are grouped into short WAV
/// segments appended to a just_audio playlist, so playback starts after the
/// first segment instead of after the whole reply.
class JustAudioPlayback implements VoicePlayback {
  // Created on first use, like the recorder: most sessions never play.
  AudioPlayer? _player;
  final _pending = BytesBuilder(copy: false);
  Future<void> _queue = Future.value();

  /// Bumped by [stop] so segments already queued are dropped, not played.
  int _generation = 0;

  /// Plays a partial segment once the stream pauses. A tool turn's first
  /// reply gets no `reply_done` (the agent speaks again after the tools),
  /// so without this its last words would wait for the next reply.
  Timer? _quiet;

  /// ~300 ms per segment: short enough to start quickly, long enough that
  /// segment joins stay rare.
  static const _segmentBytes = voiceSampleRate * 2 * 3 ~/ 10;
  static const _quietGap = Duration(milliseconds: 250);

  @override
  void add(Uint8List pcm) {
    _pending.add(pcm);
    if (_pending.length >= _segmentBytes) _enqueue();
    _quiet?.cancel();
    _quiet = Timer(_quietGap, () {
      if (_pending.isNotEmpty) _enqueue();
    });
  }

  @override
  Future<void> flush() {
    _quiet?.cancel();
    if (_pending.isNotEmpty) _enqueue();
    return _queue;
  }

  @override
  Future<void> stop() async {
    _quiet?.cancel();
    _pending.clear();
    _generation++;
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    _quiet?.cancel();
    _pending.clear();
    await _player?.dispose();
  }

  void _enqueue() {
    final segment = _WavSegment(pcm16Wav(_pending.takeBytes()));
    final generation = _generation;
    _queue = _queue
        .then((_) => generation == _generation ? _append(segment) : null)
        .catchError((Object e) => debugPrint('Voice playback failed: $e'));
  }

  Future<void> _append(_WavSegment segment) async {
    final player = _player ??= AudioPlayer();
    final state = player.processingState;
    if (state == ProcessingState.idle || state == ProcessingState.completed) {
      // Nothing playing (a new reply, or the stream ran dry): start over.
      await player.setAudioSources([segment]);
      // play() completes only when playback pauses or stops; don't wait.
      unawaited(player.play());
    } else {
      await player.addAudioSource(segment);
    }
  }
}

/// One in-memory WAV segment served to the player.
class _WavSegment extends StreamAudioSource {
  _WavSegment(this._bytes);
  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(Uint8List.sublistView(_bytes, from, to)),
      contentType: 'audio/wav',
    );
  }
}

/// Wraps raw PCM16 mono 24 kHz samples in a 44-byte RIFF/WAVE header.
@visibleForTesting
Uint8List pcm16Wav(Uint8List pcm) {
  const channels = 1;
  const bitsPerSample = 16;
  const blockAlign = channels * bitsPerSample ~/ 8;
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // "RIFF"
    ..setUint32(4, 36 + pcm.length, Endian.little)
    ..setUint32(8, 0x57415645) // "WAVE"
    ..setUint32(12, 0x666d7420) // "fmt "
    ..setUint32(16, 16, Endian.little) // fmt chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, voiceSampleRate, Endian.little)
    ..setUint32(28, voiceSampleRate * blockAlign, Endian.little)
    ..setUint16(32, blockAlign, Endian.little)
    ..setUint16(34, bitsPerSample, Endian.little)
    ..setUint32(36, 0x64617461) // "data"
    ..setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}
