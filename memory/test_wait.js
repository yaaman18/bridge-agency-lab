// Stage 21 test with scripted partners (no person, no LLM). Protocol as test_partner.js: per seed (1-5) newborn,
// curriculum (nursery 400, school 400) with the partner absent, then the seasonal world: phase A 3000 steps with the
// partner condition, B 2000 absent, C 1000 with the condition again.
// Conditions: RESPONSIVE (answers a call w.p. 0.8 after 2-8 steps if no answer is already on its way, kinds rotate;
// spontaneous gesture w.p. 0.01 per step), REPLAY (the RESPONSIVE run's gestures of the same seed, shifted by half a phase),
// ABSENT, NOPROPRIO (RESPONSIVE with a circuit without r10/r11), BASELINE (memory.js).
const N = require("./wait.js"), M = require("./memory.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const CUR = [];
for (let i = 0; i < 400; i++) CUR.push([[5, 0], [0, 5]][Math.floor(i / 50) % 2]);
for (let i = 0; i < 400; i++) CUR.push([[5, 2], [2, 5]][Math.floor(i / 15) % 2]);
const PH = [["A", 3000, true], ["B", 2000, false], ["C", 1000, true]];
function scripted(seed) {
  const pr = N.rng(seed + 1000); let sched = null, rot = 0;
  return {
    gesture(now) { const s = pr(); if (sched === now) { sched = null; return (rot++ % 4) + 1; } return s < 0.01 ? 1 + Math.floor(pr() * 4) : 0; },
    after(now, o) { if (o.call && sched === null) { const a = pr(), dl = pr(); if (a < 0.8) sched = now + 2 + Math.floor(dl * 7); } },
  };
}
function run(seed, cond, replayLog) {
  const b = N.newborn(true, cond !== "NOPROPRIO"), st = N.init(b), noise = N.rng(seed), win = [], log = {};
  const ek = (a, c) => b.edges.findIndex(e => b.names[e[0]] === a && b.names[e[1]] === c);
  const qs = (a, c) => { const k = ek(a, c); return k < 0 ? null : [st.q[k], st.sg[k]]; };
  const partner = cond === "RESPONSIVE" || cond === "NOPROPRIO" ? scripted(seed) : null;
  for (const y of CUR) N.step(st, b, [...y, 0], { noise });
  let R = [50, 50], wt = 0; const out = {};
  for (const [ph, len, present] of PH) {
    const m = { calls: 0, answered: 0, patchActs: 0, patchAns: 0, form: 0, gestures: 0, callsLast500: 0, firstGesture: null, firstCallAfter: null,
                early: [0, 0], late: [0, 0] };
    for (let i = 0; i < len; i++) {
      const now = st.t + 1; let g = 0;
      if (present && partner) g = partner.gesture(now);
      if (present && cond === "REPLAY") { const t0 = now - i; g = replayLog[t0 + ((i + Math.floor(len / 2)) % len)] || 0; }
      if (g) { m.gestures++; log[now] = g; if (m.firstGesture === null) m.firstGesture = i; }
      const o = N.step(st, b, [Math.min(R[0], 5), Math.min(R[1], 5), g], { noise });
      if (partner && present) partner.after(now, o);
      wt++; R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + season(wt)[k]));
      win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > 5) win.shift();
      if (N.form(win, b)) m.form++;
      if (o.call) {
        m.calls++; if (i >= len - 500) m.callsLast500++;
        if (m.firstGesture !== null && i > m.firstGesture && m.firstCallAfter === null) m.firstCallAfter = i - m.firstGesture;
        if (i < 300) { m.early[0]++; if (o.callWhileWaiting) m.early[1]++; }
        if (i >= len - 1000) { m.late[0]++; if (o.callWhileWaiting) m.late[1]++; }
      }
      if (o.callAnswered) m.answered++;
      for (const a of o.acting) if (b.patch[a] <= 2) { m.patchActs++; if (o.answered.get(a)) m.patchAns++; }
    }
    m.answerRate = +(m.answered / Math.max(1, m.calls)).toFixed(3); m.patchAnsFrac = +(m.patchAns / Math.max(1, m.patchActs)).toFixed(3); m.form = +(m.form / len).toFixed(3);
    m.waitingShareEarly = m.early[0] ? +(m.early[1] / m.early[0]).toFixed(3) : null; m.waitingShareLate = m.late[0] ? +(m.late[1] / m.late[0]).toFixed(3) : null;
    m.end = { r9: qs("r9", "m3"), r10: qs("r10", "m3"), r11: qs("r11", "m3"), c3: qs("c3", "m3"),
              others: b.names.filter(n => /^r[1-8]$/.test(n)).map(r => r + ":" + qs(r, "m3").join("/")).filter(x => !x.endsWith(":0/0")).join(" ") };
    out[ph] = m;
  }
  return { out, log };
}
function baseline(seed) {
  const b = M.newborn(), st = M.init(b), noise = M.rng(seed), win = [];
  for (const y of CUR) M.step(st, b, y, { noise });
  let R = [50, 50], wt = 0; const out = {};
  for (const [ph, len] of PH) {
    let acts = 0, ans = 0, form = 0;
    for (let i = 0; i < len; i++) {
      const o = M.step(st, b, [Math.min(R[0], 5), Math.min(R[1], 5)], { noise });
      wt++; R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + season(wt)[k]));
      win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > 5) win.shift();
      if (M.form(win, b)) form++;
      for (const a of o.acting) { acts++; if (o.answered.get(a)) ans++; }
    }
    out[ph] = { patchAnsFrac: +(ans / Math.max(1, acts)).toFixed(3), form: +(form / len).toFixed(3), patchActs: acts };
  }
  return out;
}
const res = {};
for (const seed of [1, 2, 3, 4, 5]) {
  const live = run(seed, "RESPONSIVE");
  res[seed] = { RESPONSIVE: live.out, REPLAY: run(seed, "REPLAY", live.log).out, ABSENT: run(seed, "ABSENT").out, NOPROPRIO: run(seed, "NOPROPRIO").out, BASELINE: baseline(seed) };
}
require("fs").writeFileSync(__dirname + "/results-wait.json", JSON.stringify(res, null, 1));
for (const [s, x] of Object.entries(res)) {
  const R = x.RESPONSIVE, P = x.REPLAY, A = x.ABSENT, Q = x.NOPROPRIO, B = x.BASELINE;
  console.log(`seed ${s}`);
  console.log(`  ABSENT form ${["A","B","C"].map(p => A[p].form)} patchAns ${["A","B","C"].map(p => A[p].patchAnsFrac)} | BASE ${["A","B","C"].map(p => B[p].patchAnsFrac)} | ABSENT calls A ${A.A.calls}`);
  for (const [n, c] of [["RESP", R], ["REPLAY", P], ["NOPROP", Q]])
    console.log(`  ${n.padEnd(7)} A calls ${c.A.calls} ans ${c.A.answerRate} waitShare early ${c.A.waitingShareEarly} late ${c.A.waitingShareLate} (late calls ${c.A.late[0]}) | end A r9 ${c.A.end.r9} r10 ${c.A.end.r10} r11 ${c.A.end.r11} c3 ${c.A.end.c3} others ${c.A.end.others} | B last500 ${c.B.callsLast500} end r11 ${c.B.end.r11} r9 ${c.B.end.r9} | C calls ${c.C.calls} ans ${c.C.answerRate} first ${c.C.firstCallAfter} | form ${c.A.form}/${c.B.form}/${c.C.form}`);
}
