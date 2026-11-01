// Stage 49: the repaired contrast rule ("learn2" of memory/turn_sed.js) on the material body. Same 10 worlds, raising and
// costs as stage 48 (PHASE = (seed - 1) x 100, FEED, RAISE "body", no capacity, U 0.02, MCOST 0.004, KC 0.002, 10000 steps).
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const C = { OLD: {}, LEARN: { CONTRAST: "learn" }, LEARN2: { CONTRAST: "learn2" }, LEARN2R: { CONTRAST: "learn2", REVR: 5800 }, NR: { DROPR: ["r5", "r6"] } }, R = {};
for (const s of S) { const o = { U: 0.02, MCOST: 0.004, STEPS: 10000, KC: 0.002, FEED: true, PHASE: (s - 1) * 100, RAISE: "body" }; R[s] = {};
  for (const [k, x] of Object.entries(C)) { R[s][k] = B.run("ORG", s, { ...o, ...x }); delete R[s][k].acts; }
  const life = r => r.death ?? 10000;
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} ${r.meanCount.toFixed(1)}/${r.meanLate.toFixed(1)} d${r.death} kept${(r.kept * 10000 / life(r)).toFixed(1)} acts${(r.nActs / life(r)).toFixed(2)} harv${(r.moved / life(r)).toFixed(3)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-learn2.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, alive = k => cnt(s => R[s][k].death === null), life = r => r.death ?? 10000, v = [];
const keptPer = r => r.kept * 10000 / life(r);   // r.kept is the mean over all STEPS; per step alive
v.push(["L0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["L1", alive("LEARN2") >= 9, `LEARN2 alive ${alive("LEARN2")}/10`]);
v.push(["L2", cnt(s => R[s].LEARN2.nActs / life(R[s].LEARN2) >= 0.9 && R[s].LEARN2.moved / life(R[s].LEARN2) >= 0.08) >= 8, `LEARN2 acts >= 0.9 and harvest >= 0.08 per step ${cnt(s => R[s].LEARN2.nActs / life(R[s].LEARN2) >= 0.9 && R[s].LEARN2.moved / life(R[s].LEARN2) >= 0.08)}/10`]);
v.push(["L3", cnt(s => R[s].LEARN2.meanCount >= R[s].NR.meanCount - 1) >= 7, `LEARN2 body >= NR body - 1 ${cnt(s => R[s].LEARN2.meanCount >= R[s].NR.meanCount - 1)}/10`]);
v.push(["L4", alive("LEARN2R") >= 7, `LEARN2 with receptors crossed at 5800 alive ${alive("LEARN2R")}/10`]);
v.push(["L5", cnt(s => keptPer(R[s].LEARN2) < keptPer(R[s].OLD)) >= 9, `LEARN2 keeps fewer contingencies than OLD ${cnt(s => keptPer(R[s].LEARN2) < keptPer(R[s].OLD))}/10`]);
v.push(["L6", cnt(s => R[s].LEARN2.meanCount > R[s].LEARN.meanCount) >= 8, `LEARN2 body larger than LEARN ${cnt(s => R[s].LEARN2.meanCount > R[s].LEARN.meanCount)}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
