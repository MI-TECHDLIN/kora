// Dump a .riv as a readable object stream using defs.json (runtime schema).
// node dump.js file.riv [filterRegex]
const fs = require('fs');
const defs = require('./defs.json');
const byKey = {}, propInfo = {};
for (const [name, c] of Object.entries(defs)) {
  if (c.typeKey != null) byKey[c.typeKey] = name;
  for (const [pn, p] of Object.entries(c.props)) propInfo[p.key] = { name: pn, type: p.type, owner: name };
}
const buf = fs.readFileSync(process.argv[2]);
let o = 0;
const varuint = () => { let r = 0, s = 0, b; do { b = buf[o++]; r += (b & 0x7f) * 2 ** s; s += 7; } while (b & 0x80); return r; };
const u32 = () => { const v = buf.readUInt32LE(o); o += 4; return v; };
if (buf.toString('latin1', 0, 4) !== 'RIVE') throw new Error('not a riv');
o = 4;
const major = varuint(), minor = varuint(), fileId = varuint();
const toc = []; for (let k = varuint(); k !== 0; k = varuint()) toc.push(k);
const tocType = {}; let cur = 0, bit = 8;
for (const k of toc) { if (bit === 8) { cur = u32(); bit = 0; } tocType[k] = ['uint', 'string', 'double', 'color'][(cur >> bit) & 3]; bit += 2; }
console.log(`RIVE ${major}.${minor} fileId=${fileId} toc=${JSON.stringify(toc.map(k => k + ':' + tocType[k]))}`);
const filter = process.argv[3] ? new RegExp(process.argv[3]) : null;
let idx = 0;
while (o < buf.length) {
  const tk = varuint();
  const name = byKey[tk] || `?${tk}`;
  const props = [];
  for (let pk = varuint(); pk !== 0; pk = varuint()) {
    const info = propInfo[pk] || {};
    let t = info.type || tocType[pk];
    if (t === 'bool') t = 'uint'; // bools are varuint-ish? handled below
    let v;
    const ft = info.type || tocType[pk];
    if (ft === 'double') { v = +buf.readFloatLE(o).toFixed(4); o += 4; }
    else if (ft === 'color') { v = '#' + u32().toString(16).padStart(8, '0'); }
    else if (ft === 'string' || ft === 'bytes') { const n = varuint(); v = ft === 'string' ? JSON.stringify(buf.toString('utf8', o, o + n)) : '[' + [...buf.slice(o, o + n)].join(',') + ']'; o += n; }
    else if (ft === 'bool') { v = buf[o++]; }
    else { v = varuint(); }
    props.push(`${info.name || '?' + pk}(${pk})=${v}`);
  }
  const line = `${String(idx).padStart(4)} ${name}(${tk}) ${props.join(' ')}`;
  if (!filter || filter.test(line)) console.log(line);
  idx++;
}
