// Stage 51 (material body part): learn3 (memory/turn_sed.js) against learn2 and the old rule, with and without the
// receptors crossed at 5800. Same 10 worlds and costs as stages 48-49. Also acts per step over steps 6800-10000.
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const C = { OLD: {}, OLDR: { REVR: 5800 }, L2: { CONTRAST: "learn2" }, L2R: { CONTRAST: "learn2", REVR: 5800 }, L3: { CONTRAST: "learn3" }, L3R: { CONTRAST: "learn3", REVR: 5800 } }, R = {};
for (const s of S) { const o = { U: 0.02, MCOST: 0.004, STEPS: 10000, KC: 0.002, FEED: true, PHASE: (s - 1) * 100, RAISE: "body" }; R[s] = {};
  for (const [k, x] of Object.entries(C)) { const r = B.run("ORG", s, { ...o, ...x }); r.actsLate = r.acts.slice(6800).reduce((a, x) => a + x.length, 0) / 3200; delete r.acts; R[s][k] = r; }
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} ${r.meanCount.toFixed(1)}/${r.meanLate.toFixed(1)} d${r.death} actsLate${r.actsLate.toFixed(2)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-learn3.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, alive = k => cnt(s => R[s][k].death === null), v = [];
v.push(["P0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["P1", alive("L3R") >= 8, `learn3 with receptors crossed alive ${alive("L3R")}/10 (learn2 ${alive("L2R")}/10, old ${alive("OLDR")}/10)`]);
v.push(["P2", alive("L3") === 10 && cnt(s => R[s].L3.meanCount >= R[s].L2.meanCount - 1) >= 8, `learn3 alive ${alive("L3")}/10, body >= learn2 - 1 in ${cnt(s => R[s].L3.meanCount >= R[s].L2.meanCount - 1)}/10`]);
v.push(["P3", cnt(s => R[s].L3R.actsLate >= 0.9) >= 8, `learn3 crossed acts per step 6800-10000 >= 0.9 in ${cnt(s => R[s].L3R.actsLate >= 0.9)}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("body predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
