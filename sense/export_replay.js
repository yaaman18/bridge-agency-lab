// Export one overnight training run (rev. 4 rules, original receptors, curriculum, seed 1) for the replay page.
const L = require("./learn.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const PLAN = [
  { name: "nursery", sched: [[5, 0], [0, 5]], period: 50, len: 400 },
  { name: "school", sched: [[5, 2], [2, 5]], period: 15, len: 400 },
  { name: "world", world: true, len: 1200 },
];
function run(plan, seed) {
  const b = L.newborn(), st = L.init(b), noise = L.rng(seed); let R = [50, 50], wt = 0; const rows = [];
  const rm = b.edges.map((e, k) => [k, b.names[e[0]], b.names[e[1]]]).filter(([k, a, c]) => (a.startsWith("r") || a.startsWith("c")) && c.startsWith("m"));
  for (const seg of plan) for (let i = 0; i < seg.len; i++) {
    const y = seg.world ? [Math.min(R[0], 5), Math.min(R[1], 5)] : seg.sched[Math.floor(i / seg.period) % seg.sched.length].slice();
    const out = L.step(st, b, y, { noise });
    if (seg.world) { wt++; const g = season(wt); R = [0, 1].map(k => Math.min(50, R[k] - out.d[k] + g[k])); }
    const act = out.acting.length ? b.patch[out.acting[0]] : 0;
    rows.push([seg.name[0], y[0], y[1], act, act ? (out.answered.get(out.acting[0]) ? 1 : 0) : -1, rm.map(([k]) => st.q[k]).join("")]);
  }
  return { edges: rm.map(([k, a, c]) => a + ">" + c), rows };
}
const out = { features: L.FEATURES.map(f => f[0]), curriculum: run(PLAN, 1), none: run([{ name: "world", world: true, len: 2000 }], 1) };
require("fs").writeFileSync(__dirname + "/replay.json", JSON.stringify(out));
console.log("edges", out.curriculum.edges.join(" "), "rows", out.curriculum.rows.length, "bytes", JSON.stringify(out).length);
