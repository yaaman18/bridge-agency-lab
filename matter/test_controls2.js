// Stages 40-41 (2026-10-31, user: run 1, 2, 3 in order): the controls of stage 39, as test_neutral.js with two options.
//   GATE (env, default 0.5): the activity a constituent needs to divide (fevo.js opts.actGate). Stage 40: GATE=0.
//   MIX (env, default 0 = never): every MIX steps the occupied sites exchange their constituents at random (a full random
//     permutation of net, bound matter B and markers among occupied sites; free matter stays). Stage 41: MIX=50 (new
//     constant), with the gate of stage 39. Bound matter is permuted, so the total is unchanged.
//   BINDC (env, stage 45): binding at this constant factor for every constituent instead of its activity (fevo.js
//     opts.bindConst); the activity then scales only the maintenance cost.
// Results go to results-<TAG>/ (TAG = gate0 or mix50). Everything else as test_neutral.js (header follows).
// Stage 39 (2026-10-31, user: separate selection from drift). Stage 38 rev. 2 found the heritable activity bias ba rising
// in all 6 runs, more in LEAN, and more founder lineages lost in LEAN, where populations are ~3x smaller (stronger drift).
// Same world as test_evo2.js (48x48, six patches, nine founder groups, nogate, 20000 steps, LEAN x0.5 / RICH x2), on
// fevo.js (bit-identical to evo_trm.js; seeds 1-3 replay the stage 38 runs), seeds 1-10, one job per WORLD and SEED (par.js).
// Three neutral references, all observers (they draw from their own rng and change nothing in the run):
//   * NMK = 20 neutral markers per constituent: numbers with no effect on anything, 0 in the founders, inherited at
//     division with the same mutation as ba (+ MUT * gauss). They share the exact genealogy (and its spatial structure)
//     of the run, so the spread of their final means is the drift expected for ba if ba had no effect.
//   * Price-type split of the change in mean ba: at the first division or death of a step the population means (ba,
//     markers) are taken; each division adds (parent value - mean) / N and each death adds -(dying value - mean) / N.
//     Cb = birth side, Cd = death side (same for every marker, as a null reference).
//   * NSH = 200 shadow populations (Bedau-Packard neutral shadow) for founder lineages: per step the same numbers of
//     deaths and divisions as the run, but who dies and who divides chosen at random in a well-mixed population.
const T = require("./fevo.js"), M = require("./fmatter.js"), fs = require("fs");
const W = 48, H = 48, PATCHES = [[8, 8], [24, 8], [40, 8], [8, 40], [24, 40], [40, 40]], SEEDS9 = [[8, 12], [24, 12], [40, 12], [8, 36], [24, 36], [40, 36], [8, 4], [24, 4], [40, 44]];
const GATE = +(process.env.GATE ?? 0.5), MIX = +(process.env.MIX || 0), BINDC = process.env.BINDC, TAG = (BINDC !== undefined ? "bind" + BINDC + "-" : "") + (MIX ? "mix" + MIX : "gate" + GATE);
const NMK = 20, NSH = 200, STEPS = +(process.env.STEPS || 20000), world = process.env.WORLD, seed = +process.env.SEED, scale = { LEAN: 0.5, RICH: 2 }[world];
function src(w, t) { const s = [], rich = Math.floor(t / 500) % 2 === 0; for (const [cx, cy] of PATCHES) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * W + cx + dx, (rich ? 1 : 0.3) * w.p.SRC * scale]); return s; }
function rng(s) { return () => { s |= 0; s = (s + 0x6D2B79F5) | 0; let t = Math.imul(s ^ (s >>> 15), 1 | s); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const gauss = r => Math.sqrt(-2 * Math.log(r() + 1e-12)) * Math.cos(2 * Math.PI * r());
const n = W * H, mk = new Array(n).fill(null), rm = rng(seed * 7919 + 1), rx = rng(seed * 31337 + 5);
let L, mean = null, Npop = 0; const Cb = new Float64Array(NMK + 1), Cd = new Float64Array(NMK + 1);   // index 0 = ba, 1.. = markers
// (the child of the division that triggers it already holds a net but no markers yet; it is not counted)
function means() { const s = new Float64Array(NMK + 1); let c = 0; for (let i = 0; i < n; i++) if (L.net[i] && mk[i]) { c++; s[0] += L.net[i].ba; for (let k = 0; k < NMK; k++) s[k + 1] += mk[i][k]; } Npop = c; mean = s.map(x => x / c); }
const val = (i, k) => k === 0 ? L.net[i].ba : mk[i][k - 1];
const hooks = {
  divide(i, j) { if (!mean) means(); for (let k = 0; k <= NMK; k++) Cb[k] += (val(i, k) - mean[k]) / Npop; mk[j] = mk[i].map(v => v + T.MUT * gauss(rm)); },
  death(i) { if (!mean) means(); for (let k = 0; k <= NMK; k++) Cd[k] -= (val(i, k) - mean[k]) / Npop; mk[i] = null; },
};
L = T.makeLife("nogate", seed, { W, H, reservoir: 1200, seeds: SEEDS9, hooks, actGate: GATE, ...(BINDC !== undefined ? { bindConst: +BINDC } : {}) });
for (let i = 0; i < n; i++) if (L.net[i]) mk[i] = new Float64Array(NMK);
function measure() {
  let count = 0, ba = 0, act = 0; const m = new Float64Array(NMK), lines = new Set();
  for (let i = 0; i < n; i++) if (L.w.C[i] && L.net[i]) { count++; ba += L.net[i].ba; act += L.act[i]; lines.add(L.net[i].line); for (let k = 0; k < NMK; k++) m[k] += mk[i][k]; }
  return { count, lines: lines.size, ba: count ? ba / count : null, act: count ? act / count : null, mk: count ? Array.from(m, x => x / count) : null };
}
const lines0 = []; for (let i = 0; i < n; i++) if (L.net[i]) lines0.push(L.net[i].line);
const T0 = M.total(L.w), log = [measure()], dN = new Int32Array(STEPS), bN = new Int32Array(STEPS); let maxErr = 0;
for (let t = 0; t < STEPS; t++) {
  const d0 = L.w.died, b0 = L.w.born; mean = null;
  L.step(src(L.w, t)); dN[t] = L.w.died - d0; bN[t] = L.w.born - b0;
  if (MIX && (t + 1) % MIX === 0) {
    const occ = []; for (let i = 0; i < n; i++) if (L.w.C[i] && L.net[i]) occ.push(i);
    const perm = occ.slice(); for (let k = perm.length - 1; k > 0; k--) { const j = Math.floor(rx() * (k + 1)), x = perm[k]; perm[k] = perm[j]; perm[j] = x; }
    const nets = occ.map(i => L.net[i]), Bs = occ.map(i => L.w.B[i]), mks = occ.map(i => mk[i]), acts = occ.map(i => L.act[i]);
    occ.forEach((i, k) => { const j = perm[k]; L.net[j] = nets[k]; L.w.B[j] = Bs[k]; mk[j] = mks[k]; L.act[j] = acts[k]; });
  }
  if ((t + 1) % 500 === 0) { maxErr = Math.max(maxErr, Math.abs(M.total(L.w) - T0)); log.push(measure()); }
}
// Neutral shadows of the founder lineages: same census, random deaths and random parents (among those present before the
// step's divisions, as in fmatter.js where a child does not divide in the step of its birth).
const shadowLines = [];
for (let s = 0; s < NSH; s++) {
  const r = rng(seed * 100003 + s + 1), pop = lines0.slice();
  for (let t = 0; t < STEPS; t++) {
    for (let k = 0; k < dN[t]; k++) { const x = Math.floor(r() * pop.length); pop[x] = pop[pop.length - 1]; pop.pop(); }
    const m = pop.length; for (let k = 0; k < bN[t]; k++) pop.push(pop[Math.floor(r() * m)]);
  }
  shadowLines.push(new Set(pop).size);
}
const out = { world, seed, steps: STEPS, maxErr, minCount: Math.min(...log.map(x => x.count)), log, Cb: Array.from(Cb), Cd: Array.from(Cd), shadowLines, births: L.w.born, deaths: L.w.died };
fs.mkdirSync(`${__dirname}/results-${TAG}`, { recursive: true });
fs.writeFileSync(`${__dirname}/results-${TAG}/${world}-${seed}${STEPS !== 20000 ? "-s" + STEPS : ""}.json`, JSON.stringify(out));
const f = log[log.length - 1], sm = shadowLines.slice().sort((a, b) => a - b);
console.log(`${world}/${seed} err ${maxErr.toExponential(1)} count ${f.count} lines ${f.lines} (shadow median ${sm[NSH >> 1]}, 2.5% ${sm[Math.floor(NSH * 0.025)]}) ba ${f.ba.toFixed(3)} markers [${Math.min(...f.mk).toFixed(3)}, ${Math.max(...f.mk).toFixed(3)}] Cb ${Cb[0].toFixed(3)} Cd ${Cd[0].toFixed(3)}`);
