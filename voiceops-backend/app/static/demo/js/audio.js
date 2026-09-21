// Browser audio: shared AudioContext, microphone capture, agent playback and
// the synthesized ringtone. Everything here needs Web Audio, so it is covered
// by the manual device checklist rather than unit tests; the maths lives in
// pcm.js and scheduler.js.

import { CapturePipeline, Pcm16Decoder, WIRE_RATE, silentFrame } from "./pcm.js";
import { ActiveSources, PlaybackClock } from "./scheduler.js";

const AudioCtx = window.AudioContext || window.webkitAudioContext;

export function audioSupported() {
  return Boolean(AudioCtx && navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
}

/** One AudioContext for ring, playback and capture. Create it from a user gesture. */
export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.analyser = null; // playback level, drives the orb while Kora speaks
    this.clock = new PlaybackClock({ jitter: 0.1 });
    this.sources = new ActiveSources();
    this.decoder = new Pcm16Decoder();
    this.analyserData = null;
    this.capture = null;
  }

  /** Create/resume the context. Safe to call repeatedly; call it inside taps. */
  async unlock() {
    if (!this.ctx) {
      this.ctx = new AudioCtx({ latencyHint: "interactive" });
      this.master = this.ctx.createGain();
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = 512;
      this.analyser.smoothingTimeConstant = 0.6;
      this.analyserData = new Uint8Array(this.analyser.fftSize);
      this.master.connect(this.analyser);
      this.analyser.connect(this.ctx.destination);
    }
    if (this.ctx.state !== "running") {
      try {
        await this.ctx.resume();
      } catch {
        // stays suspended; the UI shows a "tap to enable sound" hint
      }
    }
    return this.ctx.state === "running";
  }

  get running() {
    return Boolean(this.ctx) && this.ctx.state === "running";
  }

  // ── Playback ────────────────────────────────────────────────────────────

  /** Queue one binary frame of Kora's voice (PCM16 LE mono 24 kHz). */
  play(arrayBuffer) {
    if (!this.ctx) return;
    const floats = this.decoder.push(arrayBuffer);
    if (!floats.length) return;
    const slot = this.clock.schedule(this.ctx.currentTime, floats.length);
    if (!slot) return;
    const buffer = this.ctx.createBuffer(1, floats.length, WIRE_RATE);
    buffer.copyToChannel(floats, 0);
    const src = this.ctx.createBufferSource();
    src.buffer = buffer;
    src.connect(this.master);
    this.sources.add(src);
    src.start(slot.start);
  }

  /** Barge-in: silence everything queued or playing, right now. */
  flush() {
    this.sources.stopAll();
    this.clock.reset();
    this.decoder.reset();
  }

  /** 0..1 loudness of what is being played, for the orb. */
  outputLevel() {
    if (!this.analyser || !this.clock.isSpeaking(this.ctx.currentTime)) return 0;
    this.analyser.getByteTimeDomainData(this.analyserData);
    let sum = 0;
    for (let i = 0; i < this.analyserData.length; i++) {
      const v = (this.analyserData[i] - 128) / 128;
      sum += v * v;
    }
    return Math.min(1, Math.sqrt(sum / this.analyserData.length) * 3.2);
  }

  get speaking() {
    return Boolean(this.ctx) && this.clock.isSpeaking(this.ctx.currentTime);
  }

  // ── Capture ─────────────────────────────────────────────────────────────

  /**
   * Ask for the microphone. Must run inside the Answer tap. Throws a
   * {kind: "denied" | "missing" | "failed"} object on failure.
   */
  async openMic() {
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
        video: false,
      });
    } catch (e) {
      const name = e && e.name;
      if (name === "NotAllowedError" || name === "SecurityError" || name === "PermissionDeniedError") throw { kind: "denied" };
      if (name === "NotFoundError" || name === "OverconstrainedError" || name === "DevicesNotFoundError") throw { kind: "missing" };
      throw { kind: "failed" };
    }
    this.micStream = stream;
  }

  /**
   * Start streaming the mic as 50 ms PCM16 frames.
   * @param {(frame: ArrayBuffer) => void} onFrame
   * @param {(level: number) => void} onLevel
   * @param {() => boolean} isMuted
   */
  async startCapture(onFrame, onLevel, isMuted) {
    if (!this.micStream) throw { kind: "failed" };
    const pipeline = new CapturePipeline(this.ctx.sampleRate);
    const source = this.ctx.createMediaStreamSource(this.micStream);
    const handle = (block) => {
      const { frames, level } = pipeline.push(block);
      const muted = isMuted();
      onLevel(muted ? 0 : level);
      for (const f of frames) onFrame(muted ? silentFrame() : f);
    };
    let node = null;
    let usedWorklet = false;
    if (this.ctx.audioWorklet && typeof AudioWorkletNode !== "undefined") {
      try {
        await this.ctx.audioWorklet.addModule(new URL("./capture-worklet.js", import.meta.url));
        node = new AudioWorkletNode(this.ctx, "kora-capture", { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1] });
        node.port.onmessage = (e) => handle(e.data);
        usedWorklet = true;
      } catch {
        node = null; // fall through to ScriptProcessor
      }
    }
    if (!node) {
      node = this.ctx.createScriptProcessor(2048, 1, 1);
      node.onaudioprocess = (e) => handle(new Float32Array(e.inputBuffer.getChannelData(0)));
    }
    // The node must be pulled by the graph to run; a zero-gain sink keeps the mic out of the speaker.
    const sink = this.ctx.createGain();
    sink.gain.value = 0;
    source.connect(node);
    node.connect(sink);
    sink.connect(this.ctx.destination);
    this.capture = { source, node, sink, pipeline, usedWorklet };
  }

  stopCapture() {
    const c = this.capture;
    this.capture = null;
    if (c) {
      try {
        if (c.node.port) c.node.port.onmessage = null;
        c.node.onaudioprocess = null;
        c.source.disconnect();
        c.node.disconnect();
        c.sink.disconnect();
      } catch {
        // already torn down
      }
      c.pipeline.reset();
    }
    if (this.micStream) {
      for (const t of this.micStream.getTracks()) t.stop();
      this.micStream = null;
    }
  }

  /** Stop mic and agent audio. Keeps the context so the next ring still works. */
  endCall() {
    this.stopCapture();
    this.flush();
  }

  async close() {
    this.endCall();
    if (this.ctx) {
      try {
        await this.ctx.close();
      } catch {
        // ignore
      }
      this.ctx = null;
    }
  }
}

// ── Ringtone ──────────────────────────────────────────────────────────────

// A soft two-note chime pair, repeated every 2.4 s. Notes are E5 and A5 with a
// short sine + octave shimmer and an exponential decay.
const RING_NOTES = [
  { at: 0.0, freq: 659.25 },
  { at: 0.22, freq: 880.0 },
  { at: 0.5, freq: 659.25 },
  { at: 0.72, freq: 880.0 },
];
const RING_PERIOD = 2.4;

export function startRingtone(ctx) {
  let stopped = false;
  let nextCycle = ctx.currentTime + 0.05;
  const out = ctx.createGain();
  out.gain.value = 0.22;
  out.connect(ctx.destination);
  const live = new Set();

  const note = (when, freq) => {
    for (const [mult, peak] of [
      [1, 0.9],
      [2, 0.18],
    ]) {
      const osc = ctx.createOscillator();
      const g = ctx.createGain();
      osc.type = "sine";
      osc.frequency.value = freq * mult;
      g.gain.setValueAtTime(0.0001, when);
      g.gain.exponentialRampToValueAtTime(peak, when + 0.012);
      g.gain.exponentialRampToValueAtTime(0.0001, when + 0.5);
      osc.connect(g);
      g.connect(out);
      osc.start(when);
      osc.stop(when + 0.55);
      live.add(osc);
      osc.onended = () => live.delete(osc);
    }
  };

  const pump = () => {
    if (stopped) return;
    // Schedule cycles slightly ahead so a busy main thread never drops a ring.
    while (nextCycle < ctx.currentTime + 1.2) {
      for (const n of RING_NOTES) note(nextCycle + n.at, n.freq);
      nextCycle += RING_PERIOD;
    }
  };
  pump();
  const timer = setInterval(pump, 400);

  return () => {
    stopped = true;
    clearInterval(timer);
    const t = ctx.currentTime;
    out.gain.cancelScheduledValues(t);
    out.gain.setTargetAtTime(0, t, 0.03);
    for (const o of live) {
      try {
        o.stop(t + 0.15);
      } catch {
        // already stopped
      }
    }
  };
}

/** A short rising blip when the call connects, and a falling one on hang up. */
export function playCue(ctx, kind) {
  const t = ctx.currentTime + 0.01;
  const freqs = kind === "connect" ? [523.25, 783.99] : [587.33, 392.0];
  freqs.forEach((f, i) => {
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = "sine";
    osc.frequency.value = f;
    const at = t + i * 0.11;
    g.gain.setValueAtTime(0.0001, at);
    g.gain.exponentialRampToValueAtTime(0.16, at + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, at + 0.28);
    osc.connect(g);
    g.connect(ctx.destination);
    osc.start(at);
    osc.stop(at + 0.3);
  });
}
