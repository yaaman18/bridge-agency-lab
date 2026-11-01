// Stage 31 (2026-10-31), option A: a third kind of partner, an LLM that does not know the circuit's rules or the
// predictions. It sees only what a person sees on the page (the lamp, whether the last call was made in a pause or
// over a pending call, pending answers, the freshness of each gesture) once per 5 steps (1 s at 5 steps/s), with the
// segment instruction of the app, and answers one digit (a gesture 1-4 or 0). Its rule is frozen in PROMPT_partner.md:
// it is declared as part of the environment (lab rule), never reads the circuit. The world waits while it decides.
// The circuit and its world are the app's own (turn.js rev. 2 + life_turn.js v3.2, the auto session of 3 x 1500 steps).
// Usage: node llm_partner.js <llm|script> <seed> [model]   -> results-llm-<kind>-seed<seed>.json (+ decision log)
const fs = require("fs"), { execFileSync } = require("child_process"), strip = s => s.replace(/^module\.exports.*$/m, "");
const E = new Function(strip(fs.readFileSync(__dirname + "/turn.js", "utf8")) + strip(fs.readFileSync(__dirname + "/life_turn.js", "utf8")) + "; return { makeLife, rng, P };")();
const { analyze } = require("./analyze_session2.js");
const PROMPT = fs.readFileSync(__dirname + "/PROMPT_partner.md", "utf8");
const [kind, seedArg, model = "haiku"] = process.argv.slice(2), seed = +seedArg;
const INSTR = { 1: "呼びかけに何度でも答えてください（身ぶりは混ぜて）。", 2: "「間を置いた呼びかけ」にだけ答え、「重ねた呼びかけ」には答えずに待ってください。", 3: "自由に関わってください。" };
function ask(text) {
  const t0 = Date.now(); let out = "";
  try { out = execFileSync("claude", ["-p", "--model", model, "--tools", "", "--no-session-persistence", "--system-prompt", PROMPT], { input: text, encoding: "utf8", timeout: 120000 }); }
  catch (e) { out = "ERROR " + String(e.message || "").slice(0, 80); }
  const m = out.trim().match(/^[0-4]/); return { g: m ? +m[0] : 0, ok: !!m, raw: out.trim().slice(0, 40), ms: Date.now() - t0 };
}
const life = E.makeLife(null); life.L.rng = 20261030 + seed; life.L.partner.brng = 777 + seed;
life.live(800);                       // nursery and school without the partner (as the ADULT conditions of stages 24-25)
life.setCounting(true); life.startAuto();
const pr = E.rng(seed + 5000); let sched = null, rot = 0, lastG = null, lastGAge = null, win = [], decisions = [];
while (life.L.session.auto.seg <= 3) {
  const now = life.L.age + 1;
  if (kind === "script") {           // matched scripted partner: RESP in segments 1 and 3, TURN (pause calls only) in segment 2
    const s0 = pr(); if (sched === now) { sched = null; life.gesture((rot++ % 4) + 1); } else if (s0 < 0.01) life.gesture(1 + Math.floor(pr() * 4));
  }
  const l = life.live(1), snap = life.snapshot(false), seg = life.L.session.auto.seg;
  if (kind === "script" && l.call && sched === null && (seg !== 2 || !l.callWhileWaiting)) { const a = pr(), d = pr(); if (a < 0.8) sched = now + 2 + Math.floor(d * 7); }
  if (kind !== "llm") continue;
  win.push(l.callAnswered ? "答えが届いた" : l.call ? (l.callWhileWaiting ? "呼びかけた（重ねた呼びかけ）" : "呼びかけた（間を置いた呼びかけ）") : snap.pend ? `呼びかけている（${snap.pend.n} 件が答え待ち、いちばん古い呼びかけの残り ${Math.max(0, snap.pend.left)} 歩）` : "静か");
  if (win.length < 5) continue;
  const active = win.some(w => w !== "静か"), every = Math.floor(now / 5) % 5 === 0;
  if (active || every) {
    const text = `いまの指示：${INSTR[seg]}\n直前の5歩：\n${win.map((w, i) => `  ${i + 1}歩目：${w}`).join("\n")}\n身ぶりの新しさ：1 ○=${snap.fresh[0]}、2 △=${snap.fresh[1]}、3 □=${snap.fresh[2]}、4 ◇=${snap.fresh[3]}\n` +
      (lastG ? `あなたが前に押した身ぶり：${lastG}（${life.L.age - lastGAge} 歩前）\n` : "") + "押す身ぶりの数字（0〜4）：";
    const q = ask(text); decisions.push([now, seg, q.g, q.ok ? undefined : q.raw, q.ms]);
    if (q.g) { life.gesture(q.g); lastG = q.g; lastGAge = life.L.age; }
    if (decisions.length % 50 === 0) fs.writeFileSync(__dirname + `/results-llm-${kind}-seed${seed}.partial.json`, JSON.stringify({ decisions, age: life.L.age, seg }));
  }
  win = [];
}
const res = { kind, seed, model: kind === "llm" ? model : null, analysis: analyze(life.L), decisions: decisions.length, parseFailures: decisions.filter(d => d[3]).length,
              meanMs: decisions.length ? Math.round(decisions.reduce((s, d) => s + d[4], 0) / decisions.length) : null, decisionLog: decisions };
fs.writeFileSync(__dirname + `/results-llm-${kind}-seed${seed}.json`, JSON.stringify(res, null, 1));
const A = res.analysis.segments;
console.log(kind, seed, "decisions", res.decisions, "fail", res.parseFailures, "ms", res.meanMs);
for (const k of ["1", "2", "3"]) if (A[k]) console.log(" seg", k, JSON.stringify({ all: A[k].all, last750w: A[k].last750.waitingShare, last300c: A[k].last300.callsPer100, form: A[k].formShare, atEnd: A[k].atEnd, live: A[k].live, replay: A[k].replay }));
