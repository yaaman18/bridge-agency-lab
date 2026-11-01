// Stage 33 tests: TRM-type constituents vs the stage 32 fixed rule and two ablations, seeds 1-3.
const T = require("./trm.js"), M = require("./matter2.js"), fs = require("fs");
function run(mode, seed, { steps = 6000, scale = 1, starve = null, damageAt = null } = {}) {
  const L = T.makeLife(mode, seed), w = L.w, T0 = M.total(w), log = [], acts = []; let maxErr = 0;
  for (let t = 0; t < steps; t++) {
    if (damageAt === t) for (let i = 0; i < w.C.length; i++) if (w.C[i] && (i % w.p.W) < 12) { w.A[i] += w.B[i]; w.B[i] = 0; w.C[i] = 0; L.net[i] = null; }
    L.step(T.sources(w, t, scale, starve)); maxErr = Math.max(maxErr, Math.abs(M.total(w) - T0));
    const s = L.stats(); if ((t + 1) % 100 === 0) log.push(s); acts.push(s.activity);
  }
  return { log, acts, maxErr };
}
const modes = ["trm", "fixed", "nogate", "noinherit"], seeds = [1, 2, 3], R = {};
for (const mode of modes) for (const seed of seeds) {
  const k = `${mode}/${seed}`, r = R[k] = {};
  for (const sc of [0.5, 1]) { const x = run(mode, seed, { scale: sc }); r["x" + sc] = { min: Math.min(...x.log.map(s => s.count)), maxErr: x.maxErr,
    leanMean: mean(x.log.filter((_, i) => i >= 30 && Math.floor(i / 5) % 2 === 1).map(s => s.count)), richMean: mean(x.log.filter((_, i) => i >= 30 && Math.floor(i / 5) % 2 === 0).map(s => s.count)),
    precision: mean(x.log.slice(30).map(s => s.precision)), F: mean(x.log.slice(30).map(s => s.F)),
    actBeforeLean: mean([1500, 2500, 3500, 4500, 5500].filter(t => t >= 3000).flatMap(t => x.acts.slice(t - 100, t))), actBeforeRich: mean([3000, 4000, 5000].flatMap(t => x.acts.slice(t - 100, t))) }; }
  r.survived = {}; for (const Ls of [500, 1000, 1500]) { const x = run(mode, seed, { steps: 4000 + Ls + 2000, starve: [4000, 4000 + Ls] }); r.survived[Ls] = x.log[x.log.length - 1].count > 0; r.maxErrStarve = Math.max(r.maxErrStarve || 0, x.maxErr); }
  const tw = run(mode, seed, { steps: 5500 }), dm = run(mode, seed, { steps: 5500, damageAt: 4000 });
  r.regen = [44, 49, 54].map(i => +(dm.log[i].count / Math.max(1, tw.log[i].count)).toFixed(2));
  console.log(k.padEnd(12), JSON.stringify(r));
}
function mean(a) { return a.length ? +(a.reduce((s, x) => s + x, 0) / a.length).toFixed(3) : null; }
fs.writeFileSync(__dirname + "/results-trm.json", JSON.stringify(R, null, 1));
