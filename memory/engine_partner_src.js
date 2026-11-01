// The partner as part of the world (2026-10-30, stage 20). Built on memory.js (copied, not imported, so that
// memory.js stays frozen). The person who has the page open enters the circuit's world in two ways, never as a
// judge: no reward, no rating, no target (M4 / P-01).
//   * r9, a receptor that is on at a step where the partner made a gesture (any of 4 kinds). The circuit is not told
//     what it is; it is one more numbered receptor.
//   * m3, a third motor driven by a third core unit c3 (joined to c1 and c2 like they are joined to each other).
//     m3 does not act on a patch: it CALLS. The call is answered when the partner gestures within W steps after it.
// A call's answer is late, so its confirmation is deferred: at the call step the contingencies that would have been
// confirmed had the call been answered at once are kept; a fresh answer within W steps confirms them by the usual
// rule (with sediment); a call that expires, or is superseded by the next call, fails by the usual rule.
// Digestion of an answer = the freshness of the gesture kind (0..5, +1 every FRESH steps, used up by the answer).
// A kind repeated before it regrows does not answer: the same reply over and over leaves nothing to digest, just as
// an emptied patch does not answer.
// partner=false builds the circuit of memory.js exactly (same units, edges and order).
// Revision 2 (after results-partner-rev1.json): selection ranks input by confident contingencies first, then by
// sedimented ones (a habit whose confidence has dissipated), then sampled input. In rev. 1 (and memory.js) habit-only
// input ranked like sampled input, so an untried m3 sampling many receptors beat m2 whose inputs were sediment-only
// (seed 2, step 251 of the nursery); m2 then never acted again and m3 called into an absent world for good.
// Revision 3 (after results-partner-rev2.json: no harm, but not one call in the world in any seed or condition, since
// a patch motor is a candidate at every step and always outranks an untried m3): the call is a separate channel
// (voice) from foraging (hands). "One action per step" (stage 12, option A) was introduced for the competition of
// patch actions for digestion capacity, and a call digests nothing from the patches, so the selection runs among
// the patch motors only and m3 acts whenever its input reaches threshold, alongside them.
const P = { smax: 4, decay: 8, window: 5, capacity: 5, cap: 50, W: 10, FRESH: 20, KINDS: 4 };
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
// Receptor features of the world (the circuit is not told which is which). y = [yield1, yield2, gesture kind or 0].
const FEATURES = [
  ["y1>=3", (y) => y[0] >= 3], ["y2>=3", (y) => y[1] >= 3], ["y1==0", (y) => y[0] === 0], ["y2==0", (y) => y[1] === 0],
  ["noise", (y, t, r) => r() < 0.5], ["clock3", (y, t) => t % 3 === 0], ["y1>y2", (y) => y[0] > y[1]], ["y2>y1", (y) => y[1] > y[0]],
  ["partner", (y) => (y[2] || 0) > 0],
];
function newborn(partner = true) {
  const names = [], kind = [], feat = [], theta = [], patch = [], nr = partner ? 9 : 8;
  for (let i = 0; i < nr; i++) { names.push("r" + (i + 1)); kind.push("R"); feat.push(i); theta.push(0); patch.push(0); }
  (partner ? ["c1", "c2", "c3"] : ["c1", "c2"]).forEach(n => { names.push(n); kind.push("C"); feat.push(-1); theta.push(1); patch.push(0); });
  (partner ? ["m1", "m2", "m3"] : ["m1", "m2"]).forEach((n, i) => { names.push(n); kind.push("M"); feat.push(-1); theta.push(2); patch.push(i + 1); });
  const id = n => names.indexOf(n), edges = [], q0 = [];
  const add = (a, b, q) => { edges.push([id(a), id(b), 1]); q0.push(q); };
  add("c1", "c1", 4); add("c2", "c2", 4); add("c1", "c2", 4); add("c2", "c1", 4);
  if (partner) { add("c3", "c3", 4); add("c1", "c3", 4); add("c3", "c1", 4); add("c2", "c3", 4); add("c3", "c2", 4); }
  const pairs = partner ? [["c1", "m1"], ["c2", "m2"], ["c3", "m3"]] : [["c1", "m1"], ["c2", "m2"]];
  for (const [c, m] of pairs) { add(c, m, 0); for (let i = 0; i < nr; i++) add("r" + (i + 1), m, 0); }
  return { names, kind, feat, theta, patch, edges, q0, initial: names.map(n => n[0] === "c") };
}
function init(b) { return { active: b.initial.slice(), q: b.q0.slice(), sg: b.q0.map(() => 0), t: 0, pend: null, fresh: new Array(P.KINDS).fill(5) }; }
const S = P.smax;
function allocate(offer) { const d = [0, 0]; let left = P.capacity; for (const i of [0, 1].filter(i => offer[i] > 0).sort((i, j) => (offer[j] - offer[i]) || (i - j))) { d[i] = Math.min(offer[i], left); left -= d[i]; } return d; }
// opts: { explore=true, fail=true, memory=true, sil:Set, noise: rng }
function step(st, b, y, opts) {
  const explore = opts.explore !== false, fail = opts.fail !== false, sil = opts.sil || new Set();
  const n = b.names.length, old = st.active, ins = u => b.edges.map((e, k) => e[1] === u ? k : -1).filter(k => k >= 0);
  const mem = opts.memory !== false, now = st.t + 1;
  const stale = b.names.map((_, u) => explore && b.kind[u] !== "R" && ins(u).length > 0 && ins(u).every(k => st.q[k] === 0 && (!mem || st.sg[k] === 0)));
  const total = new Array(n).fill(0), conf = new Array(n).fill(0), habit = new Array(n).fill(0), drove = new Array(b.edges.length).fill(false);
  b.edges.forEach(([a, c, w], k) => { if ((st.q[k] >= 1 || (mem && st.sg[k] >= 1) || stale[c]) && old[a] && !sil.has(a)) { total[c] += w; if (st.q[k] >= 1) conf[c] += w; else if (mem && st.sg[k] >= 1) habit[c] += w; drove[k] = true; } });
  const nw = new Array(n);
  for (let u = 0; u < n; u++) {
    if (b.kind[u] === "R") nw[u] = FEATURES[b.feat[u]][1](y, now, opts.noise);
    else nw[u] = total[u] >= b.theta[u];
  }
  const motors = b.names.map((_, u) => u).filter(u => b.kind[u] === "M");
  const cand = motors.filter(m => nw[m] && b.patch[m] <= 2);
  if (cand.length > 1) {
    const key = m => conf[m] * 1e6 + habit[m] * 1e3 + total[m];
    const best = Math.max(...cand.map(key)), tied = cand.filter(m => key(m) === best), prev = tied.filter(m => old[m]);
    const win = (prev.length ? prev : tied).sort((a, c) => b.patch[a] - b.patch[c])[0];
    for (const m of cand) if (m !== win) nw[m] = false;
  }
  const acting = motors.filter(m => nw[m] && !sil.has(m));
  const onPatch = acting.filter(m => b.patch[m] <= 2), call = acting.find(m => b.patch[m] === 3);
  const offer = [0, 0]; for (const m of onPatch) offer[b.patch[m] - 1] = y[b.patch[m] - 1];
  const d = allocate(offer), answered = new Map(onPatch.map(m => [m, d[b.patch[m] - 1] > 0]));
  const gate = d[0] + d[1] > 0 && [...answered.values()].every(Boolean);
  const ok = u => b.kind[u] !== "M" || answered.get(u) === true;
  const confirmed = b.edges.map(([a, c], k) => drove[k] && nw[c] && gate && ok(a) && ok(c));
  const grow = k => { if (st.q[k] < P.smax) { st.q[k] = Math.min(P.smax, st.q[k] + 1 + (mem ? st.sg[k] : 0)); if (mem && st.q[k] === P.smax) st.sg[k] = Math.min(S, st.sg[k] + 1); } };
  const weaken = k => { if (st.q[k] > 0 || !mem) st.q[k] = Math.max(st.q[k] - 1, 0); else st.sg[k] = Math.max(st.sg[k] - 1, 0); };
  confirmed.forEach((c, k) => { if (c) grow(k); });
  if (fail) for (const m of onPatch) if (!answered.get(m)) b.edges.forEach(([a, c], k) => { if (c === m && b.kind[a] === "R" && drove[k] && !confirmed[k]) weaken(k); });
  // The partner's answer to a pending call (a gesture at a later step, within W steps, of a fresh kind).
  let callAnswered = false, callFailed = 0;
  const g = y[2] || 0;
  if (st.pend && g > 0 && now - st.pend.t <= P.W && st.fresh[g - 1] >= 1) {
    st.fresh[g - 1] = 0; callAnswered = true;
    for (const k of st.pend.E) if (!confirmed[k]) { grow(k); confirmed[k] = true; }
    st.pend = null;
  }
  const failCall = p => { callFailed++; if (fail) for (const k of p.R) if (!confirmed[k]) weaken(k); };
  if (st.pend && (now - st.pend.t >= P.W || call !== undefined)) { failCall(st.pend); st.pend = null; }
  if (call !== undefined) {
    const okc = u => b.kind[u] !== "M" || u === call;
    st.pend = { t: now, E: b.edges.map(([a, c], k) => (drove[k] && nw[c] && okc(a) && okc(c)) ? k : -1).filter(k => k >= 0),
                R: b.edges.map(([a, c], k) => (c === call && b.kind[a] === "R" && drove[k]) ? k : -1).filter(k => k >= 0) };
  }
  if (now % P.FRESH === 0) st.fresh = st.fresh.map(f => Math.min(5, f + 1));
  if (now % P.decay === 0) confirmed.forEach((c, k) => { if (!c) st.q[k] = Math.max(st.q[k] - 1, 0); });
  st.active = nw; st.t = now;
  return { acting, d, gate, answered, call: call !== undefined, callAnswered, callFailed };
}
function form(win, b) {
  const U = new Set(); for (const w of win) w.active.forEach((a, u) => { if (a && b.kind[u] !== "R") U.add(u); });
  const q = win[win.length - 1].q, adj = new Map([...U].map(u => [u, b.edges.map((e, k) => (e[0] === u && U.has(e[1]) && q[k] >= 1) ? e[1] : -1).filter(v => v >= 0)]));
  const col = new Map([...U].map(u => [u, 0]));
  const dfs = u => { col.set(u, 1); for (const v of adj.get(u)) { if (col.get(v) === 1) return true; if (col.get(v) === 0 && dfs(v)) return true; } col.set(u, 2); return false; };
  for (const u of U) if (col.get(u) === 0 && dfs(u)) return true; return false;
}


// ---- World and life loop with the partner (stage 20; runs inside the Web Worker; also testable in node) ----
// Concatenated after partner.js (without its module.exports) by build_partner.js.
const CAP = 50;
const NURSERY = 400, SCHOOL = 400, BLOCK = 300, MAXGAP = 200;
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const ORIG_FEATURES = FEATURES.slice();
function applyReversal(rev) {
  FEATURES.splice(0, FEATURES.length, ...ORIG_FEATURES);
  if (rev % 2 === 1) for (const [i, j] of [[0, 1], [2, 3], [6, 7]]) { const a = FEATURES[i]; FEATURES[i] = FEATURES[j]; FEATURES[j] = a; }
}
const emptyStats = () => ({ live: { steps: 0, calls: 0, answered: 0, gestures: 0 }, replay: { steps: 0, calls: 0, answered: 0, gestures: 0 } });
function freshPartner() { return { mode: "live", rec: [], rp: null, brng: 777, bcond: "live", bnext: 0, stats: emptyStats(), ignored: 0 }; }
function freshLife() {
  const b = newborn(true), st = init(b);
  return { v: 2, age: 0, wt: 0, R: [CAP, CAP], active: st.active, q: st.q, sg: st.sg, rng: 20261030, reversals: 0, stasisUntil: 0,
           hist: { sediment: [], unans: [], savings: [], calls: [] }, unansWindow: 0, callWindow: [0, 0], lastAct: {}, open: null,
           pend: null, fresh: st.fresh, partner: freshPartner(), born: Date.now() };
}
// A being saved before stage 20 (v 1) keeps everything it has sedimented; r9, c3, m3 and their contingencies are new.
function migrate(old) {
  const bo = newborn(false), bn = newborn(true), L = freshLife();
  const name = (b, k) => b.names[b.edges[k][0]] + ">" + b.names[b.edges[k][1]];
  const oldK = new Map(bo.edges.map((_, k) => [name(bo, k), k]));
  bn.edges.forEach((_, k) => { const j = oldK.get(name(bn, k)); if (j !== undefined) { L.q[k] = old.q[j]; L.sg[k] = old.sg[j]; } });
  L.active = bn.names.map((n, u) => { const j = bo.names.indexOf(n); return j >= 0 ? old.active[j] : bn.initial[u]; });
  const idx = u => bn.names.indexOf(bo.names[u]);
  L.lastAct = Object.fromEntries(Object.entries(old.lastAct || {}).map(([u, a]) => [idx(+u), a]));
  L.open = old.open ? { ...old.open, m: idx(old.open.m) } : null;
  for (const f of ["age", "wt", "R", "rng", "reversals", "stasisUntil", "unansWindow", "born", "speed", "savedAt"]) if (old[f] !== undefined) L[f] = old[f];
  L.hist = { ...old.hist, calls: [] }; L.migratedAt = old.age;
  return L;
}
function makeLife(saved) {
  const L = !saved ? freshLife() : saved.v === 2 ? saved : migrate(saved);
  const b = newborn(true);
  const st = { active: L.active.slice(), q: L.q.slice(), sg: L.sg.slice(), t: L.age, pend: L.pend, fresh: L.fresh.slice() };
  applyReversal(L.reversals);
  const noise = () => { L.rng = (L.rng + 0x6D2B79F5) | 0; let t = Math.imul(L.rng ^ (L.rng >>> 15), 1 | L.rng); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const brand = () => { const p = L.partner; p.brng = (p.brng + 0x6D2B79F5) | 0; let t = Math.imul(p.brng ^ (p.brng >>> 15), 1 | p.brng); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const win = [], queue = [];
  const recIn = m => b.edges.map((e, k) => (e[1] === m && b.kind[e[0]] === "R") ? k : -1).filter(k => k >= 0);
  let last = null, counting = false;
  function phase() { return L.age < NURSERY ? "nursery" : L.age < NURSERY + SCHOOL ? "school" : "world"; }
  // Which partner the circuit meets at this step: the person (live) or the record of the person's past gestures (replay).
  function condition(now) {
    const p = L.partner;
    if (p.mode !== "blind") return p.mode;
    if (now >= p.bnext) { p.bcond = brand() < 0.5 ? "live" : "replay"; p.bnext = now + BLOCK; p.rp = null; }
    return p.bcond;
  }
  function replayGesture() {
    const p = L.partner, rec = p.rec;
    if (rec.length < 3) return 0;
    if (!p.rp) p.rp = { j: 0, wait: 1 };
    if (--p.rp.wait > 0) return 0;
    const j = p.rp.j, g = rec[j][1], nj = (j + 1) % rec.length;
    p.rp = { j: nj, wait: nj === 0 ? 50 : Math.max(1, Math.min(MAXGAP, rec[nj][0] - rec[j][0])) };
    return g;
  }
  function live(n) {
    for (let i = 0; i < n; i++) {
      const ph = phase(), now = L.age + 1, p = L.partner; let y, inWorld = ph === "world";
      if (ph === "nursery") y = [[5, 0], [0, 5]][Math.floor(L.age / 50) % 2].slice();
      else if (ph === "school") y = [[5, 2], [2, 5]][Math.floor((L.age - NURSERY) / 15) % 2].slice();
      else { y = L.age < L.stasisUntil ? [0, 0] : [Math.min(L.R[0], 5), Math.min(L.R[1], 5)]; }
      const cond = condition(now); let g = 0;
      if (cond === "live") { g = queue.length ? queue.shift() : 0; if (g) { p.rec.push([now, g]); if (p.rec.length > 2000) p.rec.shift(); } }
      else { if (queue.length) { p.ignored += queue.length; queue.length = 0; } g = replayGesture(); }
      y.push(g);
      const before = st.q.slice();
      const o = step(st, b, y, { noise });
      L.age = st.t;
      if (inWorld) {
        L.wt++;
        const gr = L.age <= L.stasisUntil ? [0, 0] : season(L.wt);
        L.R = [0, 1].map(k => Math.min(CAP, L.R[k] - o.d[k] + gr[k]));
      }
      win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > P.window) win.shift();
      for (const m of o.acting) {
        if (b.patch[m] > 2) continue;
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
      if (o.call) L.callWindow[0]++; if (o.callAnswered) L.callWindow[1]++;
      if (counting) { const s = p.stats[cond]; s.steps++; if (o.call) s.calls++; if (o.callAnswered) s.answered++; if (g) s.gestures++; }
      if (L.age % 100 === 0) {
        L.hist.sediment.push([L.age, st.sg.reduce((a, c) => a + c, 0)]); if (L.hist.sediment.length > 600) L.hist.sediment.shift();
        L.hist.calls.push([L.age, L.callWindow[0], L.callWindow[1]]); L.callWindow = [0, 0]; if (L.hist.calls.length > 600) L.hist.calls.shift();
      }
      if (L.age % 1000 === 0) { L.hist.unans.push([L.age, L.unansWindow]); L.unansWindow = 0; if (L.hist.unans.length > 300) L.hist.unans.shift(); }
      const pa = o.acting.filter(m => b.patch[m] <= 2);
      last = { y, acting: pa.map(m => b.patch[m]), answered: pa.map(m => o.answered.get(m)), call: o.call, callAnswered: o.callAnswered,
               callFailed: o.callFailed, gesture: g, cond, formed: form(win, b), phase: ph };
    }
    L.active = st.active.slice(); L.q = st.q.slice(); L.sg = st.sg.slice(); L.pend = st.pend; L.fresh = st.fresh.slice();
    return last;
  }
  function snapshot(reveal) {
    const p = L.partner, hide = p.mode === "blind" && !reveal;
    return { age: L.age, wt: L.wt, R: L.R.slice(), q: st.q.slice(), sg: st.sg.slice(), active: st.active.slice(), reversals: L.reversals,
             stasis: L.age < L.stasisUntil, last: last && hide ? { ...last, cond: null } : last, phase: phase(), hist: L.hist,
             edges: b.edges.map(e => [b.names[e[0]], b.names[e[1]]]), names: b.names, born: L.born, migratedAt: L.migratedAt,
             pend: st.pend ? { left: P.W - (L.age - st.pend.t) } : null, fresh: st.fresh.slice(),
             partner: { mode: p.mode, rec: p.rec.length, ignored: p.ignored, stats: hide ? null : p.stats } };
  }
  return { L, b, st, live, snapshot, queue, setCounting(on) { counting = on; },
           gesture(k) { if (k >= 1 && k <= P.KINDS && queue.length < 4) queue.push(k); },
           setMode(m) { const p = L.partner; if (p.mode === m) return; p.mode = m; p.rp = null; p.bnext = 0; },
           clearStats() { L.partner.stats = emptyStats(); L.partner.ignored = 0; },
           reverse() { L.reversals++; applyReversal(L.reversals); }, stasis(n) { L.stasisUntil = L.age + n; } };
}

