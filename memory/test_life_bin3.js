// Stage 55 checks of the app's life loop v3.5 (turn_sed.js + life_turn.js, rule bin3), from the being as saved in the db
// (backup/being-state-pre-learn3-age86642.json, never run under learn3) and from a being that ran 3000 steps under v3.4.
const fs = require("fs"), strip = s => s.replace(/^module\.exports.*$/m, "");
const eng = (core, life) => new Function(strip(fs.readFileSync(__dirname + "/" + core, "utf8")) + "\n" + strip(fs.readFileSync(__dirname + "/" + life, "utf8")) + "; return { makeLife };")();
const V35 = () => eng("turn_sed.js", "life_turn.js"), V34 = () => eng("turn_sed.js", "backup/life_turn-v3.4.js"), V33 = () => eng("turn.js", "backup/life_turn-v3.3.js");
const saved = () => { const d = JSON.parse(fs.readFileSync(__dirname + "/backup/being-state-pre-learn3-age86642.json", "utf8")); return d.data || d; };
const rt = L => JSON.parse(JSON.stringify(L)), same = (a, b) => JSON.stringify(a) === JSON.stringify(b), out = [];
{ const s0 = saved(), l = V35().makeLife(rt(s0));
  out.push(["from v3.3 state", same(l.L.q, s0.q) && same(l.L.sg, s0.sg) && same(l.L.h, s0.h) && l.L.rule === "bin3", `ruleHist ${JSON.stringify(l.L.ruleHist)}`]); }
{ const a = V34().makeLife(rt(saved())); a.live(3000); const s34 = rt(a.L), l = V35().makeLife(rt(s34));
  out.push(["from v3.4 state", same(l.L.q, s34.q) && same(l.L.sg, s34.sg) && l.L.cOn === null && l.st.lastM.every(x => x === s34.age), `ruleHist ${JSON.stringify(l.L.ruleHist)}`]); }
{ const a = V35().makeLife(rt(saved())); a.live(6000); const b1 = V35().makeLife(rt(saved())); b1.live(3000); const b2 = V35().makeLife(rt(b1.L)); b2.live(3000);
  const pick = l => rt({ q: l.L.q, sg: l.L.sg, h: l.L.h, active: l.L.active, R: l.L.R, age: l.L.age, cOn: l.L.cOn, cOff: l.L.cOff, lastM: l.L.lastM, rng: l.L.rng });
  out.push(["restore", same(pick(a), pick(b2)), `age ${a.L.age}`]); }
function life(E) { const l = E.makeLife(rt(saved())); let acts = 0, ans = 0, steps = 0; const count = k => { for (let i = 0; i < k; i++) { const o = l.live(1); steps++; acts += o.acting.length; ans += o.answered.filter(Boolean).length; } };
  count(5000); const pre = [acts / steps, ans / Math.max(1, acts)]; acts = ans = steps = 0; l.reverse(); count(3000); const post = [acts / steps, ans / Math.max(1, acts)];
  const jk = ["r5", "r6"].flatMap(r => ["m1", "m2"].map(m => l.b.edges.findIndex(e => l.b.names[e[0]] === r && l.b.names[e[1]] === m)));
  return { pre: pre.map(x => +x.toFixed(3)), post: post.map(x => +x.toFixed(3)), junk: jk.reduce((s, k) => s + l.L.sg[k], 0) }; }
const r5 = life(V35()), r4 = life(V34()), r3 = life(V33());
out.push(["world", r5.pre[0] >= 0.9 && r5.pre[1] >= 0.95 && r5.post[0] >= 0.85, `v3.5 ${JSON.stringify(r5)} | v3.4 ${JSON.stringify(r4)} | v3.3 ${JSON.stringify(r3)}`]);
for (const [k, ok, msg] of out) console.log(k, ok ? "OK" : "FAIL", "-", msg);
