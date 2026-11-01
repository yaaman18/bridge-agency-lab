// Stage 54 (material body part): plan 1 (bin3: learn3's structure with answer probabilities instead of amounts of
// digestion) and plan 2 (donly: the old rule plus part D only), against the old rule and learn3, with and without the
// receptors crossed at 5800. Same 10 worlds and costs as stages 48-51.
const B = require("./body_org.js"), fs = require("fs"), S = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const C = { OLD: {}, OLDR: { REVR: 5800 }, L3: { CONTRAST: "learn3" }, L3R: { CONTRAST: "learn3", REVR: 5800 }, BIN3: { CONTRAST: "bin3" }, BIN3R: { CONTRAST: "bin3", REVR: 5800 }, DONLY: { CONTRAST: "donly" }, DONLYR: { CONTRAST: "donly", REVR: 5800 } }, R = {};
for (const s of S) { const o = { U: 0.02, MCOST: 0.004, STEPS: 10000, KC: 0.002, FEED: true, PHASE: (s - 1) * 100, RAISE: "body" }; R[s] = {};
  for (const [k, x] of Object.entries(C)) { const r = B.run("ORG", s, { ...o, ...x }); r.actsLate = r.acts.slice(6800).reduce((a, x) => a + x.length, 0) / 3200; delete r.acts; R[s][k] = r; }
  const life = r => r.death ?? 10000;
  console.log(s, Object.entries(R[s]).map(([c, r]) => `${c} ${r.meanCount.toFixed(1)} d${r.death} kept${(r.kept * 10000 / life(r)).toFixed(1)} late${r.actsLate.toFixed(2)}`).join(" | ")); }
fs.writeFileSync(__dirname + "/results-alt.json", JSON.stringify(R));
