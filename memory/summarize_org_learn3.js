// Stage 51 (organization part) verdicts: results-org-learn3.json and results-scaffold-learn3.json vs results-scaffold.json.
const fs = require("fs"), S = ["1", "2", "3", "4", "5"], CONDS = ["RESP-ADULT", "SCAF-ADULT", "SCAF-RAISED"];
const A = JSON.parse(fs.readFileSync(__dirname + "/results-scaffold.json")), B = JSON.parse(fs.readFileSync(__dirname + "/results-scaffold-learn3.json")), O = JSON.parse(fs.readFileSync(__dirname + "/results-org-learn3.json"));
for (const s of S) console.log("org", s, JSON.stringify(O[s]));
for (const c of CONDS) console.log(c, "waitLate old", S.map(s => A[s][c].A.waitingShareLate).join(","), "| L3", S.map(s => B[s][c].A.waitingShareLate).join(","));
const cnt = f => S.filter(f).length, v = [];
v.push(["P4", cnt(s => O[s].L3.actsPost >= 0.85) >= 4, `org world crossed: learn3 acts per step >= 0.85 in ${cnt(s => O[s].L3.actsPost >= 0.85)}/5 (L3 ${S.map(s => O[s].L3.actsPost)}, L2 ${S.map(s => O[s].L2.actsPost)}, old ${S.map(s => O[s].OLD.actsPost)})`]);
v.push(["P5", cnt(s => O[s].L3.junk <= 2) === 5, `noise/clock sediment <= 2: ${cnt(s => O[s].L3.junk <= 2)}/5 (${S.map(s => O[s].L3.junk)})`]);
let n = 0; for (const c of CONDS) for (const s of S) for (const p of ["A", "B", "C"]) if (B[s][c][p].patchAnsFrac >= A[s][c][p].patchAnsFrac - 0.02) n++;
const w = cnt(s => B[s]["SCAF-RAISED"].A.waitingShareLate <= A[s]["SCAF-RAISED"].A.waitingShareLate + 0.05);
v.push(["P6", n >= 36 && w >= 4, `scaffold: patch answered kept ${n}/45, SCAF-RAISED waiting kept ${w}/5`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("organization predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
