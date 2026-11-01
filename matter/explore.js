// Exploratory pass (before freezing predictions; reported as such): reservoir size and supply level.
const M = require("./matter.js");
function run(reservoir, srcScale, steps, starveFrom, starveTo, spontaneous) {
  const w = M.makeWorld({ reservoir, spontaneous }); M.seed(w, 12, 12, 1); const W = w.p.W, T0 = M.total(w), log = [];
  for (let t = 0; t < steps; t++) {
    const on = Math.floor(t / 500) % 2 === 0, starving = t >= starveFrom && t < starveTo, s = [];
    if (!starving) for (const [cx, cy] of [[6, 12], [18, 12]]) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (on ? 1 : 0.3) * w.p.SRC * srcScale]);
    M.step(w, s); if ((t + 1) % 500 === 0) log.push([t + 1, M.count(w).constituents]);
  }
  return { log: log.map(x => x.join(":")).join(" "), err: (M.total(w) - T0).toExponential(1) };
}
for (const res of [150, 300, 600]) for (const sc of [0.5, 1, 2]) console.log("res", res, "src x", sc, JSON.stringify(run(res, sc, 4000, 1e9, 1e9)));
console.log("starve 1000-3000, res 300:", JSON.stringify(run(300, 1, 5000, 1000, 3000)));
console.log("starve 1000-3000, res 300, spontaneous:", JSON.stringify(run(300, 1, 5000, 1000, 3000, true)));
