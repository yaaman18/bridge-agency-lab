// The educator (2026-10-29): shapes only the world the newborn lives in (curriculum). No reward, no target, no
// access to the circuit. Usage: node educate.js  -> results.json and a printed summary.
const L = require("./learn.js"), SIM = require("../viewer/sim.js"), TYPES = require("../viewer/types.js");
// HELD-OUT validation (2026-10-29): receptor meanings and order changed, world seasons changed; rules (learn.js rev. 4)
// and curriculum unchanged. Written and frozen before running.
L.FEATURES.splice(0, L.FEATURES.length,
  ["noise.3", (y, t, r) => r() < 0.3], ["y2>=4", (y) => y[1] >= 4], ["clock5", (y, t) => t % 5 === 0], ["y1>=1", (y) => y[0] >= 1],
  ["y1==0", (y) => y[0] === 0], ["y2>y1", (y) => y[1] > y[0]], ["y1>=4", (y) => y[0] >= 4], ["y2==0", (y) => y[1] === 0]);
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 250 ? [2, 4] : c <= 500 ? [4, 0] : c <= 750 ? [0, 4] : [3, 3]; };
// segments: {sched: [[y],[y]], period, len}  or  {world: true, len}
const CURRICULUM = [
  { name: "nursery", sched: [[5, 0], [0, 5]], period: 50, len: 400 },   // one patch answers at a time, slow
  { name: "school", sched: [[5, 2], [2, 5]], period: 15, len: 400 },    // both answer, one more, faster
  { name: "world", world: true, len: 1200 },                            // the depletion world with seasons
];
const NONE = [{ name: "world", world: true, len: 2000 }];
function live(b, plan, opts, st0, R0, wt0) {
  const st = st0 || L.init(b); let R = R0 ? R0.slice() : [50, 50], wt = wt0 || 0; const noise = L.rng(opts.seed || 1);
  const win = [], log = [];
  for (const seg of plan) for (let i = 0; i < seg.len; i++) {
    let y;
    if (seg.world) y = [Math.min(R[0], 5), Math.min(R[1], 5)];
    else y = seg.sched[Math.floor(i / seg.period) % seg.sched.length].slice();
    const out = L.step(st, b, y, { ...opts, noise, sil: opts.silAt ? opts.silAt(st.t + 1) : undefined });
    if (seg.world) { wt++; const g = season(wt); R = [0, 1].map(k => Math.min(50, R[k] - out.d[k] + g[k])); }
    win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > L.P.window) win.shift();
    const act = out.acting.length ? b.patch[out.acting[0]] : 0;
    log.push({ seg: seg.name, y, act, answered: act ? out.answered.get(out.acting[0]) : null, formed: L.form(win, b), q: st.q.slice() });
  }
  return { st, R, wt, log };
}
const eidx = (b, a, c) => b.edges.findIndex(e => b.names[e[0]] === a && b.names[e[1]] === c);
function matrix(b, q) { const m = {}; for (const r of b.names.filter((_, u) => b.kind[u] === "R")) m[r] = [q[eidx(b, r, "m1")], q[eidx(b, r, "m2")]]; m.c = [q[eidx(b, "c1", "m1")], q[eidx(b, "c2", "m2")]]; return m; }
function behaviour(log) {
  const acts = log.filter(x => x.act), ans = acts.filter(x => x.answered);
  const richer = acts.filter(x => x.y[x.act - 1] >= x.y[2 - x.act]);
  return { form: +(log.filter(x => x.formed).length / log.length).toFixed(3), acting: +(acts.length / log.length).toFixed(3),
           answered: +(ans.length / Math.max(1, acts.length)).toFixed(3), richer: +(richer.length / Math.max(1, acts.length)).toFixed(3) };
}
// Sensation test: from the state after training, branch 10 steps at 20 start points in the test world, with a
// receptor group silenced vs intact; share of branch steps whose acting patch differs.
function sensation(b, trained, opts, group) {
  let diff = 0, n = 0;
  for (let k = 0; k < 20; k++) {
    const pre = live(b, [{ name: "world", world: true, len: 25 * k + 5 }], opts, JSON.parse(JSON.stringify(trained.st)), trained.R, trained.wt);
    const ids = new Set(group.map(g => b.names.indexOf(g)));
    const A = live(b, [{ name: "world", world: true, len: 10 }], { ...opts, seed: 99 + k }, JSON.parse(JSON.stringify(pre.st)), pre.R, pre.wt);
    const B = live(b, [{ name: "world", world: true, len: 10 }], { ...opts, seed: 99 + k, silAt: () => ids }, JSON.parse(JSON.stringify(pre.st)), pre.R, pre.wt);
    A.log.forEach((x, i) => { n++; if (x.act !== B.log[i].act) diff++; });
  }
  return +(diff / n).toFixed(3);
}
function trial(plan, opts) {
  const b = L.newborn();
  const tr = live(b, plan, opts);
  const firstUseful = tr.log.findIndex(x => (x.q[eidx(b, "r4", "m1")] >= 1 || x.q[eidx(b, "r7", "m1")] >= 1) || (x.q[eidx(b, "r2", "m2")] >= 1 || x.q[eidx(b, "r6", "m2")] >= 1));
  const test = live(b, [{ name: "test", world: true, len: 1000 }], opts, JSON.parse(JSON.stringify(tr.st)), [50, 50], 0);
  const nurseryEnd = plan[0].name === "nursery" ? matrix(b, tr.log[plan[0].len - 1].q) : null;
  return { matrix_end_nursery: nurseryEnd, matrix_end_training: matrix(b, tr.st.q), first_step_useful_learned: firstUseful < 0 ? null : firstUseful + 1,
           training: behaviour(tr.log), test: behaviour(test.log),
           sensation: { informative: sensation(b, tr, opts, ["r2", "r4", "r6", "r7"]), noise: sensation(b, tr, opts, ["r1"]), clock: sensation(b, tr, opts, ["r3"]), empties: sensation(b, tr, opts, ["r5", "r8"]) } };
}
function handwiredTest() {
  const s = SIM.build(TYPES.find(t => t.name === "selfloop-pair-agent")), st = SIM.init(s); 
  let R = [50, 50]; const win = [], log = [];
  for (let t = 1; t <= 1000; t++) {
    const y = [Math.min(R[0], 5), Math.min(R[1], 5)], out = SIM.step(st, s, y, new Set());
    R = [0, 1].map(k => Math.min(50, R[k] - out.digested[k] + season(t)[k]));
    win.push({ active: st.active.slice(), strength: st.strength.slice() }); if (win.length > 5) win.shift();
    const act = out.acting.length ? s.motors[out.acting[0]] : 0;
    log.push({ y, act, answered: act ? out.digested[act - 1] > 0 : null, formed: SIM.form(win, s) });
  }
  return behaviour(log);
}
const results = { handwired_test: handwiredTest(), runs: {} };
for (const [name, plan] of [["curriculum", CURRICULUM], ["no-curriculum", NONE]])
  for (const [abl, o] of [["full", {}], ["fail-off", { fail: false }], ["explore-off", { explore: false }]])
    for (const seed of [1, 2, 3, 4, 5]) {
      if (abl !== "full" && seed > 1) continue;
      results.runs[`${name}/${abl}/seed${seed}`] = trial(plan, { ...o, seed });
    }
require("fs").writeFileSync(__dirname + "/results-heldout.json", JSON.stringify(results, null, 1));
console.log("handwired test:", JSON.stringify(results.handwired_test));
for (const [k, r] of Object.entries(results.runs)) {
  const m = r.matrix_end_training;
  console.log(k.padEnd(32), "useful@", r.first_step_useful_learned, " test", JSON.stringify(r.test), " sens", JSON.stringify(r.sensation));
  if (r.matrix_end_nursery) console.log("   nursery-end q:", Object.entries(r.matrix_end_nursery).map(([r, v]) => `${r}:${v.join("/")}`).join(" "));
  console.log("   q(r->m1,r->m2):", Object.entries(m).map(([r, v]) => `${r}:${v.join("/")}`).join(" "));
}
