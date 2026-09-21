// Drives the mock server with a scripted client over a real WebSocket, using the
// page's own protocol code, to prove the wire protocol end to end (no browser).

import test from "node:test";
import assert from "node:assert/strict";
import { createMockServer } from "./mock_server.mjs";
import { PHASE, initialState, parseServerMessage, reduce } from "../js/protocol.js";
import { Pcm16Decoder } from "../js/pcm.js";

const SPEED = 12;

async function withServer(fn) {
  const mock = createMockServer({ code: "DEMO", speed: SPEED });
  const port = await mock.listen(0, "127.0.0.1");
  try {
    await fn(mock, port);
  } finally {
    await mock.close();
  }
}

/** Scripted customer: collects events and binary frames, exposes await-by-predicate. */
function client(port, path = "/ws/demo/customer") {
  const ws = new WebSocket(`ws://127.0.0.1:${port}${path}`);
  ws.binaryType = "arraybuffer";
  const events = [];
  const audio = [];
  const waiters = [];
  let closeCode = null;
  const poke = () => {
    for (const w of [...waiters]) if (w.test()) { waiters.splice(waiters.indexOf(w), 1); w.ok(); }
  };
  ws.onmessage = (e) => {
    if (typeof e.data === "string") events.push(JSON.parse(e.data));
    else audio.push(e.data);
    poke();
  };
  ws.onclose = (e) => { closeCode = e.code; poke(); };
  const until = (test, ms = 8000, label = "condition") =>
    new Promise((ok, no) => {
      const t = setTimeout(() => no(new Error(`timeout waiting for ${label}; events=${JSON.stringify(events.map((x) => x.event))}`)), ms);
      const w = { test, ok: () => { clearTimeout(t); ok(); } };
      waiters.push(w);
      poke();
    });
  return {
    ws, events, audio,
    get closeCode() { return closeCode; },
    open: () => new Promise((ok, no) => { ws.onopen = ok; ws.onerror = () => no(new Error("ws error")); }),
    send: (o) => ws.send(JSON.stringify(o)),
    until,
    waitEvent: (name) => until(() => events.some((e) => e.event === name), 8000, name),
    waitClose: () => until(() => closeCode !== null, 3000, "close"),
  };
}

test("wrong demo code is refused with close 4401", async () => {
  await withServer(async (_m, port) => {
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "NOPE" });
    await c.waitClose();
    assert.equal(c.closeCode, 4401);
  });
});

test("ring with no page waiting is reported, not thrown", async () => {
  await withServer(async (mock) => {
    assert.equal(mock.ring().ok, false);
  });
});

test("full call: hello, waiting, ring, answer, connected, audio, captions, ended with summary", async () => {
  await withServer(async (mock, port) => {
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "DEMO" });
    await c.waitEvent("waiting");
    assert.deepEqual(mock.ring(), { ok: true });
    await c.waitEvent("ring");
    const ring = parseServerMessage(JSON.stringify(c.events.find((e) => e.event === "ring")));
    assert.equal(ring.onBehalfOf, "Sam");
    assert.equal(ring.customerName, "Alex");

    // Audio must not flow before answer.
    await new Promise((r) => setTimeout(r, 150));
    assert.equal(c.audio.length, 0);

    c.send({ type: "answer" });
    await c.waitEvent("connected");
    await c.until(() => c.audio.length > 10, 5000, "agent audio");
    for (const f of c.audio.slice(0, 5)) assert.equal(f.byteLength, 2400, "50 ms PCM16 mono 24 kHz frames");
    const dec = new Pcm16Decoder();
    assert.ok(c.audio.slice(0, 10).some((f) => dec.push(f).some((v) => Math.abs(v) > 0.01)), "audio is not silence");

    await c.waitEvent("ended");
    const ended = c.events.find((e) => e.event === "ended");
    assert.equal(ended.reason, "agent_done");
    assert.ok(ended.summary.headline);
    assert.ok(ended.summary.points.length >= 1);

    // Captions: interim then final for the agent, and a customer line.
    const agentCaps = c.events.filter((e) => e.event === "caption" && e.speaker === "agent");
    assert.ok(agentCaps.some((e) => e.final === false));
    assert.ok(agentCaps.some((e) => e.final === true));
    assert.ok(c.events.some((e) => e.event === "caption" && e.speaker === "customer" && e.final));

    // The page's own reducer, fed the same events, lands on the summary screen.
    let s = reduce(initialState({ code: "DEMO" }), { type: "submit-code", code: "DEMO" });
    for (const ev of c.events) {
      s = reduce(s, { type: "server", msg: parseServerMessage(JSON.stringify(ev)) });
      if (ev.event === "ring") s = reduce(s, { type: "answer" });
    }
    assert.equal(s.phase, PHASE.SUMMARY);
    assert.equal(s.summary.points.length, ended.summary.points.length);
    await c.until(() => c.events.filter((e) => e.event === "waiting").length >= 2, 3000, "waiting again");
    c.ws.close();
  });
});

test("customer hangup while ringing = decline", async () => {
  await withServer(async (mock, port) => {
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "DEMO" });
    await c.waitEvent("waiting");
    mock.ring();
    await c.waitEvent("ring");
    c.send({ type: "hangup" });
    await c.waitEvent("ended");
    assert.equal(c.events.find((e) => e.event === "ended").reason, "customer_hangup");
    assert.equal(mock.activeCall, null);
    c.ws.close();
  });
});

test("driver hangup mid-call ends with driver_hangup and stops audio", async () => {
  await withServer(async (mock, port) => {
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "DEMO" });
    await c.waitEvent("waiting");
    mock.ring();
    await c.waitEvent("ring");
    c.send({ type: "answer" });
    await c.until(() => c.audio.length > 3, 5000, "audio");
    mock.driverHangup();
    await c.waitEvent("ended");
    assert.equal(c.events.find((e) => e.event === "ended").reason, "driver_hangup");
    const n = c.audio.length;
    await new Promise((r) => setTimeout(r, 200));
    assert.equal(c.audio.length, n, "no audio after the call ended");
    c.ws.close();
  });
});

test("barge-in: loud customer audio while Kora speaks yields `interrupted`, then Kora yields the floor", async () => {
  await withServer(async (mock, port) => {
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "DEMO" });
    await c.waitEvent("waiting");
    mock.ring();
    await c.waitEvent("ring");
    c.send({ type: "answer" });
    await c.until(() => c.audio.length > 3, 5000, "audio");
    const loud = new Int16Array(1200).map((_, i) => Math.round(Math.sin(i / 5) * 12000));
    c.ws.send(loud.buffer);
    await c.waitEvent("interrupted");
    c.ws.close();
  });
});

test("scenarios: no-summary ends without a summary; error ends with an error event", async () => {
  await withServer(async (mock, port) => {
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "DEMO" });
    await c.waitEvent("waiting");
    mock.ring("nosummary");
    await c.waitEvent("ring");
    c.send({ type: "answer" });
    await c.waitEvent("ended");
    assert.equal(c.events.find((e) => e.event === "ended").summary, undefined);
    c.ws.close();
  });
  await withServer(async (mock, port) => {
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "DEMO" });
    await c.waitEvent("waiting");
    mock.ring("busy");
    await c.waitEvent("ring");
    c.send({ type: "answer" });
    await c.waitEvent("error");
    await c.waitEvent("ended");
    assert.equal(c.events.find((e) => e.event === "ended").reason, "error");
    c.ws.close();
  });
});

test("stage feed mirrors events without audio", async () => {
  await withServer(async (mock, port) => {
    const stage = client(port, "/ws/demo/stage");
    await stage.open();
    stage.send({ type: "hello", code: "DEMO" });
    await stage.waitEvent("waiting");
    const c = client(port);
    await c.open();
    c.send({ type: "hello", code: "DEMO" });
    await c.waitEvent("waiting");
    mock.ring();
    await stage.waitEvent("ring");
    c.send({ type: "answer" });
    await stage.waitEvent("connected");
    await stage.until(() => stage.events.some((e) => e.event === "caption"), 5000, "caption");
    assert.equal(stage.audio.length, 0);
    stage.ws.close();
    c.ws.close();
  });
});

test("static files: page is served at / and /demo/, dev folder is not", async () => {
  await withServer(async (_m, port) => {
    for (const p of ["/", "/demo/", "/customer.js", "/demo/js/pcm.js", "/customer.css"]) {
      const r = await fetch(`http://127.0.0.1:${port}${p}`);
      assert.equal(r.status, 200, p);
    }
    assert.match((await fetch(`http://127.0.0.1:${port}/js/pcm.js`)).headers.get("content-type"), /javascript/);
    assert.equal((await fetch(`http://127.0.0.1:${port}/dev/mock_server.mjs`)).status, 404);
    assert.equal((await fetch(`http://127.0.0.1:${port}/%2e%2e/%2e%2e/etc/passwd`)).status, 404);
  });
});
