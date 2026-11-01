// Stage 47: the stage 46 conditions with and without the contingencies of the noise (r5) and clock (r6) receptors
// (body_org.js DROPR), in worlds that differ by seed (PHASE = (seed - 1) x 100). FEED, U = 0.02, MCOST = 0.004, KC = 0.002,
// PER = 1 where named, 10000 steps.
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], NR = { DROPR: ["r5", "r6"] };
const C = { GROW: { RAISE: "body", PER: 1 }, GROWNR: { RAISE: "body", PER: 1, ...NR }, PRECAP: { PER: 1 }, PRECAPNR: { PER: 1, ...NR },
            BODYNR: { RAISE: "body", ...NR }, GROWRNR: { RAISE: "body", PER: 1, REVR: 5800, ...NR } }, R = {};
for (const s of S) { const o = { U: 0.02, MCOST: 0.004, STEPS: 10000, KC: 0.002, FEED: true, PHASE: (s - 1) * 100 }; R[s] = {};
  for (const [k, x] of Object.entries(C)) { R[s][k] = B.run("ORG", s, { ...o, ...x }); delete R[s][k].acts; }
  R[s].GREEDY = B.run("GREEDY", s, o); delete R[s].GREEDY.acts;
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} ${r.meanCount.toFixed(1)}/${r.meanLate.toFixed(1)} d${r.death} k${r.keptEnd} lost${r.lost}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-nonoise.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, alive = k => cnt(s => R[s][k].death === null), v = [];
const lossRate = r => r.lost / (r.death === null ? 10000 : r.death);
v.push(["N0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["N1", alive("GROWNR") >= 8 && alive("GROW") <= 3, `GROW without noise/clock alive ${alive("GROWNR")}/10; with them ${alive("GROW")}/10`]);
v.push(["N2", alive("PRECAPNR") >= 8, `PRECAP without noise/clock alive ${alive("PRECAPNR")}/10`]);
v.push(["N3", cnt(s => lossRate(R[s].GROWNR) < lossRate(R[s].GROW)) >= 8, `contingencies lost per step lower without noise/clock ${cnt(s => lossRate(R[s].GROWNR) < lossRate(R[s].GROW))}/10`]);
v.push(["N4", alive("GROWRNR") >= 7, `GROW without noise/clock, receptors crossed at 5800, alive ${alive("GROWRNR")}/10`]);
v.push(["N5", 10 - alive("BODYNR") >= 8, `without capacity still dies ${10 - alive("BODYNR")}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
