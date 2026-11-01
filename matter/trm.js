// Stage 33: TRM-type constituents on the material layer (matter2.js). Each constituent carries, bound to its matter,
// a tiny recursive network ("TRM-type": a persistent latent z refined by N_REC inner recursions per world step; not the
// deep-supervised TRM of the paper):
//   z <- tanh(Wz z + Wx x + Wn zbar + b)  N_REC times,   x = local senses, zbar = mean latent of neighbouring constituents
//   (the dense coupling); y = Wy z predicts the next local senses; a = 0.1 + 0.9 sigmoid(wa . z + ba) is its activity.
// Two currencies (user decision): matter (existence, the bound matter) and digested prediction error:
//   * within a life only the read-out Wy learns, by the delta rule on its own next-sense prediction error (self-
//     supervised, no target from outside: M4); precision pi = 1 / (1 + err / ERR0), err = running mean |error|;
//   * division (A-gen, meta-layer axiom) also requires pi >= THETA_PI: a constituent reproduces only where it has digested
//     its surroundings; the child inherits all weights and z with small mutations (heredity, variation);
//   * activity a scales maintenance cost and binding (a low a = a dormant constituent that spends and takes less) and
//     division requires a >= 0.5. Nothing rewards a: what persists is what keeps its matter (natural drift).
// Modes: "trm" (all of the above), "fixed" (stage 32 rule: a = 1, no gate), "nogate" (TRM without the precision gate),
// "noinherit" (children get fresh random weights).
const M = require("./matter2.js");
const D = 4, K = 4, N_REC = 3, ETA = 0.05, ERR0 = 0.05, THETA_PI = 0.5, MUT = 0.05, INIT = 0.5;
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function gauss(r) { return Math.sqrt(-2 * Math.log(r() + 1e-12)) * Math.cos(2 * Math.PI * r()); }
const mat = (r, m, n, s) => Array.from({ length: m }, () => Array.from({ length: n }, () => s * gauss(r)));
function freshNet(r) { return { Wz: mat(r, D, D, INIT), Wx: mat(r, D, K, INIT), Wn: mat(r, D, D, INIT), b: mat(r, 1, D, INIT)[0], Wy: mat(r, K, D, 0.1), wa: mat(r, 1, D, INIT)[0], ba: 0,
  z: new Array(D).fill(0), y: null, err: 0.2 }; }
const clone = (o, r, s) => JSON.parse(JSON.stringify(o), (k, v) => typeof v === "number" && s && k !== "err" ? v + s * gauss(r) : v);
function makeLife(mode, seed, opts = {}) {
  const w = M.makeWorld({ reservoir: 300 }), r = rng(seed), W = w.p.W, H = w.p.H, n = W * H, net = new Array(n).fill(null);
  M.seed(w, ...(opts.at || [12, 12]), 1); for (let i = 0; i < n; i++) if (w.C[i]) net[i] = freshNet(r);
  const nb = i => { const x = i % W, y = (i / W) | 0; return [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => ((y + dy + H) % H) * W + ((x + dx + W) % W)); };
  const senses = i => { const ns = nb(i); return [w.A[i] * 4, ns.reduce((s, j) => s + w.A[j], 0), w.B[i], ns.reduce((s, j) => s + w.B[j], 0) / 4]; };
  const pi = i => 1 / (1 + net[i].err / ERR0), act = new Float64Array(n).fill(1);
  function think() {   // learning on the last prediction, then recursion and a new prediction, for every constituent
    const zs = net.map(c => c && c.z.slice());
    for (let i = 0; i < n; i++) { const c = net[i]; if (!c) continue; const x = senses(i);
      if (c.y) { let e = 0; for (let k = 0; k < K; k++) { const d = x[k] - c.y[k]; e += Math.abs(d) / K; for (let j = 0; j < D; j++) c.Wy[k][j] += ETA * d * c.z[j]; } c.err = 0.95 * c.err + 0.05 * e; }
      const ns = nb(i).filter(j => zs[j]), zbar = new Array(D).fill(0); for (const j of ns) for (let d = 0; d < D; d++) zbar[d] += zs[j][d] / ns.length;
      for (let rep = 0; rep < N_REC; rep++) c.z = c.z.map((_, d) => Math.tanh(c.b[d] + c.Wz[d].reduce((s, v, e) => s + v * c.z[e], 0) + c.Wx[d].reduce((s, v, e) => s + v * x[e], 0) + c.Wn[d].reduce((s, v, e) => s + v * zbar[e], 0)));
      c.y = c.Wy.map(row => row.reduce((s, v, e) => s + v * c.z[e], 0));
      act[i] = mode === "fixed" ? 1 : 0.1 + 0.9 / (1 + Math.exp(-(c.ba + c.wa.reduce((s, v, e) => s + v * c.z[e], 0))));
    }
  }
  const ctl = mode === "fixed" ? {} : {
    activity: i => act[i],
    mayDivide: i => act[i] >= 0.5 && (mode === "nogate" || pi(i) >= THETA_PI),
    onDivide: (i, j) => { net[j] = mode === "noinherit" ? freshNet(r) : clone(net[i], r, MUT); net[j].y = null; },
    onDeath: i => { net[i] = null; },
  };
  if (mode === "fixed") { ctl.onDivide = (i, j) => { net[j] = freshNet(r); }; ctl.onDeath = i => { net[i] = null; }; }
  function step(sources) { if (mode !== "fixed") think(); M.step(w, sources, ctl); }
  function stats() {
    let c = 0, aSum = 0, piSum = 0; for (let i = 0; i < n; i++) if (w.C[i]) { c++; aSum += act[i]; if (net[i]) piSum += pi(i); }
    // form F: share of constituents in connected groups (>= 3) of neighbouring constituents that are both precise (pi >= THETA_PI)
    const ok = i => w.C[i] && net[i] && (mode === "fixed" || pi(i) >= THETA_PI), seen = new Uint8Array(n); let inForm = 0;
    for (let i = 0; i < n; i++) if (ok(i) && !seen[i]) { const st = [i], comp = []; seen[i] = 1; while (st.length) { const u = st.pop(); comp.push(u); for (const v of nb(u)) if (ok(v) && !seen[v]) { seen[v] = 1; st.push(v); } } if (comp.length >= 3) inForm += comp.length; }
    return { count: c, activity: c ? aSum / c : 0, precision: c ? piSum / c : 0, F: c ? inForm / c : 0, bound: M.count(w).bound };
  }
  return { w, step, stats, net, act };
}
function sources(w, t, scale = 1, starve = null) {
  const W = w.p.W, on = Math.floor(t / 500) % 2 === 0, s = [];
  if (starve && t >= starve[0] && t < starve[1]) return s;
  for (const [cx, cy] of [[6, 12], [18, 12]]) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (on ? 1 : 0.3) * w.p.SRC * scale]);
  return s;
}
module.exports = { makeLife, sources, D, K, N_REC, THETA_PI };
