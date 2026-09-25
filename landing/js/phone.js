/*
 * A phone-frame recreation of the Kora app, driven by scripted flows.
 *
 * Everything here is client-side. There is no backend, no API key and no
 * network call. The screens copy the Flutter widgets they stand in for:
 *   Voice    lib/features/voice/screens/voice_screen.dart, widgets/next_orders_card.dart
 *   Map      lib/features/map/widgets/route_card.dart
 *   Summary  lib/features/summary/screens/summary_screen.dart + widgets/*
 *   Settings lib/features/settings/widgets/auto_accept_preferences_card.dart
 *   Overlays lib/overlays/task_progress_card.dart, order_offer_card.dart, voice_overlay.dart
 *   Push-to-talk lib/core/widgets/push_to_talk_button.dart
 * and the copy for task steps and reasoning follows the relay's own strings
 * (voiceops-backend/app/api/websocket/events.py, reasoning.py).
 *
 * The phone emits the same event names the real WebSocket sends
 * (docs/contracts/interface.md) so the demo section can show the trace.
 */

import { Orb, MOOD_LABELS } from "./orb.js";

const reduceMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export const ic = (name, cls = "") =>
  `<svg class="i ${cls}" aria-hidden="true" focusable="false"><use href="assets/icons.svg#i-${name}"/></svg>`;

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

class Cancelled extends Error {}

/** Neutral sample data: generic names, addresses, metric units, 24h times. */
const seedQueue = () => [
  { seq: 9, name: "Alex K.", address: "12 Central Avenue, Unit 4", window: "14:00–15:00", eta: 9, done: false },
  { seq: 10, name: "Mika T.", address: "87 Park Lane", window: "14:30–15:30", eta: 14, done: false },
  { seq: 11, name: "Robin S.", address: "3 Station Road", window: "15:00–16:00", eta: 19, done: false },
  { seq: 12, name: "Noa L.", address: "41 Orchard Street", window: "15:15–16:15", eta: 24, done: false },
  { seq: 13, name: "Sam D.", address: "9 Harbor Road", window: "15:30–16:30", eta: 31, done: false },
];
const BASE_COMPLETED = 8;
const OFFER = { id: "ord-2041", area: "Riverside Drive area", km: 1.2, window: "16:00–17:00", packages: 2 };

/* Map artwork: a stylised street grid in the OpenFreeMap dark palette. */
const ROADS_X = [40, 120, 200, 285, 350];
const ROADS_Y = [130, 210, 300, 400, 500, 600];
const ROUTE_D = "M120 400 L120 300 L200 300 L200 210 L285 210 L285 130";
const DRIVER = { x: 120, y: 400 };
const STOPS = [
  { seq: 9, x: 285, y: 130, active: true },
  { seq: 10, x: 40, y: 210 },
  { seq: 11, x: 200, y: 130 },
  { seq: 12, x: 350, y: 300 },
];

function mapSvg() {
  const roads =
    ROADS_X.map((x) => `<line x1="${x}" y1="0" x2="${x}" y2="812" class="road${x === 200 ? " road--main" : ""}"/>`).join("") +
    ROADS_Y.map((y) => `<line x1="0" y1="${y}" x2="380" y2="${y}" class="road${y === 300 ? " road--main" : ""}"/>`).join("");
  const xs = [-20, ...ROADS_X, 400];
  const ys = [-20, ...ROADS_Y, 830];
  let blocks = "";
  for (let i = 0; i < xs.length - 1; i++)
    for (let j = 0; j < ys.length - 1; j++)
      blocks += `<rect x="${xs[i] + 7}" y="${ys[j] + 7}" width="${xs[i + 1] - xs[i] - 14}" height="${ys[j + 1] - ys[j] - 14}" rx="5" class="block"/>`;
  const stops = STOPS.map(
    (s) =>
      `<g class="stop${s.active ? " stop--active" : ""}" data-stop="${s.seq}" transform="translate(${s.x} ${s.y})">` +
      `<circle r="${s.active ? 22 : 17}" class="stop__disc"/><text class="stop__n" y="${s.active ? 6 : 5}" text-anchor="middle">${s.seq}</text></g>`,
  ).join("");
  return `
  <svg class="p-map" viewBox="0 0 380 812" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
    <rect width="380" height="812" fill="#0c0c0c"/>
    <path d="M0 640 C 90 620 150 690 260 700 S 380 760 380 780 L380 812 L0 812Z" class="water"/>
    <rect x="212" y="410" width="128" height="80" rx="8" class="park"/>
    <rect x="52" y="312" width="58" height="78" rx="6" class="park"/>
    <g class="blocks">${blocks}</g>
    <g>${roads}</g>
    <text x="206" y="322" class="maplabel">Central Avenue</text>
    <text x="8" y="296" class="maplabel">Park Lane</text>
    <text x="216" y="516" class="maplabel">Station Road</text>
    <g class="route" data-el="route">
      <path d="${ROUTE_D}" class="route__casing" pathLength="1"/>
      <path d="${ROUTE_D}" class="route__line" pathLength="1" data-el="routeLine"/>
      ${stops}
    </g>
    <g transform="translate(${DRIVER.x} ${DRIVER.y})">
      <circle r="22" class="me__halo"/><circle r="9" class="me__dot"/>
    </g>
  </svg>`;
}

function template() {
  return `
  <div class="phone__bezel">
    <div class="phone__screen" data-el="screen" data-tab="voice">
      <div class="p-bg" aria-hidden="true"><i></i><i></i><i></i><i></i></div>

      <!-- Voice -->
      <section class="ps ps--voice" data-screen="voice" aria-label="Voice screen">
        <div class="ps__scroll" data-el="voiceScroll">
          <div class="pcard pcard--status">
            <div class="prow">
              <span class="pcap">${ic("route", "i--sm i--light")}<span data-bind="shiftLabel">SHIFT ACTIVE</span></span>
              <span class="p-avatar">${ic("user-circle", "i--lg")}</span>
            </div>
            <div class="p-orbwrap"><canvas class="p-orb" data-el="orbMain" aria-hidden="true"></canvas></div>
            <div class="p-title p-title--center" data-bind="stateLabel">Ready when you are</div>
            <hr class="p-divider"/>
            <div data-el="nextStop"></div>
          </div>
          <div class="pcard pcard--target" data-el="targetInd"></div>
          <div class="pcard" data-el="nextOrders"></div>
          <div class="pcard" data-el="convo"></div>
        </div>
        <div class="p-pttblock">
          <button type="button" class="ptt" data-el="ptt" data-state="idle" aria-label="Push to talk">
            <span class="ptt__halo" aria-hidden="true"></span>
            <span class="ptt__icons" aria-hidden="true">
              <span data-i="idle">${ic("microphone", "i--xl")}</span>
              <span data-i="recording">${ic("microphone-f", "i--xl")}</span>
              <span data-i="processing">${ic("loader-2", "i--xl")}</span>
              <span data-i="speaking">${ic("wave-sine", "i--xl")}</span>
            </span>
          </button>
          <div class="pcap" data-bind="pttHint">Tap to talk to your co-rider</div>
        </div>
      </section>

      <!-- Map -->
      <section class="ps ps--map" data-screen="map" aria-label="Map screen" inert>
        ${mapSvg()}
        <div class="p-routecard glass" data-el="routeCard"></div>
      </section>

      <!-- Summary -->
      <section class="ps ps--summary" data-screen="summary" aria-label="Summary screen" inert>
        <div class="ps__scroll ps__scroll--pad" data-el="summaryScroll">
          <div class="p-headline">Your shift summary</div>
          <div class="pcard glass" data-el="overview"></div>
          <div class="pcard glass" data-el="targetCard"></div>
          <div class="pcard glass" data-el="queueCard"></div>
        </div>
      </section>

      <!-- Settings -->
      <section class="ps ps--settings" data-screen="settings" aria-label="Settings screen" inert>
        <div class="ps__scroll ps__scroll--pad" data-el="settingsScroll">
          <div class="p-headline">Settings</div>
          <div class="pcap pcap--gap">YOUR VEHICLE</div>
          <div class="pcard glass pcard--choices">
            <span class="choice choice--on">${ic("bike", "i--sm")}Motorbike</span>
            <span class="choice">${ic("truck-delivery", "i--sm")}Car</span>
            <span class="choice">${ic("bike", "i--sm")}Bicycle</span>
            <span class="choice">${ic("route", "i--sm")}Walking</span>
          </div>
          <div class="pcap pcap--gap">AUTO-ACCEPT ORDERS</div>
          <div class="pcard glass" data-el="autoCard"></div>
          <div class="pcap pcap--gap">HANDS-FREE VOICE</div>
          <div class="pcard glass pcard--row">
            <div class="grow"><div class="p-label">“Kora” wake word</div><div class="p-muted">Say a trained Kora phrase while the app is open</div></div>
            <span class="switch switch--on" aria-hidden="true"></span>
          </div>
        </div>
      </section>

      <!-- Overlays: co-rider bubble on other tabs, caption, call, offer, task progress -->
      <div class="p-bubble" data-el="bubble" aria-hidden="true"><canvas data-el="orbBubble"></canvas></div>
      <div class="p-caption glass" data-el="caption" hidden></div>
      <div class="p-top" data-el="top"></div>
      <div class="p-task" data-el="task" aria-live="polite"></div>

      <nav class="p-nav glass" aria-label="Kora app tabs">
        <button type="button" class="p-nav__i is-active" data-tab="voice" aria-label="Voice" aria-pressed="true">${ic("microphone", "i--lg")}</button>
        <button type="button" class="p-nav__i" data-tab="map" aria-label="Map" aria-pressed="false">${ic("map-2", "i--lg")}</button>
        <button type="button" class="p-nav__i" data-tab="summary" aria-label="Summary" aria-pressed="false">${ic("chart-bar", "i--lg")}</button>
        <button type="button" class="p-nav__i" data-tab="settings" aria-label="Settings" aria-pressed="false">${ic("settings", "i--lg")}</button>
      </nav>

      <div class="p-statusbar" aria-hidden="true">
        <span>09:41</span><span class="p-cam"></span>
        <span class="p-sys"><i class="p-sig"></i><i class="p-bat"></i></span>
      </div>
      <div class="p-gesture" aria-hidden="true"></div>
    </div>
  </div>
  <p class="sr-only" data-el="sr" aria-live="polite"></p>`;
}

export class Phone {
  /**
   * @param {HTMLElement} root the .phone element (empty)
   */
  constructor(root) {
    this.root = root;
    root.innerHTML = template();
    this.el = {};
    root.querySelectorAll("[data-el]").forEach((n) => (this.el[n.dataset.el] = n));
    this.binds = {};
    root.querySelectorAll("[data-bind]").forEach((n) => (this.binds[n.dataset.bind] = n));
    this.listeners = new Set();
    this.runToken = 0;
    this.busy = false;
    this.orbMain = new Orb(this.el.orbMain, { material: "chrome" });
    this.orbBubble = new Orb(this.el.orbBubble, { material: "chrome", motes: false });
    this.reset(false);

    root.querySelectorAll(".p-nav__i").forEach((b) =>
      b.addEventListener("click", () => this.setTab(b.dataset.tab)),
    );
    // Delegated clicks for controls that live in re-rendered markup.
    root.addEventListener("click", (e) => {
      const t = e.target.closest("[data-act]");
      if (!t) return;
      const act = t.dataset.act;
      if (act === "accept") this.respondToOffer(true);
      else if (act === "decline") this.respondToOffer(false);
      else if (act === "end-call") this.endCall();
      else if (act === "complete") this.completeActive();
      else if (act === "toggle-auto") this.setAutoAccept(!this.s.autoAccept, "touch");
      else if (act === "toggle-card") {
        this.s.cardOpen = !this.s.cardOpen;
        this.renderRouteCard();
      }
    });
    this.el.ptt.addEventListener("click", () => this.onPttTap?.());
  }

  /* ------------------------------------------------------------------ state */

  reset(announce = true) {
    this.runToken++;
    clearInterval(this.offerTimer);
    clearTimeout(this.taskTimer);
    clearTimeout(this.callTimer);
    this.s = {
      tab: "voice",
      mood: "idle",
      ptt: "idle",
      route: false,
      autoAccept: false,
      target: 15,
      queue: seedQueue(),
      lines: [],
      steps: [],
      offer: null,
      offerNotice: null,
      call: null,
      sms: null,
      caption: null,
      cardOpen: true,
      nextSeq: 14,
    };
    this.busy = false;
    this.setTabInstant("voice");
    this.renderAll();
    this.el.voiceScroll.scrollTo({ top: 0 });
    this.orbMain.setMood("idle");
    this.orbBubble.setMood("idle");
    this.setPtt("idle");
    if (announce) this.emit({ event: "reset" });
  }

  get counts() {
    const pending = this.s.queue.filter((o) => !o.done).length;
    const completed = BASE_COMPLETED + this.s.queue.filter((o) => o.done).length;
    return { completed, active: pending > 0 ? 1 : 0, pending: Math.max(0, pending - 1), total: completed + pending };
  }
  get active() {
    return this.s.queue.find((o) => !o.done) || null;
  }

  on(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
  emit(evt) {
    for (const fn of this.listeners) fn(evt);
  }

  /* ---------------------------------------------------------------- helpers */

  wait(ms) {
    const token = this.runToken;
    const scaled = reduceMotion() ? Math.min(ms, 350) : ms;
    return new Promise((resolve, reject) => {
      setTimeout(() => (token === this.runToken ? resolve() : reject(new Cancelled())), scaled);
    });
  }

  setTabInstant(tab) {
    this.s.tab = tab;
    this.el.screen.dataset.tab = tab;
    this.root.querySelectorAll(".ps").forEach((sec) => {
      const on = sec.dataset.screen === tab;
      sec.classList.toggle("is-active", on);
      sec.toggleAttribute("inert", !on);
    });
    this.root.querySelectorAll(".p-nav__i").forEach((b) => {
      const on = b.dataset.tab === tab;
      b.classList.toggle("is-active", on);
      b.setAttribute("aria-pressed", String(on));
    });
    this.renderCaption();
  }
  setTab(tab, viaVoice = false) {
    if (this.s.tab === tab) return;
    this.setTabInstant(tab);
    if (viaVoice) this.emit({ event: "screen_navigate", screen: tab });
  }

  setMood(mood) {
    this.s.mood = mood;
    this.orbMain.setMood(mood);
    this.orbBubble.setMood(mood);
    this.binds.stateLabel.textContent = MOOD_LABELS[mood] || "Ready when you are";
    this.emit({ event: "agent_state", state: mood });
  }

  setPtt(state) {
    this.s.ptt = state;
    this.el.ptt.dataset.state = state;
    const labels = {
      idle: "Push to talk",
      recording: "Recording. Tap to stop",
      processing: "Working on it",
      speaking: "Co-rider speaking. Tap to interrupt",
    };
    this.el.ptt.setAttribute("aria-label", labels[state]);
    this.binds.pttHint.textContent = {
      idle: "Tap to try the next prompt",
      recording: "Listening · tap to end",
      processing: "Working on it…",
      speaking: "Tap to interrupt",
    }[state];
  }

  /* ------------------------------------------------------------------ steps */

  /** Applies one task_step like TaskProgressNotifier.applyStep. */
  step(label, status, reasoning) {
    clearTimeout(this.taskTimer);
    const steps = this.s.steps;
    const finished = steps.length > 0 && steps.every((x) => x.status === "done");
    const i = steps.findIndex((x) => x.label === label);
    if (i === -1) this.s.steps = [...(finished ? [] : steps), { label, status, reasoning }];
    else steps[i] = { label, status, reasoning: reasoning ?? steps[i].reasoning };
    this.renderTask();
    const evt = { event: "task_step", step: label, status };
    if (reasoning) evt.reasoning = reasoning;
    this.emit(evt);
    if (this.s.steps.every((x) => x.status === "done")) {
      this.taskTimer = setTimeout(() => {
        this.s.steps = [];
        this.renderTask();
      }, 3600);
    }
  }

  /* ---------------------------------------------------------- conversation */

  addLine(role, text = "") {
    this.s.lines.push({ role, text });
    if (this.s.lines.length > 8) this.s.lines.shift();
    this.renderConvo(true);
    return this.s.lines[this.s.lines.length - 1];
  }

  async say(role, text) {
    // Driver lines type fast (mic hot); the co-rider's are paced like speech.
    const line = this.addLine(role);
    const words = text.split(" ");
    const per = role === "driver" ? 55 : 95;
    for (let i = 1; i <= words.length; i++) {
      line.text = words.slice(0, i).join(" ");
      this.s.caption = { role, text: line.text };
      this.renderConvo();
      this.renderCaption();
      await this.wait(per);
    }
    if (role === "agent") this.el.sr.textContent = "Kora: " + text;
    this.emit({ event: "transcript", role, text });
  }

  /** The whole spoken turn: mic hot, transcribed, then processing. */
  async hear(text) {
    this.setPtt("recording");
    await this.wait(250);
    await this.say("driver", text);
    this.setPtt("processing");
    this.setMood("thinking");
    await this.wait(450);
    this.s.caption = null;
    this.renderCaption();
    await this.wait(250);
  }

  async speak(text) {
    // On Voice the caption takes the task card's place, so the card steps aside.
    if (this.s.tab === "voice") {
      clearTimeout(this.taskTimer);
      this.s.steps = [];
      this.renderTask();
    }
    this.setPtt("speaking");
    this.setMood("speaking");
    await this.say("agent", text);
    await this.wait(700);
    this.emit({ event: "reply_done" });
    this.s.caption = null;
    this.renderCaption();
    this.setMood("idle");
    this.setPtt("idle");
  }

  /* --------------------------------------------------------------- actions */

  setAutoAccept(on, via = "voice") {
    this.s.autoAccept = on;
    this.renderSettings();
    this.emit({ event: "preference", key: "auto_accept", value: on, via });
  }

  showRoute() {
    this.s.route = true;
    const line = this.root.querySelector('[data-el="routeLine"]');
    const route = this.root.querySelector('[data-el="route"]');
    route.classList.remove("is-drawn");
    void line.getBoundingClientRect();
    requestAnimationFrame(() => route.classList.add("is-drawn"));
    this.renderNextStop();
    this.renderRouteCard();
    this.emit({
      event: "map_route",
      stop: { sequence: 9, recipient_name: "Alex K.", address: "12 Central Avenue, Unit 4" },
      route: { distance_km: 2.4, duration_mins: 9 },
    });
  }

  openOffer(auto = false) {
    clearInterval(this.offerTimer);
    this.s.offerNotice = null;
    this.s.offer = { ...OFFER, remaining: 20, auto, status: "open" };
    this.renderTop();
    this.emit({
      event: "order_offer",
      order_id: OFFER.id,
      area: OFFER.area,
      distance_km: OFFER.km,
      time_window: OFFER.window,
      package_count: OFFER.packages,
      expires_in_seconds: 20,
    });
    if (auto) return;
    this.offerTimer = setInterval(() => {
      const o = this.s.offer;
      if (!o || o.status !== "open") return clearInterval(this.offerTimer);
      o.remaining -= 1;
      if (o.remaining <= 0) this.closeOffer("expired", "That offer ran out of time and went to the next driver.");
      else this.renderTop();
    }, 1000);
  }

  closeOffer(outcome, notice) {
    clearInterval(this.offerTimer);
    this.s.offer = null;
    this.s.offerNotice = notice;
    this.renderTop();
    this.emit({ event: "order_offer_closed", order_id: OFFER.id, outcome });
    clearTimeout(this.noticeTimer);
    this.noticeTimer = setTimeout(() => {
      this.s.offerNotice = null;
      this.renderTop();
    }, 4500);
  }

  dismissOffer() {
    clearInterval(this.offerTimer);
    this.s.offer = null;
    this.renderTop();
  }

  addAcceptedOrder() {
    const seq = this.s.nextSeq++;
    this.s.queue.push({ seq, name: "Riverside order", address: "Riverside Drive area", window: OFFER.window, eta: 36, done: false, isNew: true });
    this.renderQueueViews();
    this.emit({ event: "queue_updated", ...this.counts });
    return seq;
  }

  /** Manual Accept / Decline on the offer card. */
  respondToOffer(accept) {
    const o = this.s.offer;
    if (!o || o.status !== "open" || this.busy) return;
    this.handlers?.respond(accept);
  }

  hasOpenOffer() {
    return !!(this.s.offer && this.s.offer.status === "open");
  }

  completeActive() {
    const a = this.active;
    if (!a) return;
    a.done = true;
    if (this.s.route && a.seq === 9) this.s.route = false;
    this.renderAll();
    this.emit({ event: "queue_updated", ...this.counts });
  }

  endCall() {
    if (!this.s.call) return;
    clearTimeout(this.callTimer);
    this.s.call = null;
    this.renderTop();
    this.emit({ event: "call_ended", call_id: "sim-call" });
  }

  /* -------------------------------------------------------------------- run */

  /**
   * Runs one scripted turn. Starting another interrupts the current one,
   * like tapping the mic while the co-rider is speaking.
   */
  async run(script, spoken) {
    const token = ++this.runToken;
    this.busy = true;
    this.s.steps = [];
    clearTimeout(this.taskTimer);
    this.renderTask();
    this.s.caption = null;
    this.renderCaption();
    this.root.classList.add("is-running");
    try {
      await this.hear(spoken);
      await script();
    } catch (e) {
      if (!(e instanceof Cancelled)) throw e;
    } finally {
      if (token === this.runToken) {
        this.busy = false;
        this.root.classList.remove("is-running");
      }
    }
  }

  /* ---------------------------------------------------------------- render */

  renderAll() {
    this.renderNextStop();
    this.renderTarget();
    this.renderQueueViews();
    this.renderConvo();
    this.renderRouteCard();
    this.renderSettings();
    this.renderTop();
    this.renderTask();
    this.renderCaption();
    this.binds.stateLabel.textContent = MOOD_LABELS[this.s.mood] || "Ready when you are";
  }

  renderNextStop() {
    const a = this.active;
    const box = this.el.nextStop;
    if (!this.s.route || !a) {
      box.innerHTML = `<div class="prow prow--top">${ic("route-off", "i--lg i--muted")}<div><div class="p-label">No active route</div><div class="p-muted">Ask Kora when you’re ready for your next stop.</div></div></div>`;
      return;
    }
    box.innerHTML = `
      <div class="prow"><span class="pcap grow">NEXT STOP · ${a.seq}</span>${ic("clock", "i--sm i--muted")}<span class="p-label">${a.eta} min</span></div>
      <div class="p-headline p-headline--tight">${esc(a.name)}</div>
      <div class="p-muted">${esc(a.address)}</div>`;
  }

  renderTarget() {
    const { completed } = this.counts;
    const t = this.s.target;
    const label = `${completed} / ${t} deliveries`;
    const frac = Math.min(1, completed / t);
    if (!this.targetBuilt) {
      this.el.targetInd.innerHTML = `${ic("target", "i--md i--light")}<span class="p-label" data-t="label"></span><span class="meter meter--thin grow"><i data-t="fill"></i></span>`;
      this.targetBuilt = true;
    }
    this.el.targetInd.querySelector('[data-t="label"]').textContent = label;
    this.el.targetInd.querySelector('[data-t="fill"]').style.width = frac * 100 + "%";
  }

  renderQueueViews() {
    this.renderTarget();
    this.renderNextOrders();
    this.renderSummary();
  }

  renderNextOrders() {
    const pending = this.s.queue.filter((o) => !o.done);
    if (!pending.length) {
      this.el.nextOrders.hidden = true;
      return;
    }
    this.el.nextOrders.hidden = false;
    const shown = pending.slice(0, 3);
    const more = pending.length - shown.length;
    this.el.nextOrders.innerHTML = `
      <div class="prow"><span class="pcap grow">NEXT ORDERS</span>${ic("chevron-right", "i--md i--muted")}</div>
      ${shown
        .map((o, i) => {
          const act = i === 0;
          return `<div class="p-order${o.isNew ? " is-new" : ""}">${ic(act ? "route" : "circle", "i--md " + (act ? "i--light" : "i--muted"))}
            <div class="grow"><div class="${act ? "p-title" : "p-label"} ellip">${esc(o.name)}${act ? " · now" : ""}</div><div class="p-muted ellip">${esc(o.address)}</div></div>
            <span class="p-label p-faint">${o.window}</span></div>`;
        })
        .join("")}
      ${more > 0 ? `<div class="p-label p-muted" data-more>+ ${more} more</div>` : ""}`;
  }

  renderConvo(scroll = false) {
    const lines = this.s.lines.slice(-3);
    const box = this.el.convo;
    if (!lines.length) {
      box.innerHTML = `<div class="pcap">CONVERSATION</div><div class="p-order"><div><div class="p-label">No conversation yet</div><div class="p-muted">Your conversation with Kora will appear here.</div></div></div>`;
    } else {
      box.innerHTML =
        `<div class="pcap">CONVERSATION</div>` +
        lines
          .map(
            (l) =>
              `<div class="p-line"><div class="p-label${l.role === "agent" ? " p-accent" : ""}">${l.role === "driver" ? "You" : "Co-rider"}</div><div class="${l.role === "driver" ? "p-body p-muted" : "p-body"}">${esc(l.text)}</div></div>`,
          )
          .join("");
    }
    const sc = this.el.voiceScroll;
    if (scroll) sc.scrollTo({ top: 0 });
  }

  renderCaption() {
    const c = this.el.caption;
    const cap = this.s.caption;
    c.hidden = !cap;
    if (cap) {
      const agent = cap.role === "agent";
      c.innerHTML = `<span class="pcap${agent ? " pcap--accent" : ""}">${agent ? "CO-RIDER" : "YOU"}</span><span class="p-body">${esc(cap.text)}</span>`;
    }
    this.el.bubble.classList.toggle("is-on", this.s.tab !== "voice");
    // A long caption beside the bubble nudges the overlay stack down instead of covering it.
    const extra = cap && this.s.tab !== "voice" ? Math.max(0, c.offsetHeight - 66) : 0;
    this.el.screen.style.setProperty("--cap-x", extra + "px");
  }

  renderTask() {
    const steps = this.s.steps;
    const box = this.el.task;
    if (!steps.length) {
      box.classList.remove("is-on");
      return;
    }
    const done = steps.filter((x) => x.status === "done").length;
    const all = done === steps.length;
    const status = {
      pending: ["circle", "Pending", "pending"],
      active: ["loader-2", "In progress", "active"],
      done: ["circle-check", "Done", "done"],
    };
    box.innerHTML = `<div class="pcard glass task">
      <div class="prow">${ic(all ? "circle-check" : "sparkles", "i--md " + (all ? "i--ok" : "i--light"))}<span class="p-title grow">${all ? "Task complete" : "Co-rider working"}</span><span class="pcap">${done}/${steps.length}</span></div>
      ${steps
        .map((x) => {
          const [icon, text, cls] = status[x.status];
          return `<div class="tstep tstep--${cls}"><div class="p-title p-title--bold">${esc(x.label)}</div>${
            x.reasoning ? `<div class="${x.status === "done" ? "p-body p-reason-done" : "p-label p-reason-active"}">${esc(x.reasoning)}</div>` : ""
          }<div class="tstep__st">${ic(icon, "i--md" + (x.status === "active" ? " spin" : ""))}<span class="pcap">${text}</span></div></div>`;
        })
        .join("")}</div>`;
    box.classList.add("is-on");
  }

  renderTop() {
    const s = this.s;
    let html = "";
    if (s.call) {
      html += `<div class="pcard glass call" data-card="call">
        <span class="call__ic">${ic("phone-call", "i--lg i--light")}</span>
        <div class="grow"><div class="pcap">ON A CALL · STOP ${this.active ? this.active.seq : 9}</div><div class="p-title ellip">Calling ${esc(s.call.name)}</div></div>
        <button type="button" class="pbtn pbtn--ghost" data-act="end-call">End</button></div>`;
    }
    if (s.sms) {
      html += `<div class="pcard glass notice" data-card="sms">${ic("message-circle", "i--md i--light")}<div class="grow"><div class="pcap">MESSAGE SENT · ${esc(s.sms.name).toUpperCase()}</div><div class="p-label">“${esc(s.sms.text)}”</div></div></div>`;
    }
    if (s.offer) {
      const o = s.offer;
      html += `<div class="pcard glass offer${o.auto ? " offer--auto" : ""}${o.status === "accepted" ? " offer--done" : ""}" data-card="offer">
        <div class="prow">
          <span class="offer__ic">${ic("package", "i--lg i--light")}</span>
          <div class="grow"><div class="pcap">NEW DELIVERY OFFER</div><div class="p-title ellip">${o.area}</div></div>
          <span class="countdown">${o.status === "accepted" ? "Taken" : o.remaining > 0 ? o.remaining + "s" : "Closing…"}</span>
        </div>
        <div class="offer__chips">
          <span>${ic("route", "i--sm i--muted")}${o.km} km away</span>
          <span>${ic("clock", "i--sm i--muted")}${o.window}</span>
          <span>${ic("packages", "i--sm i--muted")}${o.packages} packages</span>
        </div>
        ${
          o.auto || o.status === "accepted"
            ? `<div class="offer__auto">${ic(o.status === "accepted" ? "circle-check" : "sparkles", "i--md i--ok")}<span class="p-label">${o.status === "accepted" ? (o.auto ? "Auto-accepted out loud" : "Accepted") : "Auto-accept is deciding…"}</span></div>`
            : `<div class="offer__btns"><button type="button" class="pbtn pbtn--outline" data-act="decline">Decline</button><button type="button" class="pbtn pbtn--violet" data-act="accept">Accept</button></div>`
        }</div>`;
    } else if (s.offerNotice) {
      html += `<div class="pcard glass notice">${ic("info-circle", "i--md i--light")}<span class="p-label grow">${esc(s.offerNotice)}</span></div>`;
    }
    this.el.top.innerHTML = html;
    // On Voice the overlay stack pushes the content down, so the orb stays in view.
    this.el.screen.style.setProperty("--top-h", (this.el.top.offsetHeight || 0) + "px");
  }

  renderRouteCard() {
    const a = this.active;
    const card = this.el.routeCard;
    const open = this.s.cardOpen;
    let head;
    if (!this.s.route || !a) {
      head = `<div class="pcap">NO ROUTE YET</div><div class="p-title">Ask your co-rider for directions</div><div class="p-muted">Say "take me to my next stop" and the route draws here.</div>`;
    } else {
      head = `<div class="prow"><span class="pcap grow">NEXT STOP · ${a.seq}</span><span class="pill">${ic("clock", "i--sm i--light")}${a.eta} min</span></div>
        <div class="p-headline p-headline--tight">${esc(a.name)}</div><div class="p-muted">${esc(a.address)}</div>`;
    }
    const stats =
      this.s.route && a && open
        ? `<div class="stats">
            <div class="stat">${ic("route", "i--md i--light")}<b>2.4 km</b><span class="pcap">Distance</span></div>
            <div class="stat">${ic("clock", "i--md i--light")}<b>${a.eta} min</b><span class="pcap">Drive time</span></div>
            <div class="stat">${ic("map-pins", "i--md i--light")}<b>${this.s.queue.filter((o) => !o.done).length}</b><span class="pcap">Stops</span></div>
          </div>
          <div class="prow prow--via">${ic("road-sign", "i--sm i--muted")}<span class="p-muted">via Central Avenue</span></div>`
        : "";
    card.innerHTML = `<button type="button" class="handle-btn" data-act="toggle-card" aria-label="${open ? "Show less" : "Show trip details"}" aria-expanded="${open}"><span class="handle"></span></button>${head}${stats}`;
  }

  renderSummary() {
    const { completed, active, pending, total } = this.counts;
    const t = this.s.target;
    const frac = total ? completed / total : 0;
    const tfrac = Math.min(1, completed / t);
    const left = Math.max(0, t - completed);

    // Overview + target keep their meters in the DOM so the fill animates.
    if (!this.summaryBuilt) {
      this.el.overview.innerHTML = `
        <div class="prow"><span class="pcap grow">TODAY'S ACTIVITY</span><span class="status"><i class="sdot"></i>Shift active</span></div>
        <div class="p-title" data-s="progress"></div>
        <div class="meter"><i data-s="shiftFill"></i></div>
        <div class="tiles">
          <div class="tile">${ic("circle-check", "i--md i--ok")}<b data-s="c">0</b><span class="pcap">Completed</span></div>
          <div class="tile">${ic("route", "i--md i--light")}<b data-s="a">0</b><span class="pcap">Active</span></div>
          <div class="tile">${ic("hourglass", "i--md i--amber")}<b data-s="p">0</b><span class="pcap">Pending</span></div>
        </div>
        <div class="p-muted">Your full shift summary is generated as you complete orders. Ask your co-rider "how did my shift go?" any time.</div>`;
      this.el.targetCard.innerHTML = `
        <div class="prow">${ic("target", "i--md i--light")}<span class="pcap grow">DAILY TARGET</span></div>
        <div class="p-title" data-s="tlabel"></div>
        <div class="meter"><i data-s="tFill"></i></div>
        <div class="p-muted" data-s="tleft"></div>`;
      this.summaryBuilt = true;
    }
    const q = (sel, root = this.root) => root.querySelector(`[data-s="${sel}"]`);
    q("progress").textContent = `${completed} of ${total} ${total === 1 ? "delivery" : "deliveries"} completed`;
    q("shiftFill").style.width = frac * 100 + "%";
    q("c").textContent = completed;
    q("a").textContent = active;
    q("p").textContent = pending;
    q("tlabel").textContent = `${completed} of ${t} target deliveries completed`;
    q("tFill").style.width = tfrac * 100 + "%";
    q("tleft").textContent = left === 0 ? "Target reached. Nice work today." : left === 1 ? "1 delivery to go" : `${left} deliveries to go`;

    const a = this.active;
    const pend = this.s.queue.filter((o) => !o.done).slice(1);
    this.el.queueCard.innerHTML = `
      <div class="prow"><span class="pcap grow">ORDER QUEUE</span>${ic("refresh", "i--md i--muted")}</div>
      ${
        a
          ? `<div class="active-order"><div class="pcap">ACTIVE · STOP ${a.seq}</div><div class="p-title">${esc(a.name)}</div>
              <div class="dl">${ic("map-pin", "i--sm i--muted")}<span class="p-muted">${esc(a.address)}</span></div>
              <div class="dl">${ic("clock", "i--sm i--muted")}<span class="p-muted">${a.window}</span></div>
              <div class="dl">${ic("route", "i--sm i--muted")}<span class="p-muted">${a.eta} min away</span></div>
              <button type="button" class="pbtn pbtn--violet pbtn--block" data-act="complete">${ic("check", "i--md")}Mark completed</button></div>`
          : `<div class="p-muted">No orders in your queue</div>`
      }
      ${pend.length ? `<div class="pcap pcap--gap">UP NEXT · ${pend.length}</div>` : ""}
      ${pend
        .map(
          (o) =>
            `<div class="p-order${o.isNew ? " is-new" : ""}">${ic("circle", "i--md i--muted")}<div class="grow"><div class="p-label">${o.seq}. ${esc(o.name)}</div><div class="p-muted">${esc(o.address)}</div><div class="p-label p-faint">${o.window}</div></div></div>`,
        )
        .join("")}`;
  }

  renderSettings() {
    const on = this.s.autoAccept;
    this.el.autoCard.innerHTML = `
      <div class="pcard--row">
        <div class="grow"><div class="p-label">Auto-accept orders</div><div class="p-muted">Let your co-rider take matching orders for you — always out loud, never silent</div></div>
        <button type="button" class="switch${on ? " switch--on" : ""}" role="switch" aria-checked="${on}" aria-label="Auto-accept orders" data-act="toggle-auto"></button>
      </div>
      ${
        on
          ? `<hr class="p-divider"/>
             <div class="prow"><div class="grow"><div class="p-label">Max pickup distance</div><div class="p-muted">Blank means no distance limit</div></div><span class="field">5 km</span></div>
             <div class="p-label pcap--gap">Preferred &amp; avoided areas</div>
             <div class="chips"><span class="choice choice--on">City center · 3 km</span><span class="choice">+ Add area</span></div>
             <div class="p-label pcap--gap">Order types</div>
             <div class="p-muted">Blank accepts every order type</div>
             <div class="chips"><span class="choice">+ Add type</span></div>`
          : ""
      }`;
  }
}
