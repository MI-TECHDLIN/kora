// The co-rider orb, drawn on one 2D canvas. Holographic bubble material from
// the orb spec (violet / pink / blue / mint), never lime. Cost per frame: one
// path fill, one radial + one conic gradient, a few strokes. No blur filters.

const TAU = Math.PI * 2;
const HOLO = ["#C4B5FD", "#F9A8D4", "#7DD3FC", "#A7F3D0"];

// Per-state look: how fast it turns, how much it breathes, glow strength, tint.
const MOODS = {
  idle: { spin: 0.06, breathe: 0.018, glow: 0.35, tint: [139, 92, 246], ripple: false },
  waiting: { spin: 0.08, breathe: 0.03, glow: 0.45, tint: [139, 92, 246], ripple: false },
  ringing: { spin: 0.35, breathe: 0.05, glow: 0.7, tint: [196, 181, 253], ripple: true },
  connecting: { spin: 0.5, breathe: 0.04, glow: 0.55, tint: [125, 211, 252], ripple: false },
  speaking: { spin: 0.18, breathe: 0.02, glow: 0.8, tint: [255, 255, 255], ripple: false },
  listening: { spin: 0.1, breathe: 0.035, glow: 0.5, tint: [167, 243, 208], ripple: false },
  done: { spin: 0.05, breathe: 0.015, glow: 0.4, tint: [249, 168, 212], ripple: false },
  error: { spin: 0.02, breathe: 0.01, glow: 0.2, tint: [248, 113, 113], ripple: false },
};

const lerp = (a, b, t) => a + (b - a) * t;

export class Orb {
  /**
   * @param {HTMLCanvasElement} canvas  square canvas; CSS controls display size
   * @param {object} o
   * @param {number} o.size  CSS pixel size of the drawing surface
   * @param {boolean} o.reducedMotion
   */
  constructor(canvas, { size = 320, reducedMotion = false } = {}) {
    this.canvas = canvas;
    this.size = size;
    this.reduced = reducedMotion;
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(size * this.dpr);
    canvas.height = Math.round(size * this.dpr);
    this.ctx = canvas.getContext("2d", { alpha: true });
    this.ctx.scale(this.dpr, this.dpr);
    this.mood = "idle";
    // Smoothed, eased parameters chasing the mood targets.
    this.cur = { ...MOODS.idle, tint: [...MOODS.idle.tint] };
    this.level = 0; // smoothed input level 0..1
    this.target = 0;
    this.phase = 0;
    this.spin = 0;
    this.raf = 0;
    this.last = 0;
    this.running = false;
    this.getLevel = () => 0;
    this.hasConic = typeof this.ctx.createConicGradient === "function";
    this.tick = this.tick.bind(this);
    this.onVisibility = () => {
      if (document.hidden) this.#halt();
      else if (this.running) this.#kick();
    };
    document.addEventListener("visibilitychange", this.onVisibility);
  }

  setMood(name) {
    this.mood = MOODS[name] ? name : "idle";
    if (this.reduced) this.draw(0);
  }

  /** Provide a function returning the current 0..1 voice level. */
  setLevelSource(fn) {
    this.getLevel = fn || (() => 0);
  }

  start() {
    this.running = true;
    this.#kick();
  }

  stop() {
    this.running = false;
    this.#halt();
  }

  destroy() {
    this.stop();
    document.removeEventListener("visibilitychange", this.onVisibility);
  }

  #kick() {
    if (this.raf || document.hidden) return;
    this.last = 0;
    this.raf = requestAnimationFrame(this.tick);
  }

  #halt() {
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = 0;
  }

  tick(now) {
    this.raf = 0;
    if (!this.running) return;
    const dt = this.last ? Math.min(0.05, (now - this.last) / 1000) : 0.016;
    this.last = now;
    this.draw(dt);
    this.raf = requestAnimationFrame(this.tick);
  }

  draw(dt) {
    const m = MOODS[this.mood];
    const k = 1 - Math.pow(0.001, dt || 0.016); // frame-rate independent ease
    const c = this.cur;
    c.spin = lerp(c.spin, m.spin, k);
    c.breathe = lerp(c.breathe, m.breathe, k);
    c.glow = lerp(c.glow, m.glow, k);
    for (let i = 0; i < 3; i++) c.tint[i] = lerp(c.tint[i], m.tint[i], k);
    c.ripple = m.ripple;

    this.target = Math.max(0, Math.min(1, this.getLevel()));
    const rate = this.target > this.level ? 0.5 : 0.12; // quick attack, slow release
    this.level = lerp(this.level, this.target, rate);

    const motion = this.reduced ? 0 : 1;
    this.phase += dt * motion;
    this.spin += dt * c.spin * TAU * motion;

    const ctx = this.ctx;
    const S = this.size;
    const cx = S / 2;
    const cy = S / 2;
    const base = S * 0.27;
    const lvl = this.level;
    const breathe = 1 + Math.sin(this.phase * 1.6) * c.breathe * motion + lvl * 0.16 * (this.reduced ? 0.5 : 1);
    const R = base * breathe;
    const [tr, tg, tb] = c.tint.map(Math.round);

    ctx.clearRect(0, 0, S, S);

    // Halo: one big radial gradient, cheap and soft.
    const haloR = R * (2.15 + lvl * 0.5);
    const halo = ctx.createRadialGradient(cx, cy, R * 0.6, cx, cy, haloR);
    const a = Math.min(0.85, c.glow * (0.55 + lvl * 0.6));
    halo.addColorStop(0, `rgba(${tr},${tg},${tb},${a})`);
    halo.addColorStop(0.45, `rgba(139,92,246,${a * 0.32})`);
    halo.addColorStop(1, "rgba(139,92,246,0)");
    ctx.fillStyle = halo;
    ctx.fillRect(0, 0, S, S);

    // Ringing ripples: three expanding hairline rings.
    if (c.ripple && !this.reduced) {
      ctx.lineWidth = 1.5;
      for (let i = 0; i < 3; i++) {
        const t = (this.phase * 0.55 + i / 3) % 1;
        ctx.strokeStyle = `rgba(196,181,253,${(1 - t) * 0.5})`;
        ctx.beginPath();
        ctx.arc(cx, cy, R * (1.05 + t * 1.1), 0, TAU);
        ctx.stroke();
      }
    }

    // Body: a slightly organic circle. Three low harmonics, amplitude grows with voice level.
    const wob = this.reduced ? 0 : R * (0.012 + lvl * 0.06);
    ctx.beginPath();
    const N = 56;
    for (let i = 0; i <= N; i++) {
      const th = (i / N) * TAU;
      const r =
        R +
        wob * (Math.sin(th * 3 + this.phase * 2.1) * 0.6 + Math.sin(th * 5 - this.phase * 1.7) * 0.3 + Math.sin(th * 2 + this.phase * 0.9) * 0.5);
      const x = cx + Math.cos(th) * r;
      const y = cy + Math.sin(th) * r;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.closePath();

    const body = ctx.createRadialGradient(cx - R * 0.35, cy - R * 0.4, R * 0.1, cx, cy, R * 1.05);
    body.addColorStop(0, "#3B2A78");
    body.addColorStop(0.55, "#1E1540");
    body.addColorStop(1, "#0C0820");
    ctx.fillStyle = body;
    ctx.fill();

    ctx.save();
    ctx.clip();

    // Holographic film, rotating slowly.
    if (this.hasConic) {
      const film = ctx.createConicGradient(this.spin, cx, cy);
      HOLO.forEach((col, i) => film.addColorStop(i / HOLO.length, col));
      film.addColorStop(1, HOLO[0]);
      ctx.globalAlpha = 0.5 + lvl * 0.3;
      ctx.globalCompositeOperation = "screen";
      ctx.fillStyle = film;
      ctx.fillRect(cx - R * 1.3, cy - R * 1.3, R * 2.6, R * 2.6);
    } else {
      const ang = this.spin;
      const film = ctx.createLinearGradient(cx + Math.cos(ang) * R, cy + Math.sin(ang) * R, cx - Math.cos(ang) * R, cy - Math.sin(ang) * R);
      HOLO.forEach((col, i) => film.addColorStop(i / (HOLO.length - 1), col));
      ctx.globalAlpha = 0.5;
      ctx.globalCompositeOperation = "screen";
      ctx.fillStyle = film;
      ctx.fillRect(cx - R * 1.3, cy - R * 1.3, R * 2.6, R * 2.6);
    }

    // Depth: darken the lower-right rim so the film reads as a sphere.
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
    const shade = ctx.createRadialGradient(cx - R * 0.3, cy - R * 0.35, R * 0.25, cx, cy, R * 1.1);
    shade.addColorStop(0, "rgba(7,6,11,0)");
    shade.addColorStop(0.7, "rgba(7,6,11,0.28)");
    shade.addColorStop(1, "rgba(7,6,11,0.72)");
    ctx.fillStyle = shade;
    ctx.fillRect(cx - R * 1.3, cy - R * 1.3, R * 2.6, R * 2.6);

    // Inner light that follows the voice.
    const inner = ctx.createRadialGradient(cx, cy, 0, cx, cy, R * 0.9);
    inner.addColorStop(0, `rgba(${tr},${tg},${tb},${0.1 + lvl * 0.42})`);
    inner.addColorStop(1, `rgba(${tr},${tg},${tb},0)`);
    ctx.globalCompositeOperation = "screen";
    ctx.fillStyle = inner;
    ctx.fillRect(cx - R, cy - R, R * 2, R * 2);
    ctx.restore();

    // Rim light and specular highlight.
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
    ctx.lineWidth = 1.25;
    ctx.strokeStyle = "rgba(244,241,255,0.28)";
    ctx.beginPath();
    ctx.arc(cx, cy, R, 0, TAU);
    ctx.stroke();

    const hl = ctx.createRadialGradient(cx - R * 0.38, cy - R * 0.48, 0, cx - R * 0.38, cy - R * 0.48, R * 0.42);
    hl.addColorStop(0, "rgba(255,255,255,0.85)");
    hl.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = hl;
    ctx.beginPath();
    ctx.ellipse(cx - R * 0.38, cy - R * 0.48, R * 0.3, R * 0.2, -0.6, 0, TAU);
    ctx.fill();
  }
}
