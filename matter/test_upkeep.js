// Stage 44: the circuit pays for its own structure (body_org.js KC: per maintained contingency per step, from the body's
// bound matter; GREEDY pays for its 4). Seeds 1-10, U = 0.02, MCOST = 0.004, 10000 steps; KC in {0, 0.001, 0.002, 0.004,
// 0.006}; at KC = 0.002 also crossed receptors from 5000 (REVR).
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], KCS = [0, 0.001, 0.002, 0.004, 0.006];
const o = { U: 0.02, MCOST: 0.004, STEPS: 10000 }, R = {};
for (const s of S) { R[s] = {};
  for (const KC of KCS) { R[s]["ORG" + KC] = B.run("ORG", s, { ...o, KC }); if (KC === 0 || KC === 0.002) R[s]["GREEDY" + KC] = B.run("GREEDY", s, { ...o, KC }); }
  R[s].ORGR = B.run("ORG", s, { ...o, KC: 0.002, REVR: 5000 }); R[s].GREEDYR = B.run("GREEDY", s, { ...o, KC: 0.002, REVR: 5000 });
  for (const c of Object.keys(R[s])) delete R[s][c].acts;
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} ${r.meanCount.toFixed(1)}/${r.meanLate.toFixed(1)} d${r.death} k${r.kept.toFixed(1)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-upkeep.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, v = [], gap = (s, k) => (R[s]["GREEDY" + k].meanCount - R[s]["ORG" + k].meanCount) / R[s]["ORG" + k].meanCount;
v.push(["U0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["U1", cnt(s => [0, 0.001, 0.002, 0.004].every((k, i, a) => i === 0 || R[s]["ORG" + k].meanCount < R[s]["ORG" + a[i - 1]].meanCount)) >= 9, `ORG body falls with KC (0..0.004) ${cnt(s => [0, 0.001, 0.002, 0.004].every((k, i, a) => i === 0 || R[s]["ORG" + k].meanCount < R[s]["ORG" + a[i - 1]].meanCount))}/10`]);
v.push(["U2", cnt(s => R[s]["ORG0.006"].death !== null) >= 9 && cnt(s => R[s]["ORG0.001"].death === null) === 10, `ORG dies at 0.006 ${cnt(s => R[s]["ORG0.006"].death !== null)}/10, alive at 0.001 ${cnt(s => R[s]["ORG0.001"].death === null)}/10`]);
v.push(["U3", cnt(s => gap(s, 0.002) > gap(s, 0)) >= 9, `GREEDY's lead larger at KC 0.002 than 0 ${cnt(s => gap(s, 0.002) > gap(s, 0))}/10`]);
v.push(["U4", cnt(s => R[s].ORGR.death === null) >= 8 && cnt(s => R[s].GREEDYR.death !== null) === 10, `KC 0.002 crossed: ORG alive ${cnt(s => R[s].ORGR.death === null)}/10, GREEDY dies ${cnt(s => R[s].GREEDYR.death !== null)}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
