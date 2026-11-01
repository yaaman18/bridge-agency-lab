// Stage 29 (2026-10-31): three treatments of orienting / habituation for configural units (user: run three candidates
// and report). Copy of surprise.js (stage 28; surprise.js stays frozen). opts.jorient selects one; omitted = surprise.js.
//   "a" novelty is inherited: a J unit orients at its onset only if one of its two receptors is itself still novel for
//       the call (its own contingency into m3 untried and not habituated: q 0, sediment 0, h 0);
//   "b" one-shot: a J unit's habituation never recovers, so it is tried by orienting until its first failure only;
//   "c" absence of the configuration's stimuli: a J unit's habituation recovers only over steps on which BOTH of its
//       receptors are off (an element-wise absence), not merely the conjunction.
// No new numerical constants.
//
// (Header of surprise.js follows.)
// Stage 28 (2026-10-31): candidate 1 (i), configural units grown on SURPRISE with shared credit (user decision).
// Copy of turn.js rev. 2 (stage 25, the app's v3); with surprise=false, or before the first surprise, it is turn.js.
// The elemental receptor -> m3 contingencies stay. Added, for the call channel only:
//   * configural units J(a,b) (on when receptors a and b are both on, read at the end of the step, like config.js),
//     each with an untried edge J -> m3; orienting, habituation and the failure rule apply to them as to receptors;
//   * they are grown only on surprise (Pearce: a configuration is recruited when the outcome is not predicted):
//     (S1) a call that was driven by a confident (or sedimented) receptor contingency a -> m3 fails: J(a,b) for every
//          other receptor b that was on when the call was driven;
//     (S2) a call that was driven only by untried (sampled) receptor contingencies is answered: J(a,b) for each such
//          driving receptor a and every other receptor b that was on;
//   * shared credit (the core of Rescorla-Wagner and Pearce: one prediction error shared by all predictors): when an
//     answered call was driven by a configural unit J(a,b), the confirmation goes to J -> m3 and NOT to the elemental
//     a -> m3 and b -> m3 that it contains (the more specific predictor takes the credit). Failures weaken every
//     driving contingency as before. So an element that is right only inside a configuration stops being confirmed,
//     is still weakened when it is wrong, and gives way to the configuration.
// No new numerical constants.
//
// (Header of turn.js rev. 2 follows.)
// Stage 23 (2026-10-30): learning to wait, on top of the orienting response with habituation (stage 22 rev. 2).
// Copy of orient.js rev. 2 with the changes of wait.js (stage 21): no superseding (every call pending on its own, a
// fresh gesture answers the oldest), proprioceptive receptors r10 (waiting) and r11 (not waiting). proprio=false
// keeps the circuit without r10/r11 (but still without superseding). No new constants.
// Revision 2 (2026-10-30, after diag_scaffold.js): r10/r11 read the pending calls at the START of the step, so a call made
// at this step was not yet felt: the next step could be driven by "not waiting" although the circuit had just called
// (r11 drove 10-13 of 37-54 calls made while waiting). Proprioception is an efference copy: r10/r11 now take the state
// at the END of the step, after this step's call, answer and expiry (they drive the next step as every receptor does).
//
// (Header of orient.js rev. 2 follows.)
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
  ["waiting", (y) => y[3] > 0], ["not waiting", (y) => y[3] === 0],
];
function newborn(partner = true, proprio = partner) {
  const names = [], kind = [], feat = [], theta = [], patch = [], nr = partner ? (proprio ? 11 : 9) : 8;
  for (let i = 0; i < nr; i++) { names.push("r" + (i + 1)); kind.push("R"); feat.push(i); theta.push(0); patch.push(0); }
  (partner ? ["c1", "c2", "c3"] : ["c1", "c2"]).forEach(n => { names.push(n); kind.push("C"); feat.push(-1); theta.push(1); patch.push(0); });
  (partner ? ["m1", "m2", "m3"] : ["m1", "m2"]).forEach((n, i) => { names.push(n); kind.push("M"); feat.push(-1); theta.push(2); patch.push(i + 1); });
  const id = n => names.indexOf(n), edges = [], q0 = [];
  const add = (a, b, q) => { edges.push([id(a), id(b), 1]); q0.push(q); };
  add("c1", "c1", 4); add("c2", "c2", 4); add("c1", "c2", 4); add("c2", "c1", 4);
  if (partner) { add("c3", "c3", 4); add("c1", "c3", 4); add("c3", "c1", 4); add("c2", "c3", 4); add("c3", "c2", 4); }
  const pairs = partner ? [["c1", "m1"], ["c2", "m2"], ["c3", "m3"]] : [["c1", "m1"], ["c2", "m2"]];
  for (const [c, m] of pairs) { add(c, m, 0); for (let i = 0; i < nr; i++) add("r" + (i + 1), m, 0); }
  return { names, kind, feat, theta, patch, edges, q0, initial: names.map(n => n[0] === "c"), jpairs: {} };
}
function init(b) { return { active: b.initial.slice(), q: b.q0.slice(), sg: b.q0.map(() => 0), h: b.q0.map(() => 0), off: b.names.map(() => 0), t: 0, pend: [], fresh: new Array(P.KINDS).fill(5) }; }
const S = P.smax;
function allocate(offer) { const d = [0, 0]; let left = P.capacity; for (const i of [0, 1].filter(i => offer[i] > 0).sort((i, j) => (offer[j] - offer[i]) || (i - j))) { d[i] = Math.min(offer[i], left); left -= d[i]; } return d; }
// opts: { explore=true, fail=true, memory=true, sil:Set, noise: rng }
function step(st, b, y, opts) {
  const explore = opts.explore !== false, fail = opts.fail !== false, sil = opts.sil || new Set();
  const n = b.names.length, old = st.active, ins = u => b.edges.map((e, k) => e[1] === u ? k : -1).filter(k => k >= 0);
  const ys = [y[0], y[1], y[2] || 0, st.pend.length > 0 ? 1 : 0];
  const mem = opts.memory !== false, now = st.t + 1, orient = opts.orient !== false, prev = st.prev || old;
  const surprise = opts.surprise !== false, sense = u => b.kind[u] === "R" || b.kind[u] === "J";
  const jor = opts.jorient, callM = b.names.indexOf("m3");
  const novel = r => { const k = b.edges.findIndex(([a, c]) => a === r && c === callM); return k >= 0 && st.q[k] === 0 && st.sg[k] === 0 && st.h[k] === 0; };
  const onset = b.names.map((n, u) => orient && sense(u) && old[u] && !prev[u] && !(jor === "a" && b.kind[u] === "J" && !b.jpairs[n].some(novel)));
  const stale = b.names.map((_, u) => explore && b.kind[u] !== "R" && ins(u).length > 0 && ins(u).every(k => st.q[k] === 0 && (!mem || st.sg[k] === 0)));
  const total = new Array(n).fill(0), conf = new Array(n).fill(0), habit = new Array(n).fill(0), drove = new Array(b.edges.length).fill(false);
  b.edges.forEach(([a, c, w], k) => { if ((st.q[k] >= 1 || (mem && st.sg[k] >= 1) || stale[c] || (onset[a] && st.q[k] === 0 && st.sg[k] === 0 && st.h[k] === 0)) && old[a] && !sil.has(a)) { total[c] += w; if (st.q[k] >= 1) conf[c] += w; else if (mem && st.sg[k] >= 1) habit[c] += w; drove[k] = true; } });
  const nw = new Array(n);
  for (let u = 0; u < n; u++) {
    if (b.kind[u] === "R") nw[u] = FEATURES[b.feat[u]][1](ys, now, opts.noise);
    else if (b.kind[u] === "J") nw[u] = false;   // set at the end of the step
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
  function recruit(as, act, m) {
    for (const a of as) for (const c of act) {
      if (c === a) continue; const [x, z] = a < c ? [a, c] : [c, a], n = "j:" + b.names[x] + "+" + b.names[z];
      if (b.jpairs[n]) continue;
      const u = b.names.length; b.names.push(n); b.kind.push("J"); b.feat.push(-1); b.theta.push(0); b.patch.push(0); b.initial.push(false);
      b.jpairs[n] = [x, z]; nw.push(false); st.off.push(0); if (st.prev) st.prev.push(false);
      b.edges.push([u, m, 1]); b.q0.push(0); st.q.push(0); st.sg.push(0); st.h.push(0);
    }
  }
  confirmed.forEach((c, k) => { if (c) grow(k); });
  if (fail) for (const m of onPatch) if (!answered.get(m)) b.edges.forEach(([a, c], k) => { if (c === m && sense(a) && drove[k] && !confirmed[k]) weaken(k); });
  // The partner's answer: a fresh gesture answers the oldest call still pending (made at an earlier step, within W).
  let callAnswered = false, callFailed = 0;
  const g = y[2] || 0;
  if (g > 0 && st.fresh[g - 1] >= 1) {
    const i = st.pend.findIndex(p => p.t < now && now - p.t <= P.W);
    if (i >= 0) {
      const pd = st.pend[i]; st.fresh[g - 1] = 0; callAnswered = true;
      const covered = new Set(); if (surprise) for (const k of pd.R) { const a = b.edges[k][0]; if (b.kind[a] === "J") for (const x of b.jpairs[b.names[a]]) covered.add(x); }
      for (const k of pd.E) { const a = b.edges[k][0]; if (covered.has(a) && b.edges[k][1] === pd.m) continue; if (!confirmed[k]) { grow(k); confirmed[k] = true; } }
      if (surprise && !pd.conf) recruit(pd.tried, pd.act, pd.m);
      st.pend.splice(i, 1);
    }
  }
  const failCall = p => { callFailed++; if (fail) for (const k of p.R) if (!confirmed[k]) weaken(k); if (surprise && p.conf) recruit(p.confEl, p.act, p.m); };
  st.pend = st.pend.filter(p => { if (now - p.t >= P.W) { failCall(p); return false; } return true; });
  if (call !== undefined) {
    const okc = u => b.kind[u] !== "M" || u === call;
    const R = b.edges.map(([a, c], k) => (c === call && sense(a) && drove[k]) ? k : -1).filter(k => k >= 0);
    const confK = R.filter(k => st.q[k] >= 1 || (mem && st.sg[k] >= 1));
    st.pend.push({ t: now, m: call, E: b.edges.map(([a, c], k) => (drove[k] && nw[c] && okc(a) && okc(c)) ? k : -1).filter(k => k >= 0), R,
                   conf: confK.length > 0, confEl: confK.map(k => b.edges[k][0]).filter(a => b.kind[a] === "R"),
                   tried: R.map(k => b.edges[k][0]).filter(a => b.kind[a] === "R"), act: b.names.map((_, u) => u).filter(u => b.kind[u] === "R" && old[u] && !sil.has(u)) });
  }
  b.names.forEach((_, u) => { if (b.kind[u] === "R" && b.feat[u] >= 9) nw[u] = FEATURES[b.feat[u]][1]([0, 0, 0, st.pend.length > 0 ? 1 : 0], now); });
  b.names.forEach((n, u) => { if (b.kind[u] === "J") { const [x, z] = b.jpairs[n]; nw[u] = nw[x] && nw[z]; } });
  if (now % P.FRESH === 0) st.fresh = st.fresh.map(f => Math.min(5, f + 1));
  if (now % P.decay === 0) confirmed.forEach((c, k) => { if (!c) st.q[k] = Math.max(st.q[k] - 1, 0); });
  b.names.forEach((n, u) => { if (!sense(u)) return;
    const absent = b.kind[u] === "J" && jor === "c" ? !nw[b.jpairs[n][0]] && !nw[b.jpairs[n][1]] : !nw[u];
    st.off[u] = absent ? st.off[u] + 1 : 0;
    if (b.kind[u] === "J" && jor === "b") return;
    if (st.off[u] > 0 && st.off[u] % P.decay === 0) b.edges.forEach(([a], k) => { if (a === u && st.h[k] > 0) st.h[k]--; }); });
  st.prev = old; st.active = nw; st.t = now;
  return { acting, d, gate, answered, call: call !== undefined, callWhileWaiting: call !== undefined && ys[3] > 0, callAnswered, callFailed };
}
function form(win, b) {
  const U = new Set(); for (const w of win) w.active.forEach((a, u) => { if (a && b.kind[u] !== "R") U.add(u); });
  const q = win[win.length - 1].q, adj = new Map([...U].map(u => [u, b.edges.map((e, k) => (e[0] === u && U.has(e[1]) && q[k] >= 1) ? e[1] : -1).filter(v => v >= 0)]));
  const col = new Map([...U].map(u => [u, 0]));
  const dfs = u => { col.set(u, 1); for (const v of adj.get(u)) { if (col.get(v) === 1) return true; if (col.get(v) === 0 && dfs(v)) return true; } col.set(u, 2); return false; };
  for (const u of U) if (col.get(u) === 0 && dfs(u)) return true; return false;
}
module.exports = { P, S, FEATURES, rng, newborn, init, step, form, allocate };
