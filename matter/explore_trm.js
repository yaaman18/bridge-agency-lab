// Exploratory pass for stage 33 (before freezing; reported).
const T = require("./trm.js"), M = require("./matter2.js");
for (const mode of ["fixed", "trm", "nogate", "noinherit"]) for (const seed of [1, 2]) {
  const L = T.makeLife(mode, seed), T0 = M.total(L.w), log = [];
  for (let t = 0; t < 4000; t++) { L.step(T.sources(L.w, t, 1)); if ((t + 1) % 500 === 0) { const s = L.stats(); log.push(`${s.count}/${s.activity.toFixed(2)}/${s.precision.toFixed(2)}/${s.F.toFixed(2)}`); } }
  console.log(mode.padEnd(9), seed, "err", (M.total(L.w) - T0).toExponential(1), "count/act/pi/F every 500:", log.join(" "));
}
