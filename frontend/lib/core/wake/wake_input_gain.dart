import 'dart:math' as math;
import 'dart:typed_data';

import 'wake_tuning.dart';

/// Automatic gain for the wake-word stream only.
///
/// A phone on the dashboard hears the driver far below the level the keyword
/// model was trained on. This lifts quiet speech towards [WakeGainTuning.
/// targetRmsDb] before it reaches sherpa. The AssemblyAI stream never sees it.
///
/// The gain only ever rises on frames that stand clear of a tracked noise
/// floor, so steady engine or road noise is not pumped up. It works in
/// 10 ms frames and is stateful across [process] calls; it has no Flutter
/// dependency so it can run in the wake worker isolate.
class WakeInputGain {
  WakeInputGain(this.tuning)
    : _minActive = _linear(tuning.minActiveDb),
      _activeRatio = _linear(tuning.activeRatioDb),
      _target = _linear(tuning.targetRmsDb),
      _maxGain = _linear(tuning.maxGainDb),
      _idleGain = _linear(tuning.idleGainDb),
      _floorRise = _linear(tuning.floorRiseDbPerSecond / _framesPerSecond),
      _envDecay = math
          .pow(0.5, 1 / (_framesPerSecond * tuning.envHalfLifeSeconds))
          .toDouble(),
      _release = 1 - math.exp(-1 / (_framesPerSecond * tuning.releaseSeconds)) {
    _gain = _idleGain;
  }

  static const frameSamples = 160; // 10 ms at 16 kHz
  static const _framesPerSecond = 100.0;

  final WakeGainTuning tuning;
  final double _minActive;
  final double _activeRatio;
  final double _target;
  final double _maxGain;
  final double _idleGain;
  final double _floorRise;
  final double _envDecay;
  final double _release;

  double _gain = 1;
  double _floor = 1e-3;
  double _env = 0;
  Float32List _carry = Float32List(0);

  double get currentGain => _gain;

  /// Restores the resting gain, e.g. after the wake stream is reset.
  void reset() {
    _gain = _idleGain;
    _floor = 1e-3;
    _env = 0;
    _carry = Float32List(0);
  }

  /// Returns the gained samples for the complete 10 ms frames in [input].
  ///
  /// A trailing partial frame is held until the next call, so one call can
  /// return up to one frame fewer or more samples than it was given.
  Float32List process(Float32List input) {
    final joined = Float32List(_carry.length + input.length)
      ..setRange(0, _carry.length, _carry)
      ..setRange(_carry.length, _carry.length + input.length, input);
    final frames = joined.length ~/ frameSamples;
    final output = Float32List(frames * frameSamples);
    for (var frame = 0; frame < frames; frame++) {
      final base = frame * frameSamples;
      var energy = 0.0;
      for (var i = 0; i < frameSamples; i++) {
        final sample = joined[base + i];
        output[base + i] = sample;
        energy += sample * sample;
      }
      _applyFrame(output, base, math.sqrt(energy / frameSamples));
    }
    _carry = Float32List.sublistView(joined, frames * frameSamples);
    return output;
  }

  void _applyFrame(Float32List out, int base, double rms) {
    if (rms < _floor) {
      _floor = math.max(rms, 1e-6);
    } else {
      _floor *= _floorRise;
    }
    final active = rms > math.max(_floor * _activeRatio, _minActive);
    double target;
    if (active) {
      _env = math.max(rms, _env * _envDecay);
      target = (_target / _env).clamp(1.0, _maxGain).toDouble();
    } else {
      _env *= _envDecay;
      target = _env < _minActive ? _idleGain : _gain;
    }
    final next = target < _gain
        ? _gain + (target - _gain) * tuning.attack
        : _gain + (target - _gain) * _release;
    for (var i = 0; i < frameSamples; i++) {
      final gain = _gain + (next - _gain) * i / frameSamples;
      out[base + i] = (out[base + i] * gain).clamp(-1.0, 1.0).toDouble();
    }
    _gain = next;
  }

  static double _linear(double db) => math.pow(10, db / 20).toDouble();
}
