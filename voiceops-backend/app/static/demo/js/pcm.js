// Pure PCM helpers for the wire format: PCM16 little-endian, mono, 24 kHz.
// No DOM or Web Audio here, so all of it runs under `node --test`.

export const WIRE_RATE = 24000;
export const FRAME_MS = 50;
export const FRAME_SAMPLES = (WIRE_RATE * FRAME_MS) / 1000; // 1200 samples = 2400 bytes

/** Float [-1, 1] -> Int16, clamped, rounded to nearest. */
export function floatToPcm16(input) {
  const out = new Int16Array(input.length);
  for (let i = 0; i < input.length; i++) {
    const s = input[i];
    const c = s > 1 ? 1 : s < -1 ? -1 : s;
    out[i] = Math.round(c < 0 ? c * 0x8000 : c * 0x7fff);
  }
  return out;
}

/** Int16 -> Float32 in [-1, 1). */
export function pcm16ToFloat(input) {
  const out = new Float32Array(input.length);
  for (let i = 0; i < input.length; i++) out[i] = input[i] / 0x8000;
  return out;
}

/** Int16Array -> little-endian ArrayBuffer, independent of host endianness. */
export function int16ToLeBytes(samples) {
  const buf = new ArrayBuffer(samples.length * 2);
  const view = new DataView(buf);
  for (let i = 0; i < samples.length; i++) view.setInt16(i * 2, samples[i], true);
  return buf;
}

/** Root-mean-square level of float samples, 0..1. */
export function rms(samples) {
  if (!samples.length) return 0;
  let sum = 0;
  for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
  return Math.sqrt(sum / samples.length);
}

/**
 * Decodes a stream of little-endian PCM16 byte chunks into floats. Network
 * chunks may split a sample across two frames, so a dangling byte is carried
 * over to the next call.
 */
export class Pcm16Decoder {
  constructor() {
    this.carry = null;
  }

  push(arrayBuffer) {
    let bytes = new Uint8Array(arrayBuffer);
    if (this.carry !== null) {
      const merged = new Uint8Array(bytes.length + 1);
      merged[0] = this.carry;
      merged.set(bytes, 1);
      bytes = merged;
      this.carry = null;
    }
    const whole = bytes.length >> 1;
    if (bytes.length & 1) this.carry = bytes[bytes.length - 1];
    const out = new Float32Array(whole);
    const view = new DataView(bytes.buffer, bytes.byteOffset, whole * 2);
    for (let i = 0; i < whole; i++) out[i] = view.getInt16(i * 2, true) / 0x8000;
    return out;
  }

  reset() {
    this.carry = null;
  }
}

/** One second-order low-pass section (RBJ cookbook), direct form I. */
class Biquad {
  constructor(sampleRate, cutoff, q) {
    const w0 = (2 * Math.PI * cutoff) / sampleRate;
    const alpha = Math.sin(w0) / (2 * q);
    const cosw = Math.cos(w0);
    const a0 = 1 + alpha;
    this.b0 = (1 - cosw) / 2 / a0;
    this.b1 = (1 - cosw) / a0;
    this.b2 = this.b0;
    this.a1 = (-2 * cosw) / a0;
    this.a2 = (1 - alpha) / a0;
    this.x1 = this.x2 = this.y1 = this.y2 = 0;
  }

  process(x) {
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1;
    this.x1 = x;
    this.y2 = this.y1;
    this.y1 = y;
    return y;
  }
}

/**
 * Streaming mono resampler. Linear interpolation, preceded by a 4th-order
 * Butterworth low-pass when downsampling so speech above the new Nyquist
 * does not alias. State is kept across push() calls, so feeding it 128- or
 * 960-sample blocks gives the same result as one long buffer.
 */
export class Resampler {
  constructor(fromRate, toRate) {
    this.fromRate = fromRate;
    this.toRate = toRate;
    this.step = fromRate / toRate; // input samples per output sample
    this.pos = 0; // fractional read position into the (virtual) stream
    this.prev = 0; // last input sample of the previous block
    this.filters = [];
    if (toRate < fromRate) {
      const cutoff = toRate * 0.45;
      this.filters = [new Biquad(fromRate, cutoff, 0.5412), new Biquad(fromRate, cutoff, 1.3066)];
    }
  }

  get passthrough() {
    return this.fromRate === this.toRate;
  }

  push(input) {
    if (this.passthrough) return Float32Array.from(input);
    let src = input;
    if (this.filters.length) {
      src = new Float32Array(input.length);
      for (let i = 0; i < input.length; i++) {
        let v = input[i];
        for (const f of this.filters) v = f.process(v);
        src[i] = v;
      }
    }
    // Virtual stream: index 0 is the carried sample, 1..n the new block.
    const n = src.length;
    const out = [];
    let pos = this.pos;
    while (pos < n) {
      const i0 = Math.floor(pos);
      const frac = pos - i0;
      const a = i0 === 0 ? this.prev : src[i0 - 1];
      const b = src[i0];
      out.push(a + (b - a) * frac);
      pos += this.step;
    }
    this.pos = pos - n;
    if (n) this.prev = src[n - 1];
    return Float32Array.from(out);
  }

  reset() {
    this.pos = 0;
    this.prev = 0;
    for (const f of this.filters) f.x1 = f.x2 = f.y1 = f.y2 = 0;
  }
}

/**
 * Microphone path: raw context-rate float blocks in, fixed 50 ms PCM16 wire
 * frames (2400 bytes) out, plus a smoothed 0..1 level for the mic meter.
 */
export class CapturePipeline {
  constructor(inputRate, { frameSamples = FRAME_SAMPLES } = {}) {
    this.resampler = new Resampler(inputRate, WIRE_RATE);
    this.frameSamples = frameSamples;
    this.pending = new Float32Array(0);
    this.level = 0;
  }

  /** @returns {{frames: ArrayBuffer[], level: number}} */
  push(block) {
    const resampled = this.resampler.push(block);
    const instant = rms(block);
    this.level = instant > this.level ? instant : this.level * 0.85 + instant * 0.15;
    let buf = resampled;
    if (this.pending.length) {
      buf = new Float32Array(this.pending.length + resampled.length);
      buf.set(this.pending, 0);
      buf.set(resampled, this.pending.length);
    }
    const frames = [];
    let offset = 0;
    while (buf.length - offset >= this.frameSamples) {
      frames.push(int16ToLeBytes(floatToPcm16(buf.subarray(offset, offset + this.frameSamples))));
      offset += this.frameSamples;
    }
    this.pending = buf.slice(offset);
    return { frames, level: this.level };
  }

  reset() {
    this.resampler.reset();
    this.pending = new Float32Array(0);
    this.level = 0;
  }
}

/** A frame of digital silence, used to keep the stream cadence while muted. */
export function silentFrame(frameSamples = FRAME_SAMPLES) {
  return new ArrayBuffer(frameSamples * 2);
}
