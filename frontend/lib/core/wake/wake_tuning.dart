import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Every wake-word tunable lives in this file: capture, input gain, decoder
/// defaults and the per-sensitivity profiles. Change a number here, never in
/// the engine, and re-run the offline check described in `frontend/README.md`.

/// The driver's "Wake sensitivity" choice in Settings.
enum WakeSensitivity {
  /// Default. Lifts quiet speech moderately; tuned for a phone within reach.
  normal('Normal'),

  /// For a phone mounted far from the driver. Lifts speech harder and loosens
  /// the detector, so false accepts are more likely too.
  high('High');

  const WakeSensitivity(this.label);

  final String label;

  static WakeSensitivity fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => WakeSensitivity.normal,
  );
}

/// Settings that change what the wake engine listens for. The service
/// reconfigures the engine whenever one of them changes.
@immutable
class WakeWordSettings {
  const WakeWordSettings({
    this.sensitivity = WakeSensitivity.normal,
    this.wakeOnGreetings = false,
  });

  final WakeSensitivity sensitivity;

  /// Also wake on a bare "hi", "hey" or "hello". Off by default: those words
  /// are common in ordinary conversation.
  final bool wakeOnGreetings;

  WakeTuning get tuning => WakeTuning.forSensitivity(sensitivity);

  @override
  bool operator ==(Object other) =>
      other is WakeWordSettings &&
      other.sensitivity == sensitivity &&
      other.wakeOnGreetings == wakeOnGreetings;

  @override
  int get hashCode => Object.hash(sensitivity, wakeOnGreetings);
}

/// Input gain for the wake stream (see `WakeInputGain`). All levels are dBFS
/// or dB of gain; times are seconds.
@immutable
class WakeGainTuning {
  const WakeGainTuning({
    required this.targetRmsDb,
    required this.maxGainDb,
    required this.idleGainDb,
    this.minActiveDb = -60,
    this.activeRatioDb = 6,
    this.floorRiseDbPerSecond = 1,
    this.envHalfLifeSeconds = 0.5,
    this.attack = 0.5,
    this.releaseSeconds = 0.4,
  });

  /// RMS level speech is lifted towards.
  final double targetRmsDb;

  /// The most gain ever applied.
  final double maxGainDb;

  /// Gain while nothing has been said recently. Sized so the first word after
  /// a quiet spell is already lifted, because the gain reacts only after it.
  final double idleGainDb;

  /// A frame quieter than this is never treated as speech.
  final double minActiveDb;

  /// A frame must exceed the tracked noise floor by this much to be speech.
  final double activeRatioDb;

  /// How fast the tracked noise floor may climb when it is being exceeded.
  final double floorRiseDbPerSecond;

  final double envHalfLifeSeconds;

  /// Fraction of a gain drop applied per 10 ms frame (loud speech is not
  /// clipped while the gain catches up).
  final double attack;

  final double releaseSeconds;
}

/// Everything that differs between "Normal" and "High".
@immutable
class WakeTuning {
  const WakeTuning({
    required this.gain,
    this.scoreDelta = 0,
    this.thresholdDelta = 0,
  });

  final WakeGainTuning gain;

  /// Added to every phrase's sherpa keyword score (clamped to 0.1..4).
  final double scoreDelta;

  /// Added to every phrase's sherpa trigger threshold (clamped to 0.05..0.95).
  /// Negative accepts more.
  final double thresholdDelta;

  static const normal = WakeTuning(
    gain: WakeGainTuning(targetRmsDb: -24, maxGainDb: 24, idleGainDb: 12),
  );

  static const high = WakeTuning(
    gain: WakeGainTuning(targetRmsDb: -24, maxGainDb: 36, idleGainDb: 24),
    scoreDelta: 1.0,
    thresholdDelta: -0.10,
  );

  static WakeTuning forSensitivity(WakeSensitivity sensitivity) =>
      switch (sensitivity) {
        WakeSensitivity.normal => normal,
        WakeSensitivity.high => high,
      };

  double adjustScore(double base) => (base + scoreDelta).clamp(0.1, 4.0);

  double adjustThreshold(double base) =>
      (base + thresholdDelta).clamp(0.05, 0.95);
}

/// Capture and decoder settings for the sherpa engine.
abstract final class WakeCaptureConfig {
  static const sampleRate = 16000;
  static const streamBufferSize = sampleRate * 2 ~/ 10; // 100 ms PCM16 mono
  static const keywordsScore = 1.0;
  static const keywordsThreshold = 0.25;
  static const numTrailingBlanks = 1;
  static const maxActivePaths = 4;

  /// Android's voice-recognition source avoids the device-selected processing
  /// used by the default source. No platform gain, echo-cancel, or
  /// noise-suppression effect is added: [WakeInputGain] provides the gain in
  /// software, on the wake stream only, so it behaves the same on every phone.
  static const androidAudioSource = AndroidAudioSource.voiceRecognition;
}
