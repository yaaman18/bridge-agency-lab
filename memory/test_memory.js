const L = require("./memory.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const ORIG = L.FEATURES.slice();
function trial(seed, memory) {
  L.FEATURES.splice(0, L.FEATURES.length, ...ORIG);
  const b = L.newborn(), st = L.init(b), noise = L.rng(seed), opts = { memory, noise };
  const win = [], recM = { lastAct: {}, events: [] };
  let R = [50, 50], wt = 0;
  const motors = b.names.map((_, u) => u).filter(u => b.kind[u] === "M");
  const recIn = m => b.edges.map((e, k) => (e[1] === m && b.kind[e[0]] === "R") ? k : -1).filter(k => k >= 0);
  const stats = { cycles: [], form: 0, steps: 0 };
  function stepWorld(y, phase) {
    const o = L.step(st, b, y, opts);
    if (y === null) return o;
    win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > 5) win.shift();
    return o;
  }
  for (const [sch, p, n] of [[[[5, 0], [0, 5]], 50, 400], [[[5, 2], [2, 5]], 15, 400]])
    for (let i = 0; i < n; i++) stepWorld(sch[Math.floor(i / p) % 2]);
  let open = null; // pending savings measurement: {m, confirmations}
  const runWorld = (n, tag) => {
    let unans = 0, acts = 0, unansFirst200 = 0, ansLast500 = 0, actsLast500 = 0, form = 0;
    for (let i = 0; i < n; i++) {
      wt++; const y = [Math.min(R[0], 5), Math.min(R[1], 5)];
      const before = st.q.slice();
      const o = stepWorld(y);
      R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + season(wt)[k]));
      if (L.form(win, b)) form++;
      for (const m of o.acting) {
        acts++; const ans = o.answered.get(m); if (!ans) { unans++; if (i < 200) unansFirst200++; }
        if (i >= n - 500) { actsLast500++; if (ans) ansLast500++; }
        const gap = recM.lastAct[m] === undefined ? Infinity : wt - recM.lastAct[m];
        if (ans && gap >= 32 && !open) open = { m, conf: 0, cycle: Math.floor((wt - 1) / 1000) + 1 };
        recM.lastAct[m] = wt;
      }
      if (open) {
        const ks = recIn(open.m), grew = ks.some(k => st.q[k] > before[k]);
        if (grew) open.conf++;
        if (ks.some(k => st.q[k] >= L.P.smax)) { recM.events.push({ cycle: open.cycle, conf: open.conf }); open = null; }
        else if (open.conf > 20) { recM.events.push({ cycle: open.cycle, conf: 99 }); open = null; }
      }
      if (tag === "cycles" && (wt % 1000 === 0)) { stats.cycles.push(unans); unans = 0; }
    }
    return { unans, acts, unansFirst200, answeredLast500: actsLast500 ? ansLast500 / actsLast500 : 0, form: form / n };
  }
  const cyc = runWorld(10000, "cycles");
  const sedimentAfterCycles = Object.fromEntries(b.edges.map((e, k) => [b.names[e[0]] + ">" + b.names[e[1]], st.sg[k]]).filter(([, v]) => v > 0));
  // reversal
  const swap = [[0, 1], [2, 3], [6, 7]]; const F = L.FEATURES.slice();
  for (const [i, j] of swap) { L.FEATURES[i] = F[j]; L.FEATURES[j] = F[i]; }
  const rev = runWorld(1000, "reversal");
  L.FEATURES.splice(0, L.FEATURES.length, ...ORIG);
  const ev = recM.events.filter(e => e.cycle >= 2 && e.cycle <= 10).map(e => e.conf).sort((a, c) => a - c);
  return { unans_cycles_2_10: stats.cycles.slice(1).reduce((a, c) => a + c, 0), unans_per_cycle: stats.cycles, form_cycles: +cyc.form.toFixed(3),
           savings_median: ev.length ? ev[Math.floor(ev.length / 2)] : null, savings_events: ev.length,
           reversal_unans_first200: rev.unansFirst200, reversal_answered_last500: +rev.answeredLast500.toFixed(3), sediment: sedimentAfterCycles };
}
const out = {};
for (const seed of [1, 2, 3, 4, 5]) for (const memory of [false, true]) out[`seed${seed}/${memory ? "ON" : "OFF"}`] = trial(seed, memory);
require("fs").writeFileSync(__dirname + "/results-memory.json", JSON.stringify(out, null, 1));
for (const [k, r] of Object.entries(out)) console.log(k.padEnd(12), JSON.stringify({ ...r, sediment: Object.keys(r.sediment).length + " sedimented: " + Object.entries(r.sediment).map(([e, v]) => e + "=" + v).join(" ") }));
