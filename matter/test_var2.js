// Stage 37: (1) the variable world with 10 seeds and two strengths of variation (sources move every MOVE = 1000 or 500
// steps; season period drawn per life from 300-800 or 200-800), modes predact / frozen / nogate of trm2.js; (2) two form
// measures that do not depend on the prediction currency:
//   F_conn   share of constituents in connected groups (>= 3) of neighbouring constituents (the body's spatial cohesion);
//   F_coup   the same, counting only constituents whose latent is actually moved by their neighbours: |Wn zbar| >= 0.1
//            (zbar = mean latent of neighbouring constituents) — the coupling structure of the body.
// Paired comparison per seed (same world for all modes of a seed).
const T = require("./trm2.js"), M = require("./matter2.js"), fs = require("fs");
const MOVE = +(process.env.MOVE || 1000), PMIN = MOVE === 1000 ? 300 : 200, SEEDS = 10, STEPS = 8000;
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function env(seed) {
  const r = rng(seed * 7 + 3), period = PMIN + Math.floor(r() * (801 - PMIN)), sites = [];
  for (let k = 0; k < Math.ceil(STEPS / MOVE); k++) sites.push([[2 + Math.floor(r() * 20), 2 + Math.floor(r() * 20)], [2 + Math.floor(r() * 20), 2 + Math.floor(r() * 20)]]);
  return { period, src(w, t) { const W = w.p.W, rich = Math.floor(t / period) % 2 === 0, s = [], pair = t < MOVE ? [[6, 12], [18, 12]] : sites[Math.floor(t / MOVE) - 1];
    for (const [cx, cy] of pair) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (rich ? 1 : 0.3) * w.p.SRC]); return s; } };
}
function forms(L) {
  const w = L.w, W = w.p.W, H = w.p.H, n = W * H, nb = i => { const x = i % W, y = (i / W) | 0; return [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => ((y + dy + H) % H) * W + ((x + dx + W) % W)); };
  const coupled = new Uint8Array(n);
  for (let i = 0; i < n; i++) { const c = L.net[i]; if (!w.C[i] || !c) continue; const ns = nb(i).filter(j => w.C[j] && L.net[j]); if (!ns.length) continue;
    const zbar = c.z.map((_, d) => ns.reduce((s, j) => s + L.net[j].z[d], 0) / ns.length); const v = c.Wn.map(row => row.reduce((s, x, e) => s + x * zbar[e], 0));
    if (Math.hypot(...v) >= 0.1) coupled[i] = 1; }
  const share = ok => { const seen = new Uint8Array(n); let tot = 0, inG = 0; for (let i = 0; i < n; i++) if (w.C[i]) tot++;
    for (let i = 0; i < n; i++) if (ok(i) && !seen[i]) { const st = [i], comp = []; seen[i] = 1; while (st.length) { const u = st.pop(); comp.push(u); for (const v of nb(u)) if (ok(v) && !seen[v]) { seen[v] = 1; st.push(v); } } if (comp.length >= 3) inG += comp.length; }
    return tot ? inG / tot : 0; };
  return { F_conn: share(i => w.C[i]), F_coup: share(i => w.C[i] && coupled[i]) };
}
const R = {};
for (let seed = 1; seed <= SEEDS; seed++) { const E = env(seed);
  for (const mode of ["predact", "frozen", "nogate"]) {
    const L = T.makeLife(mode, seed), T0 = M.total(L.w), counts = [], fc = [], fp = []; let maxErr = 0;
    for (let t = 0; t < STEPS; t++) { L.step(E.src(L.w, t)); maxErr = Math.max(maxErr, Math.abs(M.total(L.w) - T0));
      if ((t + 1) % 50 === 0) { counts.push(L.stats().count); if (t >= 2000 && (t + 1) % 200 === 0) { const f = forms(L); fc.push(f.F_conn); fp.push(f.F_coup); } } }
    const after = counts.slice(40), mv = []; for (let m = MOVE; m < STEPS; m += MOVE) mv.push(Math.min(...counts.slice(m / 50, m / 50 + 10)));
    const avg = a => +(a.reduce((s, x) => s + x, 0) / a.length).toFixed(3);
    R[`${mode}/${seed}`] = { period: E.period, maxErr, min: Math.min(...counts), mean: avg(after), meanMinAfterMoves: avg(mv), F_conn: avg(fc), F_coup: avg(fp) };
  }
  console.log(seed, ["predact", "frozen", "nogate"].map(m => `${m} ${R[m + "/" + seed].mean}/${R[m + "/" + seed].meanMinAfterMoves}/${R[m + "/" + seed].F_conn}/${R[m + "/" + seed].F_coup}`).join(" | "));
}
fs.writeFileSync(__dirname + `/results-var2-move${MOVE}.json`, JSON.stringify(R, null, 1));
