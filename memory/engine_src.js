// Memory as sedimentation (2026-10-30). Built on sense/learn.js rev. 4 (copied, not imported, so that rev. 4 stays frozen).
// Enactive / phenomenological reading: memory is not a store of world-states (no database, no episodes). With the
// world bracketed (phenomenological reduction), all the system has is how its own enacted contingencies were given
// to it; memory is the SEDIMENT those enactments leave in its sensorimotor dispositions (Husserl's sedimentation,
// Merleau-Ponty's habit body), and it shows only when the disposition is re-enacted.
// Per contingency: confidence q (0..smax, dissipates as before) and sediment sg (0..S, S = smax).
//   * a contingency that reaches full confidence from below gains 1 sediment (each full re-establishment sediments);
//   * confirmation regrows confidence by 1 + sediment (savings: a sedimented habit comes back at once);
//   * a sedimented contingency still transmits when its confidence has dissipated (the habit stays available);
//   * a unit with any sedimented incoming contingency is not "untried", so it does not sample everything;
//   * a failed prediction first lowers confidence; at confidence 0 it erodes sediment by 1 (habits unlearn slowly).
// MEMORY = false gives rev. 4 exactly.
//
// (Header of sense/learn.js rev. 4 follows.)
// Acquisition of sensation (2026-10-29, overnight). A newborn circuit has raw receptors whose meaning it is not
// told, a self-sustaining core, and two motors. Every contingency from a receptor or the core into a motor
// starts with confidence 0 (untried). Rules: those of viewer/sim.js (digestion-gated confirmation with
// :consolidate, dissipation every 8 steps, epistemic sampling of a unit whose incoming contingencies are all at
// 0, one motor acts per step, capacity 5 allocated richest first), plus ONE new rule (FAIL):
//   when the acting motor is not answered, every contingency FROM A RECEPTOR that drove it this step (source
//   active and sending, and transmitting: confidence >= 1 or sampled) loses 1 confidence. A failed prediction about
//   the world lowers its precision. (Revision 2: rev. 1 also punished the core's drive of the motor; then a motor
//   whose core drive fell to 0 while a receptor contingency stayed confident could never fire again: the core is the
//   body's drive, not a prediction about the world. See results-rev1.json.)
// Operational definition (not a phenomenal claim; phenomenal_claim stays not_certified): the circuit has
// ACQUIRED SENSATION of a receptor when the receptor's activity controls which action is taken through confident
// contingencies, measured by silencing the receptor (P-04) and seeing the action change.
const P = { smax: 4, decay: 8, window: 5, capacity: 5, cap: 50 };
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
// Receptor features of the world (the circuit is not told which is which).
const FEATURES = [
  ["y1>=3", (y) => y[0] >= 3], ["y2>=3", (y) => y[1] >= 3], ["y1==0", (y) => y[0] === 0], ["y2==0", (y) => y[1] === 0],
  ["noise", (y, t, r) => r() < 0.5], ["clock3", (y, t) => t % 3 === 0], ["y1>y2", (y) => y[0] > y[1]], ["y2>y1", (y) => y[1] > y[0]],
];
function newborn() {
  const names = [], kind = [], feat = [], theta = [], patch = [];
  FEATURES.forEach(([n], i) => { names.push("r" + (i + 1)); kind.push("R"); feat.push(i); theta.push(0); patch.push(0); });
  ["c1", "c2"].forEach(n => { names.push(n); kind.push("C"); feat.push(-1); theta.push(1); patch.push(0); });
  ["m1", "m2"].forEach((n, i) => { names.push(n); kind.push("M"); feat.push(-1); theta.push(2); patch.push(i + 1); });
  const id = n => names.indexOf(n), edges = [], q0 = [];
  const add = (a, b, q) => { edges.push([id(a), id(b), 1]); q0.push(q); };
  add("c1", "c1", 4); add("c2", "c2", 4); add("c1", "c2", 4); add("c2", "c1", 4);
  // Rev. 3: each motor is driven by one core unit (m1 <- c1, m2 <- c2), as in the hand-wired agent; in rev. 1-2 both
  // core units drove both motors, so the core alone reached the motor threshold and receptors were never needed.
  for (const [c, m] of [["c1", "m1"], ["c2", "m2"]]) { add(c, m, 0); FEATURES.forEach((_, i) => add("r" + (i + 1), m, 0)); }
  return { names, kind, feat, theta, patch, edges, q0, initial: names.map(n => n === "c1" || n === "c2") };
}
function init(b) { return { active: b.initial.slice(), q: b.q0.slice(), sg: b.q0.map(() => 0), t: 0 }; }
const S = P.smax;
function allocate(offer) { const d = [0, 0]; let left = P.capacity; for (const i of [0, 1].filter(i => offer[i] > 0).sort((i, j) => (offer[j] - offer[i]) || (i - j))) { d[i] = Math.min(offer[i], left); left -= d[i]; } return d; }
// opts: { explore=true, fail=true, sil:Set, noise: rng }
function step(st, b, y, opts) {
  const explore = opts.explore !== false, fail = opts.fail !== false, sil = opts.sil || new Set();
  const n = b.names.length, old = st.active, ins = u => b.edges.map((e, k) => e[1] === u ? k : -1).filter(k => k >= 0);
  const mem = opts.memory !== false;
  const stale = b.names.map((_, u) => explore && b.kind[u] !== "R" && ins(u).length > 0 && ins(u).every(k => st.q[k] === 0 && (!mem || st.sg[k] === 0)));
  const total = new Array(n).fill(0), conf = new Array(n).fill(0), drove = new Array(b.edges.length).fill(false);
  b.edges.forEach(([a, c, w], k) => { if ((st.q[k] >= 1 || (mem && st.sg[k] >= 1) || stale[c]) && old[a] && !sil.has(a)) { total[c] += w; if (st.q[k] >= 1) conf[c] += w; drove[k] = true; } });
  const nw = new Array(n);
  for (let u = 0; u < n; u++) {
    if (b.kind[u] === "R") nw[u] = FEATURES[b.feat[u]][1](y, st.t + 1, opts.noise);
    else nw[u] = total[u] >= b.theta[u];
  }
  const motors = b.names.map((_, u) => u).filter(u => b.kind[u] === "M");
  const cand = motors.filter(m => nw[m]);
  if (cand.length > 1) {
    // Rev. 3: precision-weighted selection. Input through confident contingencies ranks first; sampled input only
    // breaks ties (in rev. 2 an exploring motor with many sampled inputs always outranked a confident one).
    const key = m => conf[m] * 1000 + total[m];
    const best = Math.max(...cand.map(key)), tied = cand.filter(m => key(m) === best), prev = tied.filter(m => old[m]);
    const win = (prev.length ? prev : tied).sort((a, c) => b.patch[a] - b.patch[c])[0];
    for (const m of cand) if (m !== win) nw[m] = false;
  }
  const acting = motors.filter(m => nw[m] && !sil.has(m));
  const offer = [0, 0]; for (const m of acting) offer[b.patch[m] - 1] = y[b.patch[m] - 1];
  const d = allocate(offer), answered = new Map(acting.map(m => [m, d[b.patch[m] - 1] > 0]));
  const gate = d[0] + d[1] > 0 && [...answered.values()].every(Boolean);
  const ok = u => b.kind[u] !== "M" || answered.get(u) === true;
  // Rev. 4: only a contingency that was actually tested (it transmitted into the unit) can be confirmed. In rev. 1-3 any
  // receptor merely co-active with an answered action was confirmed, so noise and clock receptors grew confident.
  const confirmed = b.edges.map(([a, c], k) => drove[k] && nw[c] && gate && ok(a) && ok(c));
  confirmed.forEach((c, k) => { if (c && st.q[k] < P.smax) { st.q[k] = Math.min(P.smax, st.q[k] + 1 + (mem ? st.sg[k] : 0)); if (mem && st.q[k] === P.smax) st.sg[k] = Math.min(S, st.sg[k] + 1); } });
  if (fail) for (const m of acting) if (!answered.get(m)) b.edges.forEach(([a, c], k) => { if (c === m && b.kind[a] === "R" && drove[k] && !confirmed[k]) { if (st.q[k] > 0 || !mem) st.q[k] = Math.max(st.q[k] - 1, 0); else st.sg[k] = Math.max(st.sg[k] - 1, 0); } });
  if ((st.t + 1) % P.decay === 0) confirmed.forEach((c, k) => { if (!c) st.q[k] = Math.max(st.q[k] - 1, 0); });
  st.active = nw; st.t += 1;
  return { acting, d, gate, answered };
}
function form(win, b) {
  const U = new Set(); for (const w of win) w.active.forEach((a, u) => { if (a && b.kind[u] !== "R") U.add(u); });
  const q = win[win.length - 1].q, adj = new Map([...U].map(u => [u, b.edges.map((e, k) => (e[0] === u && U.has(e[1]) && q[k] >= 1) ? e[1] : -1).filter(v => v >= 0)]));
  const col = new Map([...U].map(u => [u, 0]));
  const dfs = u => { col.set(u, 1); for (const v of adj.get(u)) { if (col.get(v) === 1) return true; if (col.get(v) === 0 && dfs(v)) return true; } col.set(u, 2); return false; };
  for (const u of U) if (col.get(u) === 0 && dfs(u)) return true; return false;
}


// ---- World and life loop (runs inside the Web Worker; also testable in node) ----
const CAP = 50;
const NURSERY = 400, SCHOOL = 400;
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const ORIG_FEATURES = FEATURES.slice();
function applyReversal(rev) {
  FEATURES.splice(0, FEATURES.length, ...ORIG_FEATURES);
  if (rev % 2 === 1) for (const [i, j] of [[0, 1], [2, 3], [6, 7]]) { const a = FEATURES[i]; FEATURES[i] = FEATURES[j]; FEATURES[j] = a; }
}
function freshLife() {
  const b = newborn(), st = init(b);
  return { v: 1, age: 0, wt: 0, R: [CAP, CAP], active: st.active, q: st.q, sg: st.sg, rng: 20261030, reversals: 0, stasisUntil: 0,
           hist: { sediment: [], unans: [], savings: [] }, unansWindow: 0, lastAct: {}, open: null, born: Date.now() };
}
function makeLife(saved) {
  const L = saved && saved.v === 1 ? saved : freshLife();
  const b = newborn();
  const st = { active: L.active.slice(), q: L.q.slice(), sg: L.sg.slice(), t: L.age };
  applyReversal(L.reversals);
  const noise = () => { L.rng = (L.rng + 0x6D2B79F5) | 0; let t = Math.imul(L.rng ^ (L.rng >>> 15), 1 | L.rng); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const win = [];
  const motors = b.names.map((_, u) => u).filter(u => b.kind[u] === "M");
  const recIn = m => b.edges.map((e, k) => (e[1] === m && b.kind[e[0]] === "R") ? k : -1).filter(k => k >= 0);
  let last = null;
  function phase() { return L.age < NURSERY ? "nursery" : L.age < NURSERY + SCHOOL ? "school" : "world"; }
  function live(n) {
    for (let i = 0; i < n; i++) {
      const ph = phase(); let y, inWorld = ph === "world";
      if (ph === "nursery") y = [[5, 0], [0, 5]][Math.floor(L.age / 50) % 2].slice();
      else if (ph === "school") y = [[5, 2], [2, 5]][Math.floor((L.age - NURSERY) / 15) % 2].slice();
      else { y = L.age < L.stasisUntil ? [0, 0] : [Math.min(L.R[0], 5), Math.min(L.R[1], 5)]; }
      const before = st.q.slice();
      const o = step(st, b, y, { noise });
      L.age = st.t;
      if (inWorld) {
        L.wt++;
        const g = L.age <= L.stasisUntil ? [0, 0] : season(L.wt);
        L.R = [0, 1].map(k => Math.min(CAP, L.R[k] - o.d[k] + g[k]));
      }
      win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > P.window) win.shift();
      for (const m of o.acting) {
        const ans = o.answered.get(m); if (!ans) L.unansWindow++;
        const gap = L.lastAct[m] === undefined ? Infinity : L.age - L.lastAct[m];
        if (ans && gap >= 32 && !L.open) L.open = { m, conf: 0, age: L.age };
        L.lastAct[m] = L.age;
      }
      if (L.open) {
        const ks = recIn(L.open.m);
        if (ks.some(k => st.q[k] > before[k])) L.open.conf++;
        if (ks.some(k => st.q[k] >= P.smax) || L.open.conf > 20) { L.hist.savings.push([L.open.age, L.open.conf]); if (L.hist.savings.length > 300) L.hist.savings.shift(); L.open = null; }
      }
      if (L.age % 100 === 0) { L.hist.sediment.push([L.age, st.sg.reduce((a, c) => a + c, 0)]); if (L.hist.sediment.length > 600) L.hist.sediment.shift(); }
      if (L.age % 1000 === 0) { L.hist.unans.push([L.age, L.unansWindow]); L.unansWindow = 0; if (L.hist.unans.length > 300) L.hist.unans.shift(); }
      last = { y, acting: o.acting.map(m => b.patch[m]), answered: o.acting.map(m => o.answered.get(m)), formed: form(win, b), phase: ph };
    }
    L.active = st.active.slice(); L.q = st.q.slice(); L.sg = st.sg.slice();
    return last;
  }
  function snapshot() {
    return { age: L.age, wt: L.wt, R: L.R.slice(), q: st.q.slice(), sg: st.sg.slice(), active: st.active.slice(), reversals: L.reversals,
             stasis: L.age < L.stasisUntil, last, phase: phase(), hist: L.hist, edges: b.edges.map(e => [b.names[e[0]], b.names[e[1]]]), names: b.names, born: L.born };
  }
  return { L, b, st, live, snapshot, reverse() { L.reversals++; applyReversal(L.reversals); }, stasis(n) { L.stasisUntil = L.age + n; } };
}
