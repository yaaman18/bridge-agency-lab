// Stage 32 tests of the material layer (matter.js), constituents with fixed rules (no learning yet).
const M = require("./matter.js"), fs = require("fs");
function sources(w, t, scale, starve) {
  const W = w.p.W, on = Math.floor(t / 500) % 2 === 0, s = [];
  if (starve && t >= starve[0] && t < starve[1]) return s;
  for (const [cx, cy] of [[6, 12], [18, 12]]) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (on ? 1 : 0.3) * w.p.SRC * scale]);
  return s;
}
function run({ steps, scale = 1, starve = null, spontaneous = false, at = [12, 12], damageAt = null }) {
  const w = M.makeWorld({ reservoir: 300, spontaneous }); M.seed(w, at[0], at[1], 1); const T0 = M.total(w), log = []; let maxErr = 0;
  for (let t = 0; t < steps; t++) {
    if (damageAt === t) for (let i = 0; i < w.C.length; i++) if (w.C[i] && (i % w.p.W) < 12) { w.A[i] += w.B[i]; w.B[i] = 0; w.C[i] = 0; }
    M.step(w, sources(w, t, scale, starve)); maxErr = Math.max(maxErr, Math.abs(M.total(w) - T0));
    if ((t + 1) % 100 === 0) log.push(M.count(w).constituents);
  }
  return { log, maxErr };
}
const R = {};
for (const sc of [0.5, 1, 2]) for (const at of [[12, 12], [9, 15]]) R[`persist x${sc} at${at}`] = run({ steps: 5000, scale: sc, at });
R["starve1000 A-gen"] = run({ steps: 6000, starve: [1000, 2000] });
R["starve1000 spontaneous"] = run({ steps: 6000, starve: [1000, 2000], spontaneous: true });
R["starve200 A-gen"] = run({ steps: 4000, starve: [1000, 1200] });
R["twin"] = run({ steps: 4000 }); R["damaged"] = run({ steps: 4000, damageAt: 2000 });
fs.writeFileSync(__dirname + "/results-matter.json", JSON.stringify(R));
for (const [k, r] of Object.entries(R)) console.log(k.padEnd(26), "maxErr", r.maxErr.toExponential(1), "min", Math.min(...r.log), "| every 500:", r.log.filter((_, i) => i % 5 === 4).join(" "));
const tw = R.twin.log, dm = R.damaged.log; console.log("regeneration: damaged/twin at +500,+1000,+1500,+2000:", [24, 29, 34, 39].map(i => (dm[i] / tw[i]).toFixed(2)).join(" "), " (step 2000 damaged count right after:", dm[20], "twin", tw[20], ")");
