// Stage 52 verdicts (predictions-waiting.md): is the worse waiting of learn2/learn3 in a few seeds (stage 50-51) systematic
// or the divergence of chaotic runs? test_scaffold_seeds.js, seeds 1-40, turn.js vs turn_learn3.js.
const fs = require("fs"), A = JSON.parse(fs.readFileSync(__dirname + "/results-waiting-old.json")), B = JSON.parse(fs.readFileSync(__dirname + "/results-waiting-l3.json"));
const S = Object.keys(A), CONDS = ["RESP-ADULT", "SCAF-ADULT", "SCAF-RAISED"], med = a => { const b = a.slice().sort((x, y) => x - y); return (b[(b.length - 1) >> 1] + b[b.length >> 1]) / 2; };
// two-sided sign test at 5%: the count of "worse" among n untied pairs is significant if P(X <= min) * 2 < 0.05
const binom = (n, k) => { let c = 1; for (let i = 0; i < k; i++) c = c * (n - i) / (i + 1); return c; };
const signP = (w, n) => { const k = Math.min(w, n - w); let p = 0; for (let i = 0; i <= k; i++) p += binom(n, i) / 2 ** n; return Math.min(1, 2 * p); };
const v = [];
for (const c of CONDS) for (const ph of ["A", "C"]) {
  const d = S.map(s => [A[s][c][ph].waitingShareLate, B[s][c][ph].waitingShareLate]).filter(([a, b]) => a !== null && b !== null).map(([a, b]) => b - a);
  const worse = d.filter(x => x > 0).length, better = d.filter(x => x < 0).length, n = worse + better, p = signP(worse, n);
  const mo = S.map(s => A[s][c][ph].waitingShareLate).filter(x => x !== null), ml = S.map(s => B[s][c][ph].waitingShareLate).filter(x => x !== null), mean = a => a.reduce((x, y) => x + y, 0) / a.length;
  console.log(`${c} ${ph}: pairs ${d.length}, worse ${worse}, better ${better}, tied ${d.length - n}, sign p ${p.toFixed(3)}, median diff ${med(d).toFixed(3)}, mean old ${mean(mo).toFixed(3)} L3 ${mean(ml).toFixed(3)}, worse by > 0.05: ${d.filter(x => x > 0.05).length}, better by > 0.05: ${d.filter(x => x < -0.05).length}`);
  if (ph === "A") { v.push([`W1 ${c}`, p >= 0.05, `sign test p ${p.toFixed(3)} (worse ${worse} / better ${better})`]); v.push([`W2 ${c}`, Math.abs(med(d)) <= 0.03 && mean(ml) <= mean(mo) + 0.03, `median diff ${med(d).toFixed(3)}, mean ${mean(mo).toFixed(3)} -> ${mean(ml).toFixed(3)}`]); }
}
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
