// Generates assets/rive/voice_characters.riv directly in the open .riv runtime
// format (major 7). The Rive editor can't export without a paid plan, so this
// script is the source of truth for the file. Spec: docs/kora-voice-characters-rive-spec.md.
//
//   node tool/rive/build_voice_characters.js [out.riv]     (run from frontend/)
//   node tool/rive/dump.js assets/rive/voice_characters.riv  (inspect result)
//
// Contract the Flutter side depends on (voice_character_rive.dart): one
// 500x500 transparent artboard per voice, named the voice's lowercase name,
// each with a state machine `Voice` and Boolean inputs `selected`, `speaking`.
// tool/rive/defs.json is the runtime schema; regenerate it with defs.js.
const fs = require('fs');
const path = require('path');
const OUT = path.resolve(process.argv[2] || 'assets/rive/voice_characters.riv');
const defs = require('./defs.json');

// ------------------------------------------------------------ schema helpers
const T = {}, PROP = {}, KEY = {};
for (const [name, d] of Object.entries(defs)) {
  if (d.typeKey != null) T[name] = d.typeKey;
  for (const [pn, p] of Object.entries(d.props)) { PROP[p.key] = p.type; KEY[`${name}.${pn}`] = p.key; }
}
// Property key by name, searching the class and then its ancestors.
const k = (cls, prop) => {
  for (let c = cls; c && defs[c]; c = defs[c].parent) if (defs[c].props[prop]) return defs[c].props[prop].key;
  throw new Error(`no key ${cls}.${prop}`);
};
const ANY_KEYS = new Set();

class Obj { constructor(type, props = {}) { this.type = type; this.props = props; } }

class W {
  constructor() { this.b = []; }
  byte(v) { this.b.push(v & 0xff); }
  varuint(v) { v = Math.floor(v); do { let x = v % 128; v = Math.floor(v / 128); if (v) x |= 0x80; this.byte(x); } while (v); }
  f32(v) { const a = Buffer.alloc(4); a.writeFloatLE(v); a.forEach(x => this.byte(x)); }
  u32(v) { const a = Buffer.alloc(4); a.writeUInt32LE(v >>> 0); a.forEach(x => this.byte(x)); }
  bytes(arr) { this.varuint(arr.length); arr.forEach(x => this.byte(x)); }
}
function writeObject(w, o) {
  const tk = T[o.type];
  if (tk == null) throw new Error('unknown type ' + o.type);
  w.varuint(tk);
  for (const [key, v] of Object.entries(o.props)) {
    if (v === undefined || v === null) continue;
    const type = PROP[+key];
    if (!type) throw new Error(`no field type for property ${key} on ${o.type}`);
    ANY_KEYS.add(+key);
    w.varuint(+key);
    switch (type) {
      case 'uint': w.varuint(v); break;
      case 'double': w.f32(v); break;
      case 'bool': w.byte(v ? 1 : 0); break;
      case 'color': w.u32(v); break;
      case 'string': w.bytes([...Buffer.from(v, 'utf8')]); break;
      default: throw new Error('unhandled type ' + type);
    }
  }
  w.varuint(0);
}

// ------------------------------------------------------------ property keys
const P = {
  name: k('Component', 'name'), parent: k('Component', 'parentId'),
  w: k('Artboard', 'width') , h: k('Artboard', 'height'), clip: k('Artboard', 'clip'),
  x: k('Node', 'x'), y: k('Node', 'y'),
  rot: k('TransformComponent', 'rotation'), sx: k('TransformComponent', 'scaleX'), sy: k('TransformComponent', 'scaleY'),
  op: k('WorldTransformComponent', 'opacity'),
  pw: k('ParametricPath', 'width'), ph: k('ParametricPath', 'height'),
  cornerTL: k('Rectangle', 'cornerRadiusTL'),
  closed: k('PointsCommonPath', 'isClosed'),
  vx: k('Vertex', 'x'), vy: k('Vertex', 'y'),
  inR: k('CubicDetachedVertex', 'inRotation'), inD: k('CubicDetachedVertex', 'inDistance'),
  outR: k('CubicDetachedVertex', 'outRotation'), outD: k('CubicDetachedVertex', 'outDistance'),
  solid: k('SolidColor', 'colorValue'),
  gx1: k('LinearGradient', 'startX'), gy1: k('LinearGradient', 'startY'),
  gx2: k('LinearGradient', 'endX'), gy2: k('LinearGradient', 'endY'),
  stopColor: k('GradientStop', 'colorValue'), stopPos: k('GradientStop', 'position'),
  thick: k('Stroke', 'thickness'), cap: k('Stroke', 'cap'), join: k('Stroke', 'join'),
  defaultSM: k('Artboard', 'defaultStateMachineId'),
  animName: k('Animation', 'name'), fps: k('LinearAnimation', 'fps'), dur: k('LinearAnimation', 'duration'),
  loop: k('LinearAnimation', 'loopValue'),
  koObj: k('KeyedObject', 'objectId'), kpKey: k('KeyedProperty', 'propertyKey'),
  kfFrame: k('KeyFrame', 'frame'), kfInterp: k('InterpolatingKeyFrame', 'interpolationType'),
  kfInterpId: k('InterpolatingKeyFrame', 'interpolatorId'), kfValue: k('KeyFrameDouble', 'value'),
  cx1: k('CubicInterpolator', 'x1'), cy1: k('CubicInterpolator', 'y1'),
  cx2: k('CubicInterpolator', 'x2'), cy2: k('CubicInterpolator', 'y2'),
  smName: k('StateMachineComponent', 'name'), boolValue: k('StateMachineBool', 'value'),
  animId: k('AnimationState', 'animationId'),
  toId: k('StateTransition', 'stateToId'), flags: k('StateTransition', 'flags'),
  tDur: k('StateTransition', 'duration'), tInterp: k('StateTransition', 'interpolationType'),
  tInterpId: k('StateTransition', 'interpolatorId'),
  condInput: k('TransitionInputCondition', 'inputId'), condOp: k('TransitionValueCondition', 'opValue'),
};
const RAD = Math.PI / 180;
const EASE = { x1: 0.65, y1: 0, x2: 0.35, y2: 1 }; // easeInOutCubic
const FPS = 60;
const f = s => Math.round(s * FPS);

// ------------------------------------------------------------ colour helpers
const hex = s => [1, 3, 5].map(i => parseInt(s.slice(i, i + 2), 16));
const argb = ([r, g, b], a = 1) => (((Math.round(a * 255) << 24) | (r << 16) | (g << 8) | b) >>> 0);
const mixc = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
const WHITE = [255, 255, 255], INK = hex('#1B1730');
const lighten = (c, t) => mixc(c, WHITE, t);
const deepen = (c, t) => mixc(c, [40, 22, 84], t); // toward a deep violet, never toward lime

// ------------------------------------------------------------ silhouettes
// Closed smooth curve through anchor points (Catmull-Rom -> detached cubic vertices).
function smoothVertices(pts, closed = true) {
  const n = pts.length;
  return pts.map((p, i) => {
    const a = pts[closed ? (i + n - 1) % n : Math.max(i - 1, 0)];
    const b = pts[closed ? (i + 1) % n : Math.min(i + 1, n - 1)];
    const tx = (b[0] - a[0]) / 6, ty = (b[1] - a[1]) / 6;
    const d = Math.hypot(tx, ty), r = Math.atan2(ty, tx);
    return { x: p[0], y: p[1], inR: r + Math.PI, inD: d, outR: r, outD: d };
  });
}
const sgnPow = (v, e) => Math.sign(v) * Math.abs(v) ** e;
// Superellipse-based body sampled at 12 anchors, then optionally warped.
function body({ R = 140, sx = 1, sy = 1, n = 2, warp = () => [0, 0], tilt = 0 }) {
  const pts = [];
  for (let i = 0; i < 12; i++) {
    const th = i * 30 * RAD;
    let x = R * sx * sgnPow(Math.sin(th), 2 / n), y = -R * sy * sgnPow(Math.cos(th), 2 / n);
    const [dx, dy] = warp(th, x, y);
    x += dx; y += dy;
    const c = Math.cos(tilt * RAD), s = Math.sin(tilt * RAD);
    pts.push([x * c - y * s, x * s + y * c]);
  }
  return smoothVertices(pts);
}
const bump = (th, at, w) => { // gaussian bump on the circle, peak at `at`
  const d = ((th - at + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
  return Math.exp(-(d * d) / (w * w));
};

// ------------------------------------------------------------ the cast
// accent: spec table. Silhouette + feature are the primary identity; colour is second.
// breath/blink/motes vary per character so the picker doesn't pulse in lockstep.
const CAST = [
  { name: 'alba', accent: '#C4B5FD', breath: 2.4, blink: 4.6, motes: [8, 11, 14],
    body: body({ R: 138, sx: 0.82, sy: 1.08 }), face: -22,
    feature: { kind: 'crest' } },
  { name: 'eve', accent: '#F9A8D4', breath: 2.6, blink: 5.3, motes: [9, 12, 15],
    body: body({ R: 140, tilt: 8 }), face: -10,
    feature: { kind: 'sprig' } },
  { name: 'george', accent: '#7DD3FC', breath: 2.8, blink: 4.2, motes: [10, 13, 8],
    body: body({ R: 138, sx: 1.06, sy: 0.9, n: 3.2 }), face: 8,
    feature: { kind: 'brim' } },
  { name: 'jane', accent: '#A7F3D0', breath: 2.2, blink: 5.6, motes: [7, 10, 13],
    body: body({ R: 132, warp: th => [0, -34 * bump(th, 0, 0.5)] }), face: 0,
    feature: { kind: 'antenna' } },
  { name: 'jean', accent: '#FDBA74', breath: 2.5, blink: 4.9, motes: [11, 9, 14],
    body: body({ R: 134, sy: 1.08, warp: (th, x, y) => [x * 0.1 * (y / 140), 0] }), face: -6,
    feature: { kind: 'halo' } },
  { name: 'mary', accent: '#FCA5A5', breath: 2.3, blink: 4.4, motes: [8, 12, 15],
    body: body({ R: 140, sx: 1.05, sy: 0.96, warp: (th, x, y) => [x * 0.16 * (y / 140), -12 * bump(th, 0, 0.6)] }),
    face: 14, feature: { kind: 'cheeks' } },
  { name: 'michael', accent: '#93C5FD', breath: 2.7, blink: 5.1, motes: [9, 11, 13],
    body: body({ R: 138, sx: 1.08, sy: 0.9, warp: (th, x, y) => [x * 0.14 * (-y / 140), 0] }), face: 0,
    feature: { kind: 'glasses' } },
  { name: 'anna', accent: '#D8B4FE', breath: 2.4, blink: 4.8, motes: [8, 11, 14], // default voice
    body: body({ R: 140, sx: 0.8, sy: 1.02, warp: (th, x, y) => [x * 0.08 * (y / 140), -22 * bump(th, 0, 0.7)] }), face: -6,
    feature: { kind: 'ribbon' } },
  { name: 'charles', accent: '#FDE68A', breath: 2.6, blink: 5.5, motes: [10, 12, 9],
    body: body({ R: 138, sx: 0.98, sy: 0.92, n: 4.2 }), face: -14,
    feature: { kind: 'bowtie' } },
  { name: 'paul', accent: '#5EEAD4', breath: 2.0, blink: 4.0, motes: [7, 9, 12],
    body: body({ R: 136, warp: th => [12 * Math.cos(th - 1.0), 8 * Math.cos(th + 0.2)] }), face: 6,
    feature: { kind: 'tuft' } },
  { name: 'vera', accent: '#F0ABFC', breath: 2.4, blink: 5.9, motes: [9, 13, 10],
    body: body({ R: 146, sx: 0.9, sy: 1.02, n: 1.45 }), face: 0,
    feature: { kind: 'streak' } },
];

// ------------------------------------------------------------ one artboard
function buildArtboard(ch) {
  const A = hex(ch.accent);
  const light = lighten(A, 0.45), pale = lighten(A, 0.75), deep = deepen(A, 0.55);
  const objs = [], idx = new Map();
  const add = (type, props, tag, parentTag) => {
    const o = new Obj(type, { ...props });
    if (parentTag !== undefined) {
      if (!idx.has(parentTag)) throw new Error(`no parent ${parentTag}`);
      o.props[P.parent] = idx.get(parentTag);
    }
    if (tag) idx.set(tag, objs.length);
    objs.push(o);
    return o;
  };
  const node = (name, tag, parent, extra = {}) => add('Node', { [P.name]: name, ...extra }, tag, parent);
  const solid = (tag, parent, color, type = 'Fill', stroke = {}) => {
    add(type, stroke, `${tag}.paint`, parent);
    add('SolidColor', { [P.solid]: color }, `${tag}.solid`, `${tag}.paint`);
  };
  // A shape: transform node + path + paint (fill, or stroke when `stroke` is set).
  const ellipse = (name, tag, parent, x, y, w, h, color, { rot = 0, stroke = 0, op } = {}) => {
    add('Shape', { [P.name]: name, [P.x]: x, [P.y]: y, [P.rot]: rot * RAD, [P.op]: op }, tag, parent);
    add('Ellipse', { [P.pw]: w, [P.ph]: h }, `${tag}.path`, tag);
    if (stroke) solid(tag, tag, color, 'Stroke', { [P.thick]: stroke });
    else solid(tag, tag, color);
  };
  const rect = (name, tag, parent, x, y, w, h, radius, color, { rot = 0 } = {}) => {
    add('Shape', { [P.name]: name, [P.x]: x, [P.y]: y, [P.rot]: rot * RAD }, tag, parent);
    add('Rectangle', { [P.pw]: w, [P.ph]: h, [P.cornerTL]: radius }, `${tag}.path`, tag);
    solid(tag, tag, color);
  };
  const poly = (name, tag, parent, verts, color, { closed = true, x = 0, y = 0, stroke = 0 } = {}) => {
    add('Shape', { [P.name]: name, [P.x]: x, [P.y]: y }, tag, parent);
    add('PointsPath', { [P.closed]: closed }, `${tag}.path`, tag);
    verts.forEach((v, i) => add('CubicDetachedVertex', {
      [P.vx]: v.x, [P.vy]: v.y, [P.inR]: v.inR, [P.inD]: v.inD, [P.outR]: v.outR, [P.outD]: v.outD,
    }, `${tag}.v${i}`, `${tag}.path`));
    if (stroke) solid(tag, tag, color, 'Stroke', { [P.thick]: stroke, [P.cap]: 1, [P.join]: 1 });
    else if (color.grad) {
      add('Fill', {}, `${tag}.paint`, tag);
      gradient('LinearGradient', `${tag}.paint`, `${tag}.grad`, color.grad.line, color.grad.stops);
    } else solid(tag, tag, color);
  };
  const gradient = (kind, parent, tag, [x1, y1, x2, y2], stops) => {
    add(kind, { [P.gx1]: x1, [P.gy1]: y1, [P.gx2]: x2, [P.gy2]: y2 }, tag, parent);
    stops.forEach(([col, pos], i) => add('GradientStop', { [P.stopColor]: col, [P.stopPos]: pos }, `${tag}.s${i}`, tag));
  };

  add('Artboard', { [P.name]: ch.name, [P.w]: 500, [P.h]: 500, [P.clip]: false, [P.defaultSM]: 0 }, 'artboard');
  node('Root', 'root', 'artboard', { [P.x]: 250, [P.y]: 250 });
  // Draw order: earlier siblings draw on top. Motes sit at the bottom, outside Lift.
  node('Lift', 'lift', 'root');          // presenting: scale up
  node('Talk', 'talk', 'lift');          // speaking: swell
  node('Breath', 'breath', 'talk');      // idle: breathe

  // ---- face + features (top of the character)
  const fy = ch.face; // vertical face offset per silhouette
  const eyeY = fy - 22, eyeX = 46;
  const kf = ch.feature.kind;

  // front features
  if (kf === 'brim') rect('Brim', 'feat.brim', 'breath', 0, -104, 200, 24, 12, argb(deep));
  if (kf === 'cheeks') for (const s of [-1, 1]) ellipse(`Cheek ${s}`, `feat.cheek${s}`, 'breath', s * 78, fy + 26, 46, 28, argb(hex('#FB7185'), 0.5));
  if (kf === 'bowtie') {
    poly('Bow', 'feat.bow', 'breath', [[-44, -20], [0, -6], [44, -20], [44, 20], [0, 6], [-44, 20]].map(([x, y]) =>
      ({ x, y, inR: 0, inD: 0, outR: 0, outD: 0 })), argb(hex('#4C1D95')), { y: 108 });
    ellipse('Knot', 'feat.knot', 'breath', 0, 108, 20, 20, argb(hex('#6D28D9')));
  }
  if (kf === 'glasses') {
    for (const s of [-1, 1]) ellipse(`Lens ${s}`, `feat.lens${s}`, 'breath', s * eyeX, eyeY, 74, 74, argb(INK), { stroke: 7 });
    rect('Bridge', 'feat.bridge', 'breath', 0, eyeY, 20, 7, 3, argb(INK));
  }
  if (kf === 'streak') ellipse('Streak', 'feat.streak', 'breath', -70, -60, 12, 96, argb(WHITE, 0.75), { rot: 34 });

  // mouth: a small rounded D that opens when talking (scaleY animated)
  poly('Mouth', 'mouth', 'breath', smoothVertices([[-24, 0], [0, -3], [24, 0], [0, 24]]), argb(INK), { y: fy + 44 });
  // eyes: dark oval + shine, blink scales the whole eye node
  for (const s of [-1, 1]) {
    const t = `eye${s}`;
    node(`Eye ${s}`, t, 'breath', { [P.x]: s * eyeX, [P.y]: eyeY });
    ellipse('Shine', `${t}.shine`, t, -5, -8, 9, 9, argb(WHITE, 0.95));
    ellipse('Pupil', `${t}.pupil`, t, 0, 0, 24, 32, argb(INK));
  }
  if (kf === 'ribbon') { // trailing ribbon, drawn in front at the shoulder
    poly('Ribbon', 'feat.ribbon', 'breath', smoothVertices([[76, -112], [112, -142], [148, -118], [134, -78]], false),
      argb(pale), { closed: false, stroke: 15 });
  }

  // highlight + body
  ellipse('Highlight', 'hl', 'breath', -52, -84, 76, 38, argb(WHITE, 0.32), { rot: -32 });
  poly('Body', 'body', 'breath', ch.body, {
    grad: { line: [0, -150, 0, 150], stops: [[argb(light), 0], [argb(A), 0.62], [argb(mixc(A, deep, 0.22)), 1]] },
  });
  // features behind the body
  if (kf === 'crest') {
    ellipse('Ray C', 'feat.rayc', 'breath', 0, -158, 34, 52, argb(pale));
    for (const s of [-1, 1]) ellipse(`Ray ${s}`, `feat.ray${s}`, 'breath', s * 40, -146, 24, 42, argb(light), { rot: s * 38 });
  }
  if (kf === 'sprig') {
    ellipse('Leaf A', 'feat.leafa', 'breath', 20, -150, 24, 50, argb(hex('#6EE7B7')), { rot: 32 });
    ellipse('Leaf B', 'feat.leafb', 'breath', -8, -156, 20, 42, argb(hex('#34D399')), { rot: -28 });
  }
  if (kf === 'antenna') {
    rect('Stalk', 'feat.stalk', 'breath', 0, -172, 7, 46, 3, argb(deep));
    ellipse('Bulb', 'feat.bulb', 'breath', 0, -200, 24, 24, argb(pale));
  }
  if (kf === 'halo') ellipse('Halo', 'feat.halo', 'breath', 0, -172, 84, 26, argb(hex('#FFE9B8')), { stroke: 9 });
  if (kf === 'tuft') for (const [x, r] of [[-16, -24], [0, 0], [16, 24]]) ellipse(`Tuft ${x}`, `feat.tuft${x}`, 'breath', x, -142, 16, 42, argb(deep), { rot: r });

  // ---- glow ring (only visible while presenting)
  ellipse('Glow', 'ring', 'lift', 0, 0, 372, 372, argb(light, 0.9), { stroke: 8, op: 0 });

  // ---- motes: tilt (static) > spin (animated) > dot
  ch.motes.forEach((period, i) => {
    node(`Mote ${i} Tilt`, `tilt${i}`, 'root', { [P.rot]: (i * 57 - 20) * RAD, [P.sy]: 0.78 });
    node(`Mote ${i} Spin`, `spin${i}`, `tilt${i}`);
    ellipse(`Mote ${i}`, `mote${i}`, `spin${i}`, 196 + i * 12, 0, 12 + i * 3, 12 + i * 3, argb(i === 1 ? pale : light, 0.85));
  });

  add('CubicEaseInterpolator', { [P.cx1]: EASE.x1, [P.cy1]: EASE.y1, [P.cx2]: EASE.x2, [P.cy2]: EASE.y2 }, 'ease');

  // ------------------------------------------------------- animations
  // tracks: [ [tag, propertyKey, [[frame, value, 'cubic'|'linear'], ...]], ... ]
  const anims = [];
  const anim = (name, frames, loop, tracks) => { anims.push({ name, frames, loop, tracks }); return anims.length - 1; };
  const both = (tag, a) => [[tag, P.sx, a], [tag, P.sy, a]];

  const bp = 2 * Math.round(f(ch.breath) / 2);
  anim('idle', bp, 1, both('breath', [[0, 0.98, 'cubic'], [bp / 2, 1.02, 'cubic'], [bp, 0.98, 'cubic']]));
  const bl = f(ch.blink);
  const blinkTrack = [[0, 1, 'linear'], [bl - 12, 1, 'linear'], [bl - 7, 0.08, 'linear'], [bl, 1, 'linear']];
  anim('blink', bl, 1, [['eye-1', P.sy, blinkTrack], ['eye1', P.sy, blinkTrack]]);
  ch.motes.forEach((period, i) => anim(`mote_${i}`, f(period), 1,
    [[`spin${i}`, P.rot, [[0, 0, 'linear'], [f(period), (i % 2 ? -1 : 1) * 2 * Math.PI, 'linear']]]]));

  const iUnsel = anim('unselected', 1, 0, [
    ...both('lift', [[0, 1, 'linear']]), ['ring', P.op, [[0, 0, 'linear']]],
    ...both('eye-1.shine', [[0, 1, 'linear']]), ...both('eye1.shine', [[0, 1, 'linear']]),
  ]);
  const iPres = anim('presenting', 1, 0, [
    ...both('lift', [[0, 1.08, 'linear']]), ['ring', P.op, [[0, 1, 'linear']]],
    ...both('eye-1.shine', [[0, 1.4, 'linear']]), ...both('eye1.shine', [[0, 1.4, 'linear']]),
  ]);
  const iQuiet = anim('quiet', 1, 0, [
    ...both('talk', [[0, 1, 'linear']]), ['mouth', P.sy, [[0, 0.3, 'linear']]],
  ]);
  const tl = 28; // ~0.47s speech cadence
  const iTalk = anim('talking', tl, 1, [
    ['talk', P.sx, [[0, 1, 'cubic'], [7, 1.035, 'cubic'], [14, 0.985, 'cubic'], [21, 1.03, 'cubic'], [tl, 1, 'cubic']]],
    ['talk', P.sy, [[0, 1, 'cubic'], [7, 0.975, 'cubic'], [14, 1.02, 'cubic'], [21, 0.98, 'cubic'], [tl, 1, 'cubic']]],
    ['mouth', P.sy, [[0, 0.35, 'cubic'], [5, 1, 'cubic'], [11, 0.5, 'cubic'], [17, 0.95, 'cubic'], [23, 0.4, 'cubic'], [tl, 0.35, 'cubic']]],
  ]);
  const iIdle = 0, iBlink = 1, iMote = i => 2 + i;

  const stream = [...objs];
  for (const a of anims) {
    stream.push(new Obj('LinearAnimation', { [P.animName]: a.name, [P.fps]: FPS, [P.dur]: a.frames, [P.loop]: a.loop }));
    const byObj = new Map();
    for (const [tag, pk, kfs] of a.tracks) {
      if (!idx.has(tag)) throw new Error(`anim ${a.name}: no object ${tag}`);
      if (!byObj.has(tag)) byObj.set(tag, []);
      byObj.get(tag).push([pk, kfs]);
    }
    for (const [tag, props] of byObj) {
      stream.push(new Obj('KeyedObject', { [P.koObj]: idx.get(tag) }));
      for (const [pk, kfs] of props) {
        stream.push(new Obj('KeyedProperty', { [P.kpKey]: pk }));
        for (const [frame, value, interp] of kfs) {
          const p = { [P.kfFrame]: Math.round(frame), [P.kfInterp]: interp === 'cubic' ? 2 : 1, [P.kfValue]: value };
          if (interp === 'cubic') p[P.kfInterpId] = idx.get('ease');
          stream.push(new Obj('KeyFrameDouble', p));
        }
      }
    }
  }

  // ------------------------------------------------------- state machine
  stream.push(new Obj('StateMachine', { [P.animName]: 'Voice' }));
  stream.push(new Obj('StateMachineBool', { [P.smName]: 'selected', [P.boolValue]: false }));
  stream.push(new Obj('StateMachineBool', { [P.smName]: 'speaking', [P.boolValue]: false }));
  const SEL = 0, SPK = 1;
  const easeId = idx.get('ease');
  const layerHead = name => stream.push(new Obj('StateMachineLayer', { [P.smName]: name }),
    new Obj('EntryState'), new Obj('StateTransition', { [P.toId]: 3 }), new Obj('AnyState'), new Obj('ExitState'));
  const loopLayer = (name, animIdx) => { layerHead(name); stream.push(new Obj('AnimationState', { [P.animId]: animIdx })); };
  // Boolean toggle layer: state 3 (off) <-> state 4 (on), eased mix.
  const toggleLayer = (name, offAnim, onAnim, input, ms) => {
    layerHead(name);
    const mix = to => ({ [P.toId]: to, [P.tDur]: ms, [P.tInterp]: 2, [P.tInterpId]: easeId });
    stream.push(new Obj('AnimationState', { [P.animId]: offAnim }),
      new Obj('StateTransition', mix(4)), new Obj('TransitionBoolCondition', { [P.condInput]: input, [P.condOp]: 0 }),
      new Obj('AnimationState', { [P.animId]: onAnim }),
      new Obj('StateTransition', mix(3)), new Obj('TransitionBoolCondition', { [P.condInput]: input, [P.condOp]: 1 }));
  };
  loopLayer('Base', iIdle);
  loopLayer('Blink', iBlink);
  ch.motes.forEach((_, i) => loopLayer(`Motes ${'ABC'[i]}`, iMote(i)));
  toggleLayer('Selection', iUnsel, iPres, SEL, 400);
  toggleLayer('Voice', iQuiet, iTalk, SPK, 300);
  return { stream, vertexCount: countVertices(objs) };
}

function countVertices(objs) {
  let n = 0;
  for (const o of objs) {
    if (o.type === 'CubicDetachedVertex') n++;
    else if (o.type === 'Ellipse' || o.type === 'Rectangle') n += 4;
  }
  return n;
}

// ------------------------------------------------------------ file
const stream = [new Obj('Backboard')];
const report = [];
for (const ch of CAST) {
  const { stream: s, vertexCount } = buildArtboard(ch);
  stream.push(...s);
  report.push(`${ch.name}: ${vertexCount} vertices`);
}
report.forEach(l => console.log(l));

const body_ = new W();
for (const o of stream) writeObject(body_, o);
const head = new W();
'RIVE'.split('').forEach(ch => head.byte(ch.charCodeAt(0)));
head.varuint(7); head.varuint(0); head.varuint(0);
// ToC: every property written, with its backing type (0 uint/bool, 1 string, 2 double, 3 color)
const keys = [...ANY_KEYS].sort((a, b) => a - b);
keys.forEach(key => head.varuint(key)); head.varuint(0);
const code = t => ({ uint: 0, bool: 0, string: 1, double: 2, color: 3 })[t];
for (let i = 0; i < keys.length; i += 4) {
  let v = 0;
  for (let j = 0; j < 4 && i + j < keys.length; j++) v |= code(PROP[keys[i + j]]) << (j * 2);
  head.u32(v);
}
const out = Buffer.from([...head.b, ...body_.b]);
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, out);
console.log('wrote', OUT, out.length, 'bytes,', stream.length, 'objects');
