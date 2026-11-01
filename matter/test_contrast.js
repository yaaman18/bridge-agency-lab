// Stage 48: a rule under which chance contingencies do not sediment (memory/turn_sed.js, body_org.js CONTRAST), with the
// noise and clock receptors kept. Same worlds as stage 47 (PHASE = (seed - 1) x 100), FEED, the circuit raised on the
// body (RAISE "body"), no capacity limit, U = 0.02, MCOST = 0.004, KC = 0.002, 10000 steps.
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const C = { OLD: {}, SED: { CONTRAST: "sed" }, LEARN: { CONTRAST: "learn" }, LEARNR: { CONTRAST: "learn", REVR: 5800 }, NR: { DROPR: ["r5", "r6"] } }, R = {};
for (const s of S) { const o = { U: 0.02, MCOST: 0.004, STEPS: 10000, KC: 0.002, FEED: true, PHASE: (s - 1) * 100, RAISE: "body" }; R[s] = {};
  for (const [k, x] of Object.entries(C)) { R[s][k] = B.run("ORG", s, { ...o, ...x }); delete R[s][k].acts; }
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} ${r.meanCount.toFixed(1)}/${r.meanLate.toFixed(1)} d${r.death} kept${r.kept.toFixed(1)} end${r.keptEnd} ans${r.answered.toFixed(2)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-contrast.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, alive = k => cnt(s => R[s][k].death === null), v = [];
const keptRate = r => r.kept / (r.death === null ? 10000 : r.death);   // mean kept contingencies per step alive
v.push(["S0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["S1", 10 - alive("OLD") >= 8, `old rule (noise and clock kept) dies ${10 - alive("OLD")}/10`]);
v.push(["S2", 10 - alive("SED") >= 6, `sediment gate only dies ${10 - alive("SED")}/10`]);
v.push(["S3", alive("LEARN") >= 8, `learning gate alive ${alive("LEARN")}/10`]);
v.push(["S4", cnt(s => keptRate(R[s].LEARN) < keptRate(R[s].OLD)) === 10, `LEARN keeps fewer contingencies than OLD ${cnt(s => keptRate(R[s].LEARN) < keptRate(R[s].OLD))}/10`]);
v.push(["S5", alive("LEARNR") >= 7, `LEARN with receptors crossed at 5800 alive ${alive("LEARNR")}/10`]);
v.push(["S6", cnt(s => R[s].LEARN.meanCount >= R[s].NR.meanCount - 1) >= 7, `LEARN body >= receptors-removed body - 1 in ${cnt(s => R[s].LEARN.meanCount >= R[s].NR.meanCount - 1)}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
