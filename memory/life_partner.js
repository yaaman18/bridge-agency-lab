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
module.exports = { makeLife, freshLife, migrate, FEATURES, ORIG_FEATURES };
