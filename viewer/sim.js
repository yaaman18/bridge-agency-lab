// JavaScript port of the lab's final rule set (2026-10-29) for the viewer: AgencySubstrate's threshold
// network with variant_digest (no resource, digestion-gated confirmation, epistemic sampling, form),
// variant_attention (winner-take-all capacity 5, :consolidate) and variant_select (one motor acts per step),
// in the world of env_digest_wta.jl. Checked against reference_trace.txt by check.js.
const SIM = (() => {
  const P = { smax: 4, decay: 8, window: 5, strength0: 4, capacity: 5, cap: 50 };
  function build(t) {
    const idx = Object.fromEntries(t.units.map((u, i) => [u, i]));
    return {
      name: t.name, names: t.units, theta: t.theta, maintain: t.maintain,
      edges: t.edges.map(([a, b, w]) => [idx[a], idx[b], w]),
      motors: Object.fromEntries(Object.entries(t.motors).map(([k, v]) => [idx[k], v])),
      sensors: Object.fromEntries(Object.entries(t.sensors).map(([k, v]) => [idx[k], v])),
      initial: t.units.map(u => t.initial.includes(u)),
    };
  }
  const isMotor = (s, u) => s.motors[u] !== undefined;
  const isSensor = (s, u) => s.sensors[u] !== undefined;
  function init(s) {
    return { active: s.initial.slice(), strength: s.edges.map(() => P.strength0), t: 0 };
  }
  function allocate(offer) {
    const d = [0, 0]; let left = P.capacity;
    const order = [0, 1].filter(i => offer[i] > 0).sort((i, j) => (offer[j] - offer[i]) || (i - j));
    for (const i of order) { d[i] = Math.min(offer[i], left); left -= d[i]; }
    return d;
  }
  // y: [yield1, yield2]; sil: Set of silenced unit indices; opts.explore (default true);
  // opts.sensors: optional [patch1, patch2] booleans supplied by an external extractor (the LLM trial)
  function step(st, s, y, sil, opts = {}) {
    const explore = opts.explore !== false;
    const n = s.names.length, old = st.active;
    const stale = new Array(n).fill(false);
    if (explore) for (let u = 0; u < n; u++) {
      if (isSensor(s, u)) continue;
      const ins = s.edges.map((e, k) => e[1] === u ? k : -1).filter(k => k >= 0);
      stale[u] = ins.length > 0 && ins.every(k => st.strength[k] === 0);
    }
    const total = new Array(n).fill(0);
    s.edges.forEach(([a, b, w], k) => { if ((st.strength[k] >= 1 || stale[b]) && old[a] && !sil.has(a)) total[b] += w; });
    const nw = new Array(n);
    for (let u = 0; u < n; u++) {
      if (isSensor(s, u)) { const p = s.sensors[u] - 1; nw[u] = opts.sensors ? !!opts.sensors[p] : (y[p] > 0 && y[p] >= y[1 - p]); }
      else nw[u] = total[u] >= s.theta[u];
    }
    const cand = Object.keys(s.motors).map(Number).filter(m => nw[m]);
    if (cand.length > 1) {
      const best = Math.max(...cand.map(m => total[m]));
      const tied = cand.filter(m => total[m] === best);
      const prev = tied.filter(m => old[m]);
      const byPatch = (a, b) => s.motors[a] - s.motors[b];
      const win = (prev.length ? prev.sort(byPatch) : tied.sort(byPatch))[0];
      for (const m of cand) if (m !== win) nw[m] = false;
    }
    const acting = Object.keys(s.motors).map(Number).filter(m => nw[m] && !sil.has(m));
    const offer = [0, 0];
    for (const m of acting) offer[s.motors[m] - 1] = y[s.motors[m] - 1];
    const d = allocate(offer);
    const answered = new Map(acting.map(m => [m, d[s.motors[m] - 1] > 0]));
    const gate = d[0] + d[1] > 0 && [...answered.values()].every(Boolean);
    const ok = u => !isMotor(s, u) || answered.get(u) === true;
    const confirmed = s.edges.map(([a, b], k) => old[a] && !sil.has(a) && nw[b] && gate && ok(a) && ok(b));
    if (s.maintain) {
      confirmed.forEach((c, k) => { if (c && st.strength[k] < P.smax) st.strength[k] += 1; });
      if ((st.t + 1) % P.decay === 0) confirmed.forEach((c, k) => { if (!c) st.strength[k] = Math.max(st.strength[k] - 1, 0); });
    }
    st.active = nw; st.t += 1;
    return { acting, offer, digested: d, gate, stale, answered };
  }
  function form(windowStates, s) {
    const n = s.names.length, U = new Set();
    for (const w of windowStates) for (let u = 0; u < n; u++) if (w.active[u] && !isSensor(s, u)) U.add(u);
    const q = windowStates[windowStates.length - 1].strength;
    const adj = new Map([...U].map(u => [u, s.edges.map((e, k) => (e[0] === u && U.has(e[1]) && q[k] >= 1) ? e[1] : -1).filter(v => v >= 0)]));
    const color = new Map([...U].map(u => [u, 0]));
    const dfs = u => { color.set(u, 1); for (const v of adj.get(u)) { if (color.get(v) === 1) return true; if (color.get(v) === 0 && dfs(v)) return true; } color.set(u, 2); return false; };
    for (const u of U) if (color.get(u) === 0 && dfs(u)) return true;
    return false;
  }
  return { P, build, init, step, allocate, form };
})();
if (typeof module !== "undefined") module.exports = SIM;
