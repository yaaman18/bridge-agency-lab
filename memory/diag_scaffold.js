// S4 of predictions-scaffold.md: what drives the calls made while waiting (SCAF-ADULT, last 1000 steps of phase A).
const N = require(process.env.CORE || "./turn.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const out = {};
for (const seed of [1, 2, 3, 4, 5]) {
  const b = N.newborn(true), st = N.init(b), noise = N.rng(seed);
  for (let i = 0; i < 800; i++) N.step(st, b, [...(i < 400 ? [[5, 0], [0, 5]][Math.floor(i / 50) % 2] : [[5, 2], [2, 5]][Math.floor((i - 400) / 15) % 2]), 0], { noise });
  const pr = N.rng(seed + 1000); let sched = null, rot = 0, s = 0, R = [50, 50], wt = 0, lastG = -99;
  const cnt = { waitingCalls: 0, afterGesture: 0, drivers: {} };
  for (let i = 0; i < 3000; i++) {
    const now = st.t + 1; s++; const s1 = pr(); let g = 0;
    if (sched === now) { sched = null; g = (rot++ % 4) + 1; } else if (s1 < 0.01) g = 1 + Math.floor(pr() * 4);
    const o = N.step(st, b, [Math.min(R[0], 5), Math.min(R[1], 5), g], { noise });
    if (o.call && sched === null) { const p = !o.callWhileWaiting ? 0.8 : 0.8 * Math.max(0, 1 - s / 1500); const a = pr(), dl = pr(); if (a < p) sched = now + 2 + Math.floor(dl * 7); }
    wt++; R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + season(wt)[k]));
    if (i >= 2000 && o.call && o.callWhileWaiting) {
      cnt.waitingCalls++; if (i - lastG === 1) cnt.afterGesture++;
      const p = st.pend[st.pend.length - 1]; for (const k of p.R) { const n = b.names[b.edges[k][0]]; cnt.drivers[n] = (cnt.drivers[n] || 0) + 1; }
      if (!p.R.length) cnt.drivers.none = (cnt.drivers.none || 0) + 1;
    }
    if (g) lastG = i;
  }
  out[seed] = { ...cnt, afterGestureShare: +(cnt.afterGesture / Math.max(1, cnt.waitingCalls)).toFixed(3) };
}
require("fs").writeFileSync(__dirname + "/results-diag-scaffold.json", JSON.stringify(out, null, 1));
for (const [s, c] of Object.entries(out)) console.log(s, JSON.stringify(c));
