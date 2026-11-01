// Stage 53 checks of the app's life loop v3.4 (turn_sed.js + life_turn.js, rule learn3) on the being saved before the
// change (backup/being-state-pre-learn3-age86642.json), against v3.3 (turn.js + backup/life_turn-v3.3.js).
const fs = require("fs"), strip = s => s.replace(/^module\.exports.*$/m, "");
const eng = (core, life) => new Function(strip(fs.readFileSync(__dirname + "/" + core, "utf8")) + "\n" + strip(fs.readFileSync(__dirname + "/" + life, "utf8")) + "; return { makeLife };")();
const NEW = () => eng("turn_sed.js", "life_turn.js"), OLD = () => eng("turn.js", "backup/life_turn-v3.3.js");
const saved = () => { const d = JSON.parse(fs.readFileSync(__dirname + "/backup/being-state-pre-learn3-age86642.json", "utf8")); return d.data || d; };
const rt = L => JSON.parse(JSON.stringify(L));   // what the page's save does (NaN -> null)
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const out = [];
// 1. the change keeps every contingency and its sediment, records the rule, starts empty statistics
{ const s0 = saved(), l = NEW().makeLife(rt(s0));
  out.push(["kept", same(l.L.q, s0.q) && same(l.L.sg, s0.sg) && same(l.L.h, s0.h), `rule ${l.L.rule}, ruleHist ${JSON.stringify(l.L.ruleHist)}, lastM all = age: ${l.st.lastM.every(x => x === s0.age)}`]); }
// 2. save/restore in the middle gives the same run as without (NaN through JSON)
{ const a = NEW().makeLife(rt(saved())); a.live(6000);
  const b1 = NEW().makeLife(rt(saved())); b1.live(3000); const b2 = NEW().makeLife(rt(b1.L)); b2.live(3000);
  const pick = l => rt({ q: l.L.q, sg: l.L.sg, h: l.L.h, active: l.L.active, R: l.L.R, age: l.L.age, cOn: l.L.cOn, cOff: l.L.cOff, lastM: l.L.lastM, rng: l.L.rng });
  out.push(["restore", same(pick(a), pick(b2)), `age ${a.L.age}`]); }
// 3. foraging and the reversal button: 5000 steps, then reverse() and 3000 steps; acts per step and answered fraction
function life(E, n1, rev, n2) {
  const l = E.makeLife(rt(saved())); let acts = 0, ans = 0, steps = 0; const count = k => { for (let i = 0; i < k; i++) { const o = l.live(1); steps++; acts += o.acting.length; ans += o.answered.filter(Boolean).length; } };
  count(n1); const pre = [acts / steps, ans / Math.max(1, acts)]; acts = ans = steps = 0;
  if (rev) l.reverse(); count(n2); const post = [acts / steps, ans / Math.max(1, acts)];
  const jk = ["r5", "r6"].flatMap(r => ["m1", "m2"].map(m => l.b.edges.findIndex(e => l.b.names[e[0]] === r && l.b.names[e[1]] === m)));
  return { pre: pre.map(x => +x.toFixed(3)), post: post.map(x => +x.toFixed(3)), junkSed: jk.reduce((s, k) => s + l.L.sg[k], 0), sed: l.L.sg.reduce((a, c) => a + c, 0) };
}
const rN = life(NEW(), 5000, true, 3000), rO = life(OLD(), 5000, true, 3000);
out.push(["world", rN.pre[0] >= 0.9 && rN.pre[1] >= 0.95, `v3.4 acts/step, answered: before reverse ${rN.pre}, after ${rN.post}; noise/clock sediment ${rN.junkSed}, total ${rN.sed} | v3.3: ${rO.pre}, ${rO.post}; ${rO.junkSed}, ${rO.sed}`]);
out.push(["reverse", rN.post[0] >= 0.85, `v3.4 acts/step after reverse ${rN.post[0]} (v3.3 ${rO.post[0]})`]);
for (const [k, ok, msg] of out) console.log(k, ok ? "OK" : "FAIL", "-", msg);
