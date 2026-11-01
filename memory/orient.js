// Stage 22 (2026-10-30): the orienting response, given as an innate rule (user: run the experiments in order; first
// (a), then (b) waiting, then (c) upbringing). Copy of partner.js rev. 3 (adopted; partner.js stays frozen).
// Stage 21 (wait.js) showed that waiting cannot be learned when a unit that has left the untried state never tests a
// contingency it has not tried. The given rule: at the step after a receptor switches ON (off two steps ago, on at the
// previous step), each of its contingencies that is untried (confidence 0 and sediment 0) transmits, as a sample.
// Sampled input ranks last in the selection (rev. 2), and confirmation and failure apply as usual. No habituation is
// given: a contingency that failed stays untried and is tried again at the next onset. orient=false gives partner.js.
// Revision 2 (after results-orient-rev1.json: the clock and noise receptors switch on every few steps, so their untried
// contingencies into m3 were tried at every onset, the circuit called at about half of all steps whether anyone answered
// or not, and live and replayed partners became indistinguishable): HABITUATION of the orienting response (Sokolov).
// Per contingency h (0..smax): a failure of an untried contingency (confidence 0, sediment 0) raises h by 1; an onset
// orients only contingencies with h = 0; h falls by 1 for every `decay` consecutive steps that its receptor stays off
// (recovery needs the stimulus to be absent, not just time). No new constants (smax 4, decay 8).
//
// (Header of partner.js rev. 3 follows.)
// The partner as part of the world (2026-10-30, stage 20). Built on memory.js (copied, not imported, so that
// memory.js stays frozen). The person who has the page open enters the circuit's world in two ways, never as a
// judge: no reward, no rating, no target (M4 / P-01).
//   * r9, a receptor that is on at a step where the partner made a gesture (any of 4 kinds). The circuit is not told
//     what it is; it is one more numbered receptor.
//   * m3, a third motor driven by a third core unit c3 (joined to c1 and c2 like they are joined to each other).
//     m3 does not act on a patch: it CALLS. The call is answered when the partner gestures within W steps after it.
// A call's answer is late, so its confirmation is deferred: at the call step the contingencies that would have been
// confirmed had the call been answered at once are kept; a fresh answer within W steps confirms them by the usual
// rule (with sediment); a call that expires, or is superseded by the next call, fails by the usual rule.
// Digestion of an answer = the freshness of the gesture kind (0..5, +1 every FRESH steps, used up by the answer).
// A kind repeated before it regrows does not answer: the same reply over and over leaves nothing to digest, just as
// an emptied patch does not answer.
// partner=false builds the circuit of memory.js exactly (same units, edges and order).
// Revision 2 (after results-partner-rev1.json): selection ranks input by confident contingencies first, then by
// sedimented ones (a habit whose confidence has dissipated), then sampled input. In rev. 1 (and memory.js) habit-only
// input ranked like sampled input, so an untried m3 sampling many receptors beat m2 whose inputs were sediment-only
// (seed 2, step 251 of the nursery); m2 then never acted again and m3 called into an absent world for good.
// Revision 3 (after results-partner-rev2.json: no harm, but not one call in the world in any seed or condition, since
// a patch motor is a candidate at every step and always outranks an untried m3): the call is a separate channel
// (voice) from foraging (hands). "One action per step" (stage 12, option A) was introduced for the competition of
// patch actions for digestion capacity, and a call digests nothing from the patches, so the selection runs among
// the patch motors only and m3 acts whenever its input reaches threshold, alongside them.
const P = { smax: 4, decay: 8, window: 5, capacity: 5, cap: 50, W: 10, FRESH: 20, KINDS: 4 };
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
// Receptor features of the world (the circuit is not told which is which). y = [yield1, yield2, gesture kind or 0].
const FEATURES = [
  ["y1>=3", (y) => y[0] >= 3], ["y2>=3", (y) => y[1] >= 3], ["y1==0", (y) => y[0] === 0], ["y2==0", (y) => y[1] === 0],
  ["noise", (y, t, r) => r() < 0.5], ["clock3", (y, t) => t % 3 === 0], ["y1>y2", (y) => y[0] > y[1]], ["y2>y1", (y) => y[1] > y[0]],
  ["partner", (y) => (y[2] || 0) > 0],
];
function newborn(partner = true) {
  const names = [], kind = [], feat = [], theta = [], patch = [], nr = partner ? 9 : 8;
  for (let i = 0; i < nr; i++) { names.push("r" + (i + 1)); kind.push("R"); feat.push(i); theta.push(0); patch.push(0); }
  (partner ? ["c1", "c2", "c3"] : ["c1", "c2"]).forEach(n => { names.push(n); kind.push("C"); feat.push(-1); theta.push(1); patch.push(0); });
  (partner ? ["m1", "m2", "m3"] : ["m1", "m2"]).forEach((n, i) => { names.push(n); kind.push("M"); feat.push(-1); theta.push(2); patch.push(i + 1); });
  const id = n => names.indexOf(n), edges = [], q0 = [];
  const add = (a, b, q) => { edges.push([id(a), id(b), 1]); q0.push(q); };
  add("c1", "c1", 4); add("c2", "c2", 4); add("c1", "c2", 4); add("c2", "c1", 4);
  if (partner) { add("c3", "c3", 4); add("c1", "c3", 4); add("c3", "c1", 4); add("c2", "c3", 4); add("c3", "c2", 4); }
  const pairs = partner ? [["c1", "m1"], ["c2", "m2"], ["c3", "m3"]] : [["c1", "m1"], ["c2", "m2"]];
  for (const [c, m] of pairs) { add(c, m, 0); for (let i = 0; i < nr; i++) add("r" + (i + 1), m, 0); }
  return { names, kind, feat, theta, patch, edges, q0, initial: names.map(n => n[0] === "c") };
}
function init(b) { return { active: b.initial.slice(), q: b.q0.slice(), sg: b.q0.map(() => 0), h: b.q0.map(() => 0), off: b.names.map(() => 0), t: 0, pend: null, fresh: new Array(P.KINDS).fill(5) }; }
const S = P.smax;
function allocate(offer) { const d = [0, 0]; let left = P.capacity; for (const i of [0, 1].filter(i => offer[i] > 0).sort((i, j) => (offer[j] - offer[i]) || (i - j))) { d[i] = Math.min(offer[i], left); left -= d[i]; } return d; }
// opts: { explore=true, fail=true, memory=true, sil:Set, noise: rng }
function step(st, b, y, opts) {
  const explore = opts.explore !== false, fail = opts.fail !== false, sil = opts.sil || new Set();
  const n = b.names.length, old = st.active, ins = u => b.edges.map((e, k) => e[1] === u ? k : -1).filter(k => k >= 0);
  const mem = opts.memory !== false, now = st.t + 1, orient = opts.orient !== false, prev = st.prev || old;
  const onset = b.names.map((_, u) => orient && b.kind[u] === "R" && old[u] && !prev[u]);
  const stale = b.names.map((_, u) => explore && b.kind[u] !== "R" && ins(u).length > 0 && ins(u).every(k => st.q[k] === 0 && (!mem || st.sg[k] === 0)));
  const total = new Array(n).fill(0), conf = new Array(n).fill(0), habit = new Array(n).fill(0), drove = new Array(b.edges.length).fill(false);
  b.edges.forEach(([a, c, w], k) => { if ((st.q[k] >= 1 || (mem && st.sg[k] >= 1) || stale[c] || (onset[a] && st.q[k] === 0 && st.sg[k] === 0 && st.h[k] === 0)) && old[a] && !sil.has(a)) { total[c] += w; if (st.q[k] >= 1) conf[c] += w; else if (mem && st.sg[k] >= 1) habit[c] += w; drove[k] = true; } });
  const nw = new Array(n);
  for (let u = 0; u < n; u++) {
    if (b.kind[u] === "R") nw[u] = FEATURES[b.feat[u]][1](y, now, opts.noise);
    else nw[u] = total[u] >= b.theta[u];
  }
  const motors = b.names.map((_, u) => u).filter(u => b.kind[u] === "M");
  const cand = motors.filter(m => nw[m] && b.patch[m] <= 2);
  if (cand.length > 1) {
    const key = m => conf[m] * 1e6 + habit[m] * 1e3 + total[m];
    const best = Math.max(...cand.map(key)), tied = cand.filter(m => key(m) === best), prev = tied.filter(m => old[m]);
    const win = (prev.length ? prev : tied).sort((a, c) => b.patch[a] - b.patch[c])[0];
    for (const m of cand) if (m !== win) nw[m] = false;
  }
  const acting = motors.filter(m => nw[m] && !sil.has(m));
  const onPatch = acting.filter(m => b.patch[m] <= 2), call = acting.find(m => b.patch[m] === 3);
  const offer = [0, 0]; for (const m of onPatch) offer[b.patch[m] - 1] = y[b.patch[m] - 1];
  const d = allocate(offer), answered = new Map(onPatch.map(m => [m, d[b.patch[m] - 1] > 0]));
  const gate = d[0] + d[1] > 0 && [...answered.values()].every(Boolean);
  const ok = u => b.kind[u] !== "M" || answered.get(u) === true;
  const confirmed = b.edges.map(([a, c], k) => drove[k] && nw[c] && gate && ok(a) && ok(c));
  const grow = k => { if (st.q[k] < P.smax) { st.q[k] = Math.min(P.smax, st.q[k] + 1 + (mem ? st.sg[k] : 0)); if (mem && st.q[k] === P.smax) st.sg[k] = Math.min(S, st.sg[k] + 1); } };
  const weaken = k => { if (st.q[k] === 0 && st.sg[k] === 0) st.h[k] = Math.min(P.smax, st.h[k] + 1);
    if (st.q[k] > 0 || !mem) st.q[k] = Math.max(st.q[k] - 1, 0); else st.sg[k] = Math.max(st.sg[k] - 1, 0); };
  confirmed.forEach((c, k) => { if (c) grow(k); });
  if (fail) for (const m of onPatch) if (!answered.get(m)) b.edges.forEach(([a, c], k) => { if (c === m && b.kind[a] === "R" && drove[k] && !confirmed[k]) weaken(k); });
  // The partner's answer to a pending call (a gesture at a later step, within W steps, of a fresh kind).
  let callAnswered = false, callFailed = 0;
  const g = y[2] || 0;
  if (st.pend && g > 0 && now - st.pend.t <= P.W && st.fresh[g - 1] >= 1) {
    st.fresh[g - 1] = 0; callAnswered = true;
    for (const k of st.pend.E) if (!confirmed[k]) { grow(k); confirmed[k] = true; }
    st.pend = null;
  }
  const failCall = p => { callFailed++; if (fail) for (const k of p.R) if (!confirmed[k]) weaken(k); };
  if (st.pend && (now - st.pend.t >= P.W || call !== undefined)) { failCall(st.pend); st.pend = null; }
  if (call !== undefined) {
    const okc = u => b.kind[u] !== "M" || u === call;
    st.pend = { t: now, E: b.edges.map(([a, c], k) => (drove[k] && nw[c] && okc(a) && okc(c)) ? k : -1).filter(k => k >= 0),
                R: b.edges.map(([a, c], k) => (c === call && b.kind[a] === "R" && drove[k]) ? k : -1).filter(k => k >= 0) };
  }
  if (now % P.FRESH === 0) st.fresh = st.fresh.map(f => Math.min(5, f + 1));
  if (now % P.decay === 0) confirmed.forEach((c, k) => { if (!c) st.q[k] = Math.max(st.q[k] - 1, 0); });
  b.names.forEach((_, u) => { if (b.kind[u] !== "R") return; st.off[u] = nw[u] ? 0 : st.off[u] + 1;
    if (st.off[u] > 0 && st.off[u] % P.decay === 0) b.edges.forEach(([a], k) => { if (a === u && st.h[k] > 0) st.h[k]--; }); });
  st.prev = old; st.active = nw; st.t = now;
  return { acting, d, gate, answered, call: call !== undefined, callAnswered, callFailed };
}
function form(win, b) {
  const U = new Set(); for (const w of win) w.active.forEach((a, u) => { if (a && b.kind[u] !== "R") U.add(u); });
  const q = win[win.length - 1].q, adj = new Map([...U].map(u => [u, b.edges.map((e, k) => (e[0] === u && U.has(e[1]) && q[k] >= 1) ? e[1] : -1).filter(v => v >= 0)]));
  const col = new Map([...U].map(u => [u, 0]));
  const dfs = u => { col.set(u, 1); for (const v of adj.get(u)) { if (col.get(v) === 1) return true; if (col.get(v) === 0 && dfs(v)) return true; } col.set(u, 2); return false; };
  for (const u of U) if (col.get(u) === 0 && dfs(u)) return true; return false;
}
module.exports = { P, S, FEATURES, rng, newborn, init, step, form, allocate };
