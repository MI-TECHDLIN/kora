/* Kora landing page: wiring. Plain ES modules, no framework, no network calls beyond the page's own files. */

import { CONFIG } from "./config.js";
import { Orb, MOODS, MOOD_LABELS } from "./orb.js";
import { Phone, ic } from "./phone.js";
import { PROMPTS, ask, attach } from "./flows.js";

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const reduceMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ------------------------------------------------------------ Android CTA */

function initAndroidCta() {
  const url = (CONFIG.androidUrl || "").trim();
  const soon = !url;
  for (const a of $$("[data-android-cta]")) {
    const main = a.hasAttribute("data-android-main");
    if (soon) {
      if (main) {
        a.removeAttribute("href");
        a.setAttribute("aria-disabled", "true");
        a.classList.add("is-soon");
        const label = $("[data-android-label]", a);
        if (label) label.textContent = "Android build: coming soon";
        a.insertAdjacentHTML("beforeend", '<span class="soon-badge">Soon</span>');
      }
    } else if (main) {
      a.href = url;
      a.setAttribute("rel", "noopener");
      $("[data-android-label]", a).textContent = "Download the Android build";
    } else {
      a.href = url;
      a.setAttribute("rel", "noopener");
    }
  }
  for (const n of $$("[data-android-note]")) {
    n.textContent = soon
      ? n.closest(".cta")
        ? "The download link goes live with the first release."
        : "Android build coming soon. The phone preview follows the app's real flow, scripted in your browser."
      : n.closest(".cta")
        ? "Android only for now. Sideload the APK when your device asks."
        : "Android build available. The phone preview follows the app's real flow, scripted in your browser.";
  }
}

/* ------------------------------------------------------------------ nav */

function initNav() {
  const nav = $("[data-nav]");
  const onScroll = () => nav.classList.toggle("is-stuck", window.scrollY > 12);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
}

/* --------------------------------------------------------- reveal on scroll */

function initReveal() {
  const items = $$(".reveal");
  if (!("IntersectionObserver" in window) || reduceMotion()) {
    items.forEach((n) => n.classList.add("is-in"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.classList.add("is-in");
        io.unobserve(e.target);
      }
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0.12 },
  );
  items.forEach((n) => io.observe(n));
  // Hold-and-play animations that should start when seen.
  const seen = new IntersectionObserver(
    (entries) =>
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add("is-in");
          seen.unobserve(e.target);
        }
      }),
    { threshold: 0.3 },
  );
  $$("[data-parallel]").forEach((n) => seen.observe(n));
}

/* ----------------------------------------------------------- orb canvases */

function initOrbs() {
  for (const c of $$("canvas[data-orb]")) {
    new Orb(c, { material: c.dataset.material || "chrome", mood: c.dataset.mood || "idle" });
  }
  const row = $("[data-moods]");
  if (!row) return;
  row.innerHTML = Object.keys(MOODS)
    .map(
      (m) =>
        `<li><canvas class="orb orb--sm" data-mood="${m}" width="72" height="72" aria-hidden="true"></canvas><span>${m}</span><small>${MOOD_LABELS[m] || "Resting"}</small></li>`,
    )
    .join("");
  $$("canvas", row).forEach((c) => new Orb(c, { mood: c.dataset.mood, motes: false }));
}

/* -------------------------------------------------------------- phones */

const PHONE_W = 404;
const PHONE_H = 836;

function fitPhone(stage) {
  const phone = $(".phone", stage);
  const apply = () => {
    const s = stage.clientWidth / PHONE_W;
    if (!s) return;
    phone.style.setProperty("--s", s.toFixed(4));
    stage.style.height = Math.round(PHONE_H * s) + "px";
  };
  apply();
  if ("ResizeObserver" in window) new ResizeObserver(apply).observe(stage);
  else window.addEventListener("resize", apply);
}

const TRACE_MAX = 80;
function traceLine(evt) {
  const short = (s, n = 54) => (s.length > n ? s.slice(0, n - 1) + "…" : s);
  switch (evt.event) {
    case "transcript":
      return [evt.event, `${evt.role}: “${short(evt.text)}”`];
    case "agent_state":
      return [evt.event, evt.state];
    case "task_step":
      return [evt.event, `${evt.step} · ${evt.status}${evt.reasoning ? " · " + short(evt.reasoning, 44) : ""}`];
    case "screen_navigate":
      return [evt.event, evt.screen];
    case "map_route":
      return [evt.event, `stop ${evt.stop.sequence} · ${evt.route.distance_km} km · ${evt.route.duration_mins} min`];
    case "call_started":
      return [evt.event, `stop ${evt.sequence} · ${evt.customer_name}`];
    case "call_ended":
      return [evt.event, "ended"];
    case "order_offer":
      return [evt.event, `${evt.distance_km} km · ${evt.time_window} · ${evt.package_count} packages`];
    case "order_offer_closed":
      return [evt.event, evt.outcome];
    case "queue_updated":
      return [evt.event, `${evt.completed} done · ${evt.active + evt.pending} open`];
    case "preference":
      return ["set_preference", `${evt.key} = ${evt.value}`];
    case "reply_done":
      return [evt.event, ""];
    default:
      return null;
  }
}

function initPhones() {
  const phones = {};
  const build = (root) => {
    const phone = new Phone(root);
    fitPhone(root.closest("[data-phone-stage]"));
    return phone;
  };

  const heroRoot = $('[data-phone="hero"]');
  const hero = build(heroRoot);
  phones.hero = hero;

  /* Hero controls */
  const heroTry = $('[data-try="hero"]');
  const chips = $("[data-prompts]", heroTry);
  chips.innerHTML = PROMPTS.map(
    (p) =>
      `<button type="button" class="chip chip--${p.accent}${p.secondary ? " chip--2" : ""}" data-id="${p.id}"><span class="chip__disc">${ic(p.icon, "i--sm")}</span><span>${p.text}</span></button>`,
  ).join("");
  const input = $("input", heroTry);
  const form = $("[data-ask]", heroTry);

  let promptIdx = 0;
  const nextPrompt = () => PROMPTS[promptIdx++ % 4].text;
  attach(hero, { nextPrompt });

  const play = (text) => {
    const { id, done } = ask(hero, text);
    chips.querySelectorAll(".chip").forEach((c) => c.classList.toggle("is-on", c.dataset.id === id));
    done.finally(() => {
      if (!hero.busy) chips.querySelectorAll(".chip").forEach((c) => c.classList.remove("is-on"));
    });
    return { id, done };
  };
  chips.addEventListener("click", (e) => {
    const b = e.target.closest(".chip");
    if (!b) return;
    play(PROMPTS.find((p) => p.id === b.dataset.id).text);
  });
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    play(text);
  });
  hero.on((evt) => {
    if (evt.event !== "preview_hint") return;
    chips.classList.remove("nudge");
    void chips.offsetWidth;
    chips.classList.add("nudge");
  });
  $$("[data-reset]").forEach((b) =>
    b.addEventListener("click", () => phones[b.dataset.reset]?.reset()),
  );

  initMic(hero, form, input, play);

  /* Demo phone: built when it nears the viewport. */
  const demoRoot = $('[data-phone="demo"]');
  if (demoRoot) {
    const start = () => {
      const demo = build(demoRoot);
      phones.demo = demo;
      initStory(demo);
    };
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(
        (entries) => {
          if (entries.some((e) => e.isIntersecting)) {
            io.disconnect();
            start();
          }
        },
        { rootMargin: "600px 0px" },
      );
      io.observe(demoRoot.closest("[data-phone-stage]"));
    } else start();
  }
}

/* ------------------------------------------------------------- microphone */

/** Optional real speech input via the browser's Web Speech API. Never required. */
function initMic(phone, form, input, play) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const btn = $("[data-mic]", form);
  const note = $("[data-mic-note]", form.closest("[data-try]"));
  if (!SR || !btn) return;
  btn.hidden = false;
  note.hidden = false;
  note.textContent =
    "Mic is optional. It uses your browser's speech recognition, which may process audio on its provider's servers. The simulation itself makes no requests.";
  let rec = null;
  const stop = () => {
    rec?.stop();
  };
  const finish = (msg) => {
    btn.setAttribute("aria-pressed", "false");
    btn.classList.remove("is-live");
    if (!phone.busy) {
      phone.setPtt("idle");
      phone.setMood("idle");
    }
    if (msg) note.textContent = msg;
  };
  btn.addEventListener("click", () => {
    if (rec) return stop();
    rec = new SR();
    rec.lang = navigator.language || "en-US";
    rec.interimResults = true;
    rec.maxAlternatives = 1;
    let heard = "";
    rec.onstart = () => {
      btn.setAttribute("aria-pressed", "true");
      btn.classList.add("is-live");
      phone.runToken++;
      phone.busy = false;
      phone.setPtt("recording");
      note.textContent = "Listening… say one of the prompts, or ask in your own words.";
    };
    rec.onresult = (e) => {
      heard = [...e.results].map((r) => r[0].transcript).join(" ");
      input.value = heard;
    };
    rec.onerror = (e) => {
      const blocked = e.error === "not-allowed" || e.error === "service-not-allowed";
      finish(
        blocked
          ? "Microphone access is blocked. No problem: the prompts above work the same."
          : "Couldn't hear that. Try again, or tap a prompt.",
      );
    };
    rec.onend = () => {
      rec = null;
      const text = heard.trim();
      finish();
      if (text) {
        input.value = "";
        play(text);
      }
    };
    try {
      rec.start();
    } catch {
      rec = null;
      finish("Couldn't start the microphone. Tap a prompt instead.");
    }
  });
}

/* ---------------------------------------------------------- guided story */

const STORY = [
  { id: "next", title: "Find the next stop", say: "What's my next delivery?" },
  { id: "call", title: "Reach the customer", say: "Call the customer and tell them I'm arriving soon." },
  { id: "auto", title: "Let Kora take orders", say: "Accept nearby orders automatically." },
  { id: "progress", title: "Check the day", say: "How am I doing today?" },
];

function initStory(phone) {
  const list = $("[data-story]");
  const playBtn = $("[data-play]");
  const log = $("[data-trace]");
  const resetBtn = $('[data-reset="demo"]');
  list.innerHTML = STORY.map(
    (s, i) =>
      `<li><button type="button" data-i="${i}"><span class="story__n">${i + 1}</span><span class="story__t"><b>${s.title}</b><small>“${s.say}”</small></span></button></li>`,
  ).join("");

  let step = 0;
  attach(phone, { nextPrompt: () => STORY[step++ % STORY.length].say });

  let playing = false;
  let session = 0;
  const mark = (i) =>
    $$("button", list).forEach((b, k) => b.classList.toggle("is-on", k === i));
  const setPlaying = (on) => {
    playing = on;
    playBtn.querySelector("span").textContent = on ? "Stop" : "Play the shift";
    playBtn.querySelector("use").setAttribute("href", `assets/icons.svg#i-player-${on ? "pause" : "play"}`);
  };

  phone.on((evt) => {
    if (evt.event === "reset") {
      log.innerHTML = "";
      return;
    }
    const line = traceLine(evt);
    if (!line) return;
    const li = document.createElement("div");
    li.className = "ev ev--" + evt.event;
    li.innerHTML = `<span class="ev__n"></span><span class="ev__d"></span>`;
    li.firstChild.textContent = line[0];
    li.lastChild.textContent = line[1];
    log.appendChild(li);
    while (log.children.length > TRACE_MAX) log.firstChild.remove();
    log.scrollTop = log.scrollHeight;
  });

  list.addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b) return;
    session++;
    setPlaying(false);
    const i = +b.dataset.i;
    mark(i);
    ask(phone, STORY[i].say);
  });

  playBtn.addEventListener("click", async () => {
    if (playing) {
      session++;
      setPlaying(false);
      return;
    }
    const mine = ++session;
    setPlaying(true);
    phone.reset();
    for (let i = 0; i < STORY.length; i++) {
      if (mine !== session) return;
      mark(i);
      await ask(phone, STORY[i].say).done;
      if (mine !== session) return;
      await new Promise((r) => setTimeout(r, reduceMotion() ? 300 : 1500));
    }
    if (mine === session) setPlaying(false);
    mark(-1);
  });

  resetBtn.addEventListener("click", () => {
    session++;
    setPlaying(false);
    mark(-1);
  });
}

/* ------------------------------------------------------------------ media */

/**
 * Screenshot and clip slots: figure[data-media="<id>"] holds a placeholder.
 * assets/media/manifest.json says which file belongs to which id; when the
 * file exists it replaces the placeholder, otherwise the placeholder stays.
 */
async function initMedia() {
  const slots = $$("[data-media]");
  if (!slots.length) return;
  let manifest;
  try {
    const res = await fetch("assets/media/manifest.json", { cache: "no-cache" });
    if (!res.ok) return;
    manifest = await res.json();
  } catch {
    return;
  }
  const items = new Map((manifest.items || []).map((i) => [i.id, i]));

  const mount = (fig, item) => {
    const ph = $(".media__ph", fig);
    const ratio = `${item.width} / ${item.height}`;
    if (item.type === "image") {
      const img = new Image();
      img.alt = item.alt || "";
      img.decoding = "async";
      img.width = item.width;
      img.height = item.height;
      img.className = "media__el";
      img.onload = () => {
        fig.style.setProperty("--ratio", ratio);
        fig.classList.add("has-media");
        ph.replaceWith(img);
      };
      img.src = item.src;
    } else {
      const v = document.createElement("video");
      v.className = "media__el";
      v.muted = true;
      v.loop = true;
      v.playsInline = true;
      v.preload = "metadata";
      v.setAttribute("aria-label", item.alt || "");
      // Try the MP4 first and fall back to the WebM only if it is missing, so a
      // slot that has no file yet costs one request rather than three.
      const sources = [item.src, item.webm].filter(Boolean);
      let tried = 0;
      v.addEventListener("error", () => {
        if (++tried < sources.length) v.src = sources[tried];
      });
      v.addEventListener("loadedmetadata", () => {
        if (item.poster) v.poster = item.poster;
        fig.classList.add("has-media");
        ph.replaceWith(v);
        if (reduceMotion()) v.controls = true;
        else
          new IntersectionObserver(
            (es) => es.forEach((e) => (e.isIntersecting ? v.play().catch(() => {}) : v.pause())),
            { threshold: 0.4 },
          ).observe(v);
      });
      v.src = sources[0];
    }
  };

  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        io.unobserve(e.target);
        const item = items.get(e.target.dataset.media);
        if (item) mount(e.target, item);
      }
    },
    { rootMargin: "300px" },
  );
  slots.forEach((s) => io.observe(s));
}

/* ------------------------------------------------------------------ boot */

initAndroidCta();
initNav();
initReveal();
initOrbs();
initPhones();
initMedia();
