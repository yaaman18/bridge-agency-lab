// Stage 54 verdicts (matter/predictions-alt.md): ../matter/results-alt.json, results-org-alt.json, results-waiting-*.json.
const fs = require("fs"), rd = f => JSON.parse(fs.readFileSync(__dirname + "/" + f));
const M = rd("../matter/results-alt.json"), O = rd("results-org-alt.json"), W = { OLD: rd("results-waiting-old.json"), BIN3: rd("results-waiting-bin3.json"), DONLY: rd("results-waiting-donly.json") };
const S10 = Object.keys(M), S5 = Object.keys(O), cnt = (S, f) => S.filter(f).length, alive = k => cnt(S10, s => M[s][k].death === null);
for (const s of S5) console.log("org", s, JSON.stringify(O[s]));
for (const k of Object.keys(M[1])) console.log("body", k.padEnd(7), "alive", alive(k), "mean body", (S10.reduce((a, s) => a + M[s][k].meanCount, 0) / 10).toFixed(1), "acts late", S10.map(s => M[s][k].actsLate.toFixed(2)).join(","));
const binom = (n, k) => { let c = 1; for (let i = 0; i < k; i++) c = c * (n - i) / (i + 1); return c; };
const signP = (w, n) => { const k = Math.min(w, n - w); let p = 0; for (let i = 0; i <= k; i++) p += binom(n, i) / 2 ** n; return Math.min(1, 2 * p); };
const SW = Object.keys(W.OLD).filter(s => s !== "0"), CONDS = ["RESP-ADULT", "SCAF-ADULT", "SCAF-RAISED"];
const scaf = k => { let ans = 0, tot = 0; const ps = []; for (const c of CONDS) { for (const s of SW) for (const p of ["A", "B", "C"]) { tot++; if (W[k][s][c][p].patchAnsFrac >= W.OLD[s][c][p].patchAnsFrac - 0.02) ans++; }
  const d = SW.map(s => W[k][s][c].A.waitingShareLate - W.OLD[s][c].A.waitingShareLate).filter(x => !isNaN(x)), w = d.filter(x => x > 0).length, b = d.filter(x => x < 0).length; ps.push([c, w, b, signP(w, w + b)]); }
  return { ans, tot, ps }; };
const v = [], sb = scaf("BIN3"), sd = scaf("DONLY");
for (const [k, x] of [["BIN3", sb], ["DONLY", sd]]) console.log("scaffold", k, `patch answered kept ${x.ans}/${x.tot}`, x.ps.map(([c, w, b, p]) => `${c} worse ${w} better ${b} p ${p.toFixed(3)}`).join(" | "));
v.push(["Q1", cnt(S5, s => O[s].BIN3.junk <= 2) === 5, `bin3 noise/clock sediment <= 2: ${S5.map(s => O[s].BIN3.junk)}`]);
v.push(["Q2", alive("BIN3") >= 9 && cnt(S10, s => M[s].BIN3.meanCount >= M[s].OLD.meanCount + 1) >= 8, `bin3 body alive ${alive("BIN3")}/10, body >= old + 1 in ${cnt(S10, s => M[s].BIN3.meanCount >= M[s].OLD.meanCount + 1)}/10`]);
v.push(["Q3", alive("BIN3R") >= 8, `bin3 crossed body alive ${alive("BIN3R")}/10`]);
v.push(["Q4", cnt(S5, s => O[s].DONLY.junk >= 10) === 5, `donly noise/clock sediment >= 10: ${S5.map(s => O[s].DONLY.junk)}`]);
v.push(["Q5", cnt(S5, s => O[s].DONLY.actsPost >= 0.85) === 5 && alive("DONLYR") >= alive("OLDR"), `donly org crossed acts ${S5.map(s => O[s].DONLY.actsPost)}; body crossed alive ${alive("DONLYR")} vs old ${alive("OLDR")}`]);
v.push(["Q6", [sb, sd].every(x => x.ans >= 0.8 * x.tot && x.ps.every(([, , , p]) => p >= 0.05)), `scaffold kept and waiting not significantly changed for both`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
