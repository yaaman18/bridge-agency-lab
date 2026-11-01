// fevo.js = evo_trm.js on fmatter.js with think() rewritten as plain loops in the same arithmetic order (bit-identical,
// check_fast.js). Original header:
// Stage 38 (2026-10-31, user: go with option 1, evolution): copy of trm2.js with (a) world size, reservoir, seed sites
// and source layout as options, (b) a founder lineage id carried by every constituent and inherited at division.
// Dynamics are those of trm2.js.
// Stage 39: optional opts.hooks, observers of division and death that draw nothing from the world's rng. Without them the
// run is unchanged (check_fast.js).
//
// Stage 35 (2026-10-31): making the prediction currency causal. Copy of trm.js (stage 33 stays frozen). Stage 33 found
// that the precision gate on division changed little (Z8) and the advantage came from inherited low activity. New modes:
//   "predact"  activity reads the constituent's own learned prediction of its local free matter: a = 0.1 + 0.9 sigmoid(ba +
//              wa . z + wp * yhat0), wp inherited; the read-out learns within the life (delta rule); no precision gate;
//   "frozen"   the same, but the read-out never learns (its weights stay as inherited): within-life prediction learning
//              removed, everything else equal. Both without the gate, so that learning acts only through the action.
//
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
const M = require("./fmatter.js");
const D = 4, K = 4, N_REC = 3, ETA = 0.05, ERR0 = 0.05, THETA_PI = 0.5, MUT = 0.05, INIT = 0.5;
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function gauss(r) { return Math.sqrt(-2 * Math.log(r() + 1e-12)) * Math.cos(2 * Math.PI * r()); }
const mat = (r, m, n, s) => Array.from({ length: m }, () => Array.from({ length: n }, () => s * gauss(r)));
function freshNet(r) { return { Wz: mat(r, D, D, INIT), Wx: mat(r, D, K, INIT), Wn: mat(r, D, D, INIT), b: mat(r, 1, D, INIT)[0], Wy: mat(r, K, D, 0.1), wa: mat(r, 1, D, INIT)[0], ba: 0, wp: INIT * gauss(r),
  z: new Array(D).fill(0), y: null, err: 0.2 }; }
const clone = (o, r, s) => JSON.parse(JSON.stringify(o), (k, v) => typeof v === "number" && s && k !== "err" ? v + s * gauss(r) : v);
function makeLife(mode, seed, opts = {}) {
  const w = M.makeWorld({ reservoir: opts.reservoir || 300, W: opts.W || 24, H: opts.H || 24 }), r = rng(seed), W = w.p.W, H = w.p.H, n = W * H, net = new Array(n).fill(null);
  const hk = opts.hooks || {};   // stage 39: observers only (divide(i, j) after the child exists, death(i) before removal)
  const actGate = opts.actGate ?? 0.5;   // stage 40: the activity needed to divide (0 = no activity gate)
  let founders = 0; for (const at of (opts.seeds || [opts.at || [12, 12]])) M.seed(w, ...at, 1);
  for (let i = 0; i < n; i++) if (w.C[i]) { net[i] = freshNet(r); net[i].line = founders++; }
  const nb = i => { const x = i % W, y = (i / W) | 0; return [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => ((y + dy + H) % H) * W + ((x + dx + W) % W)); };
  const senses = i => { const ns = nb(i); return [w.A[i] * 4, ns.reduce((s, j) => s + w.A[j], 0), w.B[i], ns.reduce((s, j) => s + w.B[j], 0) / 4]; };
  const pi = i => 1 / (1 + net[i].err / ERR0), act = new Float64Array(n).fill(1);
  const NB = new Int32Array(n * 4); for (let i = 0; i < n; i++) { const a = nb(i); for (let m = 0; m < 4; m++) NB[i * 4 + m] = a[m]; }
  const zs = new Array(n).fill(null), x = new Array(K).fill(0), zbar = new Array(D).fill(0), ns = [];
  function think() {   // same arithmetic, same order as evo_trm.js
    for (let i = 0; i < n; i++) zs[i] = net[i] ? net[i].z.slice() : null;
    const A = w.A, B = w.B;
    for (let i = 0; i < n; i++) { const c = net[i]; if (!c) continue; const o = i * 4;
      x[0] = A[i] * 4; x[1] = 0 + A[NB[o]] + A[NB[o + 1]] + A[NB[o + 2]] + A[NB[o + 3]]; x[2] = B[i]; x[3] = (0 + B[NB[o]] + B[NB[o + 1]] + B[NB[o + 2]] + B[NB[o + 3]]) / 4;
      if (c.y) { let e = 0; for (let k = 0; k < K; k++) { const d = x[k] - c.y[k]; e += Math.abs(d) / K; if (mode !== "frozen") { const row = c.Wy[k]; for (let j = 0; j < D; j++) row[j] += ETA * d * c.z[j]; } } c.err = 0.95 * c.err + 0.05 * e; }
      ns.length = 0; for (let m = 0; m < 4; m++) if (zs[NB[o + m]]) ns.push(NB[o + m]);
      for (let d = 0; d < D; d++) zbar[d] = 0; for (const j of ns) for (let d = 0; d < D; d++) zbar[d] += zs[j][d] / ns.length;
      for (let rep = 0; rep < N_REC; rep++) { const z = c.z, nz = new Array(D);
        for (let d = 0; d < D; d++) { let s1 = 0, s2 = 0, s3 = 0; const r1 = c.Wz[d], r2 = c.Wx[d], r3 = c.Wn[d];
          for (let e = 0; e < D; e++) s1 = s1 + r1[e] * z[e]; for (let e = 0; e < K; e++) s2 = s2 + r2[e] * x[e]; for (let e = 0; e < D; e++) s3 = s3 + r3[e] * zbar[e];
          nz[d] = Math.tanh(c.b[d] + s1 + s2 + s3); }
        c.z = nz; }
      const y = new Array(K); for (let k = 0; k < K; k++) { let s = 0; const row = c.Wy[k]; for (let e = 0; e < D; e++) s = s + row[e] * c.z[e]; y[k] = s; } c.y = y;
      const pa = mode === "predact" || mode === "frozen" ? (c.wp || 0) * c.y[0] : 0;
      let sa = 0; for (let e = 0; e < D; e++) sa = sa + c.wa[e] * c.z[e];
      act[i] = mode === "fixed" ? 1 : 0.1 + 0.9 / (1 + Math.exp(-(c.ba + pa + sa)));
    }
  }
  const ctl = mode === "fixed" ? {} : {
    activity: i => act[i],
    ...(opts.bindConst !== undefined ? { bindActivity: () => opts.bindConst } : {}),   // stage 45: binding at a constant factor, cut from the activity
    mayDivide: i => act[i] >= actGate && (mode === "nogate" || mode === "predact" || mode === "frozen" || pi(i) >= THETA_PI),
    onDivide: (i, j) => { const line = net[i].line; net[j] = mode === "noinherit" ? freshNet(r) : clone(net[i], r, MUT); net[j].y = null; net[j].line = line; if (hk.divide) hk.divide(i, j); },
    onDeath: i => { if (hk.death) hk.death(i); net[i] = null; },
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
module.exports = { makeLife, sources, D, K, N_REC, THETA_PI, MUT };
