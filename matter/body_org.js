// Stage 42 (2026-10-31, user: run 1, 2, 3 in order; 3 = put the organization layer on the material body). A first,
// minimal coupling, provisional (its design is for the user to review):
//   * the body: the constituents of fmatter.js with the stage 32 rule (activity 1, no TRM network), born from one founder
//     group (3x3) at the centre of the 24x24 torus. The field has no sources: the body gets matter only through the circuit.
//   * the organization: the circuit of memory/turn.js (rev. 2, the one of the app) without partner units (partner=false:
//     r1-r8, c1-c2, m1-m2), raised by the usual curriculum (nursery 400, school 400, synthetic yields) before it is put on
//     the body; the partner is absent (gesture 0);
//   * the coupling: the two patches of the organization world made material. Patch k is a pool of matter outside the grid
//     (behind the MaterialPort): each step it receives g_k * U from the reservoir (g = the seasons of the organization
//     world, [3,2] / [0,5] / [5,0] per 1000 steps) and holds at most 50 * U (the excess returns to the reservoir: an
//     unharvested full patch loses its growth, as R is capped at 50 there). Yield y_k = min(5, floor(R_k / U)); the
//     circuit's digestion d_k (portions, turn.js allocate, capacity 5) moves d_k * U from pool k to the body (equal shares
//     onto the free matter of its sites, where the constituents bind it). Each acting motor costs MCOST of bound matter,
//     taken in equal shares from the constituents and returned to the reservoir. Matter is conserved.
//     (A first version fed source patches on the field itself; exploration showed the choice of patch could not matter
//     there: matter waited on the patches and the body reached them directly, so ORG and REPLAY were alike.)
//   * A-gen and death: the circuit lives only while the body has constituents; when the last one dies it stops for good.
// Conditions: ORG (the circuit acts), NONE (no circuit: the body alone), REPLAY (no circuit; the motor acts of the ORG
// run of the same seed, cyclically shifted by half the run plus 500 steps (half a season cycle, so that the replayed
// acts do not stay in phase with the seasons), delivered whatever the world: same number and kinds of acts,
// uncoupled from the patches' state). No reward, no target, nothing tells the circuit what it is for (M4).
// New constants: U (mu per portion), MCOST (mu per motor act), STEPS.
// Stage 43 (2026-10-31, user: verify 1, 2, 3 in order): condition GREEDY, a fixed rule with no learning that reads the
// same receptors as the circuit (r7 "y1>y2" -> patch 1, else r8 "y2>y1" -> patch 2, else r1 "y1>=3" -> 1, else r2
// "y2>=3" -> 2, else no act), and option REVR: from step REVR on the receptors are crossed (the reversal of the
// organization world: features of r1/r2, r3/r4, r7/r8 exchanged), for the circuit and the rule alike.
// Stage 44: option KC, the circuit's own maintenance: each step it costs KC per maintained contingency (confidence >= 1
// or sediment >= 1), paid from the body's bound matter like MCOST; GREEDY pays for its 4 fixed contingencies (r7, r8, r1, r2 to a motor). Defaults (no GREEDY, no REVR, KC = 0) = stage 42.
const M = require("./fmatter.js"), N0 = require("../memory/turn.js"), N1 = require("../memory/turn_sed.js");
// Stage 48: option CONTRAST ("sed" | "learn") runs the circuit with memory/turn_sed.js and opts.contrast (else turn.js).
let N = N0;
const season = t => { const c = (t % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
const seasonAt = (t, o) => { const g = o.FEED ? (t < 800 ? CUR[t] : season(t - 800 + (o.PHASE || 0))) : season(t + (o.PHASE || 0)); return o.REV !== undefined && t >= o.REV ? [g[1], g[0]] : g; };   // REV: the patches exchange their seasons from step REV on (a reversal of the world)
const CUR = [];
for (let i = 0; i < 400; i++) CUR.push([[5, 0], [0, 5]][Math.floor(i / 50) % 2]);
for (let i = 0; i < 400; i++) CUR.push([[5, 2], [2, 5]][Math.floor(i / 15) % 2]);
// Stage 46 (2026-10-31, user: grow the circuit together with the body). Options:
//   FEED  the upbringing happens in the world of the body: for the first 800 steps the pools are fed by the curriculum
//         (nursery 400: [5,0]/[0,5] every 50 steps; school 400: [5,2]/[2,5] every 15; growth g_k * U as for the
//         seasons), then the seasons begin (season(t - 800)). Applies to every condition of the run.
//   RAISE "pre" (default: raised offline by the curriculum, then put on the body, as in stages 42-45) or "body" (a newborn
//         circuit put on the founder group at step 0; it is raised by the fed pools while the body grows).
//   PER   capacity: the circuit can keep at most floor(constituents / PER) contingencies (confidence >= 1 or sediment
//         >= 1). After each circuit step, contingencies that became kept at this step are undone while over capacity;
//         if still over (the body shrank), the weakest kept ones (lowest confidence + sediment, then highest index) are
//         lost (confidence and sediment to 0). Undefined = no capacity limit.
// Stage 47 (2026-10-31, user: first run the control without noise and clock receptors). Options:
//   DROPR  names of receptors whose contingencies are removed from the newborn circuit (the units stay, with no edges),
//          e.g. ["r5", "r6"] = noise and clock3; done before the curriculum.
//   PHASE  the seasons start PHASE steps into their cycle (season(t - 800 + PHASE) with FEED): a world that differs by
//          seed, because without the noise receptor the circuit has no randomness left.
const CROSS = [[0, 1], [2, 3], [6, 7]], cross = () => { for (const [i, j] of CROSS) { const a = N.FEATURES[i]; N.FEATURES[i] = N.FEATURES[j]; N.FEATURES[j] = a; } };
function run(cond, seed, o, replayActs) {
  N = o.CONTRAST ? N1 : N0; const ORIG = N.FEATURES.slice();
  try { return run1(cond, seed, o, replayActs); } finally { N.FEATURES.splice(0, N.FEATURES.length, ...ORIG); }
}
function run1(cond, seed, o, replayActs) {
  const { U, MCOST, STEPS } = o, w = M.makeWorld({ reservoir: 300 }); M.seed(w, 12, 12, 1);
  const pool = [0, 0], T0 = M.total(w) + 0; let circuit = null, b = null, noise = null;
  if (cond === "ORG") { b = N.newborn(false);
    if (o.DROPR) { const drop = new Set(o.DROPR.map(n => b.names.indexOf(n))), keep = b.edges.map((e, k) => !drop.has(e[0])); b.edges = b.edges.filter((_, k) => keep[k]); b.q0 = b.q0.filter((_, k) => keep[k]); }
    circuit = N.init(b); noise = N.rng(seed); if (o.RAISE !== "body") for (const y of CUR) N.step(circuit, b, [...y, 0], { noise, contrast: o.CONTRAST }); }
  const keptK = k => circuit.q[k] >= 1 || circuit.sg[k] >= 1; let lost = 0, blocked = 0;
  const acts = [], log = []; let alive = true, death = null, maxErr = 0, nActs = 0, nAns = 0, moved = 0, spent = 0, sumCount = 0, sumLate = 0, form = 0, kept = 0, upkeep = 0; const win = [];
  for (let t = 0; t < STEPS; t++) {
    if (o.REVR !== undefined && t === o.REVR) cross();
    const R = pool, y = R.map(r => Math.min(5, Math.floor(r / U + 1e-9)));
    const body = []; for (let i = 0; i < w.C.length; i++) if (w.C[i]) body.push(i);
    if (alive && body.length === 0) { alive = false; death = t; }
    let acting = [], d = [0, 0];
    if (alive && cond === "ORG") { const was = circuit.q.map((_, k) => keptK(k)), q0 = circuit.q.slice(), s0 = circuit.sg.slice();
      const out = N.step(circuit, b, [y[0], y[1], 0], { noise, contrast: o.CONTRAST });
      if (o.PER) { const cap = Math.floor(body.length / o.PER); let nk = circuit.q.filter((_, k) => keptK(k)).length;
        for (let k = 0; k < circuit.q.length && nk > cap; k++) if (keptK(k) && !was[k]) { circuit.q[k] = q0[k]; circuit.sg[k] = s0[k]; nk--; blocked++; }
        while (nk > cap) { let wk = -1; for (let k = 0; k < circuit.q.length; k++) if (keptK(k) && (wk < 0 || circuit.q[k] + circuit.sg[k] <= circuit.q[wk] + circuit.sg[wk])) wk = k;
          circuit.q[wk] = 0; circuit.sg[wk] = 0; nk--; lost++; } } acting = out.acting.map(m => b.patch[m]).filter(p => p <= 2); d = out.d;
      win.push({ active: circuit.active.slice(), q: circuit.q.slice() }); if (win.length > 5) win.shift(); if (N.form(win, b)) form++; }
    if (alive && cond === "REPLAY") { acting = replayActs[(t + (STEPS >> 1) + 500) % STEPS] || []; const offer = [0, 0]; for (const p of acting) offer[p - 1] = y[p - 1]; d = N.allocate(offer); }
    if (alive && cond === "GREEDY") { const r = k => N.FEATURES[k][1](y, t + 1, () => 0), p = r(6) ? 1 : r(7) ? 2 : r(0) ? 1 : r(1) ? 2 : 0;
      acting = p ? [p] : []; const offer = [0, 0]; for (const q of acting) offer[q - 1] = y[q - 1]; d = N.allocate(offer); }
    acts.push(acting);
    if (alive && cond === "GREEDY" && o.KC) { kept += 4; const cost = o.KC * 4; let paid = 0; for (const i of body) { const m = Math.min(w.B[i], cost / body.length); w.B[i] -= m; paid += m; } w.port.give(paid); upkeep += paid; }   // the rule's 4 fixed contingencies
    if (alive && cond === "ORG" && o.KC) { const nk = circuit.q.filter((q, k) => q >= 1 || circuit.sg[k] >= 1).length; kept += nk;
      const cost = o.KC * nk; let paid = 0; for (const i of body) { const m = Math.min(w.B[i], cost / body.length); w.B[i] -= m; paid += m; } w.port.give(paid); upkeep += paid; }
    if (alive && acting.length) {
      for (let k = 0; k < 2; k++) if (d[k] > 0) { const take = Math.min(pool[k], d[k] * U); pool[k] -= take; for (const i of body) w.A[i] += take / body.length; moved += take; }
      const cost = MCOST * acting.length; let paid = 0; for (const i of body) { const m = Math.min(w.B[i], cost / body.length); w.B[i] -= m; paid += m; } w.port.give(paid); spent += paid;
      nActs += acting.length; nAns += acting.filter(p => d[p - 1] > 0).length;
    }
    const g = seasonAt(t, o); for (let k = 0; k < 2; k++) { pool[k] += w.port.take(g[k] * U); const over = pool[k] - 50 * U; if (over > 0) { pool[k] -= over; w.port.give(over); } }
    M.step(w, []);
    const c = M.count(w).constituents; sumCount += c; if (t >= STEPS / 2) sumLate += c;
    if ((t + 1) % 500 === 0) { maxErr = Math.max(maxErr, Math.abs(M.total(w) + pool[0] + pool[1] - T0)); log.push([t + 1, c, +M.count(w).bound.toFixed(2)]); }
  }
  return { cond, seed, maxErr, death, meanCount: sumCount / STEPS, lost, blocked, keptEnd: cond === "ORG" ? circuit.q.filter((_, k) => keptK(k)).length : null, meanLate: sumLate / (STEPS / 2), kept: kept / STEPS, upkeep, final: M.count(w).constituents, nActs, answered: nAns / Math.max(1, nActs), moved, spent, form: form / STEPS, log, acts };
}
module.exports = { run, season };
