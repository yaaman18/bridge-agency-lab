// Stage 36: a variable world, where inherited constants cannot fit and within-life learning could pay (Baldwin):
// per life, the season period is drawn from 300-800 steps, and every 1000 steps the two source patches move to new random
// sites. Modes predact / frozen / nogate of trm2.js, seeds 1-3, 8000 steps, supply x1.
const T = require("./trm2.js"), M = require("./matter2.js"), fs = require("fs");
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function env(seed) {
  const r = rng(seed * 7 + 3), period = 300 + Math.floor(r() * 501), sites = [];
  for (let k = 0; k < 8; k++) sites.push([[2 + Math.floor(r() * 20), 2 + Math.floor(r() * 20)], [2 + Math.floor(r() * 20), 2 + Math.floor(r() * 20)]]);
  return { period, sites, src(w, t) { const W = w.p.W, rich = Math.floor(t / period) % 2 === 0, s = [], pair = t < 1000 ? [[6, 12], [18, 12]] : sites[Math.floor(t / 1000) - 1];
    for (const [cx, cy] of pair) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (rich ? 1 : 0.3) * w.p.SRC]); return s; } };
}
const R = {};
for (const mode of ["predact", "frozen", "nogate"]) for (const seed of [1, 2, 3]) {
  const E = env(seed), L = T.makeLife(mode, seed), T0 = M.total(L.w), counts = []; let maxErr = 0;
  for (let t = 0; t < 8000; t++) { L.step(E.src(L.w, t)); maxErr = Math.max(maxErr, Math.abs(M.total(L.w) - T0)); if ((t + 1) % 50 === 0) counts.push(L.stats().count); }
  const after = counts.slice(40), postMove = []; for (let m = 1000; m < 8000; m += 1000) postMove.push(Math.min(...counts.slice(m / 50, m / 50 + 10)));
  R[`${mode}/${seed}`] = { period: E.period, maxErr, min: Math.min(...counts), mean: +(after.reduce((s, x) => s + x, 0) / after.length).toFixed(1), minAfterMoves: Math.min(...postMove), meanMinAfterMoves: +(postMove.reduce((s, x) => s + x, 0) / postMove.length).toFixed(1), final: L.stats() };
  console.log(`${mode}/${seed}`, JSON.stringify(R[`${mode}/${seed}`]));
}
fs.writeFileSync(__dirname + "/results-var.json", JSON.stringify(R, null, 1));
