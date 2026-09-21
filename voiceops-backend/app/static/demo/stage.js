// Stage (projector) view: shows the QR for the customer page and mirrors the call live.

import { Connection } from "./js/connection.js";
import { Orb } from "./js/orb.js";
import { backoffDelay, formatDuration, parseServerMessage, socketUrl } from "./js/protocol.js";
import { encodeQr, toPath } from "./js/qr.js";
import { STAGE, initialStage, stageReduce } from "./js/stage-state.js";

const $ = (id) => document.getElementById(id);
const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
const KEYS = { code: "kora-stage-code", base: "kora-stage-base" };
const ls = {
  get(k) { try { return localStorage.getItem(k) || ""; } catch { return ""; } },
  set(k, v) { try { v ? localStorage.setItem(k, v) : localStorage.removeItem(k); } catch { /* ignore */ } },
};

const params = new URLSearchParams(location.search);
let code = (params.get("code") || ls.get(KEYS.code)).trim();
let base = ls.get(KEYS.base) || `${location.origin}${location.pathname.replace(/[^/]*$/, "")}`.replace(/\/$/, "");
if (params.get("base")) base = params.get("base").replace(/\/$/, "");

let st = initialStage();
let conn = null;
let attempt = 0;
let timer = 0;

const orb = new Orb($("orb"), { size: 360, reducedMotion: reduced.matches });
orb.setLevelSource(() => (st.speaking ? 0.35 + 0.25 * Math.sin(performance.now() / 110) : st.phase === STAGE.LIVE ? 0.08 : 0));
orb.start();

function customerUrl() {
  const b = base.replace(/\/$/, "");
  return `${b}/customer.html?code=${encodeURIComponent(code)}`;
}

function drawQr() {
  const card = $("qrCard");
  if (!code) { card.hidden = true; $("linkText").textContent = "Open Setup and enter the demo code."; $("setup").open = true; return; }
  card.hidden = false;
  const url = customerUrl();
  try {
    const q = encodeQr(url);
    const n = q.size + 8;
    $("qr").setAttribute("viewBox", `0 0 ${n} ${n}`);
    $("qrPath").setAttribute("d", toPath(q.modules, 4));
    $("linkText").textContent = url.replace(/\?code=.*/, "");
  } catch {
    $("qrPath").setAttribute("d", "");
    $("linkText").textContent = "That address is too long to fit in a QR code.";
  }
  $("codeText").textContent = code;
}

const LABEL = {
  [STAGE.CONNECTING]: ["Connecting", "reconnecting"],
  [STAGE.WAITING]: ["Waiting for a customer to join", "ok"],
  [STAGE.RINGING]: ["Ringing the customer", "ok"],
  [STAGE.LIVE]: ["Live call", "ok"],
  [STAGE.ENDED]: ["Call finished", "ok"],
};

function render() {
  document.body.dataset.stage = st.phase;
  const [text, state] = LABEL[st.phase];
  $("stateText").textContent = st.error || text;
  $("statePill").dataset.state = st.error ? "reconnecting" : state;
  $("title").textContent =
    st.phase === STAGE.RINGING ? `Calling ${st.ring && st.ring.customerName ? st.ring.customerName : "the customer"}…`
    : st.phase === STAGE.LIVE ? "Kora is on the line"
    : st.phase === STAGE.ENDED ? "Call finished"
    : "Scan to take Kora’s call";
  $("timer").hidden = st.phase !== STAGE.LIVE;
  orb.setMood(st.phase === STAGE.RINGING ? "ringing" : st.phase === STAGE.LIVE ? (st.speaking ? "speaking" : "listening") : st.phase === STAGE.ENDED ? "done" : "waiting");

  const box = $("captions");
  box.hidden = st.phase === STAGE.ENDED && st.summary !== null;
  box.replaceChildren(...st.captions.lines.slice(-4).map((l) => {
    const d = document.createElement("div");
    d.className = `cap cap--${l.speaker}${l.final ? " is-final" : ""}${l.interrupted ? " is-interrupted" : ""}`;
    const who = document.createElement("span");
    who.className = "cap__who";
    who.textContent = l.speaker === "agent" ? "Kora" : "Customer";
    const p = document.createElement("p");
    p.className = "cap__text";
    p.textContent = l.text;
    d.append(who, p);
    return d;
  }));

  const showSummary = st.phase === STAGE.ENDED && st.summary;
  $("summary").hidden = !showSummary;
  if (showSummary) {
    $("sumHead").textContent = st.summary.headline;
    $("sumPoints").replaceChildren(...st.summary.points.map((t) => Object.assign(document.createElement("li"), { textContent: t })));
  }
}

function tick() {
  $("timer").textContent = st.startedAt ? formatDuration((performance.now() - st.startedAt) / 1000) : "0:00";
}
timer = setInterval(tick, 500);

function connect() {
  if (!code) return;
  if (!conn) {
    conn = new Connection(socketUrl(location, "/ws/demo/stage"), {
      onOpen: () => conn.sendJson({ type: "hello", code }),
      onJson(data) {
        const msg = parseServerMessage(data);
        if (msg && msg.event === "waiting") attempt = 0;
        st = stageReduce(st, msg, performance.now());
        render();
      },
      onAudio() {},
      onClose(closeCode) {
        if (closeCode === 4401) {
          st = { ...st, error: "Wrong demo code" };
          render();
          $("setup").open = true;
          return;
        }
        st = { ...st, phase: st.phase === STAGE.LIVE ? st.phase : STAGE.CONNECTING };
        render();
        setTimeout(connect, backoffDelay(attempt++));
      },
    });
  }
  conn.connect();
}

$("setupForm").addEventListener("submit", (e) => {
  e.preventDefault();
  code = $("codeInput").value.trim();
  base = ($("baseInput").value.trim() || base).replace(/\/$/, "");
  ls.set(KEYS.code, code);
  ls.set(KEYS.base, base);
  st = initialStage();
  attempt = 0;
  drawQr();
  render();
  if (conn) conn.close();
  connect();
});

$("codeInput").value = code;
$("baseInput").value = base;
if (params.get("code")) ls.set(KEYS.code, code);
drawQr();
render();
connect();
