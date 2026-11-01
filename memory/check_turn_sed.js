// turn_sed.js without opts.contrast must reproduce turn.js step for step (curriculum + 10000 world steps, seeds 1-5,
// partner off and on with scripted gestures every 37 steps).
const A = require("./turn.js"), B = require("./turn_sed.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
let bad = 0, steps = 0;
for (const seed of [1, 2, 3, 4, 5]) for (const partner of [false, true]) {
  const ba = A.newborn(partner), bb = B.newborn(partner), sa = A.init(ba), sb = B.init(bb), ra = A.rng(seed), rb = B.rng(seed); let R = [50, 50];
  for (let i = 0; i < 10800; i++) {
    const y = i < 400 ? [[5, 0], [0, 5]][Math.floor(i / 50) % 2] : i < 800 ? [[5, 2], [2, 5]][Math.floor((i - 400) / 15) % 2] : [Math.min(R[0], 5), Math.min(R[1], 5)];
    const g = partner && i % 37 === 0 ? 1 + (i % 4) : 0;
    const oa = A.step(sa, ba, [...y, g], { noise: ra }), ob = B.step(sb, bb, [...y, g], { noise: rb });
    if (i >= 800) R = [0, 1].map(k => Math.min(50, R[k] - oa.d[k] + season(i - 799)[k]));
    steps++; if (JSON.stringify([sa, oa.acting, oa.d]) !== JSON.stringify([sb, ob.acting, ob.d])) bad++;
  }
}
console.log(`turn_sed.js without contrast vs turn.js: ${steps - bad}/${steps} steps identical`);
