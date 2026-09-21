// Tiny QR Code encoder for the stage page: byte mode, error correction M,
// versions 1-10 (up to 213 bytes: plenty for a URL). No dependencies.
// Checked against a reference implementation in dev/qr.test.mjs.

// Per version: [eccCodewordsPerBlock, [blockCount, dataCodewordsPerBlock][]]
const M_TABLE = [
  null,
  [10, [[1, 16]]],
  [16, [[1, 28]]],
  [26, [[1, 44]]],
  [18, [[2, 32]]],
  [24, [[2, 43]]],
  [16, [[4, 27]]],
  [18, [[4, 31]]],
  [22, [[2, 38], [2, 39]]],
  [22, [[3, 36], [2, 37]]],
  [26, [[4, 43], [1, 44]]],
];
const ALIGN = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];
export const MAX_VERSION = 10;

const dataCodewords = (v) => M_TABLE[v][1].reduce((n, [count, len]) => n + count * len, 0);

/** Max payload bytes at version v (byte mode, ECC M). */
export function capacity(v) {
  const countBits = v < 10 ? 8 : 16;
  return Math.floor((dataCodewords(v) * 8 - 4 - countBits) / 8);
}

// ── GF(256) / Reed-Solomon ──
const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
{
  let x = 1;
  for (let i = 0; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
}
const gmul = (a, b) => (a && b ? EXP[LOG[a] + LOG[b]] : 0);

function rsGenerator(degree) {
  let poly = [1];
  for (let i = 0; i < degree; i++) {
    const next = new Array(poly.length + 1).fill(0);
    for (let j = 0; j < poly.length; j++) {
      next[j] ^= poly[j];
      next[j + 1] ^= gmul(poly[j], EXP[i]);
    }
    poly = next;
  }
  return poly; // highest degree first, leading 1
}

function rsRemainder(data, degree) {
  const gen = rsGenerator(degree);
  const rem = new Array(degree).fill(0);
  for (const b of data) {
    const factor = b ^ rem.shift();
    rem.push(0);
    if (factor) for (let i = 0; i < degree; i++) rem[i] ^= gmul(gen[i + 1], factor);
  }
  return rem;
}

// ── Bitstream ──
function buildCodewords(bytes, v) {
  const bits = [];
  const push = (val, len) => { for (let i = len - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
  push(0b0100, 4);
  push(bytes.length, v < 10 ? 8 : 16);
  for (const b of bytes) push(b, 8);
  const total = dataCodewords(v) * 8;
  push(0, Math.min(4, total - bits.length));
  while (bits.length % 8) bits.push(0);
  const out = [];
  for (let i = 0; i < bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8).join(""), 2));
  for (let pad = 0xec; out.length < dataCodewords(v); pad ^= 0xec ^ 0x11) out.push(pad);

  // Split into blocks, add ECC, interleave.
  const [eccLen, groups] = M_TABLE[v];
  const blocks = [];
  let at = 0;
  for (const [count, len] of groups) {
    for (let i = 0; i < count; i++) {
      const data = out.slice(at, at + len);
      at += len;
      blocks.push({ data, ecc: rsRemainder(data, eccLen) });
    }
  }
  const result = [];
  const maxLen = Math.max(...blocks.map((b) => b.data.length));
  for (let i = 0; i < maxLen; i++) for (const b of blocks) if (i < b.data.length) result.push(b.data[i]);
  for (let i = 0; i < eccLen; i++) for (const b of blocks) result.push(b.ecc[i]);
  return result;
}

// ── Matrix ──
const MASKS = [
  (x, y) => (x + y) % 2 === 0,
  (x, y) => y % 2 === 0,
  (x, y) => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
];

function baseMatrix(v) {
  const size = 17 + v * 4;
  const mod = Array.from({ length: size }, () => new Uint8Array(size));
  const fn = Array.from({ length: size }, () => new Uint8Array(size));
  const set = (x, y, dark) => {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    mod[y][x] = dark ? 1 : 0;
    fn[y][x] = 1;
  };
  for (let i = 0; i < size; i++) {
    set(6, i, i % 2 === 0);
    set(i, 6, i % 2 === 0);
  }
  const finder = (cx, cy) => {
    for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
      const d = Math.max(Math.abs(dx), Math.abs(dy));
      set(cx + dx, cy + dy, d !== 2 && d !== 4);
    }
  };
  finder(3, 3);
  finder(size - 4, 3);
  finder(3, size - 4);
  const pos = ALIGN[v];
  for (let i = 0; i < pos.length; i++) for (let j = 0; j < pos.length; j++) {
    if ((i === 0 && j === 0) || (i === 0 && j === pos.length - 1) || (i === pos.length - 1 && j === 0)) continue;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(pos[i] + dx, pos[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }
  // Reserve format areas (drawn per mask) and draw version info.
  drawFormat(set, size, 0, true);
  if (v >= 7) {
    let rem = v;
    for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
    const bits = (v << 12) | rem;
    for (let i = 0; i < 18; i++) {
      const b = ((bits >>> i) & 1) === 1;
      const a = size - 11 + (i % 3);
      const c = Math.floor(i / 3);
      set(a, c, b);
      set(c, a, b);
    }
  }
  return { size, mod, fn };
}

function drawFormat(set, size, mask, reserveOnly = false) {
  const data = (0 << 3) | mask; // ECC M = 0b00
  let rem = data;
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
  const bits = ((data << 10) | rem) ^ 0x5412;
  const bit = (i) => (reserveOnly ? false : ((bits >>> i) & 1) === 1);
  for (let i = 0; i <= 5; i++) set(8, i, bit(i));
  set(8, 7, bit(6));
  set(8, 8, bit(7));
  set(7, 8, bit(8));
  for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
  for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
  for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
  set(8, size - 8, true);
}

function placeData(base, codewords) {
  const { size, mod, fn } = base;
  let i = 0;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        if (!fn[y][x] && i < codewords.length * 8) {
          mod[y][x] = (codewords[i >>> 3] >>> (7 - (i & 7))) & 1;
          i++;
        }
      }
    }
  }
}

function penalty(mod, size) {
  let p = 0;
  const line = (get) => {
    let run = 1;
    for (let i = 1; i < size; i++) {
      if (get(i) === get(i - 1)) run++;
      else { if (run >= 5) p += 3 + (run - 5); run = 1; }
    }
    if (run >= 5) p += 3 + (run - 5);
  };
  for (let y = 0; y < size; y++) line((i) => mod[y][i]);
  for (let x = 0; x < size; x++) line((i) => mod[i][x]);
  for (let y = 0; y < size - 1; y++) for (let x = 0; x < size - 1; x++) {
    const c = mod[y][x];
    if (c === mod[y][x + 1] && c === mod[y + 1][x] && c === mod[y + 1][x + 1]) p += 3;
  }
  const pat = [1, 0, 1, 1, 1, 0, 1];
  const scan = (get) => {
    for (let i = 0; i + 7 <= size; i++) {
      if (!pat.every((b, k) => get(i + k) === b)) continue;
      const white = (a, b) => { for (let k = a; k < b; k++) if (k >= 0 && k < size && get(k) === 1) return false; return true; };
      if (white(i - 4, i)) p += 40;
      if (white(i + 7, i + 11)) p += 40;
    }
  };
  for (let y = 0; y < size; y++) scan((i) => mod[y][i]);
  for (let x = 0; x < size; x++) scan((i) => mod[i][x]);
  let dark = 0;
  for (const row of mod) for (const c of row) dark += c;
  p += 10 * Math.floor(Math.abs(dark * 20 - size * size * 10) / (size * size));
  return p;
}

/**
 * @param {string} text
 * @param {{mask?: number}} [opts]  force a mask (tests); default picks the lowest penalty
 * @returns {{version:number, size:number, mask:number, modules:Uint8Array[]}}
 */
export function encodeQr(text, { mask } = {}) {
  const bytes = new TextEncoder().encode(text);
  let v = 1;
  while (v <= MAX_VERSION && capacity(v) < bytes.length) v++;
  if (v > MAX_VERSION) throw new RangeError("Text too long for the built-in QR encoder");
  const codewords = buildCodewords(bytes, v);
  const base = baseMatrix(v);
  placeData(base, codewords);
  const { size, fn } = base;

  const build = (m) => {
    const mod = base.mod.map((r) => Uint8Array.from(r));
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (!fn[y][x] && MASKS[m](x, y)) mod[y][x] ^= 1;
    drawFormat((x, y, dark) => { mod[y][x] = dark ? 1 : 0; }, size, m);
    return mod;
  };
  if (mask !== undefined) return { version: v, size, mask, modules: build(mask) };
  let best = null;
  for (let m = 0; m < 8; m++) {
    const mod = build(m);
    const score = penalty(mod, size);
    if (!best || score < best.score) best = { score, mask: m, mod };
  }
  return { version: v, size, mask: best.mask, modules: best.mod };
}

/** One SVG path (`d`) covering all dark modules, merged into horizontal runs. Units are modules. */
export function toPath(modules, quiet = 4) {
  const parts = [];
  for (let y = 0; y < modules.length; y++) {
    let x = 0;
    while (x < modules.length) {
      if (!modules[y][x]) { x++; continue; }
      const start = x;
      while (x < modules.length && modules[y][x]) x++;
      parts.push(`M${start + quiet} ${y + quiet}h${x - start}v1h${-(x - start)}z`);
    }
  }
  return parts.join("");
}
