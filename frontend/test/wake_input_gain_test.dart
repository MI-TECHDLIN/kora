import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/wake/wake_input_gain.dart';
import 'package:voiceops/core/wake/wake_tuning.dart';

Float32List tone(double rmsDb, {double seconds = 1, double hz = 300}) {
  final n = (seconds * 16000).round();
  final amplitude = math.pow(10, rmsDb / 20) * math.sqrt2;
  return Float32List.fromList([
    for (var i = 0; i < n; i++)
      (amplitude * math.sin(2 * math.pi * hz * i / 16000)).toDouble(),
  ]);
}

double rmsDb(Float32List x, {int from = 0}) {
  var sum = 0.0;
  for (var i = from; i < x.length; i++) {
    sum += x[i] * x[i];
  }
  return 10 * math.log(sum / (x.length - from)) / math.ln10;
}

Float32List run(WakeInputGain gain, Float32List input, {int chunk = 1600}) {
  final out = <double>[];
  for (var i = 0; i < input.length; i += chunk) {
    out.addAll(
      gain.process(input.sublist(i, math.min(i + chunk, input.length))),
    );
  }
  return Float32List.fromList(out);
}

void main() {
  test('a quiet voice is lifted towards the target level', () {
    final gain = WakeInputGain(WakeTuning.high.gain);
    // -40 dBFS peak is about -43 dBFS RMS: far-field speech.
    final out = run(gain, tone(-43, seconds: 2));

    final lifted = rmsDb(out, from: 16000);
    expect(lifted, greaterThan(-30));
    expect(lifted, lessThan(-18));
  });

  test('gain never exceeds the configured maximum', () {
    final gain = WakeInputGain(WakeTuning.normal.gain);
    final out = run(gain, tone(-58, seconds: 2));

    final applied = rmsDb(out, from: 16000) - -58;
    expect(applied, lessThanOrEqualTo(WakeTuning.normal.gain.maxGainDb + 0.5));
  });

  test('loud speech is not clipped or amplified', () {
    final gain = WakeInputGain(WakeTuning.high.gain);
    final input = tone(-12, seconds: 2);
    final out = run(gain, input);

    expect(out.every((s) => s.abs() <= 1.0), isTrue);
    expect(rmsDb(out, from: 16000), lessThan(-12 + 0.5));
  });

  test('a steady noise floor is not pumped up beyond the idle gain', () {
    final random = math.Random(1);
    final noise = Float32List.fromList([
      for (var i = 0; i < 16000 * 5; i++)
        (random.nextDouble() - 0.5) * 2 * 0.002,
    ]);
    final gain = WakeInputGain(WakeTuning.high.gain);
    final out = run(gain, noise);

    final applied = rmsDb(out, from: 16000 * 3) - rmsDb(noise, from: 16000 * 3);
    expect(applied, lessThan(WakeTuning.high.gain.idleGainDb + 1));
  });

  test('chunking does not change the output', () {
    final input = tone(-40, seconds: 1);
    final a = run(WakeInputGain(WakeTuning.high.gain), input, chunk: 1600);
    final b = run(WakeInputGain(WakeTuning.high.gain), input, chunk: 1234);

    final shared = math.min(a.length, b.length);
    expect(shared, greaterThan(15000));
    for (var i = 0; i < shared; i++) {
      expect(a[i], closeTo(b[i], 1e-6));
    }
  });

  test('reset returns to the resting gain', () {
    final gain = WakeInputGain(WakeTuning.high.gain);
    run(gain, tone(-12, seconds: 1));
    expect(gain.currentGain, lessThan(2));

    gain.reset();

    expect(
      20 * math.log(gain.currentGain) / math.ln10,
      closeTo(WakeTuning.high.gain.idleGainDb, 0.001),
    );
  });
}
