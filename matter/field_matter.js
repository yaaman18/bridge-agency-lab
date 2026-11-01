// Stage 34: the state field on the material layer. During a starvation that starts at step 4000 (supply x1 before),
// every 50 steps: M = bound matter / bound matter at 4000, F = form share (trm.js stats().F), count, and
// R = 1 - T/1000, T = steps until F > 0 again in the most favourable world (rich supply x2, every step), run on a clone;
// R = 1 if F > 0 now; R = 0 if no constituent is left (A-gen: material death) or F does not return within 1000 steps.
const T = require("./trm.js"), M = require("./matter2.js"), fs = require("fs");
function clone(L, mode, seed) {
  const L2 = T.makeLife(mode, seed + 100), w = L.w, v = L2.w;
  v.A.set(w.A); v.B.set(w.B); v.C.set(w.C); Object.assign(v.port, { reservoir: w.port.reservoir, inflow: w.port.inflow, outflow: w.port.outflow }); v.t = w.t;
  L2.net.splice(0, L2.net.length, ...JSON.parse(JSON.stringify(L.net))); L2.act.set(L.act); return L2;
}
function rich(w) { const W = w.p.W, s = []; for (const [cx, cy] of [[6, 12], [18, 12]]) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, 2 * w.p.SRC]); return s; }
function R(L, mode, seed) {
  const s = L.stats(); if (s.F > 0) return 1; if (s.count === 0) return 0;
  const L2 = clone(L, mode, seed); for (let t = 1; t <= 1000; t++) { L2.step(rich(L2.w)); const x = L2.stats(); if (x.F > 0) return +(1 - t / 1000).toFixed(3); if (x.count === 0) return 0; } return 0;
}
const out = {};
for (const [mode, seed] of [["trm", 1], ["trm", 2], ["trm", 3], ["fixed", 1]]) {
  const L = T.makeLife(mode, seed); for (let t = 0; t < 4000; t++) L.step(T.sources(L.w, t, 1));
  const b0 = L.stats().bound, pts = [];
  for (let t = 4000; t < 6000; t++) { if ((t - 4000) % 50 === 0) { const s = L.stats(), r = R(L, mode, seed); pts.push({ t, M: +(s.bound / b0).toFixed(3), F: +s.F.toFixed(3), count: s.count, R: r,
      region: s.count === 0 ? "物質の死" : s.F > 0 ? "生存" : r > 0 ? "休眠" : "組織の死" }); if (s.count === 0) break; }
    L.step([]); }
  out[`${mode}/${seed}`] = pts;
  const reg = {}; pts.forEach(p => reg[p.region] = (reg[p.region] || 0) + 1);
  console.log(`${mode}/${seed}`, JSON.stringify(reg), pts.map(p => `${p.t - 4000}:${p.M}/${p.F}/${p.count}/${p.R}`).join(" "));
}
fs.writeFileSync(__dirname + "/results-field-matter.json", JSON.stringify(out, null, 1));
