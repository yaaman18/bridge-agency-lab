// Stage 39 verdicts (predictions-neutral.md) from results-neutral/{LEAN,RICH}-{1..10}.json, plus the replay check of
// seeds 1-3 against stage 38 (results-evo2-LEAN/RICH.json; fevo.js is bit-identical to evo_trm.js and hooks only observe).
const fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], WS = ["LEAN", "RICH"];
const R = {}; for (const w of WS) for (const s of S) R[w + s] = JSON.parse(fs.readFileSync(`${__dirname}/results-neutral/${w}-${s}.json`));
const fin = r => r.log[r.log.length - 1], med = a => { const b = a.slice().sort((x, y) => x - y); return (b[(b.length - 1) >> 1] + b[b.length >> 1]) / 2; };
const q025 = a => a.slice().sort((x, y) => x - y)[Math.floor(a.length * 0.025)];
const cnt = f => S.filter(f).length, row = [];
for (const w of WS) for (const s of S) { const r = R[w + s], f = fin(r);
  row.push(`${w}/${s}`.padEnd(8) + ` n=${f.count} ba=${f.ba.toFixed(3)} mk=[${Math.min(...f.mk).toFixed(3)},${Math.max(...f.mk).toFixed(3)}] med ${med(f.mk).toFixed(3)} act=${f.act.toFixed(3)}`
    + ` Cb=${r.Cb[0].toFixed(3)} Cd=${r.Cd[0].toFixed(3)} mkCb=${med(r.Cb.slice(1)).toFixed(3)} mkCd=${med(r.Cd.slice(1)).toFixed(3)} lines=${f.lines} shadow med ${med(r.shadowLines)} 2.5% ${q025(r.shadowLines)}`); }
console.log(row.join("\n"));
const v = [];
v.push(["N0", WS.every(w => S.every(s => R[w + s].maxErr < 1e-6 && R[w + s].minCount > 0)), "max err " + Math.max(...Object.values(R).map(r => r.maxErr)).toExponential(1) + ", min count " + Math.min(...Object.values(R).map(r => r.minCount))]);
const n1 = WS.map(w => cnt(s => fin(R[w + s]).ba > Math.max(...fin(R[w + s]).mk))); v.push(["N1", n1.every(c => c >= 8), `ba above all 20 markers: LEAN ${n1[0]}/10, RICH ${n1[1]}/10`]);
const ex = (w, s) => fin(R[w + s]).ba - med(fin(R[w + s]).mk), n2 = cnt(s => ex("LEAN", s) > ex("RICH", s)); v.push(["N2", n2 >= 7, `excess LEAN > RICH ${n2}/10`]);
const n3a = WS.map(w => cnt(s => R[w + s].Cb[0] > 0)), n3b = WS.map(w => cnt(s => R[w + s].Cb[0] > R[w + s].Cd[0]));
v.push(["N3", n3a.every(c => c >= 8) && n3b.every(c => c >= 7), `Cb>0 LEAN ${n3a[0]}/10 RICH ${n3a[1]}/10; Cb>Cd LEAN ${n3b[0]}/10 RICH ${n3b[1]}/10`]);
const n4 = WS.map(w => cnt(s => fin(R[w + s]).lines < q025(R[w + s].shadowLines))); v.push(["N4", n4.every(c => c >= 8), `real lines below shadow 2.5%: LEAN ${n4[0]}/10 RICH ${n4[1]}/10`]);
const n5 = cnt(s => med(R["LEAN" + s].shadowLines) < med(R["RICH" + s].shadowLines)); v.push(["N5", n5 >= 8, `shadow median lines LEAN < RICH ${n5}/10`]);
const n6 = cnt(s => fin(R["LEAN" + s]).lines < fin(R["RICH" + s]).lines); v.push(["N6", n6 >= 8, `real lines LEAN < RICH ${n6}/10`]);
for (const [k, ok, msg] of v) console.log(k, ok ? "HOLDS" : "FAILS", "-", msg);
console.log("predictions holding:", v.filter(x => x[1]).length + "/" + v.length);
for (const w of WS) { try { const o = JSON.parse(fs.readFileSync(`${__dirname}/results-evo2-${w}.json`));
  for (const s of [1, 2, 3]) { const a = o[`${w}/${s}`].log.at(-1), b = fin(R[w + s]); console.log(`replay ${w}/${s}:`, a.count === b.count && a.lines === b.lines && a.ba === +b.ba.toFixed(3) ? "identical to stage 38" : "DIFFERENT", JSON.stringify([a.count, a.lines, a.ba]), JSON.stringify([b.count, b.lines, +b.ba.toFixed(3)])); } } catch (e) { console.log("replay check failed:", e.message); } }
