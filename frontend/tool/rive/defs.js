// Parse rive-runtime's generated *_base.hpp headers (bundled with rive_native)
// into { ClassName: { parent, typeKey, props: { name: {key, type, def} } } }.
// node defs.js > defs.json
const fs = require('fs');
const path = require('path');
const RT = path.join(process.env.LOCALAPPDATA, 'Pub/Cache/hosted/pub.dev/rive_native-0.1.11/runtime/include/rive/generated');

function walk(d, out = []) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (fs.statSync(p).isDirectory()) walk(p, out); else if (f.endsWith('_base.hpp')) out.push(p);
  }
  return out;
}
const TYPES = { CoreUintType: 'uint', CoreDoubleType: 'double', CoreStringType: 'string', CoreColorType: 'color', CoreBoolType: 'bool', CoreBytesType: 'bytes', CoreUint64Type: 'uint64' };
const defs = {};
for (const f of walk(RT)) {
  const src = fs.readFileSync(f, 'utf8');
  const m = src.match(/class (\w+)Base\s*:\s*public\s+([\w:]+)/);
  if (!m) continue;
  const name = m[1];
  const parent = m[2].replace(/^rive::/, '');
  const tk = src.match(/static const uint16_t typeKey = (\d+);/);
  const props = {};
  for (const pm of src.matchAll(/static const uint16_t (\w+)PropertyKey = (\d+);/g)) props[pm[1]] = { key: +pm[2] };
  // field types from deserialize switch: case xPropertyKey: m_X = CoreDoubleType::deserialize(reader)
  for (const dm of src.matchAll(/case (\w+)PropertyKey:\s*\n?\s*m_\w+ = (Core\w+Type)::deserialize/g)) {
    if (props[dm[1]]) props[dm[1]].type = TYPES[dm[2]] || dm[2];
  }
  // defaults: Type m_Name = value;
  for (const vm of src.matchAll(/^\s*[\w:<>]+ m_(\w+) = ([^;]+);/gm)) {
    const pn = vm[1][0].toLowerCase() + vm[1].slice(1);
    const hit = Object.keys(props).find(k => k.toLowerCase() === pn.toLowerCase());
    if (hit) props[hit].def = vm[2].trim();
  }
  defs[name] = { parent: parent.replace(/Base$/, ''), typeKey: tk ? +tk[1] : null, props, file: path.relative(RT, f) };
}
fs.writeFileSync(path.join(__dirname, 'defs.json'), JSON.stringify(defs, null, 1));
console.log(Object.keys(defs).length, 'classes');
