// Gapless playback scheduling maths. Pure: the caller supplies the audio
// clock (`now`, in seconds) and does the actual source.start(when).

import { WIRE_RATE } from "./pcm.js";

export class PlaybackClock {
  /**
   * @param {object} o
   * @param {number} [o.jitter]     seconds of head start when (re)priming, ~100 ms
   * @param {number} [o.maxBacklog] seconds of queued audio beyond which a chunk is dropped
   * @param {number} [o.rate]       sample rate of the incoming chunks
   */
  constructor({ jitter = 0.1, maxBacklog = 4, rate = WIRE_RATE } = {}) {
    this.jitter = jitter;
    this.maxBacklog = maxBacklog;
    this.rate = rate;
    this.nextStart = 0;
  }

  /**
   * Where a chunk of `samples` should start. After an underrun (or first
   * chunk) the clock re-primes with the jitter buffer so a bursty network
   * does not stutter; otherwise chunks butt up against each other exactly.
   * Returns null when the backlog is so long the chunk is stale.
   */
  schedule(now, samples) {
    const duration = samples / this.rate;
    let start = this.nextStart;
    if (start < now + 0.005) start = now + this.jitter;
    if (start - now > this.maxBacklog) return null;
    this.nextStart = start + duration;
    return { start, duration };
  }

  /** Seconds of audio still queued or playing. */
  queued(now) {
    return Math.max(0, this.nextStart - now);
  }

  isSpeaking(now) {
    return this.queued(now) > 0;
  }

  /** Barge-in: forget everything queued. */
  reset() {
    this.nextStart = 0;
  }
}

/** Tracks scheduled sources so barge-in can stop every one of them at once. */
export class ActiveSources {
  constructor() {
    this.items = new Set();
  }

  add(source) {
    this.items.add(source);
    const done = () => this.items.delete(source);
    // Not all fakes/browsers support addEventListener on sources; onended is universal.
    source.onended = done;
  }

  get size() {
    return this.items.size;
  }

  stopAll() {
    const all = [...this.items];
    this.items.clear();
    for (const s of all) {
      s.onended = null;
      try {
        s.stop(0);
      } catch {
        // already stopped
      }
      try {
        s.disconnect();
      } catch {
        // already disconnected
      }
    }
    return all.length;
  }
}
