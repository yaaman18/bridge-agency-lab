// Stage 38 rev. 2: founders placed 4 sites from the source patches (rev. 1 placed them 8-16 sites away and every run
// starved before matter reached them, results-evo-LEAN/RICH.json). Otherwise identical to test_evo.js.
// Stage 38: evolution on the material layer. A 48x48 world, six source patches, nine founder seeds (3x3 constituents
// each, 81 founder lineages), 20000 steps, mode nogate of evo_trm.js (= trm2.js nogate), seeds 1-3, two worlds: LEAN
// (supply x0.5) and RICH (x2), seasons of 500 steps. Every 500 steps: constituents, bodies (connected groups >= 3),
// founder lineages alive, mean heritable activity bias ba, mean realised activity, graded coupling form F_g
// (sum over constituents in groups >= 3 of min(1, |Wn zbar| / 0.5), divided by the count).
const T = require("./evo_trm.js"), M = require("./matter2.js"), fs = require("fs");
const W = 48, H = 48, PATCHES = [[8, 8], [24, 8], [40, 8], [8, 40], [24, 40], [40, 40]], SEEDS9 = [[8, 12], [24, 12], [40, 12], [8, 36], [24, 36], [40, 36], [8, 4], [24, 4], [40, 44]];
function src(w, t, scale) { const s = [], rich = Math.floor(t / 500) % 2 === 0; for (const [cx, cy] of PATCHES) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (rich ? 1 : 0.3) * w.p.SRC * scale]); return s; }
function measure(L) {
  const w = L.w, n = W * H, nb = i => { const x = i % W, y = (i / W) | 0; return [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => ((y + dy + H) % H) * W + ((x + dx + W) % W)); };
  let count = 0, ba = 0, act = 0; const lines = new Set(), coup = new Float64Array(n);
  for (let i = 0; i < n; i++) if (w.C[i] && L.net[i]) { const c = L.net[i]; count++; ba += c.ba; act += L.act[i]; lines.add(c.line);
    const ns = nb(i).filter(j => w.C[j] && L.net[j]); if (ns.length) { const zbar = c.z.map((_, d) => ns.reduce((s, j) => s + L.net[j].z[d], 0) / ns.length); coup[i] = Math.min(1, Math.hypot(...c.Wn.map(row => row.reduce((s, x, e) => s + x * zbar[e], 0))) / 0.5); } }
  const seen = new Uint8Array(n); let bodies = 0, inG = 0;
  for (let i = 0; i < n; i++) if (w.C[i] && !seen[i]) { const st = [i], comp = []; seen[i] = 1; while (st.length) { const u = st.pop(); comp.push(u); for (const v of nb(u)) if (w.C[v] && !seen[v]) { seen[v] = 1; st.push(v); } }
    if (comp.length >= 3) { bodies++; for (const u of comp) inG += coup[u]; } }
  return { count, bodies, lines: lines.size, ba: count ? +(ba / count).toFixed(3) : null, act: count ? +(act / count).toFixed(3) : null, Fg: count ? +(inG / count).toFixed(3) : 0 };
}
const R = {};
for (const [world, scale] of [["LEAN", 0.5], ["RICH", 2]].filter(x => !process.env.WORLD || x[0] === process.env.WORLD)) for (const seed of [1, 2, 3]) {
  const L = T.makeLife("nogate", seed, { W, H, reservoir: 1200, seeds: SEEDS9 }), T0 = M.total(L.w), log = [measure(L)]; let maxErr = 0;
  for (let t = 0; t < 20000; t++) { L.step(src(L.w, t, scale)); if ((t + 1) % 500 === 0) { maxErr = Math.max(maxErr, Math.abs(M.total(L.w) - T0)); log.push(measure(L)); } }
  R[`${world}/${seed}`] = { maxErr, log };
  const f = log[log.length - 1]; console.log(`${world}/${seed}`, "err", maxErr.toExponential(1), "start", JSON.stringify(log[0]), "end", JSON.stringify(f), "min count", Math.min(...log.map(x => x.count)));
}
fs.writeFileSync(__dirname + "/results-evo2" + (process.env.WORLD ? "-" + process.env.WORLD : "") + ".json", JSON.stringify(R));
