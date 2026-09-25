/*
 * The co-rider orb, drawn on a canvas.
 *
 * A port of the app's drawn orb (frontend/lib/mascot/mascot_display.dart:
 * _OrbMood + _OrbPainter) with the moods from
 * docs/voiceops-corider-orb-rive-spec-v2.md and the palettes from
 * KoraOrbColors. A few drifting motes are added to echo the Rive "Nebula
 * Drift" direction. The .riv itself is not shipped: the Rive web runtime would
 * add a wasm download for a decoration, and the drawn orb is what the app falls
 * back to anyway.
 *
 * Lime is never used here: it means "mic is live" and belongs to the
 * push-to-talk button alone.
 */

const CHROME = ["#EDEBF5", "#8E8AA6", "#2B2740", "#D3CFE6", "#5E5A78", "#EDEBF5"];
const HOLOGRAPHIC = ["#C4B5FD", "#F9A8D4", "#7DD3FC", "#A7F3D0", "#C4B5FD"];
const PRIMARY = "#8B5CF6";
const PRIMARY_LIGHT = "#C4B5FD";
const SHADE = "rgba(7,6,11,"; // KoraOrbColors.shade (canvas), alpha appended

/** Mirrors _OrbMood.of(AgentState): tint, tint strength, halo, breaths/s, breath depth, spin rad/s. */
export const MOODS = {
  idle: { tint: PRIMARY, ts: 0, glow: 0.3, hz: 0.22, depth: 0.02, spin: 0.25 },
  thinking: { tint: PRIMARY_LIGHT, ts: 0.35, glow: 0.55, hz: 0.8, depth: 0.03, spin: 1.6 },
  speaking: { tint: "#FFFFFF", ts: 0.35, glow: 0.7, hz: 1.4, depth: 0.05, spin: 0.4 },
  calling: { tint: "#34D399", ts: 0.4, glow: 0.6, hz: 1.2, depth: 0.05, spin: 0.6 },
  mapping: { tint: "#7DD3FC", ts: 0.4, glow: 0.55, hz: 0.6, depth: 0.03, spin: 1.0 },
  task: { tint: "#FBBF24", ts: 0.35, glow: 0.55, hz: 1.0, depth: 0.035, spin: 1.2 },
  summarizing: { tint: "#FBBF24", ts: 0.3, glow: 0.45, hz: 0.4, depth: 0.025, spin: 0.5 },
  celebrating: { tint: "#F9A8D4", ts: 0.45, glow: 0.8, hz: 1.6, depth: 0.07, spin: 1.8 },
};

/** State labels shown under the orb (AgentStateX.label). */
export const MOOD_LABELS = {
  idle: null,
  thinking: "Thinking...",
  speaking: "Speaking...",
  calling: "Calling...",
  mapping: "Finding route...",
  task: "On it!",
  summarizing: "Summarizing...",
  celebrating: "All done!",
};

const MORPH_MS = 600; // KoraMotion.orbMorph
const reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");

const hexToRgb = (hex) => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const mix = (a, b, t) => a + (b - a) * t;
const mixRgb = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
const rgba = (c, a = 1) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;
const easeInOutCubic = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

const chromeRgb = CHROME.map(hexToRgb);
const holoRgb = HOLOGRAPHIC.map(hexToRgb);

function moodVec(name) {
  const m = MOODS[name] || MOODS.idle;
  return { ...m, tint: hexToRgb(m.tint) };
}
function lerpMood(a, b, t) {
  return {
    tint: mixRgb(a.tint, b.tint, t),
    ts: mix(a.ts, b.ts, t),
    glow: mix(a.glow, b.glow, t),
    hz: mix(a.hz, b.hz, t),
    depth: mix(a.depth, b.depth, t),
    spin: mix(a.spin, b.spin, t),
  };
}

// Drifting motes (Rive spec "Particle layer": 3-5, desynced periods).
const MOTES = [
  { period: 8, orbit: 1.28, tilt: 0.5, radius: 0.028, phase: 0 },
  { period: 11, orbit: 1.32, tilt: -0.35, radius: 0.02, phase: 2.1 },
  { period: 14, orbit: 1.2, tilt: 0.9, radius: 0.024, phase: 4.2 },
  { period: 9.5, orbit: 1.36, tilt: -0.8, radius: 0.016, phase: 5.4 },
];

const orbs = new Set();
let rafId = 0;
let lastTs = 0;

function frame(ts) {
  rafId = 0;
  const dt = Math.min(0.05, (ts - lastTs) / 1000 || 0);
  lastTs = ts;
  let live = false;
  for (const orb of orbs) {
    if (!orb.visible) continue;
    orb.tick(dt);
    live = true;
  }
  if (live && !reduceMotionQuery.matches && !document.hidden) rafId = requestAnimationFrame(frame);
}
function wake() {
  if (rafId || reduceMotionQuery.matches || document.hidden) return;
  lastTs = performance.now();
  rafId = requestAnimationFrame(frame);
}
document.addEventListener("visibilitychange", wake);
reduceMotionQuery.addEventListener?.("change", () => {
  for (const orb of orbs) orb.settle();
  wake();
});

const io =
  "IntersectionObserver" in window
    ? new IntersectionObserver(
        (entries) => {
          for (const e of entries) {
            const orb = e.target.__orb;
            if (!orb) continue;
            orb.visible = e.isIntersecting;
            if (orb.visible) orb.draw();
          }
          wake();
        },
        { rootMargin: "80px" },
      )
    : null;

export class Orb {
  /**
   * @param {HTMLCanvasElement} canvas sized by CSS; the backing store follows it
   * @param {{material?: 'chrome'|'holographic', mood?: string, motes?: boolean}} [opts]
   */
  constructor(canvas, opts = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.material = opts.material || "chrome";
    this.motes = opts.motes !== false;
    this.mood = moodVec(opts.mood || "idle");
    this.from = this.mood;
    this.to = this.mood;
    this.morph = 1;
    this.pulse = Math.random();
    this.spin = Math.random() * Math.PI * 2;
    this.clock = Math.random() * 20;
    this.visible = !io;
    canvas.__orb = this;
    orbs.add(this);
    this.resize();
    if ("ResizeObserver" in window) new ResizeObserver(() => this.resize()).observe(canvas);
    io?.observe(canvas);
    this.draw();
    wake();
  }

  setMood(name) {
    this.from = this.mood;
    this.to = moodVec(name);
    this.morph = 0;
    if (reduceMotionQuery.matches) this.settle();
    else wake();
  }

  /** Reduced motion: jump to the settled pose and hold still. */
  settle() {
    this.mood = this.to;
    this.morph = 1;
    this.pulse = 0;
    this.draw();
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = this.canvas.clientWidth;
    const h = this.canvas.clientHeight;
    if (!w || !h) return;
    const pw = Math.round(w * dpr);
    const ph = Math.round(h * dpr);
    if (this.canvas.width !== pw || this.canvas.height !== ph) {
      this.canvas.width = pw;
      this.canvas.height = ph;
    }
    this.dpr = dpr;
    this.draw();
  }

  tick(dt) {
    if (this.morph < 1) {
      this.morph = Math.min(1, this.morph + (dt * 1000) / MORPH_MS);
      this.mood = lerpMood(this.from, this.to, easeInOutCubic(this.morph));
    }
    this.pulse = (this.pulse + dt * this.mood.hz) % 1;
    this.spin = (this.spin + dt * this.mood.spin) % (Math.PI * 2);
    this.clock += dt;
    this.draw();
  }

  draw() {
    const ctx = this.ctx;
    const W = this.canvas.width;
    const H = this.canvas.height;
    if (!W || !H) return;
    const holo = this.material === "holographic";
    const mood = this.mood;
    const cx = W / 2;
    const cy = H / 2;
    const maxR = Math.min(W, H) / 2;
    const breath = Math.sin(this.pulse * Math.PI * 2);
    const r = maxR * 0.72 * (1 + mood.depth * breath);

    ctx.clearRect(0, 0, W, H);

    const base = holo ? holoRgb : chromeRgb;
    const palette = base.map((c) => mixRgb(c, mood.tint, mood.ts));

    // Halo: a radial fade, not a blur filter.
    const haloBase = mixRgb(hexToRgb(holo ? PRIMARY_LIGHT : PRIMARY), mood.tint, mood.ts);
    let g = ctx.createRadialGradient(cx, cy, 0, cx, cy, maxR);
    g.addColorStop(0, rgba(haloBase, mood.glow));
    g.addColorStop(Math.min(1, (r / maxR) * 0.85), rgba(haloBase, mood.glow));
    g.addColorStop(1, rgba(haloBase, 0));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(cx, cy, maxR, 0, Math.PI * 2);
    ctx.fill();

    // Body.
    if (holo) {
      // Iridescent bands swirling around a wandering centre: thin film, not a colour wheel.
      const conic = ctx.createConicGradient(
        this.spin,
        cx + Math.cos(this.spin) * 0.4 * r,
        cy + Math.sin(this.spin) * 0.4 * r,
      );
      palette.forEach((c, i) => conic.addColorStop(i / (palette.length - 1), rgba(c)));
      ctx.fillStyle = conic;
    } else {
      // Chrome reflects a horizon: bright sky, dark band, lit ground; it sways with the spin.
      const sway = Math.sin(this.spin) * 0.12;
      const lin = ctx.createLinearGradient(
        cx + (-0.3 + sway) * r,
        cy - r,
        cx + (0.3 - sway) * r,
        cy + r,
      );
      [0, 0.38, 0.52, 0.62, 0.85, 1].forEach((s, i) => lin.addColorStop(s, rgba(palette[i])));
      ctx.fillStyle = lin;
    }
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fill();

    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.clip();

    if (holo) {
      // Counter-rotating translucent film for the soap-bubble shimmer.
      const film = ctx.createConicGradient(
        -this.spin * 1.7,
        cx - Math.sin(this.spin * 1.3) * 0.5 * r,
        cy + Math.cos(this.spin * 1.3) * 0.5 * r,
      );
      const rev = [...palette].reverse();
      rev.forEach((c, i) => film.addColorStop(i / (rev.length - 1), rgba(c, 0.45)));
      ctx.globalCompositeOperation = "screen";
      ctx.fillStyle = film;
      ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
      ctx.globalCompositeOperation = "source-over";
      // See-through core: a bubble is clear in the middle, colour at the rim.
      const core = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
      core.addColorStop(0, "rgba(76,29,149,0.45)");
      core.addColorStop(0.8, "rgba(76,29,149,0)");
      core.addColorStop(1, "rgba(76,29,149,0)");
      ctx.fillStyle = core;
      ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
    }

    // Sphere depth: darken toward the lower-right edge.
    const depth = ctx.createRadialGradient(cx - 0.35 * r, cy - 0.4 * r, 0, cx - 0.35 * r, cy - 0.4 * r, 1.1 * r);
    depth.addColorStop(0, SHADE + "0)");
    depth.addColorStop(0.5, SHADE + "0)");
    depth.addColorStop(1, SHADE + (holo ? 0.35 : 0.65) + ")");
    ctx.fillStyle = depth;
    ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
    ctx.restore();

    // Specular highlight.
    const sw = r * (holo ? 0.75 : 0.55);
    const sh = r * (holo ? 0.45 : 0.32);
    const sx = cx - r * 0.32;
    const sy = cy - r * 0.4;
    ctx.save();
    ctx.translate(sx, sy);
    ctx.scale(sw / 2, sh / 2);
    const spec = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
    spec.addColorStop(0, `rgba(255,255,255,${holo ? 0.6 : 0.9})`);
    spec.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = spec;
    ctx.beginPath();
    ctx.arc(0, 0, 1, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    // Rim.
    ctx.lineWidth = Math.max(1, r * 0.025);
    if (holo) {
      const rim = ctx.createConicGradient(-this.spin, cx, cy);
      palette.forEach((c, i) => rim.addColorStop(i / (palette.length - 1), rgba(c)));
      ctx.strokeStyle = rim;
    } else {
      ctx.strokeStyle = "rgba(255,255,255,0.3)";
    }
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();

    // Drifting motes, constant across moods so every mood reads as the same character.
    if (this.motes) {
      ctx.fillStyle = "rgba(196,181,253,0.85)";
      for (const m of MOTES) {
        const a = (this.clock / m.period) * Math.PI * 2 + m.phase;
        const ox = Math.cos(a) * m.orbit * r;
        const oy = Math.sin(a) * m.orbit * r * 0.62;
        const x = cx + ox * Math.cos(m.tilt) - oy * Math.sin(m.tilt);
        const y = cy + ox * Math.sin(m.tilt) + oy * Math.cos(m.tilt);
        ctx.beginPath();
        ctx.arc(x, y, Math.max(1.2, maxR * m.radius), 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }
}
