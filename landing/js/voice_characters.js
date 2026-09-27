/*
 * Renders the eleven co-rider voice characters as SVG, ported from the same
 * silhouette formula as `frontend/tool/rive/build_voice_characters.js` (the
 * generator for `assets/rive/voice_characters.riv`), so the web picker shows
 * the app's actual cast - not a different mascot set. See
 * docs/kora-voice-characters-rive-spec.md for the design language.
 *
 * Each character is a closed smooth body path (superellipse sampled at 12
 * anchors, Catmull-Rom smoothed into cubic beziers - same math as the
 * generator's `body()`/`smoothVertices()`), a fixed eye/mouth rig, and one
 * distinguishing feature drawn behind or in front of the body. Motes and a
 * selection ring are separate layers, animated in CSS (css/site.css).
 *
 * Root is placed at the artboard's own center via a translate(250,250), so
 * every coordinate below is relative to that center, exactly like the
 * generator's `root` node.
 */

const RAD = Math.PI / 180;
const CX = 250,
  CY = 250;
const INK = "#1B1730";

const sgnPow = (v, e) => Math.sign(v) * Math.abs(v) ** e;

function bodyPoints({ R = 140, sx = 1, sy = 1, n = 2, warp = () => [0, 0], tilt = 0 }) {
  const pts = [];
  for (let i = 0; i < 12; i++) {
    const th = i * 30 * RAD;
    let x = R * sx * sgnPow(Math.sin(th), 2 / n);
    let y = -R * sy * sgnPow(Math.cos(th), 2 / n);
    const [dx, dy] = warp(th, x, y);
    x += dx;
    y += dy;
    const c = Math.cos(tilt * RAD),
      s = Math.sin(tilt * RAD);
    pts.push([x * c - y * s, x * s + y * c]);
  }
  return pts;
}

/** Catmull-Rom tangents at each anchor (same construction as smoothVertices, cartesian form). */
function tangents(pts, closed = true) {
  const n = pts.length;
  return pts.map((p, i) => {
    const a = pts[closed ? (i + n - 1) % n : Math.max(i - 1, 0)];
    const b = pts[closed ? (i + 1) % n : Math.min(i + 1, n - 1)];
    return { x: p[0], y: p[1], tx: (b[0] - a[0]) / 6, ty: (b[1] - a[1]) / 6 };
  });
}

function smoothPathD(pts, closed = true) {
  const v = tangents(pts, closed);
  const n = v.length;
  let d = `M ${fx(v[0].x)} ${fx(v[0].y)}`;
  for (let i = 0; i < (closed ? n : n - 1); i++) {
    const cur = v[i];
    const next = v[(i + 1) % n];
    d += ` C ${fx(cur.x + cur.tx)} ${fx(cur.y + cur.ty)} ${fx(next.x - next.tx)} ${fx(next.y - next.ty)} ${fx(next.x)} ${fx(next.y)}`;
  }
  if (closed) d += " Z";
  return d;
}

function straightPathD(pts, closed = true) {
  let d = `M ${fx(pts[0][0])} ${fx(pts[0][1])}`;
  for (let i = 1; i < pts.length; i++) d += ` L ${fx(pts[i][0])} ${fx(pts[i][1])}`;
  if (closed) d += " Z";
  return d;
}

const fx = (n) => Math.round(n * 100) / 100;

/* -------------------------------------------------------------- colour */

const hexToRgb = (hex) => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
const rgb = (c, a = 1) => (a === 1 ? `rgb(${c[0]} ${c[1]} ${c[2]})` : `rgb(${c[0]} ${c[1]} ${c[2]} / ${a})`);
const WHITE = [255, 255, 255];
const DEEP_BASE = [40, 22, 84];
const lighten = (c, t) => mix(c, WHITE, t);
const deepen = (c, t) => mix(c, DEEP_BASE, t);

/* ------------------------------------------------------------- features */

/** Fixed feature accents that don't follow the character's own colour, same as the generator. */
const FIXED = {
  leafA: "#6EE7B7",
  leafB: "#34D399",
  cheek: "rgb(251 113 133 / 0.5)",
  halo: "#FFE9B8",
  bow: "#4C1D95",
  knot: "#6D28D9",
};

/** Features drawn behind the body (radiate from, or sit above/behind, the head). */
function featureBehind(kind, colors) {
  const { light, pale, deep } = colors;
  switch (kind) {
    case "crest":
      return (
        `<ellipse cx="0" cy="-158" rx="17" ry="26" fill="${rgb(pale)}"/>` +
        [-1, 1]
          .map((s) => `<ellipse cx="${40 * s}" cy="-146" rx="12" ry="21" fill="${rgb(light)}" transform="rotate(${38 * s} ${40 * s} -146)"/>`)
          .join("")
      );
    case "sprig":
      return (
        `<ellipse cx="20" cy="-150" rx="12" ry="25" fill="${FIXED.leafA}" transform="rotate(32 20 -150)"/>` +
        `<ellipse cx="-8" cy="-156" rx="10" ry="21" fill="${FIXED.leafB}" transform="rotate(-28 -8 -156)"/>`
      );
    case "antenna":
      return (
        `<rect x="-3.5" y="-195" width="7" height="46" rx="3" fill="${rgb(deep)}"/>` +
        `<circle cx="0" cy="-200" r="12" fill="${rgb(pale)}"/>`
      );
    case "halo":
      return `<ellipse cx="0" cy="-172" rx="42" ry="13" fill="none" stroke="${FIXED.halo}" stroke-width="9"/>`;
    case "tuft":
      return [-16, 0, 16]
        .map((x, i) => `<ellipse cx="${x}" cy="-142" rx="8" ry="21" fill="${rgb(deep)}" transform="rotate(${[-24, 0, 24][i]} ${x} -142)"/>`)
        .join("");
    default:
      return "";
  }
}

/** Features drawn in front of the body (over the face or body surface). */
function featureFront(kind, colors, fy) {
  const { light, pale, deep } = colors;
  switch (kind) {
    case "brim":
      return `<rect x="-100" y="-116" width="200" height="24" rx="12" fill="${rgb(deep)}"/>`;
    case "cheeks":
      return [-1, 1]
        .map((s) => `<ellipse cx="${78 * s}" cy="${fy + 26}" rx="23" ry="14" fill="${FIXED.cheek}"/>`)
        .join("");
    case "bowtie":
      return (
        `<path d="${straightPathD(
          [
            [-44, 88],
            [0, 102],
            [44, 88],
            [44, 128],
            [0, 114],
            [-44, 128],
          ],
        )}" fill="${FIXED.bow}"/>` + `<circle cx="0" cy="108" r="10" fill="${FIXED.knot}"/>`
      );
    case "glasses":
      return (
        [-1, 1]
          .map((s) => `<ellipse cx="${46 * s}" cy="${fy - 22}" rx="37" ry="37" fill="none" stroke="${INK}" stroke-width="7"/>`)
          .join("") + `<rect x="-10" y="${fy - 25.5}" width="20" height="7" rx="3" fill="${INK}"/>`
      );
    case "streak":
      return `<ellipse cx="-70" cy="-60" rx="6" ry="48" fill="rgb(255 255 255 / 0.75)" transform="rotate(34 -70 -60)"/>`;
    case "ribbon":
      return `<path d="${smoothPathD(
        [
          [76, -112],
          [112, -142],
          [148, -118],
          [134, -78],
        ],
        false,
      )}" fill="none" stroke="${rgb(pale)}" stroke-width="15" stroke-linecap="round" stroke-linejoin="round"/>`;
    default:
      return "";
  }
}

/* --------------------------------------------------------------- render */

let uidSeq = 0;

/**
 * Renders one voice character as a self-contained SVG string.
 * @param {object} voice an entry from VOICES (voices.js)
 * @param {{selected?: boolean, speaking?: boolean}} [state]
 */
export function characterSvg(voice, state = {}) {
  const uid = `vc${uidSeq++}`;
  const A = hexToRgb(voice.color);
  const light = lighten(A, 0.45);
  const pale = lighten(A, 0.75);
  const deep = deepen(A, 0.55);
  const colors = { light, pale, deep };
  const fy = voice.face;
  const eyeX = 46;
  const eyeY = fy - 22;

  const bodyD = smoothPathD(bodyPoints(voice.body));
  const gradId = `${uid}-grad`;

  const classes = ["vchar", state.selected ? "is-selected" : "", state.speaking ? "is-speaking" : ""].filter(Boolean).join(" ");
  const style = `--vbreath:${voice.breath}s;--vblink:${voice.blink}s`;

  return `<svg class="${classes}" style="${style}" viewBox="0 0 500 500" role="img" aria-hidden="true" data-voice="${voice.id}">
    <defs>
      <linearGradient id="${gradId}" gradientUnits="userSpaceOnUse" x1="${CX}" y1="${CY - 150}" x2="${CX}" y2="${CY + 150}">
        <stop offset="0" stop-color="${rgb(light)}"/>
        <stop offset="0.62" stop-color="${rgb(A)}"/>
        <stop offset="1" stop-color="${rgb(mix(A, deep, 0.22))}"/>
      </linearGradient>
    </defs>
    <g transform="translate(${CX} ${CY})">
      <g class="vchar__motes">
        ${[196, 208, 220]
          .map(
            (r, i) =>
              `<g class="vchar__tilt" transform="rotate(${i * 57 - 20})"><g class="vchar__spin" style="--mote-period:${[8, 11, 14][i]}s"><circle cx="${r}" cy="0" r="${6 + i * 1.5}" fill="${rgb(i === 1 ? pale : light, 0.85)}"/></g></g>`,
          )
          .join("")}
      </g>
      <circle class="vchar__ring" r="186" fill="none" stroke="${rgb(light)}" stroke-width="8"/>
      <g class="vchar__lift">
        <g class="vchar__talk">
          <g class="vchar__breath">
            ${featureBehind(voice.feature, colors)}
            <path class="vchar__body" d="${bodyD}" fill="url(#${gradId})"/>
            <ellipse class="vchar__hl" cx="-52" cy="-84" rx="38" ry="19" fill="rgb(255 255 255 / 0.32)" transform="rotate(-32 -52 -84)"/>
            <g class="vchar__eye" transform="translate(${-eyeX} ${eyeY})">
              <g class="vchar__blink">
                <ellipse class="vchar__pupil" cx="0" cy="0" rx="12" ry="16" fill="${INK}"/>
                <circle class="vchar__shine" cx="-2.5" cy="-4" r="4.5" fill="rgb(255 255 255 / 0.95)"/>
              </g>
            </g>
            <g class="vchar__eye" transform="translate(${eyeX} ${eyeY})">
              <g class="vchar__blink">
                <ellipse class="vchar__pupil" cx="0" cy="0" rx="12" ry="16" fill="${INK}"/>
                <circle class="vchar__shine" cx="-2.5" cy="-4" r="4.5" fill="rgb(255 255 255 / 0.95)"/>
              </g>
            </g>
            <path class="vchar__mouth" d="${smoothPathD([
              [-24, fy + 44],
              [0, fy + 41],
              [24, fy + 44],
              [0, fy + 68],
            ])}" fill="${INK}"/>
            ${featureFront(voice.feature, colors, fy)}
          </g>
        </g>
      </g>
    </g>
  </svg>`;
}
