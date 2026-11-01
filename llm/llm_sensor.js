// LLM trial (2026-10-29): Claude Code (headless `claude -p`) as the sensory front-end of the agent.
// The LLM only translates a text observation of the world into the two patch-sensor signals; it does not
// act, choose, or see the circuit. Its rule is frozen in PROMPT.md (the declared translation rule; the
// statement "the LLM's report is the sensor's meaning" is a named assumption, not a theorem).
// Usage: node llm_sensor.js closed <model> <steps>     closed loop with the agent, compared with rule sensors
//        node llm_sensor.js open <model> <variant> <n> open loop on n sampled world states (variant a|b)
const { execFileSync } = require("child_process");
const fs = require("fs");
const SIM = require("../viewer/sim.js"), TYPES = require("../viewer/types.js");
const PROMPT = fs.readFileSync(__dirname + "/PROMPT.md", "utf8");
const WORDS = {
  a: { res: "not yet predicted:", known: "already predicted:", ev: ["a ripple with no period", "a flicker at the edge", "a tone that drifts", "a shape that splits", "a pulse out of step", "a gap in the pattern", "a colour that wanders"] },
  b: { res: "still surprising:", known: "familiar:", ev: ["an echo arriving late", "a stripe that bends", "a hum that stutters", "a dot that doubles", "a beat that skips", "a crease in the field", "a shade that shifts"] },
};
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function render(y, key, variant) {
  const W = WORDS[variant], r = rng(key * 7919 + (variant === "a" ? 1 : 2));
  return [0, 1].map(i => {
    const items = [];
    for (let k = 0; k < y[i]; k++) items.push(`${W.res} ${W.ev[Math.floor(r() * W.ev.length)]}`);
    for (let k = 0; k < 5 - y[i]; k++) items.push(`${W.known} ${W.ev[Math.floor(r() * W.ev.length)]}`);
    for (let k = items.length - 1; k > 0; k--) { const j = Math.floor(r() * (k + 1)); [items[k], items[j]] = [items[j], items[k]]; }
    return `Patch ${i + 1}:\n` + items.map(x => "- " + x).join("\n");
  }).join("\n\n");
}
const rule = y => [0, 1].map(p => y[p] > 0 && y[p] >= y[1 - p]);
function ask(model, obs) {
  const t0 = Date.now();
  let out = "";
  try { out = execFileSync("claude", ["-p", "--model", model, "--tools", "", "--no-session-persistence", "--system-prompt", PROMPT], { input: obs, encoding: "utf8", timeout: 120000 }); }
  catch (e) { out = "ERROR " + (e.message || ""); }
  const m = out.match(/\{[^{}]*\}/);
  let v = null; try { const j = JSON.parse(m[0]); if (typeof j.s1 === "boolean" && typeof j.s2 === "boolean") v = [j.s1, j.s2]; } catch (e) {}
  return { v, raw: out.trim().slice(0, 120), ms: Date.now() - t0 };
}
const season = t => t <= 300 ? [3, 2] : t <= 600 ? [0, 5] : [5, 0];
const [mode, model] = process.argv.slice(2);
if (mode === "closed") {
  const steps = +process.argv[4];
  const typ = TYPES.find(t => t.name === "selfloop-pair-agent");
  const runs = {};
  for (const src of ["rule", "llm"]) {
    const s = SIM.build(typ), st = SIM.init(s); let R = [50, 50]; const win = []; const log = [];
    for (let t = 1; t <= steps; t++) {
      const y = [Math.min(R[0], 5), Math.min(R[1], 5)];
      let sens = rule(y), q = null;
      if (src === "llm") { q = ask(model, render(y, t, "a")); sens = q.v || [false, false]; }
      const out = SIM.step(st, s, y, new Set(), { sensors: sens });
      R = [0, 1].map(i => Math.min(50, R[i] - out.digested[i] + season(t)[i]));
      win.push({ active: st.active.slice(), strength: st.strength.slice() }); if (win.length > 5) win.shift();
      log.push({ t, y, sens, rule: rule(y), act: out.acting.map(m => s.names[m]).join(""), formed: SIM.form(win, s), ms: q && q.ms, raw: q && !q.v ? q.raw : undefined, state: st.active.map(a => +a).join("") + "|" + st.strength.join(",") + "|" + R.join(",") });
    }
    runs[src] = log;
  }
  const L = runs.llm, Rr = runs.rule;
  const agree = L.filter(x => x.sens[0] === x.rule[0] && x.sens[1] === x.rule[1]).length;
  const firstDiv = L.findIndex((x, i) => x.state !== Rr[i].state);
  const ms = L.map(x => x.ms).filter(Boolean);
  console.log(JSON.stringify({ model, steps, sensor_agreement: `${agree}/${steps}`, parse_failures: L.filter(x => x.raw).length,
    trajectory_identical_to_rule: firstDiv < 0, first_divergence_step: firstDiv < 0 ? null : firstDiv + 1,
    form_kept_llm: `${L.filter(x => x.formed).length}/${steps}`, form_kept_rule: `${Rr.filter(x => x.formed).length}/${steps}`,
    actions_llm: L.map(x => x.act || "-").join(" "), mean_ms: Math.round(ms.reduce((a, b) => a + b, 0) / ms.length),
    disagreements: L.filter(x => x.sens[0] !== x.rule[0] || x.sens[1] !== x.rule[1]).map(x => ({ t: x.t, y: x.y, llm: x.sens, rule: x.rule, raw: x.raw })) }, null, 1));
} else {
  const variant = process.argv[4], n = +process.argv[5];
  const r = rng(424242); const res = [];
  for (let k = 0; k < n; k++) {
    const y = [Math.floor(r() * 6), Math.floor(r() * 6)];
    const q = ask(model, render(y, 1000 + k, variant));
    res.push({ k, y, rule: rule(y), llm: q.v, ms: q.ms });
  }
  console.log(JSON.stringify(res));
}
