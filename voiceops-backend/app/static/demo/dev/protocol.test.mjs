import test from "node:test";
import assert from "node:assert/strict";
import { CaptionModel } from "../js/captions.js";
import {
  CLOSE_BAD_CODE, ERROR_KIND, PHASE, backoffDelay, fallbackHeadline, formatDuration,
  initialState, parseServerMessage, reduce, socketUrl,
} from "../js/protocol.js";

const srv = (obj) => ({ type: "server", msg: parseServerMessage(JSON.stringify(obj)) });
const run = (s, ...actions) => actions.reduce(reduce, s);
const paired = () => run(initialState({ code: "X" }), { type: "submit-code", code: "X" }, srv({ event: "waiting" }));
const ringing = () => run(paired(), srv({ event: "ring", caller: "Kora", on_behalf_of: "Sam", customer_name: "Alex" }));
const incall = () => run(ringing(), { type: "answer" }, srv({ event: "connected" }));

// ── parseServerMessage ──
test("parse: known events, snake_case mapped, junk rejected", () => {
  assert.deepEqual(parseServerMessage('{"event":"waiting"}'), { event: "waiting" });
  assert.deepEqual(parseServerMessage('{"event":"ring","caller":"Kora","on_behalf_of":"Sam","customer_name":"Alex"}'),
    { event: "ring", caller: "Kora", onBehalfOf: "Sam", customerName: "Alex" });
  assert.equal(parseServerMessage("not json"), null);
  assert.equal(parseServerMessage('{"event":"nope"}'), null);
  assert.equal(parseServerMessage('{"foo":1}'), null);
  assert.equal(parseServerMessage(new ArrayBuffer(4)), null);
  assert.equal(parseServerMessage("null"), null);
});

test("parse: ring defaults caller to Kora", () => {
  assert.equal(parseServerMessage('{"event":"ring"}').caller, "Kora");
});

test("parse: ended normalizes reason and summary", () => {
  const m = parseServerMessage('{"event":"ended","reason":"agent_done","summary":{"headline":" Done ","points":["a"," ",3,"b"]}}');
  assert.deepEqual(m.summary, { headline: "Done", points: ["a", "b"] }); // non-strings become empty, then are dropped
  assert.equal(parseServerMessage('{"event":"ended","reason":"weird"}').reason, "error");
  assert.equal(parseServerMessage('{"event":"ended","reason":"timeout"}').summary, null);
  assert.equal(parseServerMessage('{"event":"ended","reason":"timeout","summary":{"headline":"","points":[]}}').summary, null);
});

test("parse: error message never empty", () => {
  assert.ok(parseServerMessage('{"event":"error"}').message.length > 0);
});

// ── state machine ──
test("happy path: pairing -> waiting -> ringing -> answering -> in call -> summary", () => {
  let s = initialState({ code: "X" });
  assert.equal(s.phase, PHASE.PAIRING);
  s = run(s, { type: "submit-code", code: "X" });
  assert.equal(s.phase, PHASE.CONNECTING);
  s = run(s, srv({ event: "waiting" }));
  assert.equal(s.phase, PHASE.WAITING);
  s = run(s, srv({ event: "ring", caller: "Kora", on_behalf_of: "Sam", customer_name: "Alex" }));
  assert.equal(s.phase, PHASE.RINGING);
  assert.equal(s.ring.onBehalfOf, "Sam");
  s = run(s, { type: "answer" });
  assert.equal(s.phase, PHASE.ANSWERING);
  s = run(s, srv({ event: "connected" }));
  assert.equal(s.phase, PHASE.INCALL);
  s = run(s, srv({ event: "ended", reason: "agent_done", summary: { headline: "H", points: ["p"] } }));
  assert.equal(s.phase, PHASE.SUMMARY);
  assert.equal(s.endReason, "agent_done");
  assert.deepEqual(s.summary, { headline: "H", points: ["p"] });
});

test("reducer does not mutate the previous state object", () => {
  const before = ringing();
  const snapshot = { ...before };
  reduce(before, { type: "answer" });
  assert.equal(before.phase, snapshot.phase);
  assert.equal(before.muted, snapshot.muted);
});

test("wrong code: close 4401 returns to pairing with a bad-code error", () => {
  const s = run(initialState({ code: "X" }), { type: "submit-code", code: "X" }, { type: "socket-close", code: CLOSE_BAD_CODE });
  assert.equal(s.phase, PHASE.PAIRING);
  assert.equal(s.error.kind, ERROR_KIND.BAD_CODE);
});

test("decline while ringing goes back to waiting", () => {
  const s = run(ringing(), { type: "decline" });
  assert.equal(s.phase, PHASE.WAITING);
  assert.equal(s.ring, null);
});

test("ended echo after a decline is ignored", () => {
  const s = run(ringing(), { type: "decline" }, srv({ event: "ended", reason: "customer_hangup" }));
  assert.equal(s.phase, PHASE.WAITING);
});

test("customer hangup goes to summary; the later ended event supplies the summary", () => {
  let s = run(incall(), { type: "hangup" });
  assert.equal(s.phase, PHASE.SUMMARY);
  assert.equal(s.endReason, "customer_hangup");
  assert.equal(s.summary, null);
  s = run(s, srv({ event: "ended", reason: "customer_hangup", summary: { headline: "Partial", points: ["x"] } }));
  assert.equal(s.summary.headline, "Partial");
});

test("driver hangup and timeout reasons are carried through", () => {
  assert.equal(run(incall(), srv({ event: "ended", reason: "driver_hangup" })).endReason, "driver_hangup");
  assert.equal(run(incall(), srv({ event: "ended", reason: "timeout" })).endReason, "timeout");
});

test("socket drop during a call ends it with a disconnected error", () => {
  for (const s0 of [ringing(), incall()]) {
    const s = run(s0, { type: "socket-close", code: 1006 });
    assert.equal(s.phase, PHASE.SUMMARY);
    assert.equal(s.endReason, "error");
    assert.equal(s.error.kind, ERROR_KIND.DISCONNECTED);
  }
});

test("socket drop while waiting shows connecting (reconnect) without losing the code", () => {
  const s = run(paired(), { type: "socket-close", code: 1006 });
  assert.equal(s.phase, PHASE.CONNECTING);
  assert.equal(s.code, "X");
});

test("a late waiting never wipes a live call, a summary or an error", () => {
  assert.equal(run(incall(), srv({ event: "waiting" })).phase, PHASE.INCALL);
  assert.equal(run(ringing(), srv({ event: "waiting" })).phase, PHASE.RINGING);
  const done = run(incall(), srv({ event: "ended", reason: "agent_done" }));
  assert.equal(run(done, srv({ event: "waiting" })).phase, PHASE.SUMMARY);
  const err = run(paired(), { type: "mic-failed", kind: "denied" });
  assert.equal(run(err, srv({ event: "waiting" })).phase, PHASE.ERROR);
});

test("a new ring interrupts a shown summary and resets it", () => {
  const done = run(incall(), srv({ event: "ended", reason: "agent_done", summary: { headline: "H", points: [] } }));
  const s = run(done, srv({ event: "ring", caller: "Kora" }));
  assert.equal(s.phase, PHASE.RINGING);
  assert.equal(s.summary, null);
});

test("a ring during a live call is ignored", () => {
  assert.equal(run(incall(), srv({ event: "ring", caller: "Kora" })).phase, PHASE.INCALL);
});

test("server error before a call -> error screen; during a call -> summary with error", () => {
  const a = run(paired(), srv({ event: "error", message: "Kora is busy" }));
  assert.equal(a.phase, PHASE.ERROR);
  assert.equal(a.error.message, "Kora is busy");
  const b = run(incall(), srv({ event: "error", message: "boom" }));
  assert.equal(b.phase, PHASE.SUMMARY);
  assert.equal(b.error.kind, ERROR_KIND.SERVER);
});

test("mic denied / missing produce distinct error kinds", () => {
  assert.equal(run(ringing(), { type: "answer" }, { type: "mic-failed", kind: "denied" }).error.kind, ERROR_KIND.MIC_DENIED);
  assert.equal(run(ringing(), { type: "answer" }, { type: "mic-failed", kind: "missing" }).error.kind, ERROR_KIND.MIC_MISSING);
});

test("mute toggles only in a call", () => {
  assert.equal(run(incall(), { type: "toggle-mute" }).muted, true);
  assert.equal(run(incall(), { type: "toggle-mute" }, { type: "toggle-mute" }).muted, false);
  assert.equal(run(paired(), { type: "toggle-mute" }).muted, false);
});

test("interrupted sets flushAudio for exactly one transition", () => {
  const s = run(incall(), srv({ event: "interrupted" }));
  assert.equal(s.flushAudio, true);
  assert.equal(run(s, { type: "toggle-mute" }).flushAudio, false);
});

test("ending a call also asks to flush audio", () => {
  assert.equal(run(incall(), srv({ event: "ended", reason: "agent_done" })).flushAudio, true);
});

test("reset returns to connecting (has code) and clears summary/error", () => {
  const s = run(incall(), srv({ event: "ended", reason: "agent_done", summary: { headline: "H", points: [] } }), { type: "reset" });
  assert.equal(s.phase, PHASE.CONNECTING);
  assert.equal(s.summary, null);
  assert.equal(run(initialState(), { type: "reset" }).phase, PHASE.PAIRING);
});

test("unreachable -> error state", () => {
  assert.equal(run(initialState({ code: "X" }), { type: "unreachable" }).error.kind, ERROR_KIND.UNREACHABLE);
});

test("captions flow through the reducer and are finalized at call end", () => {
  let s = incall();
  s = run(s, srv({ event: "caption", speaker: "agent", text: "Hi", final: false }), srv({ event: "caption", speaker: "agent", text: "Hi Alex", final: true }));
  assert.deepEqual(s.captions.lines.map((l) => [l.text, l.final]), [["Hi Alex", true]]);
  s = run(s, srv({ event: "caption", speaker: "customer", text: "yes", final: false }));
  s = run(s, srv({ event: "ended", reason: "customer_hangup" }));
  assert.ok(s.captions.lines.every((l) => l.final));
});

test("captions before any call are ignored", () => {
  const s = run(paired(), srv({ event: "caption", speaker: "agent", text: "x", final: true }));
  assert.equal(s.captions.lines.length, 0);
});

// ── caption model ──
test("CaptionModel: interim updates replace, final closes, next starts a new line", () => {
  const m = new CaptionModel();
  m.apply({ speaker: "agent", text: "Hel", final: false });
  m.apply({ speaker: "agent", text: "Hello there", final: false });
  assert.equal(m.lines.length, 1);
  m.apply({ speaker: "agent", text: "Hello there.", final: true });
  m.apply({ speaker: "agent", text: "Next", final: false });
  assert.deepEqual(m.lines.map((l) => [l.text, l.final]), [["Hello there.", true], ["Next", false]]);
});

test("CaptionModel: speakers keep independent open lines and order", () => {
  const m = new CaptionModel();
  m.apply({ speaker: "agent", text: "A1", final: false });
  m.apply({ speaker: "customer", text: "C1", final: false });
  m.apply({ speaker: "agent", text: "A1 more", final: true });
  m.apply({ speaker: "customer", text: "C1 more", final: true });
  assert.deepEqual(m.lines.map((l) => `${l.speaker}:${l.text}`), ["agent:A1 more", "customer:C1 more"]);
});

test("CaptionModel: ignores blank text and unknown speakers", () => {
  const m = new CaptionModel();
  assert.equal(m.apply({ speaker: "agent", text: "   ", final: true }), null);
  assert.equal(m.apply({ speaker: "robot", text: "hi", final: true }), null);
  assert.equal(m.lines.length, 0);
});

test("CaptionModel.interrupt cuts Kora's open line only", () => {
  const m = new CaptionModel();
  m.apply({ speaker: "agent", text: "I was saying", final: false });
  m.apply({ speaker: "customer", text: "wait", final: false });
  m.interrupt();
  const [a, c] = m.lines;
  assert.equal(a.final, true);
  assert.equal(a.interrupted, true);
  assert.equal(c.final, false);
  assert.equal(new CaptionModel().interrupt(), null);
});

test("CaptionModel caps the number of lines", () => {
  const m = new CaptionModel(3);
  for (let i = 0; i < 6; i++) m.apply({ speaker: "agent", text: `l${i}`, final: true });
  assert.deepEqual(m.lines.map((l) => l.text), ["l3", "l4", "l5"]);
});

// ── helpers ──
test("formatDuration", () => {
  assert.equal(formatDuration(0), "0:00");
  assert.equal(formatDuration(7.9), "0:07");
  assert.equal(formatDuration(725), "12:05");
  assert.equal(formatDuration(-3), "0:00");
});

test("socketUrl picks ws/wss from the page protocol", () => {
  assert.equal(socketUrl({ protocol: "https:", host: "a.b" }), "wss://a.b/ws/demo/customer");
  assert.equal(socketUrl({ protocol: "http:", host: "localhost:8787" }, "/ws/demo/stage"), "ws://localhost:8787/ws/demo/stage");
});

test("backoffDelay doubles, caps at 8 s and stays within jitter", () => {
  const mid = () => 0.5;
  assert.equal(backoffDelay(0, mid), 1000);
  assert.equal(backoffDelay(1, mid), 2000);
  assert.equal(backoffDelay(2, mid), 4000);
  assert.equal(backoffDelay(9, mid), 8000);
  assert.ok(backoffDelay(3, () => 0) >= 6800 && backoffDelay(3, () => 1) <= 9200);
});

test("fallbackHeadline covers every reason", () => {
  for (const r of ["customer_hangup", "driver_hangup", "agent_done", "timeout", "error"]) assert.ok(fallbackHeadline(r));
});
