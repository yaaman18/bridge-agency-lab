// Stage 50 verdicts (predictions-org-learn2.md): results-scaffold.json (turn.js, stage 25) vs results-scaffold-learn2.json
// (CORE=./turn_learn2.js), and results-org-learn2.json.
const fs = require("fs"), S = ["1", "2", "3", "4", "5"], CONDS = ["RESP-ADULT", "SCAF-ADULT", "SCAF-RAISED"];
const A = JSON.parse(fs.readFileSync(__dirname + "/results-scaffold.json")), B = JSON.parse(fs.readFileSync(__dirname + "/results-scaffold-learn2.json")), O = JSON.parse(fs.readFileSync(__dirname + "/results-org-learn2.json"));
for (const c of CONDS) for (const s of S) console.log(c.padEnd(11), s, "patchAns old", ["A", "B", "C"].map(p => A[s][c][p].patchAnsFrac).join("/"), "L2", ["A", "B", "C"].map(p => B[s][c][p].patchAnsFrac).join("/"),
  "| waitLate old", A[s][c].A.waitingShareLate, "L2", B[s][c].A.waitingShareLate, "| calls A old", A[s][c].A.calls, "L2", B[s][c].A.calls, "| form A old", A[s][c].A.form, "L2", B[s][c].A.form);
const v = [], cnt = f => S.filter(f).length;
let n = 0, tot = 0; for (const c of CONDS) for (const s of S) for (const p of ["A", "B", "C"]) { tot++; if (B[s][c][p].patchAnsFrac >= A[s][c][p].patchAnsFrac - 0.02) n++; }
v.push(["O1", n >= 36, `patch answered fraction kept (>= old - 0.02) ${n}/${tot}`]);
const w = ["SCAF-RAISED", "RESP-ADULT"].map(c => cnt(s => B[s][c].A.waitingShareLate !== null && B[s][c].A.waitingShareLate <= A[s][c].A.waitingShareLate + 0.05));
v.push(["O2", w.every(x => x >= 4), `waiting kept: SCAF-RAISED ${w[0]}/5, RESP-ADULT ${w[1]}/5`]);
const j = cnt(s => O[s].L2.junk < O[s].OLD.junk); v.push(["O3", j === 5, `noise/clock sediment lower ${j}/5 (old ${S.map(s => O[s].OLD.junk)}, L2 ${S.map(s => O[s].L2.junk)})`]);
const r = cnt(s => O[s].L2.post <= O[s].OLD.post), r2 = cnt(s => O[s].L2.rec === null || (O[s].OLD.rec !== null && O[s].L2.rec > O[s].OLD.rec));
v.push(["O4", r >= 4 && r2 >= 4, `after crossing L2 answered <= old ${r}/5, recovers later or never ${r2}/5`]);
const f = cnt(s => B[s]["SCAF-RAISED"].A.form >= A[s]["SCAF-RAISED"].A.form - 0.05); v.push(["O5", f >= 4, `form kept SCAF-RAISED ${f}/5`]);
for (const s of S) console.log("org", s, JSON.stringify(O[s]));
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
