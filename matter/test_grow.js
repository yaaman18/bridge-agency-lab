// Stage 46: the circuit grows with the body (body_org.js FEED, RAISE, PER). All runs: FEED (upbringing by fed pools for
// 800 steps, then seasons), U = 0.02, MCOST = 0.004, KC = 0.002 (the upkeep that killed every pre-raised circuit in stage
// 44), 10000 steps, seeds 1-10. A 2 x 2 of raising (offline "pre" / on the body) x capacity (none / PER = 1), plus GROW
// with receptors crossed at 5800 (5000 steps after school), GREEDY (pays for 4) and NONE.
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const o = { U: 0.02, MCOST: 0.004, STEPS: 10000, KC: 0.002, FEED: true }, R = {};
const C = { PRE: ["ORG", {}], PRECAP: ["ORG", { PER: 1 }], BODY: ["ORG", { RAISE: "body" }], GROW: ["ORG", { RAISE: "body", PER: 1 }],
            GROWR: ["ORG", { RAISE: "body", PER: 1, REVR: 5800 }], GREEDY: ["GREEDY", {}], GREEDYR: ["GREEDY", { REVR: 5800 }], NONE: ["NONE", {}] };
for (const s of S) { R[s] = {}; for (const [k, [cond, x]] of Object.entries(C)) { R[s][k] = B.run(cond, s, { ...o, ...x }); delete R[s][k].acts; }
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} ${r.meanCount.toFixed(1)}/${r.meanLate.toFixed(1)} d${r.death} k${r.keptEnd} lost${r.lost} ans${r.answered.toFixed(2)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-grow.json", JSON.stringify(R));
const cnt = f => S.filter(f).length, alive = k => cnt(s => R[s][k].death === null), dead = k => 10 - alive(k), v = [];
v.push(["G0", S.every(s => Object.values(R[s]).every(r => r.maxErr < 1e-6)), "conservation"]);
v.push(["G1", alive("GROW") >= 8, `GROW alive at the end ${alive("GROW")}/10`]);
v.push(["G2", dead("PRE") >= 9, `PRE dies ${dead("PRE")}/10`]);
v.push(["G3", dead("BODY") >= 6, `BODY (raised on the body, no capacity) dies ${dead("BODY")}/10`]);
v.push(["G4", alive("PRECAP") >= 8, `PRECAP (pre-raised, capacity) alive ${alive("PRECAP")}/10`]);
v.push(["G5", alive("GROWR") >= 8 && dead("GREEDYR") === 10, `GROW crossed alive ${alive("GROWR")}/10, GREEDY crossed dies ${dead("GREEDYR")}/10`]);
v.push(["G6", cnt(s => R[s].GREEDY.meanLate > R[s].GROW.meanLate) >= 8, `GREEDY late body > GROW ${cnt(s => R[s].GREEDY.meanLate > R[s].GROW.meanLate)}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
