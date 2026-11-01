// Stage 42: the organization layer on the material body (body_org.js). Seeds 1-10, U = 0.02, MCOST = 0.004, 10000 steps.
// Conditions: ORG, REPLAY (the ORG run's acts, shifted), NONE, and ORG-REV (ORG with the patches' seasons exchanged from
// step 5000 on). Verdicts of predictions-body-org.md at the end.
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], o = { U: 0.02, MCOST: 0.004, STEPS: 10000 };
const R = {};
for (const s of S) { const org = B.run("ORG", s, o); R[s] = { ORG: org, REPLAY: B.run("REPLAY", s, o, org.acts), NONE: B.run("NONE", s, o), REV: B.run("ORG", s, { ...o, REV: 5000 }) };
  for (const c of Object.keys(R[s])) delete R[s][c].acts;
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} mean ${r.meanCount.toFixed(1)} fin ${r.final} death ${r.death} acts ${r.nActs} ans ${r.answered.toFixed(2)} err ${r.maxErr.toExponential(0)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-body-org.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, v = [];
v.push(["I0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["I1", cnt(s => R[s].NONE.death !== null) === 10, `NONE dies ${cnt(s => R[s].NONE.death !== null)}/10`]);
v.push(["I2", cnt(s => R[s].ORG.death === null) >= 9, `ORG alive at the end ${cnt(s => R[s].ORG.death === null)}/10`]);
v.push(["I3", cnt(s => R[s].ORG.meanCount > R[s].REPLAY.meanCount) >= 9, `ORG body larger than REPLAY ${cnt(s => R[s].ORG.meanCount > R[s].REPLAY.meanCount)}/10`]);
v.push(["I4", cnt(s => R[s].ORG.answered > R[s].REPLAY.answered) >= 9, `ORG answered fraction above REPLAY ${cnt(s => R[s].ORG.answered > R[s].REPLAY.answered)}/10`]);
v.push(["I5", cnt(s => R[s].REPLAY.death !== null) >= 7, `REPLAY dies ${cnt(s => R[s].REPLAY.death !== null)}/10`]);
v.push(["I6", cnt(s => R[s].REV.death === null) >= 8, `ORG-REV alive at the end ${cnt(s => R[s].REV.death === null)}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
