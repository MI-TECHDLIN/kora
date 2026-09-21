// AudioWorklet processor: batches microphone samples (mono, context rate) and
// posts them to the main thread, which resamples to 24 kHz and frames them.
// Loaded through audioWorklet.addModule(); runs in the audio thread.

class KoraCaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    // ~20 ms per message keeps the message rate low without adding latency.
    this.size = Math.max(128, Math.round(sampleRate * 0.02));
    this.buf = new Float32Array(this.size);
    this.fill = 0;
  }

  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (!ch) return true;
    let i = 0;
    while (i < ch.length) {
      const n = Math.min(ch.length - i, this.size - this.fill);
      this.buf.set(ch.subarray(i, i + n), this.fill);
      this.fill += n;
      i += n;
      if (this.fill === this.size) {
        const out = this.buf;
        this.port.postMessage(out, [out.buffer]);
        this.buf = new Float32Array(this.size);
        this.fill = 0;
      }
    }
    return true;
  }
}

registerProcessor("kora-capture", KoraCaptureProcessor);
