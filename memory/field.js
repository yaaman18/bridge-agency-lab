// State field (2026-10-31, user decision: build the proposed field). Measures, for a circuit of the memory.js family
// (memory.js, partner*.js, turn.js: same step/form/newborn API), its position in the field of README "用語と状態の場":
//   M  material: 1 always (these circuits have no material).
//   F  present form: max over directed cycles among non-sensory units active in the window, through edges with
//      confidence >= 1 (the edges of form()), of the mean confidence / smax along the cycle; 0 if no cycle (form lost).
//   L  latent form: the same over all non-sensory units and every edge that can transmit (confidence >= 1 or sediment
//      >= 1), weighted by max(confidence, sediment) / smax; a cheap stand-in for R.
//   R  recoverability: 1 - T/N, T = steps until form() holds again in the most favourable world (both patches at yield
//      5; with a partner, a fresh gesture 2 steps after every call), N = 1000 (one season cycle). 1 if formed now, 0 if
//      form does not return within N steps (organizational death, as far as N can tell).
//   Phi is defined in the README and not computed.
const N = 1000;
function maxMeanCycle(nodes, w) {          // w(u,v) -> weight in (0,1] or 0 (no edge); simple cycles by DFS (few units)
  const ns = [...nodes].sort((a, c) => a - c); let best = 0;
  for (const s of ns) {
    const dfs = (u, sum, len, seen) => {
      for (const v of ns) { if (v < s) continue; const x = w(u, v); if (!x) continue;
        if (v === s) { best = Math.max(best, (sum + x) / (len + 1)); continue; }
        if (!seen.has(v)) { seen.add(v); dfs(v, sum + x, len + 1, seen); seen.delete(v); } }
    };
    dfs(s, 0, 0, new Set([s]));
  }
  return best;
}
function edgeW(b, pick) { const m = new Map(); b.edges.forEach(([a, c], k) => { const x = pick(k); if (x > 0) m.set(a + "," + c, Math.max(m.get(a + "," + c) || 0, x)); }); return (u, v) => m.get(u + "," + v) || 0; }
function measureF(win, b, smax = 4) {
  const U = new Set(); for (const w of win) w.active.forEach((a, u) => { if (a && b.kind[u] !== "R" && b.kind[u] !== "J") U.add(u); });
  const q = win[win.length - 1].q; return +maxMeanCycle(U, edgeW(b, k => q[k] >= 1 ? q[k] / smax : 0)).toFixed(3);
}
function measureL(st, b, smax = 4) {
  const U = new Set(b.names.map((_, u) => u).filter(u => b.kind[u] !== "R" && b.kind[u] !== "J"));
  return +maxMeanCycle(U, edgeW(b, k => Math.max(st.q[k], (st.sg || [])[k] || 0) / smax)).toFixed(3);
}
function rescue(E, st0, b, opts = {}) {
  const st = JSON.parse(JSON.stringify(st0)), noise = E.rng(99), win = [], partner = !!opts.partner; let due = null, rot = 0;
  for (let t = 1; t <= N; t++) {
    let g = 0; if (partner && due === st.t + 1) { g = (rot++ % 4) + 1; due = null; }
    const o = E.step(st, b, partner ? [5, 5, g] : [5, 5], { noise });
    if (partner && o.call && due === null) due = st.t + 2;
    win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > 5) win.shift();
    if (E.form(win, b)) return +(1 - t / N).toFixed(3);
  }
  return 0;
}
function position(E, st, b, win, opts) {
  const F = measureF(win, b), L = measureL(st, b);
  return { M: 1, F, L, R: F > 0 ? 1 : rescue(E, st, b, opts) };
}
function region(p) { return p.M === 0 ? "物質の死" : p.F > 0 ? "生存" : p.R > 0 ? "休眠" : "組織の死"; }
module.exports = { N, measureF, measureL, rescue, position, region, maxMeanCycle };
