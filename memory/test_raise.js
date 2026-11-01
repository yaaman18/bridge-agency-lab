// Stage 24 (upbringing) with turn.js rules. Same world protocol as test_orient.js (curriculum 800 steps, then A 3000
// with the partner, B 2000 absent, C 1000 with the partner), but the partner can be present from birth (RAISED: also
// during the nursery and school) and can be of two kinds:
//   RESP  answers a call w.p. 0.8 after 2-8 steps if no answer is already on its way (as in stages 20-23);
//   TURN  the same, but only calls made while none of the circuit's calls is pending ("not over-talking") get an
//         answer scheduled; a gesture still answers whichever call is oldest. A caregiver who answers pauses.
// Conditions: RESP-RAISED, TURN-RAISED, TURN-ADULT (partner from phase A only), plus RESP-ADULT = stage 23 RESPONSIVE.
const N = require("./turn.js"), M = require("./memory.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const CUR = [];
for (let i = 0; i < 400; i++) CUR.push([[5, 0], [0, 5]][Math.floor(i / 50) % 2]);
for (let i = 0; i < 400; i++) CUR.push([[5, 2], [2, 5]][Math.floor(i / 15) % 2]);
const PH = [["A", 3000, true], ["B", 2000, false], ["C", 1000, true]];
function scripted(seed, kind) {
  const pr = N.rng(seed + 1000); let sched = null, rot = 0;
  return {
    gesture(now) { const s = pr(); if (sched === now) { sched = null; return (rot++ % 4) + 1; } return s < 0.01 ? 1 + Math.floor(pr() * 4) : 0; },
    after(now, o) { if (o.call && sched === null && (kind === "RESP" || !o.callWhileWaiting)) { const a = pr(), dl = pr(); if (a < 0.8) sched = now + 2 + Math.floor(dl * 7); } },
  };
}
function run(seed, kind, raised) {
  const b = N.newborn(true), st = N.init(b), noise = N.rng(seed), win = [];
  const ek = (a, c) => b.edges.findIndex(e => b.names[e[0]] === a && b.names[e[1]] === c);
  const qs = (a, c) => [st.q[ek(a, c)], st.sg[ek(a, c)]];
  const partner = scripted(seed, kind), out = {};
  const cur = { calls: 0, waiting: 0, patchActs: 0, patchAns: 0 };
  for (const y of CUR) {
    const now = st.t + 1, g = raised ? partner.gesture(now) : 0;
    const o = N.step(st, b, [...y, g], { noise });
    if (raised) partner.after(now, o);
    if (o.call) { cur.calls++; if (o.callWhileWaiting) cur.waiting++; }
    for (const a of o.acting) if (b.patch[a] <= 2) { cur.patchActs++; if (o.answered.get(a)) cur.patchAns++; }
  }
  out.curriculum = { calls: cur.calls, waitingShare: cur.calls ? +(cur.waiting / cur.calls).toFixed(3) : null, patchAnsFrac: +(cur.patchAns / Math.max(1, cur.patchActs)).toFixed(3),
                     r9: qs("r9", "m3"), r10: qs("r10", "m3"), r11: qs("r11", "m3"), c3: qs("c3", "m3"),
                     sensation_q: ["r1", "r2", "r7", "r8"].map(r => r + ":" + qs(r, "m1")[0] + "/" + qs(r, "m2")[0]).join(" ") };
  let R = [50, 50], wt = 0;
  for (const [ph, len, present] of PH) {
    const m = { calls: 0, answered: 0, patchActs: 0, patchAns: 0, form: 0, callsLast500: 0, firstGesture: null, firstCallAfter: null, early: [0, 0], late: [0, 0] };
    for (let i = 0; i < len; i++) {
      const now = st.t + 1; const g = present ? partner.gesture(now) : 0;
      if (g && m.firstGesture === null) m.firstGesture = i;
      const o = N.step(st, b, [Math.min(R[0], 5), Math.min(R[1], 5), g], { noise });
      if (present) partner.after(now, o);
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
    m.end = { r9: qs("r9", "m3"), r10: qs("r10", "m3"), r11: qs("r11", "m3"), c3: qs("c3", "m3") };
    out[ph] = m;
  }
  return out;
}
function baseline(seed) {
  const b = M.newborn(), st = M.init(b), noise = M.rng(seed);
  for (const y of CUR) M.step(st, b, y, { noise });
  let R = [50, 50], wt = 0; const out = {};
  for (const [ph, len] of PH) { let acts = 0, ans = 0;
    for (let i = 0; i < len; i++) { const o = M.step(st, b, [Math.min(R[0], 5), Math.min(R[1], 5)], { noise }); wt++; R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + season(wt)[k])); for (const a of o.acting) { acts++; if (o.answered.get(a)) ans++; } }
    out[ph] = { patchAnsFrac: +(ans / Math.max(1, acts)).toFixed(3) }; }
  return out;
}
const res = {};
for (const seed of [1, 2, 3, 4, 5]) res[seed] = { "RESP-RAISED": run(seed, "RESP", true), "TURN-RAISED": run(seed, "TURN", true), "TURN-ADULT": run(seed, "TURN", false), "RESP-ADULT": run(seed, "RESP", false), BASELINE: baseline(seed) };
require("fs").writeFileSync(__dirname + "/results-raise.json", JSON.stringify(res, null, 1));
for (const [s, x] of Object.entries(res)) {
  console.log(`seed ${s}  BASE patchAns ${["A", "B", "C"].map(p => x.BASELINE[p].patchAnsFrac)}`);
  for (const c of ["RESP-ADULT", "RESP-RAISED", "TURN-ADULT", "TURN-RAISED"]) { const r = x[c];
    console.log(`  ${c.padEnd(11)} cur calls ${r.curriculum.calls} wait ${r.curriculum.waitingShare} sens ${r.curriculum.sensation_q} | A calls ${r.A.calls} ans ${r.A.answerRate} wait early ${r.A.waitingShareEarly} late ${r.A.waitingShareLate} (late ${r.A.late[0]}) | end A r9 ${r.A.end.r9} r10 ${r.A.end.r10} r11 ${r.A.end.r11} c3 ${r.A.end.c3} | patchAns ${["A", "B", "C"].map(p => r[p].patchAnsFrac)} form ${["A", "B", "C"].map(p => r[p].form)} | B500 ${r.B.callsLast500} C first ${r.C.firstCallAfter}`); }
}
