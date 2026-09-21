import test from "node:test";
import assert from "node:assert/strict";
import {
  CapturePipeline, FRAME_SAMPLES, Pcm16Decoder, Resampler, WIRE_RATE,
  floatToPcm16, int16ToLeBytes, pcm16ToFloat, rms, silentFrame,
} from "../js/pcm.js";

const sine = (freq, rate, n, amp = 0.5, start = 0) =>
  Float32Array.from({ length: n }, (_, i) => amp * Math.sin((2 * Math.PI * freq * (i + start)) / rate));

/** Amplitude of a pure tone by projecting onto sin/cos at its frequency. */
function toneAmp(x, freq, rate) {
  let s = 0, c = 0;
  for (let i = 0; i < x.length; i++) {
    s += x[i] * Math.sin((2 * Math.PI * freq * i) / rate);
    c += x[i] * Math.cos((2 * Math.PI * freq * i) / rate);
  }
  return (2 * Math.hypot(s, c)) / x.length;
}

test("floatToPcm16: range, clamping and rounding", () => {
  const out = floatToPcm16(Float32Array.from([0, 1, -1, 0.5, -0.5, 2, -3]));
  assert.deepEqual([...out], [0, 32767, -32768, 16384, -16384, 32767, -32768]);
});

test("pcm16ToFloat inverts floatToPcm16 within one LSB", () => {
  const src = sine(440, 24000, 480, 0.8);
  const back = pcm16ToFloat(floatToPcm16(src));
  for (let i = 0; i < src.length; i++) assert.ok(Math.abs(back[i] - src[i]) < 1 / 16384);
});

test("int16ToLeBytes writes little-endian", () => {
  const b = new Uint8Array(int16ToLeBytes(Int16Array.from([1, -2, 0x1234])));
  assert.deepEqual([...b], [0x01, 0x00, 0xfe, 0xff, 0x34, 0x12]);
});

test("rms of a sine is amp/sqrt(2); empty is 0", () => {
  assert.ok(Math.abs(rms(sine(1000, 24000, 24000, 0.5)) - 0.5 / Math.SQRT2) < 1e-3);
  assert.equal(rms(new Float32Array(0)), 0);
});

test("Pcm16Decoder handles odd-sized network chunks", () => {
  const samples = Int16Array.from([100, -200, 300, -400, 32767, -32768]);
  const bytes = new Uint8Array(int16ToLeBytes(samples));
  const dec = new Pcm16Decoder();
  const got = [];
  // split at 1, 4 and 7 bytes: every boundary lands mid-sample at least once
  for (const [a, b] of [[0, 1], [1, 4], [4, 7], [7, 12]]) got.push(...dec.push(bytes.slice(a, b).buffer));
  assert.equal(got.length, samples.length);
  samples.forEach((v, i) => assert.equal(got[i], v / 0x8000));
});

test("Pcm16Decoder.reset drops a dangling byte (barge-in)", () => {
  const dec = new Pcm16Decoder();
  assert.equal(dec.push(new Uint8Array([7]).buffer).length, 0);
  dec.reset();
  assert.deepEqual([...dec.push(new Uint8Array([0x00, 0x40]).buffer)], [0.5]);
});

test("Resampler: same rate is a copy", () => {
  const r = new Resampler(24000, 24000);
  const x = sine(300, 24000, 100);
  assert.deepEqual([...r.push(x)], [...x]);
});

test("Resampler 48k -> 24k: length halves and a 1 kHz tone keeps its level", () => {
  const r = new Resampler(48000, 24000);
  const out = r.push(sine(1000, 48000, 48000));
  assert.ok(Math.abs(out.length - 24000) <= 1);
  const settled = out.subarray(2000);
  assert.ok(Math.abs(toneAmp(settled, 1000, 24000) - 0.5) < 0.02, "1 kHz amplitude preserved");
});

test("Resampler 48k -> 24k: a 20 kHz tone (above new Nyquist) is strongly attenuated", () => {
  const r = new Resampler(48000, 24000);
  const out = r.push(sine(20000, 48000, 48000));
  assert.ok(rms(out.subarray(2000)) < 0.02);
});

test("Resampler 44.1k -> 24k: ratio and tone frequency are right", () => {
  const r = new Resampler(44100, 24000);
  const out = r.push(sine(1000, 44100, 44100));
  assert.ok(Math.abs(out.length - 24000) <= 2);
  assert.ok(Math.abs(toneAmp(out.subarray(2000), 1000, 24000) - 0.5) < 0.03);
});

test("Resampler is block-size independent (streaming state is correct)", () => {
  const x = sine(700, 48000, 9600);
  const whole = new Resampler(48000, 24000).push(x);
  const r = new Resampler(48000, 24000);
  const parts = [];
  for (let i = 0; i < x.length; i += 128) parts.push(...r.push(x.subarray(i, i + 128)));
  assert.ok(Math.abs(parts.length - whole.length) <= 1);
  for (let i = 0; i < Math.min(parts.length, whole.length); i++) assert.ok(Math.abs(parts[i] - whole[i]) < 1e-4);
});

test("Resampler upsampling 16k -> 24k interpolates", () => {
  const out = new Resampler(16000, 24000).push(sine(500, 16000, 1600));
  assert.ok(Math.abs(out.length - 2400) <= 1);
  assert.ok(Math.abs(toneAmp(out, 500, 24000) - 0.5) < 0.03);
});

test("CapturePipeline emits exact 2400-byte frames and keeps the remainder", () => {
  assert.equal(FRAME_SAMPLES, 1200);
  const p = new CapturePipeline(48000);
  let frames = [];
  // 960-sample blocks (20 ms at 48 kHz) x 7 = 140 ms -> 2 whole 50 ms frames, remainder pending
  for (let i = 0; i < 7; i++) frames.push(...p.push(sine(440, 48000, 960, 0.4, i * 960)).frames);
  assert.equal(frames.length, 2);
  for (const f of frames) assert.equal(f.byteLength, 2400);
  frames.push(...p.push(sine(440, 48000, 960, 0.4)).frames);
  assert.equal(frames.length, 3); // 160 ms total
});

test("CapturePipeline at 24 kHz is byte-exact PCM16 LE", () => {
  const p = new CapturePipeline(WIRE_RATE);
  const x = sine(440, 24000, 1200, 0.5);
  const { frames } = p.push(x);
  assert.equal(frames.length, 1);
  assert.deepEqual(new Uint8Array(frames[0]), new Uint8Array(int16ToLeBytes(floatToPcm16(x))));
});

test("CapturePipeline level follows loudness, fast attack, slow release", () => {
  const p = new CapturePipeline(24000);
  const loud = p.push(sine(300, 24000, 480, 0.8)).level;
  const quiet = p.push(new Float32Array(480)).level;
  assert.ok(loud > 0.4);
  assert.ok(quiet < loud && quiet > 0, "decays rather than dropping to zero");
});

test("silentFrame is 2400 zero bytes", () => {
  const f = new Uint8Array(silentFrame());
  assert.equal(f.length, 2400);
  assert.ok(f.every((b) => b === 0));
});
