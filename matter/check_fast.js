// Bit-identity check: fmatter.js vs matter2.js and fevo.js vs evo_trm.js (all four trm modes, 48x48 and 24x24).
const E0 = require("./evo_trm.js"), E1 = require("./fevo.js"), M0 = require("./matter2.js"), M1 = require("./fmatter.js");
const P = [[8, 8], [24, 8], [40, 8], [8, 40], [24, 40], [40, 40]], S = [[8, 12], [24, 12], [40, 12], [8, 36], [24, 36], [40, 36], [8, 4], [24, 4], [40, 44]];
function src(w, t, scale, W) { const s = [], rich = Math.floor(t / 500) % 2 === 0; for (const [cx, cy] of (W === 48 ? P : [[6, 12], [18, 12]])) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (rich ? 1 : 0.3) * w.p.SRC * scale]); return s; }
const snap = L => JSON.stringify([Array.from(L.w.A), Array.from(L.w.B), Array.from(L.w.C), L.net, Array.from(L.act), L.w.port.reservoir, L.w.born, L.w.died]);
let ok = true; const t0 = Date.now(); let tOld = 0, tNew = 0;
for (const mode of ["nogate", "trm", "predact", "frozen"]) for (const [W, scale] of [[48, 0.5], [48, 2], [24, 1]]) {
  const opts = W === 48 ? { W: 48, H: 48, reservoir: 1200, seeds: S } : {};
  const a = E0.makeLife(mode, 1, opts), b = E1.makeLife(mode, 1, opts);
  let s = Date.now(); for (let t = 0; t < 1500; t++) a.step(src(a.w, t, scale, W)); tOld += Date.now() - s;
  s = Date.now(); for (let t = 0; t < 1500; t++) b.step(src(b.w, t, scale, W)); tNew += Date.now() - s;
  const same = snap(a) === snap(b); ok = ok && same; console.log(mode, W, scale, same ? "identical" : "DIFFERENT");
}
console.log("all identical:", ok, "| time old", tOld, "ms new", tNew, "ms, speed-up", (tOld / tNew).toFixed(1) + "x");
