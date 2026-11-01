// Places earlier circuits in the state field (field.js), sampling every 100 steps.
//   A stage 19: memory.js seed 1 (curriculum, 10 world cycles, reversal, 1000 steps)          no partner
//   B stage 20 rev. 1: partner-rev1.js seed 2, partner ABSENT (the calling lock-in that lost form)
//   C stage 25: turn.js seed 1, scaffolding partner (SCAF-ADULT of test_scaffold.js)
//   D the app's being: saved states after the person's session (v438) and the unattended sessions (v513)
const fs = require("fs"), FLD = require("./field.js");
const season = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const CUR = []; for (let i = 0; i < 400; i++) CUR.push([[5, 0], [0, 5]][Math.floor(i / 50) % 2]); for (let i = 0; i < 400; i++) CUR.push([[5, 2], [2, 5]][Math.floor(i / 15) % 2]);
function trace(E, seed, plan, partnerOpts) {     // plan: list of [len, kind] with kind "cur" | "world" | "reverse"; partner: fn(now, o) -> gesture
  const b = E.newborn(...(partnerOpts ? [true] : [])), st = E.init(b), noise = E.rng(seed), win = [], pts = [];
  let R = [50, 50], wt = 0, i = 0; const pr = E.rng(seed + 1000); let sched = null, rot = 0, s = 0;
  const ORIG = E.FEATURES.slice();
  for (const [len, kind, present] of plan) {
    if (kind === "reverse") { for (const [a, c] of [[0, 1], [2, 3], [6, 7]]) { const x = E.FEATURES[a]; E.FEATURES[a] = E.FEATURES[c]; E.FEATURES[c] = x; } continue; }
    for (let k = 0; k < len; k++, i++) {
      const now = st.t + 1; let g = 0;
      if (partnerOpts && present) { s++; const s1 = pr(); if (sched === now) { sched = null; g = (rot++ % 4) + 1; } else if (s1 < 0.01) g = 1 + Math.floor(pr() * 4); }
      const y = kind === "cur" ? CUR[k].slice() : [Math.min(R[0], 5), Math.min(R[1], 5)];
      const o = E.step(st, b, partnerOpts ? [...y, g] : y, { noise });
      if (partnerOpts && present && o.call && sched === null) { const p = partnerOpts.p(o, s); if (p > 0) { const a = pr(), d = pr(); if (a < p) sched = now + 2 + Math.floor(d * 7); } }
      if (kind === "world") { wt++; R = [0, 1].map(j => Math.min(50, R[j] - o.d[j] + season(wt)[j])); }
      win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > 5) win.shift();
      if ((i + 1) % 100 === 0) { const p = FLD.position(E, st, b, win, { partner: !!partnerOpts }); pts.push({ step: i + 1, ...p, region: FLD.region(p) }); }
    }
  }
  E.FEATURES.splice(0, E.FEATURES.length, ...ORIG);
  return pts;
}
const out = {};
out.A_stage19 = trace(require("./memory.js"), 1, [[800, "cur"], [10000, "world"], [0, "reverse"], [1000, "world"]], null);
out.B_stage20rev1_absent = trace(require("./partner-rev1.js"), 2, [[800, "cur"], [6000, "world", false]], { p: () => 0 });
out.C_stage25_scaf = trace(require("./turn.js"), 1, [[800, "cur"], [3000, "world", true], [2000, "world", false], [1000, "world", true]],
  { p: (o, s) => !o.callWhileWaiting ? 0.8 : 0.8 * Math.max(0, 1 - s / 1500) });
// D: the app's saved states (life_turn.js on turn.js)
const strip = x => x.replace(/^module\.exports.*$/m, "");
const LIFE = new Function(strip(fs.readFileSync(__dirname + "/turn.js", "utf8")) + strip(fs.readFileSync(__dirname + "/life_turn.js", "utf8")) + "; return { makeLife, step, form, rng, FEATURES };")();
out.D_app = ["being-state-session-v438.json", "being-state-session2-v513.json"].map(f => {
  const d = JSON.parse(fs.readFileSync(__dirname + "/backup/" + f, "utf8")), life = LIFE.makeLife(JSON.parse(JSON.stringify(d.data || d)));
  const win = [{ active: life.st.active.slice(), q: life.st.q.slice() }], p = FLD.position(LIFE, life.st, life.b, win, { partner: true });
  return { state: f, age: life.L.age, ...p, region: FLD.region(p) };
});
fs.writeFileSync(__dirname + "/results-field.json", JSON.stringify(out, null, 1));
for (const [k, pts] of Object.entries(out)) {
  const regions = {}; pts.forEach(p => regions[p.region] = (regions[p.region] || 0) + 1);
  const Fs = pts.map(p => p.F), Ls = pts.map(p => p.L), Rs = pts.map(p => p.R);
  console.log(k, "samples", pts.length, JSON.stringify(regions), "F", Math.min(...Fs), "-", Math.max(...Fs), "L", Math.min(...Ls), "-", Math.max(...Ls), "R", Math.min(...Rs), "-", Math.max(...Rs));
}
console.log("D", JSON.stringify(out.D_app));
const B = out.B_stage20rev1_absent; console.log("B first samples", JSON.stringify(B.slice(0, 12).map(p => [p.step, p.F, p.L, p.R, p.region])));
