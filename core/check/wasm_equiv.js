// Runs the scenario of being-tools wasm_equiv() through the WebAssembly module of the app (the exports the page's
// worker calls) and writes out/wasm-wasm-equiv.json; compare.js --a wasm --b native wasm-equiv checks it.
const fs = require("fs"), path = require("path"), LAB = path.join(__dirname, "..", "..");
const bytes = fs.readFileSync(path.join(LAB, "rust/target/wasm32-unknown-unknown/release/being_wasm.wasm"));
WebAssembly.instantiate(bytes, {}).then(({ instance }) => {
  const x = instance.exports, enc = new TextEncoder(), dec = new TextDecoder();
  const put = s => { const b = enc.encode(s); const p = x.alloc(b.length); new Uint8Array(x.memory.buffer, p, b.length).set(b); return [p, b.length]; };
  const get = p => dec.decode(new Uint8Array(x.memory.buffer, p, x.out_len()));
  const d = JSON.parse(fs.readFileSync(path.join(LAB, "memory/backup/being-state-session2-v513.json"), "utf8")), L = d.data || d;
  x.w_init(...put(JSON.stringify(L)), L.savedAt);   // no catch-up
  x.w_set_speed(10); x.w_counting(1); x.w_reveal(1);
  for (let i = 1; i <= 3000; i++) {
    if (i % 37 === 0) x.w_gesture(1 + (i % 4));
    if (i === 300) { x.w_auto_start(); x.w_set_speed(10); }
    if (i === 2000) x.w_reverse();
    if (i === 2500) x.w_stasis();
    if (i === 2700) x.w_mode(...put("blind"));
    x.w_tick();
  }
  const rec = JSON.parse(get(x.w_save(0))); delete rec.speed; delete rec.savedAt;
  const snap = JSON.parse(get(x.w_snapshot()));
  fs.writeFileSync(path.join(__dirname, "out", "wasm-wasm-equiv.json"), JSON.stringify({ L: rec, snap }));
  // the page side: the view draws every panel without failing
  x.v_snapshot(...put(JSON.stringify(snap))); x.v_flags(1, 1, 0);
  const ui = JSON.parse(get(x.v_ui()));
  for (const id of ["world", "mem", "cCall", "cSed", "cSav", "cUn"]) { const p = x.v_draw(...put(id), 600, 300, 2); if (!p) throw new Error(id); }
  console.log("wasm scenario written; ui keys", Object.keys(ui.t).length, "texts; age", snap.age);
});
