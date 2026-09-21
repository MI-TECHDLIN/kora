import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { capacity, encodeQr, toPath } from "../js/qr.js";

// Golden matrices produced by the Python `qrcode` package (ECC M, border 0).
const fixtures = JSON.parse(readFileSync(new URL("./qr_fixtures.json", import.meta.url), "utf8"));

// Forced-mask fixtures only: the reference picks its automatic mask with a non-ISO penalty
// score, so "auto" is checked for self-consistency below instead. Any of the 8 masks decodes.
for (const f of fixtures.filter((x) => x.mask !== null)) {
  test(`QR matches reference: v${f.version} mask=${f.mask} ${JSON.stringify(f.text.slice(0, 28))}`, () => {
    const q = encodeQr(f.text, { mask: f.mask });
    assert.equal(q.version, f.version);
    const rows = q.modules.map((r) => [...r].join(""));
    assert.deepEqual(rows, f.rows);
  });
}

test("capacity grows with version and matches known ECC-M byte capacities", () => {
  assert.deepEqual([1, 2, 5, 10].map(capacity), [14, 26, 84, 213]);
});

test("too-long text throws a clear error", () => {
  assert.throws(() => encodeQr("x".repeat(214)), /too long/);
});

test("toPath draws only dark modules inside the quiet zone", () => {
  const d = toPath([Uint8Array.from([1, 1, 0]), Uint8Array.from([0, 0, 1]), Uint8Array.from([0, 0, 0])], 4);
  assert.equal(d, "M4 4h2v1h-2zM6 5h1v1h-1z");
});

test("automatic mask selection yields a valid, reproducible symbol", () => {
  for (const text of new Set(fixtures.map((f) => f.text))) {
    const auto = encodeQr(text);
    assert.ok(auto.mask >= 0 && auto.mask < 8);
    assert.deepEqual(auto.modules.map((r) => [...r].join("")), encodeQr(text, { mask: auto.mask }).modules.map((r) => [...r].join("")));
  }
});
