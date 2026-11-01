// Regression: orient.js with orient=false reproduces partner.js rev. 3 step for step, with a scripted responsive partner
// (seeds 1-5, curriculum then 6000 world steps).
const A = require("./partner.js"), B = require("./orient.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
let same = 0, n = 0;
for (const seed of [1, 2, 3, 4, 5]) {
  const ba = A.newborn(true), bb = B.newborn(true), sa = A.init(ba), sb = B.init(bb), ra = A.rng(seed), rb = B.rng(seed), pr = A.rng(seed + 1000);
  let R = [50, 50], wt = 0, sched = null;
  for (let i = 0; i < 6800; i++) {
    let y, g = 0; const now = sa.t + 1;
    if (i < 400) y = [[5, 0], [0, 5]][Math.floor(i / 50) % 2]; else if (i < 800) y = [[5, 2], [2, 5]][Math.floor((i - 400) / 15) % 2];
    else { y = [Math.min(R[0], 5), Math.min(R[1], 5)]; const s = pr(); if (sched === now) { sched = null; g = 1 + (now % 4); } else if (s < 0.01) g = 1 + Math.floor(pr() * 4); }
    const oa = A.step(sa, ba, [...y, g], { noise: ra }), ob = B.step(sb, bb, [...y, g], { noise: rb, orient: false });
    if (i >= 800) { if (oa.call && sched === null) { const a = pr(), d = pr(); if (a < 0.8) sched = now + 2 + Math.floor(d * 7); } wt++; R = [0, 1].map(k => Math.min(50, R[k] - oa.d[k] + season(wt)[k])); }
    n++; if (JSON.stringify([sa.q, sa.sg, sa.active, oa.acting, oa.callAnswered]) === JSON.stringify([sb.q, sb.sg, sb.active, ob.acting, ob.callAnswered])) same++;
  }
}
console.log(`orient=false vs partner.js: ${same}/${n} steps identical`);
