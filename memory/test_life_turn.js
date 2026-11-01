// Checks of the app's life loop v3 (turn.js rev. 2 + life_turn.js). Copy of test_life_partner.js (stage 20): migration of the saved being, no change to its foraging when the partner is
// absent, save/restore determinism, replay and blind conditions.
const fs = require("fs");
const load = f => new Function(fs.readFileSync(__dirname + "/" + f, "utf8").replace(/^module\.exports.*$/m, "") + "; return { makeLife, freshLife };")();
const strip = s => s.replace(/^module\.exports.*$/m, "");
const NEW = new Function(strip(fs.readFileSync(__dirname + "/turn.js", "utf8")) + strip(fs.readFileSync(__dirname + "/life_turn.js", "utf8")) + "; return { makeLife, freshLife, migrate };")();
const OLD = load("engine_src.js");
const saved = JSON.parse(fs.readFileSync(__dirname + "/backup/being-state-v1-age13581.json", "utf8"));
const v1 = saved.data || saved;
const out = {};
// 1. migration keeps every old contingency's confidence and sediment
const lifeN = NEW.makeLife(JSON.parse(JSON.stringify(v1))), lifeO = OLD.makeLife(JSON.parse(JSON.stringify(v1)));
const shared = lifeO.snapshot().edges.map(([a, c], k) => [k, lifeN.snapshot().edges.findIndex(([x, y]) => x === a && y === c)]);
out.migration_kept = shared.every(([ko, kn]) => kn >= 0 && lifeO.st.q[ko] === lifeN.st.q[kn] && lifeO.st.sg[ko] === lifeN.st.sg[kn]);
// 2. partner absent for 20000 steps (as during a catch-up): foraging stays healthy compared with the stage 19 engine
// (not identical: orienting changes the patch side too, stage 22)
const win = { O: [], N: [] }; const h = { O: { acts: 0, ans: 0 }, N: { acts: 0, ans: 0, calls: 0 } };
for (let i = 0; i < 20000; i++) {
  const a = lifeO.live(1), b = lifeN.live(1);
  for (const [x, k] of [[a, "O"], [b, "N"]]) { h[k].acts += x.acting.length; h[k].ans += x.answered.filter(Boolean).length; }
  if (b.call) h.N.calls++;
}
out.absent_20000 = { old_engine_answered: +(h.O.ans / h.O.acts).toFixed(3), new_answered: +(h.N.ans / h.N.acts).toFixed(3), old_acts: h.O.acts, new_acts: h.N.acts, new_calls: h.N.calls,
  new_formed_at_end: lifeN.live(1).formed, sediment_old: lifeO.L.sg.reduce((s, x) => s + x, 0), sediment_new: lifeN.L.sg.reduce((s, x) => s + x, 0) };
// 3. save / restore determinism with gestures
const script = (life, from, to) => { for (let t = from; t < to; t++) { if (t % 37 === 0) life.gesture(1 + (t % 4)); if (t === 2500) life.setMode("replay"); if (t === 3500) life.setMode("blind"); life.live(1); } };
const A = NEW.makeLife(null); script(A, 0, 6000);
const B = NEW.makeLife(null); script(B, 0, 3000); const C = NEW.makeLife(JSON.parse(JSON.stringify(B.L))); script(C, 3000, 6000);
out.restore_identical = JSON.stringify([A.L.q, A.L.sg, A.L.age, A.L.partner.rec, A.L.pend]) === JSON.stringify([C.L.q, C.L.sg, C.L.age, C.L.partner.rec, C.L.pend]);
// 4. replay delivers recorded gestures and ignores the live ones; blind alternates in blocks
const D = NEW.makeLife(null); D.setCounting(true);
for (let t = 0; t < 3000; t++) { if (t % 23 === 0) D.gesture(1 + (t % 4)); D.live(1); }
const recN = D.L.partner.rec.length; D.setMode("replay");
let delivered = 0; for (let t = 0; t < 1000; t++) { if (t % 23 === 0) D.gesture(1); const l = D.live(1); if (l.gesture) delivered++; }
out.replay = { recorded: recN, delivered_in_1000: delivered, ignored: D.L.partner.ignored, rec_unchanged: D.L.partner.rec.length === recN };
D.setMode("blind"); const conds = []; for (let t = 0; t < 3000; t++) { const l = D.live(1); if (t % 300 === 150) conds.push(l.cond); }
out.blind_blocks = conds.join(","); out.stats = D.L.partner.stats; out.hidden_in_blind = D.snapshot(false).partner.stats === null && D.snapshot(false).last.cond === null;
out.state_bytes = JSON.stringify(D.L).length;
// 5. a v2 state (saved by the stage 20 page) migrates as well
const V2 = new Function(strip(fs.readFileSync(__dirname + "/partner.js", "utf8")) + strip(fs.readFileSync(__dirname + "/life_partner.js", "utf8")) + "; return { makeLife };")();
const l2 = V2.makeLife(JSON.parse(JSON.stringify(v1))); for (let t2 = 0; t2 < 500; t2++) { if (t2 % 30 === 0) l2.gesture(2); l2.live(1); }
const s2 = JSON.parse(JSON.stringify(l2.L)), l3 = NEW.makeLife(s2), e2 = l2.snapshot().edges, e3 = l3.snapshot().edges;
out.v2_migration_kept = e2.every(([a, c], k) => { const j = e3.findIndex(([x, y]) => x === a && y === c); return j >= 0 && l2.st.q[k] === l3.st.q[j] && l2.st.sg[k] === l3.st.sg[j]; }) && l3.L.partner.rec.length === l2.L.partner.rec.length;
fs.writeFileSync(__dirname + "/results-life-turn.json", JSON.stringify(out, null, 1));
console.log(JSON.stringify(out, null, 1));
