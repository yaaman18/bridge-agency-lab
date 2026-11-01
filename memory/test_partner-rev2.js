// Stage 20 pre-test with scripted partners (no person, no LLM). Protocol per seed (1-5): newborn, curriculum of
// sense/educate.js (nursery 400, school 400) with the partner absent, then the seasonal depletion world:
// phase A 3000 steps with the partner condition, phase B 2000 steps absent, phase C 1000 steps with the condition again.
// Conditions: RESPONSIVE (answers a call w.p. 0.8 after 2-8 steps if no answer is already on its way, kinds rotate
// 1-4; spontaneous gesture w.p. 0.01 per step, random kind), REPLAY (the gestures of the RESPONSIVE run of the same seed,
// shifted in time within the phase, cyclically by half its length, and delivered whatever the circuit does:
// perceptual crossing; rev. 1 delivered them at the same steps, which reproduced the RESPONSIVE run exactly), REPETITIVE (as RESPONSIVE, always kind 1),
// ABSENT (no gesture). BASELINE = memory.js (no partner units) on the same seed.
const N = require("./partner-rev2.js"), M = require("./memory.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const CUR = [];
for (let i = 0; i < 400; i++) CUR.push([[5, 0], [0, 5]][Math.floor(i / 50) % 2]);
for (let i = 0; i < 400; i++) CUR.push([[5, 2], [2, 5]][Math.floor(i / 15) % 2]);
const PH = [["A", 3000, true], ["B", 2000, false], ["C", 1000, true]];
function scripted(seed, kindRule) {
  const pr = N.rng(seed + 1000); let sched = null, rot = 0;
  return {
    gesture(now) { const s = pr(); if (sched === now) { sched = null; return kindRule === "same" ? 1 : (rot++ % 4) + 1; } return s < 0.01 ? 1 + Math.floor(pr() * 4) : 0; },
    after(now, o) { if (o.call && sched === null) { const a = pr(), dl = pr(); if (a < 0.8) sched = now + 2 + Math.floor(dl * 7); } },
  };
}
function run(seed, cond, replayLog) {
  const b = N.newborn(true), st = N.init(b), noise = N.rng(seed), win = [], log = {};
  const ek = (a, c) => b.edges.findIndex(e => b.names[e[0]] === a && b.names[e[1]] === c);
  const partner = cond === "RESPONSIVE" ? scripted(seed, "rotate") : cond === "REPETITIVE" ? scripted(seed, "same") : null;
  for (const y of CUR) { N.step(st, b, [...y, 0], { noise }); }
  let R = [50, 50], wt = 0; const out = {};
  for (const [ph, len, present] of PH) {
    const m = { calls: 0, answered: 0, patchActs: 0, patchAns: 0, form: 0, gestures: 0, callsLast500: 0, gesturesAfter: 0, firstGesture: null, firstCallAfter: null };
    for (let i = 0; i < len; i++) {
      const now = st.t + 1; let g = 0;
      if (present && partner) g = partner.gesture(now);
      if (present && cond === "REPLAY") { const t0 = now - i; g = replayLog[t0 + ((i + Math.floor(len / 2)) % len)] || 0; }
      if (g) { m.gestures++; log[now] = g; if (m.firstGesture === null) m.firstGesture = i; }
      const y = [Math.min(R[0], 5), Math.min(R[1], 5), g];
      const o = N.step(st, b, y, { noise });
      if (partner && present) partner.after(now, o);
      wt++; R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + season(wt)[k]));
      win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > 5) win.shift();
      if (N.form(win, b)) m.form++;
      if (o.call) { m.calls++; if (i >= len - 500) m.callsLast500++; if (m.firstGesture !== null && i > m.firstGesture && m.firstCallAfter === null) m.firstCallAfter = i - m.firstGesture; }
      if (o.callAnswered) m.answered++;
      for (const a of o.acting) if (b.patch[a] <= 2) { m.patchActs++; if (o.answered.get(a)) m.patchAns++; }
    }
    m.answerRate = +(m.answered / Math.max(1, m.calls)).toFixed(3); m.patchAnsFrac = +(m.patchAns / Math.max(1, m.patchActs)).toFixed(3); m.form = +(m.form / len).toFixed(3);
    const k9 = ek("r9", "m3"), kc = ek("c3", "m3");
    m.end = { r9m3: [st.q[k9], st.sg[k9]], c3m3: [st.q[kc], st.sg[kc]], otherRecSedToM3: b.names.filter(n => /^r[1-8]$/.test(n)).reduce((s, r) => s + st.sg[ek(r, "m3")], 0),
              r9ToPatchSed: st.sg[ek("r9", "m1")] + st.sg[ek("r9", "m2")] };
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
  res[seed] = { RESPONSIVE: live.out, REPLAY: run(seed, "REPLAY", live.log).out, REPETITIVE: run(seed, "REPETITIVE").out, ABSENT: run(seed, "ABSENT").out, BASELINE: baseline(seed) };
}
require("fs").writeFileSync(__dirname + "/results-partner-rev2.json", JSON.stringify(res, null, 1));
for (const [seed, r] of Object.entries(res)) {
  console.log("seed", seed);
  for (const [c, o] of Object.entries(r)) console.log("  " + c.padEnd(11), Object.entries(o).map(([ph, m]) => ph + ":" + JSON.stringify(m)).join("\n" + " ".repeat(14)));
}
