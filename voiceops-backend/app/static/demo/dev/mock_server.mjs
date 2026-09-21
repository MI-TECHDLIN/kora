// Mock of the Kora demo backend for developing and testing the customer page
// with no API key, no AssemblyAI and no carrier. Node built-ins only.
//
//   node dev/mock_server.mjs            # http://localhost:8787/  (demo code: DEMO)
//   curl localhost:8787/dev/ring        # or press Enter in this terminal, or use /dev/
//
// It serves the static page AND plays the server side of the wire protocol
// (spec: /ws/demo/customer and /ws/demo/stage), including a scripted
// conversation with synthesized "voice" audio so the whole playback path,
// the orb and barge-in can be exercised on a real device.

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { networkInterfaces } from "node:os";
import { dirname, extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { acceptUpgrade } from "./minimal_ws.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const RATE = 24000;
const FRAME = 1200; // 50 ms

const TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json", ".svg": "image/svg+xml",
};

export const SCRIPT = {
  ring: { caller: "Kora", on_behalf_of: "Sam", customer_name: "Alex" },
  greeting: "Hi Alex, this is Kora, calling for Sam, your delivery driver. Sam is about eight minutes away with your order.",
  question: "Quick question: will someone be home to take it, or should Sam leave it somewhere safe?",
  customerReply: "Yes, I'm home. Actually, could he leave it with the front desk?",
  wrap: "Perfect, I'll let Sam know. Thanks, Alex. See you soon!",
  summary: {
    headline: "Sam will drop your order at the front desk",
    points: ["Someone is home", "Leave the parcel with the front desk", "Arriving in about 8 minutes"],
  },
};

/** One 50 ms frame of a voice-like tone (harmonics + syllable-rate envelope), phase-continuous. */
export function synthFrame(startSample, level = 0.3) {
  const buf = Buffer.alloc(FRAME * 2);
  for (let i = 0; i < FRAME; i++) {
    const t = (startSample + i) / RATE;
    const syllable = Math.max(0, Math.sin(2 * Math.PI * 3.6 * t)) ** 0.6;
    const f0 = 150 + 25 * Math.sin(2 * Math.PI * 0.9 * t);
    let v = 0;
    for (let h = 1; h <= 6; h++) v += Math.sin(2 * Math.PI * f0 * h * t) / h;
    buf.writeInt16LE(Math.round(v * syllable * level * 0.5 * 32767), i * 2);
  }
  return buf;
}

/** True when a PCM16 frame carries more than background noise. */
export function hasSpeechEnergy(buf, threshold = 0.02) {
  const n = buf.length >> 1;
  if (!n) return false;
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const v = buf.readInt16LE(i * 2) / 32768;
    sum += v * v;
  }
  return Math.sqrt(sum / n) > threshold;
}

export function createMockServer({ code = "DEMO", speed = 1, log = () => {} } = {}) {
  const customers = new Set(); // paired customer peers, newest last
  const stages = new Set();
  let call = null; // {peer, timers, scenario, answered, done}

  const scaled = (ms) => ms / speed;
  const toStage = (obj) => stages.forEach((s) => s.sendJson(obj));
  const emit = (peer, obj) => {
    peer.sendJson(obj);
    toStage(obj);
  };

  function endCall(reason, summary) {
    if (!call || call.done) return;
    call.done = true;
    call.timers.forEach(clearTimeout);
    call.timers.clear();
    const { peer } = call;
    const msg = { event: "ended", reason };
    if (summary) msg.summary = summary;
    emit(peer, msg);
    log(`call ended: ${reason}`);
    call = null;
    setTimeout(() => {
      if (!peer.closed) emit(peer, { event: "waiting" });
    }, scaled(300));
  }

  function later(fn, ms) {
    const c = call;
    const t = setTimeout(() => {
      c.timers.delete(t);
      if (call === c && !c.done) fn();
    }, scaled(ms));
    c.timers.add(t);
  }

  /** Speak `text`: interim captions word by word, audio in real time, final caption at the end. */
  function speak(text, then) {
    const c = call;
    c.speaking = true;
    const words = text.split(/\s+/);
    const totalMs = Math.max(1200, words.length * 330);
    const frames = Math.round(totalMs / 50);
    let sent = 0;
    let shownWords = 0;
    c.speech = { cancel: () => clearInterval(timer), then };
    const timer = setInterval(() => {
      if (call !== c || c.done) return clearInterval(timer);
      c.peer.sendBinary(synthFrame(c.sampleCursor));
      c.sampleCursor += FRAME;
      sent++;
      const should = Math.min(words.length, Math.ceil((sent / frames) * words.length));
      if (should > shownWords && sent < frames) {
        shownWords = should;
        emit(c.peer, { event: "caption", speaker: "agent", text: words.slice(0, should).join(" "), final: false });
      }
      if (sent >= frames) {
        clearInterval(timer);
        c.speaking = false;
        emit(c.peer, { event: "caption", speaker: "agent", text, final: true });
        then && then();
      }
    }, 50 / Math.max(1, speed));
  }

  function customerSays(text, then) {
    const c = call;
    const words = text.split(/\s+/);
    let n = 0;
    const timer = setInterval(() => {
      if (call !== c || c.done) return clearInterval(timer);
      n++;
      const final = n >= words.length;
      emit(c.peer, { event: "caption", speaker: "customer", text: words.slice(0, n).join(" "), final });
      if (final) {
        clearInterval(timer);
        then && then();
      }
    }, scaled(240));
  }

  function runScript() {
    const c = call;
    const s = SCRIPT;
    if (c.scenario === "busy") {
      emit(c.peer, { event: "error", message: "Kora is on another call right now. Please try again in a moment." });
      return endCall("error");
    }
    emit(c.peer, { event: "connected" });
    later(() => speak(s.greeting, () => later(() => speak(s.question, waitForCustomer), 400)), 500);

    function waitForCustomer() {
      // Real customers talk; with no mic the scripted reply plays after a pause so the demo still runs.
      later(() => customerSays(s.customerReply, () => later(() => speak(s.wrap, finish), 500)), 3500);
    }
    function finish() {
      if (c.scenario === "error") {
        emit(c.peer, { event: "error", message: "Kora lost the connection to the call service." });
        return endCall("error");
      }
      later(() => endCall("agent_done", c.scenario === "nosummary" ? null : s.summary), 900);
    }
    if (c.scenario === "error") later(() => (emit(c.peer, { event: "error", message: "Kora lost the connection to the call service." }), endCall("error")), 6000);
  }

  function ring(scenario = "normal") {
    const peer = [...customers].reverse().find((p) => !p.closed);
    if (!peer) return { ok: false, reason: "no customer page is waiting" };
    if (call) return { ok: false, reason: "a call is already active" };
    call = { peer, timers: new Set(), scenario, answered: false, done: false, sampleCursor: 0, speaking: false, barged: false };
    emit(peer, { event: "ring", ...SCRIPT.ring });
    log(`ringing (${scenario})`);
    // Unanswered rings stop after 45 s, like a real phone.
    later(() => endCall("timeout"), 45000);
    return { ok: true };
  }

  function driverHangup() {
    if (!call) return { ok: false, reason: "no active call" };
    endCall("driver_hangup");
    return { ok: true };
  }

  function onCustomer(peer) {
    let authed = false;
    peer.on("message", (data, isBinary) => {
      if (isBinary) {
        const c = call;
        if (c && c.peer === peer && c.answered && c.speaking && !c.barged && hasSpeechEnergy(data)) {
          c.barged = true; // customer talked over Kora: cut her off, as the real backend does on input.speech.started
          const resume = c.speech && c.speech.then;
          c.speech && c.speech.cancel();
          c.speaking = false;
          emit(peer, { event: "interrupted" });
          log("barge-in");
          later(() => speak("Sorry, go ahead, I'm listening.", resume), 300);
        }
        return;
      }
      let msg;
      try { msg = JSON.parse(data); } catch { return; }
      if (!authed) {
        if (msg.type !== "hello" || msg.code !== code) return peer.close(4401);
        authed = true;
        customers.add(peer);
        return peer.sendJson({ event: "waiting" });
      }
      if (msg.type === "answer" && call && call.peer === peer && !call.answered) {
        call.answered = true;
        log("answered");
        runScript();
      } else if (msg.type === "hangup" && call && call.peer === peer) {
        endCall("customer_hangup");
      }
    });
    peer.on("close", () => {
      customers.delete(peer);
      if (call && call.peer === peer) endCall("customer_hangup");
    });
  }

  function onStage(peer) {
    let authed = false;
    peer.on("message", (data, isBinary) => {
      if (isBinary || authed) return;
      let msg;
      try { msg = JSON.parse(data); } catch { return; }
      if (msg.type !== "hello" || msg.code !== code) return peer.close(4401);
      authed = true;
      stages.add(peer);
      peer.sendJson({ event: "waiting" });
    });
    peer.on("close", () => stages.delete(peer));
  }

  const server = createServer(async (req, res) => {
    const url = new URL(req.url, "http://x");
    if (url.pathname.startsWith("/dev/")) return devRoute(url, res);
    let path = url.pathname.replace(/^\/demo(?=\/|$)/, "");
    if (path === "" || path === "/") path = "/customer.html";
    const file = normalize(join(ROOT, path));
    const rel = file.slice(ROOT.length + 1);
    if (!file.startsWith(ROOT + sep) || rel.startsWith("dev" + sep) || rel.includes("node_modules")) {
      res.writeHead(404).end("not found");
      return;
    }
    try {
      const body = await readFile(file);
      res.writeHead(200, { "content-type": TYPES[extname(file)] || "application/octet-stream", "cache-control": "no-store" });
      res.end(body);
    } catch {
      res.writeHead(404).end("not found");
    }
  });

  function devRoute(url, res) {
    const json = (o) => res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(o));
    switch (url.pathname) {
      case "/dev/":
        return res.writeHead(200, { "content-type": TYPES[".html"] }).end(CONTROL_PANEL);
      case "/dev/ring":
        return json(ring(url.searchParams.get("scenario") || "normal"));
      case "/dev/hangup":
        return json(driverHangup());
      case "/dev/status":
        return json({ customers: customers.size, stages: stages.size, call: call ? { answered: call.answered, scenario: call.scenario } : null });
      default:
        return res.writeHead(404).end("not found");
    }
  }

  server.on("upgrade", (req, socket) => {
    const path = new URL(req.url, "http://x").pathname;
    if (path !== "/ws/demo/customer" && path !== "/ws/demo/stage") return socket.destroy();
    const peer = acceptUpgrade(req, socket);
    if (!peer) return;
    if (path === "/ws/demo/customer") onCustomer(peer);
    else onStage(peer);
  });

  return {
    server,
    ring,
    driverHangup,
    listen: (port = 0, host = "0.0.0.0") => new Promise((ok) => server.listen(port, host, () => ok(server.address().port))),
    close: () => new Promise((ok) => {
      for (const p of [...customers, ...stages]) p.close(1001);
      server.close(() => ok());
      server.closeAllConnections?.();
    }),
    get activeCall() { return call; },
  };
}

const CONTROL_PANEL = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mock driver</title><style>body{font:16px system-ui;background:#07060b;color:#f4f1ff;padding:24px;max-width:420px;margin:auto}
button{display:block;width:100%;min-height:52px;margin:10px 0;border:0;border-radius:14px;background:#8b5cf6;color:#fff;font:600 16px system-ui}
button.alt{background:#1d1834}pre{background:#151126;padding:12px;border-radius:12px;white-space:pre-wrap}</style>
<h2>Mock driver</h2><p>Stands in for "call the customer" in the Kora app.</p>
<button onclick="go('ring')">Ring the customer page</button>
<button class="alt" onclick="go('ring?scenario=nosummary')">Ring (call ends with no summary)</button>
<button class="alt" onclick="go('ring?scenario=error')">Ring (call fails mid-way)</button>
<button class="alt" onclick="go('ring?scenario=busy')">Ring (server busy on answer)</button>
<button class="alt" onclick="go('hangup')">Driver hangs up</button><pre id=o>ready</pre>
<script>async function go(p){const r=await fetch('/dev/'+p);o.textContent=JSON.stringify(await r.json(),null,1)}</script>`;

// ── CLI ──────────────────────────────────────────────────────────────────

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const arg = (name, dflt) => {
    const i = process.argv.indexOf(`--${name}`);
    return i > -1 ? process.argv[i + 1] : dflt;
  };
  const code = arg("code", process.env.MOCK_CODE || "DEMO");
  const port = Number(arg("port", process.env.PORT || 8787));
  const mock = createMockServer({ code, speed: Number(arg("speed", 1)), log: (m) => console.log(`[mock] ${m}`) });
  const bound = await mock.listen(port);
  const lan = Object.values(networkInterfaces()).flat().find((n) => n && n.family === "IPv4" && !n.internal);
  console.log(`Mock Kora backend on http://localhost:${bound}/   (demo code: ${code})`);
  console.log(`  customer page   http://localhost:${bound}/?code=${code}`);
  console.log(`  mock driver     http://localhost:${bound}/dev/   (or: curl localhost:${bound}/dev/ring, or press Enter here)`);
  if (lan) console.log(`  on your LAN     http://${lan.address}:${bound}/   (microphone needs HTTPS off localhost; see README)`);
  process.stdin.on("data", () => console.log(`[mock] ring: ${JSON.stringify(mock.ring())}`));
}
