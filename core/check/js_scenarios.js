// Runs the check scenarios on the JavaScript copies and writes core/check/out/js-<name>.json. jl_scenarios.jl runs the
// same scenarios on the Julia rules (core/LabCore.jl); compare.js reports the first difference. Indices are 0-based in
// the outputs of both sides. Usage: node core/check/js_scenarios.js [name ...]
const fs = require("fs"), path = require("path"), LAB = path.join(__dirname, "..", "..");
const OUT = path.join(__dirname, "out"); fs.mkdirSync(OUT, { recursive: true });
const strip = s => s.replace(/^module\.exports.*$/m, "");
const eng = (core, life) => new Function(strip(fs.readFileSync(path.join(LAB, "memory", core), "utf8")) + "\n" +
  strip(fs.readFileSync(path.join(LAB, "memory", life), "utf8")) + "; return { makeLife, FEATURES };")();
const rt = x => JSON.parse(JSON.stringify(x));
const loadBeing = f => { const d = JSON.parse(fs.readFileSync(path.join(LAB, "memory", "backup", f), "utf8")); return d.data || d; };
const write = (name, x) => fs.writeFileSync(path.join(OUT, "js-" + name + ".json"), JSON.stringify(x));

// ---- circuit (memory/turn_sed.js; contrast null = turn.js) ----
const lifeSeason = t => { const c = ((t - 1) % 1000) + 1; return c <= 300 ? [3, 2] : c <= 600 ? [0, 5] : [5, 0]; };
function circuitRun(partner, contrast, variant, steps, scarce) {
  delete require.cache[require.resolve(path.join(LAB, "memory", "turn_sed.js"))];
  const N = require(path.join(LAB, "memory", "turn_sed.js"));
  const b = N.newborn(partner), st = N.init(b), noise = N.rng(7), gr = N.rng(99), m1 = b.names.indexOf("m1");
  let R = [50, 50], wt = 0; const trace = [], win = [];
  for (let t = 0; t < steps; t++) {
    if (t === 3000) for (const [i, j] of [[0, 1], [2, 3], [6, 7]]) { const a = N.FEATURES[i]; N.FEATURES[i] = N.FEATURES[j]; N.FEATURES[j] = a; }
    const sil = t >= 2000 && t < 2100 ? new Set([4, m1]) : undefined;
    const y = t < 400 ? [[5, 0], [0, 5]][Math.floor(t / 50) % 2] : t < 800 ? [[5, 2], [2, 5]][Math.floor((t - 400) / 15) % 2] : [Math.min(R[0], 5), Math.min(R[1], 5)];
    const g = partner ? (gr() < 0.1 ? 1 + Math.floor(gr() * 4) : 0) : 0;
    const o = N.step(st, b, [...y, g], { noise, contrast, ...variant, sil });
    if (t >= 800) { wt++; const s = scarce && wt % 3 !== 0 ? [0, 0] : lifeSeason(wt); R = [0, 1].map(k => Math.min(50, R[k] - o.d[k] + s[k])); }
    win.push({ active: st.active.slice(), q: st.q.slice() }); if (win.length > 5) win.shift();
    trace.push([o.acting, o.d, o.gate ? 1 : 0, o.call ? 1 : 0, o.callAnswered ? 1 : 0, o.callFailed, o.callWhileWaiting ? 1 : 0,
                st.q.reduce((a, c) => a + c, 0), st.sg.reduce((a, c) => a + c, 0), st.h.reduce((a, c) => a + c, 0), N.form(win, b) ? 1 : 0]);
  }
  return { trace, final: { q: st.q, sg: st.sg, h: st.h, off: st.off, active: st.active, prev: st.prev, pend: st.pend, fresh: st.fresh,
           cOn: st.cOn || null, cOff: st.cOff || null, lastM: st.lastM || null, t: st.t } };
}
const CIRCUITS = [];
for (const c of [null, "sed", "learn", "learn2", "learn3", "bin3", "donly"]) CIRCUITS.push([`circuit-${c}-p`, true, c, {}]);
for (const c of [null, "bin3"]) CIRCUITS.push([`circuit-${c}-np`, false, c, {}]);
for (const v of ["memory", "orient", "explore", "fail"]) CIRCUITS.push([`circuit-null-no${v}`, true, null, { [v]: false }]);
CIRCUITS.push(["circuit-bin3-nomemory", true, "bin3", { memory: false }]);
// scarce: the pools regrow only every third step, so that acts often go unanswered (the contrast statistics move).
for (const c of ["bin3", "learn3", "learn2", "sed", "learn"]) CIRCUITS.push([`circuit-${c}-scarce`, true, c, {}, true]);

// ---- life (memory/turn_sed.js + memory/life_turn.js, as built into the app) ----
const V35 = () => eng("turn_sed.js", "life_turn.js"), V34 = () => eng("turn_sed.js", "backup/life_turn-v3.4.js");
const lastOf = o => o && { ...o, answered: o.answered };
function lifeRun(start, steps, script) {
  let E = V35(), l = E.makeLife(start); if (!start) l.L.born = 0;
  l.setCounting(true); const trace = [];
  for (let i = 1; i <= steps; i++) {
    for (const [at, f] of script) if (at === i) { if (f === "reload") { l = E.makeLife(rt(l.L)); l.setCounting(true); } else f(l); }
    trace.push(lastOf(l.live(1)));
  }
  return { trace, L: rt(l.L) };
}
const SCRIPT = [];
for (let i = 37; i <= 6000; i += 37) SCRIPT.push([i, l => l.gesture(1 + (i % 4))]);
SCRIPT.push([300, l => l.startAuto()], [2000, l => l.reverse()], [2500, l => l.stasis(150)], [3000, "reload"],
            [4600, l => l.stopAuto()], [4700, l => l.setMode("blind")], [5200, l => l.mark("x")], [5500, l => l.clearStats()]);
const LIVES = {
  "life-age86642": () => lifeRun(rt(loadBeing("being-state-pre-learn3-age86642.json")), 6000, SCRIPT),
  "life-v513": () => lifeRun(rt(loadBeing("being-state-session2-v513.json")), 3000, SCRIPT),
  "life-v438-blind": () => lifeRun(rt(loadBeing("being-state-session-v438.json")), 3000, SCRIPT),
  "life-fresh": () => lifeRun(null, 3000, SCRIPT),
  "life-from-v34": () => { const a = V34().makeLife(rt(loadBeing("being-state-pre-learn3-age86642.json"))); a.live(3000);
    fs.writeFileSync(path.join(OUT, "state-v34-after3000.json"), JSON.stringify(a.L)); return lifeRun(rt(a.L), 2000, SCRIPT); },
};

// ---- matter (matter.js stage 32, fevo.js, trm.js, trm2.js) ----
const MD = path.join(LAB, "matter"), req = f => require(path.join(MD, f));
const worldOut = w => ({ A: Array.from(w.A), B: Array.from(w.B), C: Array.from(w.C), K: w.K, reservoir: w.port.reservoir,
  inflow: w.port.inflow, outflow: w.port.outflow, born: w.born, died: w.died, t: w.t });
const netOut = c => c && { Wz: c.Wz, Wx: c.Wx, Wn: c.Wn, b: c.b, Wy: c.Wy, wa: c.wa, ba: c.ba, wp: c.wp ?? null, z: c.z, y: c.y, err: c.err, line: c.line ?? null };
function matter32(spont) {
  const M = req("matter.js"), w = M.makeWorld({ spontaneous: spont }); M.seed(w, 12, 12, 1); const log = [];
  for (let t = 0; t < 2000; t++) {
    const src = []; if (!(spont && t >= 300 && t < 900)) for (const [cx, cy] of [[6, 12], [18, 12]]) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) src.push([(cy + dy) * 24 + cx + dx, (Math.floor(t / 500) % 2 === 0 ? 1 : 0.3) * w.p.SRC]);
    M.step(w, src); if (t % 100 === 99) log.push([M.total(w), M.count(w).constituents, M.count(w).bound]);
  }
  return { log, world: worldOut(w) };
}
function evoRun(file, mode, seed, opts, steps, srcf) {
  const E = req(file), divs = [], deaths = [];
  const o = { ...opts }; if (o.hooks) o.hooks = { divide: (i, j) => divs.push([i, j]), death: i => deaths.push(i) };
  const L = E.makeLife(mode, seed, o), log = [];
  for (let t = 0; t < steps; t++) { L.step(srcf(L.w, t)); if (file === "fevo.js" && t % 100 === 99) log.push(L.stats()); }
  return { log, world: worldOut(L.w), act: Array.from(L.act), net: L.net.map(netOut), divs, deaths };
}
const S48 = [[8, 12], [24, 12], [40, 12], [8, 36], [24, 36], [40, 36], [8, 4], [24, 4], [40, 44]], P48 = [[8, 8], [24, 8], [40, 8], [8, 40], [24, 40], [40, 40]];
const src48 = (w, t) => { const s = [], rich = Math.floor(t / 500) % 2 === 0; for (const [cx, cy] of P48) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s.push([(cy + dy) * 48 + cx + dx, (rich ? 1 : 0.3) * w.p.SRC * 0.5]); return s; };
const fsrc = (scale, starve) => (w, t) => req("fevo.js").sources(w, t, scale, starve);
const MATTERS = {
  "matter32": () => matter32(false), "matter32-spont": () => matter32(true),
  "trm33": () => evoRun("trm.js", "trm", 2, {}, 1000, (w, t) => req("trm.js").sources(w, t)),
  "trm35-predact": () => evoRun("trm2.js", "predact", 2, {}, 1000, (w, t) => req("trm2.js").sources(w, t)),
  "evo-48-trm": () => evoRun("fevo.js", "trm", 1, { W: 48, H: 48, reservoir: 1200, seeds: S48, hooks: true }, 600, src48),
  "evo-48-predact": () => evoRun("fevo.js", "predact", 1, { W: 48, H: 48, reservoir: 1200, seeds: S48 }, 600, src48),
  "evo-nogate-actgate0-bind": () => evoRun("fevo.js", "nogate", 4, { actGate: 0, bindConst: 0.5, hooks: true }, 1500, fsrc(1)),
  "evo-trm-starve": () => evoRun("fevo.js", "trm", 5, {}, 1500, fsrc(2, [300, 700])),
};
for (const m of ["fixed", "trm", "nogate", "noinherit", "predact", "frozen"]) MATTERS["evo-" + m] = () => evoRun("fevo.js", m, 3, {}, 1500, fsrc(1));

// ---- body_org (matter/body_org.js) ----
const B = () => req("body_org.js");
function bodyRuns(list) { const out = []; for (const [cond, seed, o, replayOf] of list) { const r = B().run(cond, seed, o, replayOf !== undefined ? out[replayOf].acts : undefined); out.push(r); } return out; }
const base = { U: 0.02, MCOST: 0.004, STEPS: 3000 };
const BODIES = {
  "body-base": () => bodyRuns([["ORG", 1, base], ["REPLAY", 1, base, 0], ["NONE", 1, base], ["GREEDY", 1, base], ["ORG", 2, { ...base, REV: 1500 }]]),
  "body-bin3-full": () => bodyRuns([["ORG", 3, { ...base, CONTRAST: "bin3", FEED: true, RAISE: "body", PER: 4, KC: 0.0005, PHASE: 37, REV: 1500, REVR: 2000 }],
                                    ["GREEDY", 3, { ...base, KC: 0.0005, REVR: 2000, FEED: true }]]),
  "body-learn3-drop": () => bodyRuns([["ORG", 4, { ...base, CONTRAST: "learn3", FEED: true, DROPR: ["r5", "r6"], PHASE: 11 }]]),
  "body-rules": () => bodyRuns(["learn2", "sed", "learn", "donly"].map(c => ["ORG", 5, { ...base, STEPS: 2000, CONTRAST: c, KC: 0.0002 }])),
};

const ALL = { ...Object.fromEntries(CIRCUITS.map(([n, p, c, v, sc]) => [n, () => circuitRun(p, c, v, 6000, sc)])), ...LIVES, ...MATTERS, ...BODIES };
const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(ALL);
for (const n of names) { const t0 = Date.now(); write(n, ALL[n]()); console.log(n, Date.now() - t0, "ms"); }
