// Stage 50: the contrast rule learn2 in the organization world (no material body). Per seed 1-5, turn.js vs
// turn_learn2.js, partner units present but no partner (gesture 0): curriculum 800, world 3000 steps, receptors crossed
// (r1/r2, r3/r4, r7/r8), 3000 more. Measures: answered fraction of patch acts (last 1000 before the crossing; steps
// 1000-3000 after it), steps after the crossing until 50 consecutive patch acts are 90% answered, and the sediment on
// noise/clock -> patch motors (r5, r6 -> m1, m2) at the crossing.
const CORES = { OLD: require("./turn.js"), L2: require("./turn_learn2.js") };
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const CUR = []; for (let i = 0; i < 400; i++) CUR.push([[5, 0], [0, 5]][Math.floor(i / 50) % 2]); for (let i = 0; i < 400; i++) CUR.push([[5, 2], [2, 5]][Math.floor((i) / 15) % 2]);
function run(N, seed) {
  const ORIG = N.FEATURES.slice(), b = N.newborn(true), st = N.init(b), noise = N.rng(seed), ek = (a, c) => b.edges.findIndex(e => b.names[e[0]] === a && b.names[e[1]] === c);
  for (const y of CUR) N.step(st, b, [...y, 0], { noise });
  let R = [50, 50], wt = 0; const ans = []; let junk = null;
  for (let i = 0; i < 6000; i++) {
    if (i === 3000) { junk = ["r5", "r6"].reduce((s, r) => s + st.sg[ek(r, "m1")] + st.sg[ek(r, "m2")], 0); for (const [p, q] of [[0, 1], [2, 3], [6, 7]]) { const a = N.FEATURES[p]; N.FEATURES[p] = N.FEATURES[q]; N.FEATURES[q] = a; } }
    const o = N.step(st, b, [Math.min(R[0], 5), Math.min(R[1], 5), 0], { noise });
    wt++; R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + season(wt)[k]));
    for (const a of o.acting) if (b.patch[a] <= 2) ans.push([i, o.answered.get(a) ? 1 : 0]);
  }
  N.FEATURES.splice(0, N.FEATURES.length, ...ORIG);
  const frac = (a, z) => { const x = ans.filter(([i]) => i >= a && i < z); return x.length ? x.reduce((s, [, v]) => s + v, 0) / x.length : 0; };
  let rec = null; const post = ans.filter(([i]) => i >= 3000); for (let j = 0; j + 50 <= post.length; j++) if (post.slice(j, j + 50).reduce((s, [, v]) => s + v, 0) >= 45) { rec = post[j][0] - 3000; break; }
  const actsPerStep = (a, z) => ans.filter(([i]) => i >= a && i < z).length / (z - a);
  return { pre: +frac(2000, 3000).toFixed(3), post: +frac(4000, 6000).toFixed(3), rec, junk, actsPre: +actsPerStep(2000, 3000).toFixed(2), actsPost: +actsPerStep(4000, 6000).toFixed(2) };
}
const R = {};
for (const seed of [1, 2, 3, 4, 5]) { R[seed] = {}; for (const [k, N] of Object.entries(CORES)) R[seed][k] = run(N, seed); console.log(seed, JSON.stringify(R[seed])); }
require("fs").writeFileSync(__dirname + "/results-org-learn2.json", JSON.stringify(R, null, 1));
