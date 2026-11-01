// Stage 45 verdicts (predictions-bind.md): binding cut from activity (BINDC=0.7), GATE 0 and 0.5, against stage 39.
const fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], WS = ["LEAN", "RICH"];
const load = (tag, w, s) => JSON.parse(fs.readFileSync(`${__dirname}/results-${tag}/${w}-${s}.json`));
const fin = r => r.log[r.log.length - 1], med = a => { const b = a.slice().sort((x, y) => x - y); return (b[(b.length - 1) >> 1] + b[b.length >> 1]) / 2; };
const cnt = f => S.filter(f).length, rank = r => 1 + fin(r).mk.filter(x => x > fin(r).ba).length;
const T = { b0: "bind0.7-gate0", b5: "bind0.7-gate0.5", ref: "neutral" }, R = {};
for (const [k, tag] of Object.entries(T)) for (const w of WS) for (const s of S) R[k + w + s] = load(tag, w, s);
for (const k of ["b0", "b5"]) for (const w of WS) console.log(T[k], w, S.map(s => { const r = R[k + w + s], f = fin(r);
  return `${s}: n${f.count} ba${f.ba.toFixed(3)} r${rank(r)} act${f.act.toFixed(2)} Cb${r.Cb[0].toFixed(2)} Cd${r.Cd[0].toFixed(2)}`; }).join(" | "));
const v = [], per = (k, f) => WS.map(w => cnt(s => f(R[k + w + s], R["ref" + w + s])));
v.push(["H0", ["b0", "b5"].every(k => WS.every(w => S.every(s => R[k + w + s].maxErr < 1e-6 && R[k + w + s].minCount > 0))), "conservation and persistence"]);
let c = per("b0", r => rank(r) === 1); v.push(["H1", c.every(x => x <= 2), `GATE 0: ba above all markers LEAN ${c[0]}/10 RICH ${c[1]}/10`]);
c = per("b0", r => fin(r).ba < med(fin(r).mk)); v.push(["H2", c.every(x => x >= 8), `GATE 0: ba below marker median LEAN ${c[0]}/10 RICH ${c[1]}/10`]);
c = per("b5", r => fin(r).ba < med(fin(r).mk)); v.push(["H3", c.every(x => x >= 6), `GATE 0.5: ba below marker median LEAN ${c[0]}/10 RICH ${c[1]}/10`]);
const c4 = ["b0", "b5"].map(k => per(k, (r, ref) => fin(r).act < fin(ref).act)); v.push(["H4", c4.flat().every(x => x >= 8), `act lower than stage 39: GATE0 LEAN ${c4[0][0]} RICH ${c4[0][1]}; GATE0.5 LEAN ${c4[1][0]} RICH ${c4[1][1]} (/10)`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
