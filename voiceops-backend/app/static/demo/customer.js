// Kora customer page controller. State lives in js/protocol.js (pure, tested);
// this file wires it to the DOM, the socket and Web Audio.

import { AudioEngine, audioSupported, playCue, startRingtone } from "./js/audio.js";
import { Connection } from "./js/connection.js";
import { Orb } from "./js/orb.js";
import {
  ERROR_KIND, PHASE, backoffDelay, fallbackHeadline, formatDuration, initialState,
  parseServerMessage, reduce, socketUrl,
} from "./js/protocol.js";

const $ = (id) => document.getElementById(id);
const el = {
  body: document.body,
  screens: [...document.querySelectorAll(".screen")],
  form: $("pairForm"), codeInput: $("codeInput"), codeError: $("codeError"),
  linkPill: $("linkPill"), linkText: $("linkText"), soundHint: $("soundHint"), leaveBtn: $("leaveBtn"),
  ringSub: $("ringSub"), answerBtn: $("answerBtn"), declineBtn: $("declineBtn"),
  callState: $("callState"), timer: $("timer"), captions: $("captions"), captionsEmpty: $("captionsEmpty"),
  meterBar: $("meterBar"), muteBtn: $("muteBtn"), muteIcon: $("muteIcon"), muteHint: $("muteHint"), hangupBtn: $("hangupBtn"),
  endChip: $("endChip"), points: $("points"), summaryNote: $("summaryNote"), againBtn: $("againBtn"),
  errorText: $("errorText"), errorSteps: $("errorSteps"), retryBtn: $("retryBtn"), errorLeaveBtn: $("errorLeaveBtn"),
  announcer: $("announcer"),
};
const eyebrowRing = document.querySelector('[data-screen="ringing"] .eyebrow');
const summaryTitle = $("t-summary");
const errorTitle = $("t-error");

const STORE_KEY = "kora-demo-code";
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

const store = {
  get() { try { return sessionStorage.getItem(STORE_KEY) || ""; } catch { return ""; } },
  set(v) { try { sessionStorage.setItem(STORE_KEY, v); } catch { /* private mode */ } },
  clear() { try { sessionStorage.removeItem(STORE_KEY); } catch { /* ignore */ } },
};

// ── Runtime ─────────────────────────────────────────────────────────────

const engine = new AudioEngine();
const orb = new Orb($("orb"), { size: 320, reducedMotion: reducedMotion.matches });
reducedMotion.addEventListener?.("change", (e) => { orb.reduced = e.matches; });

let state = initialState();
let conn = null;
let everPaired = false;
let failedAttempts = 0;
let reconnectTimer = 0;
let connectTimer = 0;
let wantConnected = false;
let stopRing = null;
let vibeTimer = 0;
let timerHandle = 0;
let callStartedAt = 0;
let micLevel = 0;
let wakeLock = null;
const rendered = { screen: "", captionSeq: new Map(), callState: "", mood: "" };

// ── Dispatch & render ───────────────────────────────────────────────────

function dispatch(action) {
  const prev = state;
  state = reduce(prev, action);
  try {
    render(prev, state);
    effects(prev, state);
  } catch (e) {
    console.warn("[kora-demo]", e);
  }
}

function screenFor(s) {
  switch (s.phase) {
    case PHASE.CONNECTING: return everPaired ? "waiting" : "pairing";
    case PHASE.ANSWERING: return "incall";
    default: return s.phase;
  }
}

function render(prev, s) {
  const screen = screenFor(s);
  if (screen !== rendered.screen) {
    rendered.screen = screen;
    for (const sc of el.screens) {
      const on = sc.dataset.screen === screen;
      sc.classList.toggle("is-active", on);
      sc.toggleAttribute("inert", !on);
      sc.setAttribute("aria-hidden", String(!on));
    }
  }
  el.body.dataset.phase = s.phase;

  // Pairing
  const busy = s.phase === PHASE.CONNECTING && !everPaired;
  el.form.querySelector("button").disabled = busy;
  el.form.querySelector("button").textContent = busy ? "Connecting…" : "Wait for the call";
  const badCode = s.error && s.error.kind === ERROR_KIND.BAD_CODE;
  el.codeError.hidden = !badCode;
  el.codeError.textContent = badCode ? s.error.message : "";
  if (badCode) el.codeInput.setAttribute("aria-invalid", "true");

  // Waiting
  const reconnecting = s.phase === PHASE.CONNECTING && everPaired;
  el.linkPill.dataset.state = reconnecting ? "reconnecting" : "ok";
  el.linkText.textContent = reconnecting ? "Reconnecting…" : "Connected to Kora";

  // Ringing
  if (s.ring) {
    const who = s.ring.onBehalfOf ? `Calling on behalf of ${s.ring.onBehalfOf}` : "Calling on behalf of your driver";
    el.ringSub.textContent = who;
    eyebrowRing.textContent = s.ring.customerName ? `Incoming call for ${s.ring.customerName}` : "Incoming call";
  }

  // In call
  if (s.phase === PHASE.INCALL || s.phase === PHASE.ANSWERING) renderCaptions(s);
  el.muteBtn.setAttribute("aria-pressed", String(s.muted));
  el.muteBtn.setAttribute("aria-label", s.muted ? "Unmute microphone" : "Mute microphone");
  el.muteIcon.setAttribute("href", s.muted ? "#i-mic-off" : "#i-mic");
  el.muteHint.textContent = s.muted ? "Microphone muted. Kora can't hear you." : "Microphone on";

  if (s.phase === PHASE.SUMMARY) renderSummary(s);
  if (s.phase === PHASE.ERROR) renderError(s);

  // Announce phase changes to screen readers.
  if (prev.phase !== s.phase) el.announcer.textContent = announcement(s);

  // Focus the primary control of a newly shown screen (keyboard and switch users).
  if (prev.phase !== s.phase) focusFor(screen);
}

function announcement(s) {
  switch (s.phase) {
    case PHASE.WAITING: return "Waiting for Kora's call.";
    case PHASE.RINGING: return "Incoming call from Kora.";
    case PHASE.ANSWERING: return "Connecting to Kora.";
    case PHASE.INCALL: return "Call connected.";
    case PHASE.SUMMARY: return "Call ended.";
    case PHASE.ERROR: return s.error ? s.error.message : "Error.";
    default: return "";
  }
}

function focusFor(screen) {
  const target = { pairing: el.codeInput, ringing: el.answerBtn, waiting: null, incall: el.hangupBtn, summary: el.againBtn, error: el.retryBtn }[screen];
  if (target && screen !== "pairing") setTimeout(() => target.focus({ preventScroll: true }), 350);
}

function renderCaptions(s) {
  const lines = s.captions.lines;
  el.captionsEmpty.hidden = lines.length > 0;
  const nearBottom = el.captions.scrollHeight - el.captions.scrollTop - el.captions.clientHeight < 80;
  const live = new Set();
  for (const line of lines) {
    live.add(line.id);
    let node = rendered.captionSeq.get(line.id);
    if (!node) {
      node = document.createElement("div");
      node.className = `cap cap--${line.speaker}`;
      const who = document.createElement("span");
      who.className = "cap__who";
      who.textContent = line.speaker === "agent" ? "Kora" : "You";
      const text = document.createElement("p");
      text.className = "cap__text";
      node.append(who, text);
      el.captions.append(node);
      rendered.captionSeq.set(line.id, node);
    }
    const text = node.lastChild;
    if (text.textContent !== line.text) text.textContent = line.text;
    node.classList.toggle("is-final", line.final);
    node.classList.toggle("is-interrupted", line.interrupted);
  }
  for (const [id, node] of rendered.captionSeq) {
    if (!live.has(id)) { node.remove(); rendered.captionSeq.delete(id); }
  }
  if (nearBottom) el.captions.scrollTop = el.captions.scrollHeight;
}

function clearCaptionsDom() {
  for (const node of rendered.captionSeq.values()) node.remove();
  rendered.captionSeq.clear();
  el.captionsEmpty.hidden = false;
}

const CHIP = {
  agent_done: "Call complete", customer_hangup: "You hung up", driver_hangup: "Driver ended the call",
  timeout: "Time limit reached", error: "Call failed",
};

function renderSummary(s) {
  const sum = s.summary;
  el.endChip.textContent = CHIP[s.endReason] || "Call ended";
  summaryTitle.textContent = (sum && sum.headline) || fallbackHeadline(s.endReason);
  el.points.replaceChildren();
  for (const p of (sum && sum.points) || []) {
    const li = document.createElement("li");
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "ico");
    svg.setAttribute("aria-hidden", "true");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", "#i-check");
    svg.append(use);
    const span = document.createElement("span");
    span.textContent = p;
    li.append(svg, span);
    el.points.append(li);
  }
  el.summaryNote.textContent = s.error
    ? s.error.message
    : sum && sum.points.length && s.endReason === "agent_done" ? "Kora has passed this on to your driver." : "";
  el.againBtn.textContent = "Call again";
}

const ERROR_COPY = {
  [ERROR_KIND.MIC_DENIED]: {
    title: "Microphone is blocked",
    steps: ["Tap the lock or settings icon next to the address.", "Set Microphone to Allow for this site.", "Ask the driver to call again."],
    action: "Try again",
  },
  [ERROR_KIND.MIC_MISSING]: { title: "No microphone found", steps: [], action: "Try again" },
  [ERROR_KIND.UNSUPPORTED]: { title: "This browser can't take the call", steps: [], action: "" },
  [ERROR_KIND.UNREACHABLE]: { title: "Can't reach Kora", steps: [], action: "Retry" },
  [ERROR_KIND.SERVER]: { title: "Kora is busy", steps: [], action: "Try again" },
  [ERROR_KIND.DISCONNECTED]: { title: "Connection lost", steps: [], action: "Reconnect" },
};

function renderError(s) {
  const copy = ERROR_COPY[s.error.kind] || { title: "Something's off", steps: [], action: "Try again" };
  errorTitle.textContent = copy.title;
  el.errorText.textContent = s.error.message;
  el.errorSteps.replaceChildren(...copy.steps.map((t) => Object.assign(document.createElement("li"), { textContent: t })));
  el.errorSteps.hidden = copy.steps.length === 0;
  el.retryBtn.hidden = !copy.action;
  el.retryBtn.textContent = copy.action;
  el.errorLeaveBtn.hidden = s.error.kind === ERROR_KIND.UNSUPPORTED;
}

// ── Side effects driven by phase transitions ────────────────────────────

function effects(prev, s) {
  if (s.flushAudio) engine.flush();

  if (prev.phase !== s.phase) {
    if (s.phase === PHASE.RINGING) startRinging();
    if (prev.phase === PHASE.RINGING) stopRinging();

    if (s.phase === PHASE.INCALL && prev.phase !== PHASE.INCALL) startTimer();
    const wasLive = prev.phase === PHASE.INCALL || prev.phase === PHASE.ANSWERING;
    const isLive = s.phase === PHASE.INCALL || s.phase === PHASE.ANSWERING;
    if (wasLive && !isLive) {
      const wasConnected = prev.phase === PHASE.INCALL;
      stopTimer();
      engine.endCall();
      micLevel = 0;
      if (wasConnected && engine.running) playCue(engine.ctx, "end");
      setTimeout(clearCaptionsDom, 800);
    }
    if (s.phase === PHASE.INCALL && engine.running && prev.phase === PHASE.ANSWERING) playCue(engine.ctx, "connect");
    if (s.phase === PHASE.RINGING) clearCaptionsDom();

    const holdScreen = [PHASE.WAITING, PHASE.RINGING, PHASE.ANSWERING, PHASE.INCALL, PHASE.CONNECTING].includes(s.phase) && everPaired;
    if (holdScreen) acquireWakeLock(); else releaseWakeLock();
    el.soundHint.hidden = !(s.phase === PHASE.WAITING && !engine.running);
  }
}

function startRinging() {
  if (engine.running) stopRing = startRingtone(engine.ctx);
  if (navigator.vibrate) {
    const buzz = () => navigator.vibrate([500, 250, 500]);
    buzz();
    vibeTimer = setInterval(buzz, 2400);
  }
}

function stopRinging() {
  if (stopRing) { stopRing(); stopRing = null; }
  clearInterval(vibeTimer);
  vibeTimer = 0;
  if (navigator.vibrate) navigator.vibrate(0);
}

function startTimer() {
  callStartedAt = performance.now();
  el.timer.textContent = "0:00";
  clearInterval(timerHandle);
  timerHandle = setInterval(() => {
    el.timer.textContent = formatDuration((performance.now() - callStartedAt) / 1000);
  }, 500);
}

function stopTimer() {
  clearInterval(timerHandle);
  timerHandle = 0;
}

async function acquireWakeLock() {
  if (wakeLock || !("wakeLock" in navigator)) return;
  try {
    const lock = await navigator.wakeLock.request("screen");
    wakeLock = lock;
    lock.addEventListener("release", () => { if (wakeLock === lock) wakeLock = null; });
  } catch { /* battery saver or unsupported: not fatal */ }
}

function releaseWakeLock() {
  const lock = wakeLock;
  wakeLock = null;
  if (lock) lock.release().catch(() => {});
}

// ── Orb: mood and level follow the audio each frame ─────────────────────

orb.setLevelSource(() => {
  let mood = "idle";
  let level = 0;
  switch (state.phase) {
    case PHASE.PAIRING: case PHASE.CONNECTING: mood = "idle"; break;
    case PHASE.WAITING: mood = "waiting"; break;
    case PHASE.RINGING: mood = "ringing"; break;
    case PHASE.ANSWERING:
      mood = "connecting";
      if (rendered.callState !== "Connecting…") { rendered.callState = "Connecting…"; el.callState.textContent = "Connecting…"; }
      break;
    case PHASE.INCALL: {
      const speaking = engine.speaking;
      mood = speaking ? "speaking" : "listening";
      level = speaking ? engine.outputLevel() : Math.min(1, micLevel * 3);
      const label = speaking ? "Kora is speaking" : state.muted ? "You're muted" : "Listening";
      if (label !== rendered.callState) { rendered.callState = label; el.callState.textContent = label; }
      break;
    }
    case PHASE.SUMMARY: mood = state.error ? "error" : "done"; break;
    case PHASE.ERROR: mood = "error"; break;
  }
  if (mood !== rendered.mood) { rendered.mood = mood; orb.setMood(mood); }
  el.meterBar.style.transform = `scaleX(${state.phase === PHASE.INCALL ? Math.min(1, micLevel * 4) : 0})`;
  return level;
});
orb.start();
if (reducedMotion.matches) orb.draw(0);

// ── Socket ──────────────────────────────────────────────────────────────

function ensureConn() {
  if (conn) return conn;
  conn = new Connection(socketUrl(location), {
    onOpen() {
      clearTimeout(connectTimer);
      conn.sendJson({ type: "hello", code: state.code });
      // The server answers hello with "waiting". If it never does, treat the attempt as failed.
      connectTimer = setTimeout(() => {
        conn.close();
        onClosed(1006);
      }, 9000);
    },
    onJson(data) {
      const msg = parseServerMessage(data);
      if (!msg) return;
      if (msg.event === "waiting") {
        clearTimeout(connectTimer);
        failedAttempts = 0;
        if (!everPaired) { everPaired = true; store.set(state.code); }
      }
      dispatch({ type: "server", msg });
    },
    onAudio(buf) {
      if (state.phase === PHASE.INCALL || state.phase === PHASE.ANSWERING) engine.play(buf);
    },
    onClose: (code) => onClosed(code),
  });
  return conn;
}

function connect() {
  wantConnected = true;
  clearTimeout(reconnectTimer);
  ensureConn().connect();
}

function onClosed(code) {
  clearTimeout(connectTimer);
  dispatch({ type: "socket-close", code });
  if (code === 4401) {
    wantConnected = false;
    everPaired = false;
    store.clear();
    return;
  }
  if (!wantConnected) return;
  failedAttempts++;
  if (!everPaired && failedAttempts >= 3) {
    wantConnected = false;
    dispatch({ type: "unreachable" });
    return;
  }
  reconnectTimer = setTimeout(connect, backoffDelay(failedAttempts - 1));
}

function disconnect() {
  wantConnected = false;
  clearTimeout(reconnectTimer);
  clearTimeout(connectTimer);
  if (conn) conn.close();
}

// ── User actions ────────────────────────────────────────────────────────

el.form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const code = el.codeInput.value.trim();
  if (!code) {
    el.codeError.hidden = false;
    el.codeError.textContent = "Enter the demo code shown on the stage screen.";
    el.codeInput.setAttribute("aria-invalid", "true");
    el.codeInput.focus();
    return;
  }
  await engine.unlock(); // inside the tap, so the ringtone can play later
  failedAttempts = 0;
  dispatch({ type: "submit-code", code });
  connect();
});
el.codeInput.addEventListener("input", () => { el.codeError.hidden = true; el.codeInput.removeAttribute("aria-invalid"); });

el.soundHint.addEventListener("click", async () => {
  await engine.unlock();
  el.soundHint.hidden = engine.running;
});

function forgetCode() {
  disconnect();
  store.clear();
  everPaired = false;
  el.codeInput.value = "";
  state = initialState();
  render({ ...state, phase: "x" }, state);
  effects({ ...state, phase: PHASE.WAITING }, state);
}
el.leaveBtn.addEventListener("click", forgetCode);
el.errorLeaveBtn.addEventListener("click", forgetCode);

el.answerBtn.addEventListener("click", async () => {
  if (state.phase !== PHASE.RINGING) return;
  dispatch({ type: "answer" }); // stops the ring, shows "Connecting…"
  await engine.unlock();
  try {
    await engine.openMic();
  } catch (err) {
    if (state.phase !== PHASE.ANSWERING) return;
    conn && conn.sendJson({ type: "hangup" });
    dispatch({ type: "mic-failed", kind: err && err.kind === "missing" ? "missing" : "denied" });
    return;
  }
  if (state.phase !== PHASE.ANSWERING) { engine.endCall(); return; } // call ended while the permission prompt was open
  conn.sendJson({ type: "answer" });
  try {
    await engine.startCapture(
      (frame) => { if (state.phase === PHASE.INCALL || state.phase === PHASE.ANSWERING) conn.sendBinary(frame); },
      (level) => { micLevel = level; },
      () => state.muted,
    );
  } catch {
    conn.sendJson({ type: "hangup" });
    dispatch({ type: "mic-failed", kind: "missing" });
  }
});

el.declineBtn.addEventListener("click", () => {
  if (state.phase !== PHASE.RINGING) return;
  conn && conn.sendJson({ type: "hangup" });
  dispatch({ type: "decline" });
});

el.hangupBtn.addEventListener("click", () => {
  if (state.phase !== PHASE.INCALL && state.phase !== PHASE.ANSWERING) return;
  conn && conn.sendJson({ type: "hangup" });
  dispatch({ type: "hangup" });
});

el.muteBtn.addEventListener("click", () => dispatch({ type: "toggle-mute" }));

function backToWaiting() {
  dispatch({ type: "reset" });
  if (everPaired && conn && conn.isOpen) dispatch({ type: "server", msg: { event: "waiting" } });
  else { failedAttempts = 0; connect(); }
}
el.againBtn.addEventListener("click", backToWaiting);
el.retryBtn.addEventListener("click", backToWaiting);

// ── Lifecycle ───────────────────────────────────────────────────────────

document.addEventListener("visibilitychange", () => {
  if (document.hidden) return;
  if (wantConnected && conn && !conn.isOpen) { clearTimeout(reconnectTimer); connect(); }
  if (wakeLock === null && state.phase !== PHASE.PAIRING) acquireWakeLock();
});
window.addEventListener("online", () => { if (wantConnected && conn && !conn.isOpen) { clearTimeout(reconnectTimer); connect(); } });
window.addEventListener("pagehide", () => {
  if (conn && (state.phase === PHASE.INCALL || state.phase === PHASE.ANSWERING || state.phase === PHASE.RINGING)) conn.sendJson({ type: "hangup" });
  disconnect();
  engine.close();
});
window.addEventListener("unhandledrejection", (e) => { e.preventDefault(); console.warn("[kora-demo]", e.reason); });

function boot() {
  const params = new URLSearchParams(location.search);
  const fromUrl = (params.get("code") || "").trim();
  if (fromUrl) {
    store.set(fromUrl);
    // Keep the code out of the address bar so a screenshot or screen share does not leak it.
    params.delete("code");
    const q = params.toString();
    try { history.replaceState(null, "", location.pathname + (q ? `?${q}` : "") + location.hash); } catch { /* ignore */ }
  }
  const code = fromUrl || store.get();
  state = initialState({ code });
  el.codeInput.value = code;
  render({ ...state, phase: "x" }, state);

  if (!audioSupported() || (window.isSecureContext === false)) {
    state = { ...state, phase: PHASE.ERROR, error: { kind: ERROR_KIND.UNSUPPORTED, message: window.isSecureContext === false
      ? "Your browser blocks the microphone on insecure pages. Open this page over HTTPS, in Chrome or Safari." : "This browser can't use the microphone or Web Audio. Try current Chrome or Safari." } };
    render({ ...state, phase: "x" }, state);
    return;
  }
  if (code) {
    dispatch({ type: "submit-code", code });
    connect();
  }
}
boot();
