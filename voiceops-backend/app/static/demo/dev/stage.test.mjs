import test from "node:test";
import assert from "node:assert/strict";
import { STAGE, initialStage, stageReduce } from "../js/stage-state.js";
import { parseServerMessage } from "../js/protocol.js";

const ev = (o) => parseServerMessage(JSON.stringify(o));
const run = (s, ...events) => events.reduce((acc, e, i) => stageReduce(acc, ev(e), 1000 + i), s);

test("stage follows waiting -> ringing -> live -> ended and keeps the summary until the next ring", () => {
  let s = run(initialStage(), { event: "waiting" });
  assert.equal(s.phase, STAGE.WAITING);
  s = run(s, { event: "ring", caller: "Kora", on_behalf_of: "Sam", customer_name: "Alex" });
  assert.equal(s.phase, STAGE.RINGING);
  assert.equal(s.ring.customerName, "Alex");
  s = run(s, { event: "connected" });
  assert.equal(s.phase, STAGE.LIVE);
  assert.ok(s.startedAt);
  s = run(s, { event: "caption", speaker: "agent", text: "Hi", final: false });
  assert.equal(s.speaking, true);
  s = run(s, { event: "caption", speaker: "agent", text: "Hi Alex", final: true });
  assert.equal(s.speaking, false);
  s = run(s, { event: "ended", reason: "agent_done", summary: { headline: "H", points: ["p"] } });
  assert.equal(s.phase, STAGE.ENDED);
  assert.equal(s.captions.lines.every((l) => l.final), true);
  s = run(s, { event: "waiting" });
  assert.equal(s.phase, STAGE.ENDED, "late waiting does not hide the summary");
  s = run(s, { event: "ring", caller: "Kora" });
  assert.equal(s.phase, STAGE.RINGING);
  assert.equal(s.captions.lines.length, 0);
  assert.equal(s.summary, null);
});

test("stage marks a barge-in and ignores null events", () => {
  let s = run(initialStage(), { event: "ring", caller: "Kora" }, { event: "connected" }, { event: "caption", speaker: "agent", text: "Let me", final: false });
  s = run(s, { event: "interrupted" });
  assert.equal(s.captions.lines[0].interrupted, true);
  assert.equal(stageReduce(s, null), s);
});
