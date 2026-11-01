// Stage 43: the circuit against a fixed rule (GREEDY, body_org.js), without and with crossed receptors from step 5000
// (REVR). Seeds 1-10 (GREEDY has no randomness; its runs are the same for every seed), U = 0.02, MCOST = 0.004, 10000 steps.
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], o = { U: 0.02, MCOST: 0.004, STEPS: 10000 }, ov = { ...o, REVR: 5000 };
const R = {};
for (const s of S) { R[s] = { ORG: B.run("ORG", s, o), GREEDY: B.run("GREEDY", s, o), ORGR: B.run("ORG", s, ov), GREEDYR: B.run("GREEDY", s, ov) };
  for (const c of Object.keys(R[s])) delete R[s][c].acts;
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} mean ${r.meanCount.toFixed(1)} late ${r.meanLate.toFixed(1)} death ${r.death} ans ${r.answered.toFixed(2)} err ${r.maxErr.toExponential(0)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-greedy.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, v = [];
v.push(["F0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["F1", cnt(s => R[s].GREEDY.meanCount >= 0.95 * R[s].ORG.meanCount) >= 8, `GREEDY >= 0.95 ORG ${cnt(s => R[s].GREEDY.meanCount >= 0.95 * R[s].ORG.meanCount)}/10`]);
v.push(["F2", cnt(s => R[s].GREEDYR.death !== null) === 10, `GREEDY with crossed receptors dies ${cnt(s => R[s].GREEDYR.death !== null)}/10`]);
v.push(["F3", cnt(s => R[s].ORGR.death === null) >= 8, `ORG with crossed receptors alive at the end ${cnt(s => R[s].ORGR.death === null)}/10`]);
v.push(["F4", cnt(s => R[s].ORGR.meanLate > R[s].GREEDYR.meanLate) >= 9, `ORG-REVR late body > GREEDY-REVR ${cnt(s => R[s].ORGR.meanLate > R[s].GREEDYR.meanLate)}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
