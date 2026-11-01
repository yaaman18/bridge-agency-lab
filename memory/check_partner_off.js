// Regression: partner.js with partner=false must reproduce memory.js step for step (q, sg, active, acting) over the
// protocol of test_memory.js (curriculum, 10 world cycles, reversal, 1000 steps), seeds 1-5, memory ON and OFF.
const M = require("./memory.js"), N = require(process.env.CORE || "./partner.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
let bad = 0, steps = 0;
for (const seed of [1, 2, 3, 4, 5]) for (const memory of [true, false]) {
  const OM = M.FEATURES.slice(), ON = N.FEATURES.slice();
  const bm = M.newborn(), bn = N.newborn(false), sm = M.init(bm), sn = N.init(bn), rm = M.rng(seed), rn = N.rng(seed);
  if (JSON.stringify(bm.edges) !== JSON.stringify(bn.edges)) { console.log("edges differ"); process.exit(1); }
  let R = [50, 50], wt = 0;
  const sched = [];
  for (let i = 0; i < 400; i++) sched.push(() => [[5, 0], [0, 5]][Math.floor(i / 50) % 2]);
  for (let i = 0; i < 400; i++) sched.push(() => [[5, 2], [2, 5]][Math.floor(i / 15) % 2]);
  for (let i = 0; i < 11000; i++) sched.push(null);
  sched.forEach((f, i) => {
    if (i === 800 + 10000) for (const F of [M.FEATURES, N.FEATURES]) for (const [a, c] of [[0, 1], [2, 3], [6, 7]]) { const x = F[a]; F[a] = F[c]; F[c] = x; }
    const world = f === null, y = world ? [Math.min(R[0], 5), Math.min(R[1], 5)] : f();
    const om = M.step(sm, bm, y, { memory, noise: rm }), on = N.step(sn, bn, [...y, 0], { memory, noise: rn });
    if (world) { wt++; R = [0, 1].map(k => Math.min(50, R[k] - om.d[k] + season(wt)[k])); }
    steps++;
    if (JSON.stringify([sm.q, sm.sg, sm.active, om.acting, om.d]) !== JSON.stringify([sn.q, sn.sg, sn.active, on.acting, on.d])) bad++;
  });
  M.FEATURES.splice(0, M.FEATURES.length, ...OM); N.FEATURES.splice(0, N.FEATURES.length, ...ON);
}
console.log(`partner=false vs memory.js: ${steps - bad}/${steps} steps identical`);
