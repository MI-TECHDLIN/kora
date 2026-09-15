// just_audio marks its in-memory source API (StreamAudioSource) experimental.
// It is the only way to play bytes without a file or URL; the version is
// pinned in pubspec.yaml, so a breaking change shows up as an upgrade.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
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

/// Plays the reply as it streams in through a small jitter buffer, so network
/// bursts do not turn into audible gaps between short WAV segments.
class JustAudioPlayback implements VoicePlayback {
  // Created on first use, like the recorder: most sessions never play.
  AudioPlayer? _player;
  late final _segmenter = ReplySegmenter(_enqueue);
  Future<void> _queue = Future.value();

  /// Bumped by [stop] so segments already queued are dropped, not played.
  int _generation = 0;

  @override
  void add(Uint8List pcm) => _segmenter.add(pcm);

  @override
  Future<void> flush() {
    _segmenter.flush();
    return _queue;
  }

  @override
  Future<void> stop() async {
    _segmenter.reset();
    _generation++;
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    _segmenter.reset();
    await _player?.dispose();
  }

  void _enqueue(Uint8List pcm) {
    final segment = _WavSegment(pcm16Wav(pcm));
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

/// Buffers streamed PCM before handing it to the audio player. It starts
/// after a short pre-roll, then extends the queued audio only as playback
/// approaches its end. Samples are kept aligned to 16-bit boundaries.
@visibleForTesting
class ReplySegmenter {
  ReplySegmenter(this._emit, {Duration Function()? clock})
    : _now = clock ?? _stopwatch();

  final void Function(Uint8List pcm) _emit;
  final Duration Function() _now;
  final _pending = BytesBuilder(copy: false);
  Timer? _timer;
  Duration? _drainsAt;
  bool _stalled = false;
  bool _flushed = false;
  Duration _preroll = minPreroll;

  static const minPreroll = Duration(milliseconds: 300);
  static const maxPreroll = Duration(seconds: 1);
  static const segment = Duration(milliseconds: 800);
  static const handoverLead = Duration(milliseconds: 150);
  static const quietStart = Duration(milliseconds: 250);
  static const stallWindow = Duration(seconds: 1);
  static const _fadeIn = Duration(milliseconds: 5);

  Duration get preroll => _preroll;

  bool get _playing => _drainsAt != null && _now() < _drainsAt!;

  void add(Uint8List pcm) {
    if (pcm.isEmpty) return;
    final drainsAt = _drainsAt;
    if (drainsAt != null && !_playing) {
      if (!_flushed && !_stalled && _now() - drainsAt < stallWindow) {
        _stalled = true;
        _preroll = _clamp(_preroll + const Duration(milliseconds: 200));
      }
      _drainsAt = null;
    }
    _flushed = false;
    _pending.add(pcm);
    _schedule();
  }

  void flush() {
    _timer?.cancel();
    _emitPending();
    if (!_stalled) {
      _preroll = _clamp(_preroll - const Duration(milliseconds: 100));
    }
    _stalled = false;
    _flushed = true;
  }

  void reset() {
    _timer?.cancel();
    _pending.clear();
    _drainsAt = null;
    _stalled = false;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_playing) {
      if (_pending.length >= _bytes(_preroll)) {
        _emitPending();
      } else {
        _timer = Timer(quietStart, _emitPending);
        return;
      }
    }
    if (_pending.length >= _bytes(segment)) _emitPending();
    _armHandover();
  }

  void _armHandover() {
    final drainsAt = _drainsAt;
    if (drainsAt == null || _pending.isEmpty) return;
    final due = drainsAt - handoverLead - _now();
    if (due > Duration.zero) {
      _timer = Timer(due, _armHandover);
    } else {
      _emitPending();
    }
  }

  void _emitPending() {
    final bytes = _pending.takeBytes();
    final whole = bytes.length & ~1;
    if (whole < bytes.length) _pending.addByte(bytes.last);
    if (whole == 0) return;
    final pcm = Uint8List.sublistView(bytes, 0, whole);
    final length = Duration(microseconds: whole * 1000000 ~/ _bytesPerSecond);
    if (_playing) {
      _drainsAt = _drainsAt! + length;
    } else {
      _fade(pcm);
      _drainsAt = _now() + length;
    }
    _emit(pcm);
  }

  static void _fade(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final samples = math.min(pcm.length ~/ 2, _bytes(_fadeIn) ~/ 2);
    for (var i = 0; i < samples; i++) {
      final sample = data.getInt16(i * 2, Endian.little);
      data.setInt16(i * 2, sample * i ~/ samples, Endian.little);
    }
  }

  static const _bytesPerSecond = voiceSampleRate * 2;
  static int _bytes(Duration duration) =>
      (duration.inMicroseconds * _bytesPerSecond ~/ 1000000) & ~1;

  static Duration _clamp(Duration duration) => duration < minPreroll
      ? minPreroll
      : duration > maxPreroll
      ? maxPreroll
      : duration;

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
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
