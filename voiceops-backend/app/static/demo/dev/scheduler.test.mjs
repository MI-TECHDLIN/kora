import test from "node:test";
import assert from "node:assert/strict";
import { ActiveSources, PlaybackClock } from "../js/scheduler.js";

const CHUNK = 1200; // 50 ms at 24 kHz

test("first chunk starts after the jitter buffer", () => {
  const c = new PlaybackClock({ jitter: 0.1 });
  const s = c.schedule(10, CHUNK);
  assert.ok(Math.abs(s.start - 10.1) < 1e-9);
  assert.ok(Math.abs(s.duration - 0.05) < 1e-9);
});

test("consecutive chunks are gapless: each starts exactly where the last ended", () => {
  const c = new PlaybackClock({ jitter: 0.1 });
  let prevEnd = null;
  for (let i = 0; i < 20; i++) {
    const s = c.schedule(10 + i * 0.05, CHUNK); // network delivers in real time
    if (prevEnd !== null) assert.ok(Math.abs(s.start - prevEnd) < 1e-9);
    prevEnd = s.start + s.duration;
  }
});

test("a bursty network does not shorten or reorder the queue", () => {
  const c = new PlaybackClock({ jitter: 0.1 });
  const a = c.schedule(5, CHUNK);
  const b = c.schedule(5.001, CHUNK * 4);
  assert.ok(Math.abs(b.start - (a.start + a.duration)) < 1e-9);
  assert.ok(Math.abs(c.queued(5.001) - (0.1 + 0.05 + 0.2 - 0.001)) < 1e-6);
});

test("underrun re-primes the jitter buffer", () => {
  const c = new PlaybackClock({ jitter: 0.1 });
  c.schedule(1, CHUNK);
  const s = c.schedule(3, CHUNK); // long gap: queue ran dry
  assert.ok(Math.abs(s.start - 3.1) < 1e-9);
});

test("reset (barge-in) forgets the queue", () => {
  const c = new PlaybackClock({ jitter: 0.1 });
  c.schedule(1, CHUNK * 10);
  assert.ok(c.isSpeaking(1.2));
  c.reset();
  assert.equal(c.isSpeaking(1.2), false);
  assert.equal(c.queued(1.2), 0);
  assert.ok(Math.abs(c.schedule(1.2, CHUNK).start - 1.3) < 1e-9);
});

test("isSpeaking turns false once the queue drains", () => {
  const c = new PlaybackClock({ jitter: 0.1 });
  c.schedule(0, CHUNK);
  assert.equal(c.isSpeaking(0.05), true);
  assert.equal(c.isSpeaking(0.2), false);
});

test("stale chunks beyond the backlog cap are dropped", () => {
  const c = new PlaybackClock({ jitter: 0.1, maxBacklog: 1 });
  assert.ok(c.schedule(0, 24000)); // 1 s queued
  assert.equal(c.schedule(0, CHUNK), null);
});

test("ActiveSources.stopAll stops and disconnects every source, once", () => {
  const log = [];
  const mk = (n) => ({ stop: (t) => log.push(`stop${n}@${t}`), disconnect: () => log.push(`dc${n}`), onended: null });
  const a = mk(1), b = mk(2);
  const set = new ActiveSources();
  set.add(a);
  set.add(b);
  assert.equal(set.size, 2);
  a.onended(); // natural end removes it
  assert.equal(set.size, 1);
  assert.equal(set.stopAll(), 1);
  assert.deepEqual(log, ["stop2@0", "dc2"]);
  assert.equal(set.size, 0);
  assert.equal(set.stopAll(), 0);
});

test("ActiveSources.stopAll tolerates sources that throw", () => {
  const set = new ActiveSources();
  set.add({ stop() { throw new Error("InvalidStateError"); }, disconnect() { throw new Error("x"); } });
  assert.equal(set.stopAll(), 1);
});
