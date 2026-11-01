// Material layer, stage 32 (2026-10-31; user decisions: an original simple conserved field after Lenia; the generation
// of constituents only from constituents as a META-LAYER AXIOM; two currencies (matter and digested prediction error);
// the abstract matter must be synchronisable later with physical matter).
//
// Terms (abstract on purpose, not "cells"):
//   matter      a conserved quantity in abstract units (mu). Free matter A flows on a torus grid; bound matter B is held
//               by a constituent at its site. A reservoir outside the grid closes the balance.
//   constituent a site-local carrier of organization: it exists while it holds bound matter B >= THETA_EXIST, binds free
//               matter at its site, and returns bound matter to free matter at a turnover rate (it must keep re-binding).
// META-LAYER AXIOM (A-gen): a constituent arises only from a constituent (division of a parent into an empty
//   neighbouring site, splitting its bound matter). No spontaneous generation. This axiom is what makes the loss of all
//   constituents irreversible (material death); opts.spontaneous = true removes it (control only).
// Field (after Lenia / Flow-Lenia, but original and simpler): affinity U = K * (A + B) with a ring kernel; potential
//   P = G(U), G the Lenia bell growth function; free matter moves up the potential gradient (advection) and down its own
//   density gradient (diffusion) by pairwise transfers between 4-neighbours, so matter is conserved exactly; a fraction
//   EROSION of free matter returns to the reservoir each step; sources inject reservoir matter at patch sites.
// Maintenance cost: each constituent returns METAB mu of its bound matter per step to the reservoir (dissipated as
//   waste; the thermodynamic cost of persisting). Without supply, constituents therefore run down and die.
// MaterialPort (synchronisation with physical matter, later): every transfer across the grid boundary goes through
//   port.inflow / port.outflow in mu; a port can map mu to a physical unit with a frozen scale (port.scale, port.unit)
//   and can be driven by measured physical quantities instead of the simulated reservoir. Here: a simulated port.
const DEF = { W: 24, H: 24, RING: 3, MU: 0.35, SIGMA: 0.12, ADV: 0.6, DIFF: 0.08, EROSION: 0.002,
              BIND: 0.25, CAP: 1, TURNOVER: 0.02, METAB: 0.004, THETA_EXIST: 0.2, THETA_DIV: 0.8, SRC: 0.06 };
function makePort(reservoir, scale = 1, unit = "mu") {
  return { reservoir, scale, unit, inflow: 0, outflow: 0,
    take(x) { const t = Math.max(0, Math.min(x, this.reservoir)); this.reservoir -= t; this.inflow += t; return t; },
    give(x) { this.reservoir += x; this.outflow += x; } };
}
function kernel(R) {
  const k = []; let s = 0;
  for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) { const r = Math.hypot(dx, dy) / R; if (r === 0 || r > 1) continue;
    const w = Math.exp(4 - 1 / (r * (1 - r) + 1e-9)); if (w > 1e-6) { k.push([dx, dy, w]); s += w; } }
  return k.map(([dx, dy, w]) => [dx, dy, w / s]);
}
function makeWorld(opts = {}) {
  const p = { ...DEF, ...opts }, n = p.W * p.H;
  return { p, A: new Float64Array(n), B: new Float64Array(n), C: new Uint8Array(n), K: kernel(p.RING), port: makePort(opts.reservoir ?? 2000),
           t: 0, born: 0, died: 0, spontaneous: !!opts.spontaneous };
}
const G = (u, mu, s) => 2 * Math.exp(-((u - mu) ** 2) / (2 * s * s)) - 1;
function total(w) { let s = w.port.reservoir; for (let i = 0; i < w.A.length; i++) s += w.A[i] + w.B[i]; return s; }
function step(w, sources) {
  const { p, A, B, C, K } = w, W = p.W, H = p.H, n = W * H, idx = (x, y) => ((y + H) % H) * W + ((x + W) % W);
  // 1. sources: reservoir matter injected at patch sites through the port
  for (const [i, amount] of sources) A[i] += w.port.take(amount);
  // 2. potential from the affinity field
  const P = new Float64Array(n);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { let u = 0; for (const [dx, dy, k] of K) { const j = idx(x + dx, y + dy); u += k * (A[j] + B[j]); } P[y * W + x] = G(u, p.MU, p.SIGMA); }
  // 3. pairwise transfers of free matter (conservative): advection up P, diffusion down A; capped by available matter
  const out = new Float64Array(n), plan = [];
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const i = y * W + x;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const j = idx(x + dx, y + dy);
      const f = p.ADV * A[i] * Math.max(0, P[j] - P[i]) / 4 + p.DIFF * Math.max(0, A[i] - A[j]) / 4; if (f > 0) { plan.push([i, j, f]); out[i] += f; } } }
  const scale = new Float64Array(n); for (let i = 0; i < n; i++) scale[i] = out[i] > A[i] ? A[i] / out[i] : 1;
  for (const [i, j, f] of plan) { const g = f * scale[i]; A[i] -= g; A[j] += g; }
  // 4. erosion of free matter back to the reservoir
  for (let i = 0; i < n; i++) { const e = A[i] * p.EROSION; A[i] -= e; w.port.give(e); }
  // 5. constituents: turnover, binding, death, division (A-gen)
  for (let i = 0; i < n; i++) if (C[i]) { const m = Math.min(B[i], p.METAB); B[i] -= m; w.port.give(m); const r = B[i] * p.TURNOVER; B[i] -= r; A[i] += r; const b = Math.min(p.CAP - B[i], p.BIND * A[i]); B[i] += b; A[i] -= b;
    if (B[i] < p.THETA_EXIST) { C[i] = 0; A[i] += B[i]; B[i] = 0; w.died++; } }
  const order = []; for (let i = 0; i < n; i++) if (C[i] && B[i] >= p.THETA_DIV) order.push(i);
  for (const i of order) { const x = i % W, y = (i / W) | 0; const nb = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => idx(x + dx, y + dy)).filter(j => !C[j]);
    if (!nb.length) continue; const j = nb.reduce((a, c) => A[c] > A[a] ? c : a, nb[0]); const half = B[i] / 2; B[i] -= half; B[j] += half; C[j] = 1; w.born++; }
  if (w.spontaneous) for (let i = 0; i < n; i++) if (!C[i] && A[i] >= p.THETA_EXIST * 2) { const b = A[i] / 2; A[i] -= b; B[i] += b; C[i] = 1; w.born++; }  // control only
  w.t++;
}
function seed(w, cx, cy, r) { const { W } = w.p; for (let y = cy - r; y <= cy + r; y++) for (let x = cx - r; x <= cx + r; x++) { const i = y * W + x; const m = w.port.take(0.6); w.B[i] = m; w.C[i] = 1; } }
function count(w) { let c = 0, b = 0; for (let i = 0; i < w.C.length; i++) if (w.C[i]) { c++; b += w.B[i]; } return { constituents: c, bound: +b.toFixed(3) }; }
module.exports = { DEF, makeWorld, step, seed, total, count, kernel, makePort };
