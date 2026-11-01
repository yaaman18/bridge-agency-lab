// The bridge between the browser and the being (v3.6, rules v3.7). Everything the being does and everything the page shows is
// computed in Rust (rust/being-core, as WebAssembly): the rules, the saved record, the texts and the panels. This
// script only does what a browser page must do in JavaScript: start the WebAssembly module (in a worker that lives
// the being, and on the page that shows it), run the clocks, save to the artifact's db, and pass on buttons and keys.
(() => {
  const $ = id => document.getElementById(id);
  const bytes = Uint8Array.from(atob($("wasm").textContent.trim()), c => c.charCodeAt(0));
  function bind(x) {
    const enc = new TextEncoder(), dec = new TextDecoder();
    return {
      put: s => { const b = enc.encode(s); const p = x.alloc(b.length); new Uint8Array(x.memory.buffer, p, b.length).set(b); return [p, b.length]; },
      get: p => dec.decode(new Uint8Array(x.memory.buffer, p, x.out_len())),
    };
  }
  const workerSrc = `${bind.toString()}
    let x = null, io = null;
    onmessage = async e => { const m = e.data;
      if (m.cmd === "init") {
        const { instance } = await WebAssembly.instantiate(m.bytes, {}); x = instance.exports; io = bind(x);
        const caught = x.w_init(...io.put(m.saved || ""), m.now);
        postMessage({ type: "ready", caught, speed: x.w_speed() });
        setInterval(() => x.w_tick(), 100);
        setInterval(() => postMessage({ type: "snap", s: io.get(x.w_snapshot()), speed: x.w_speed(), running: x.w_running() }), 120);
        return;
      }
      if (!x) return;
      if (m.cmd === "save") { postMessage({ type: "save", s: io.get(x.w_save(m.now)) }); return; }
      const f = x["w_" + m.cmd]; if (typeof f === "function") f(...(m.args || []).flatMap(a => typeof a === "string" ? io.put(a) : [a]));
    };`;

  let V = null, vio = null, worker = null, db = null, mode = "starting", lastSaved = 0, saveCode = 0, caught = 0, reveal = false, present = false;
  let lastInput = Date.now(), dragging = false;
  const tabId = Math.random().toString(36).slice(2);
  const PANELS = ["world", "mem", "cCall", "cSed", "cSav", "cUn"];
  const send = (cmd, ...args) => worker && worker.postMessage({ cmd, args });
  const dark = () => { const t = document.documentElement.dataset.theme; return t === "dark" || (t !== "light" && matchMedia("(prefers-color-scheme: dark)").matches); };

  function render() {
    if (!V) return;
    V.v_save(saveCode, caught, lastSaved ? Date.now() - lastSaved : -1);
    V.v_flags(reveal ? 1 : 0, $("observer").checked ? 1 : 0, dark() ? 1 : 0);
    const u = JSON.parse(vio.get(V.v_ui()));
    for (const [k, v] of Object.entries(u.t || {})) { const e = $(k); if (e && e.textContent !== v) e.textContent = v; }
    for (const [k, v] of Object.entries(u.c || {})) { const e = $(k); if (e && e.className !== v) e.className = v; }
    for (const [k, v] of Object.entries(u.w || {})) { const e = $(k); if (e) e.style.width = v + "%"; }
    for (const [k, v] of Object.entries(u.d || {})) { const e = $(k); if (e) e.disabled = v; }
    for (const [k, v] of Object.entries(u.h || {})) { const e = $(k); if (e) e.hidden = v; }
    const r = u.r && document.querySelector(`input[name=mode][value=${u.r}]`); if (r && !r.checked) r.checked = true;
    for (const id of PANELS) paint(id);
  }
  function paint(id) {
    const cv = $(id), dpr = devicePixelRatio || 1;
    const W = Math.max(1, Math.round(cv.clientWidth * dpr)), H = Math.max(1, Math.round(cv.clientHeight * dpr));
    if (cv.width !== W) cv.width = W; if (cv.height !== H) cv.height = H;
    const p = V.v_draw(...vio.put(id), W, H, dpr);
    cv.getContext("2d").putImageData(new ImageData(new Uint8ClampedArray(V.memory.buffer.slice(p, p + W * H * 4)), W, H), 0, 0);
  }

  function startWorker(saved) {
    worker = new Worker(URL.createObjectURL(new Blob([workerSrc], { type: "text/javascript" })));
    worker.onmessage = e => {
      const m = e.data;
      if (m.type === "snap") {
        V.v_snapshot(...vio.put(m.s));
        if (!dragging) { $("speed").value = m.speed; $("speedv").textContent = m.speed; }
        $("run").textContent = m.running ? "一時停止" : "再開";
        render();
      }
      if (m.type === "ready") { if (m.caught) { caught = m.caught; saveCode = 7; } sendPresence(true); }
      if (m.type === "save") persist(m.s);
    };
    worker.postMessage({ cmd: "init", bytes, saved, now: Date.now() });
  }
  async function persist(s) {
    if (!s) return;
    try { localStorage.setItem("being-state", s); } catch (e) {}
    if (db && mode === "owner") {
      try { await db.doc("being/state").set(JSON.parse(s)); lastSaved = Date.now(); saveCode = 1; }
      catch (e) { saveCode = e && e.code === "quota_exceeded" ? 2 : 3; }
    } else { lastSaved = Date.now(); saveCode = db ? 4 : 5; }
  }
  const requestSave = () => worker && mode !== "observer" && worker.postMessage({ cmd: "save", now: Date.now() });
  const saveSoon = () => setTimeout(requestSave, 400);

  async function boot() {
    const { instance } = await WebAssembly.instantiate(bytes, {}); V = instance.exports; vio = bind(V);
    const timeout = new Promise(r => setTimeout(() => r(null), 4000));
    try { db = await Promise.race([window.claude?.use ? window.claude.use("db") : Promise.resolve(null), timeout]); } catch (e) { db = null; }
    let saved = "";
    if (db) {
      try {
        const lease = await db.doc("being/lock").acquire({ holder: tabId, ttlMs: 60000 });
        if (!lease.acquired) { mode = "observer"; return watch(); }
        mode = "owner";
        setInterval(() => db.doc("being/lock").acquire({ holder: tabId, ttlMs: 60000 }).catch(() => {}), 30000);
        const d = await db.doc("being/state").get(); if (d.exists) saved = JSON.stringify(d.data());
      } catch (e) { mode = "local"; }
    } else mode = "local";
    if (!saved) { try { saved = localStorage.getItem("being-state") || ""; } catch (e) {} }
    startWorker(saved);
    setInterval(requestSave, 60000);
  }
  function watch() {
    saveCode = 6;
    db.doc("being/state").onSnapshot(d => { if (d.exists) { V.v_watch(...vio.put(JSON.stringify(d.data()))); render(); } }, () => {});
  }

  // presence of the person: the rule (visible, focused, used within 60 s) is in Rust
  function sendPresence(force) {
    if (!V) return;
    const p = V.v_presence(document.visibilityState === "visible" ? 1 : 0, document.hasFocus() ? 1 : 0, Date.now() - lastInput) === 1;
    if (p !== present || force) { present = p; send("counting", p ? 1 : 0); }
  }

  $("run").onclick = () => send("toggle_run");
  $("speed").oninput = () => { dragging = true; $("speedv").textContent = $("speed").value; send("set_speed", +$("speed").value); };
  $("speed").onchange = () => { dragging = false; requestSave(); };
  $("stasis").onclick = () => send("stasis");
  $("reverse").onclick = () => { send("reverse"); saveSoon(); };
  $("observer").onchange = render;
  const flash = k => { const b = $("pad" + k); if (!b) return; b.classList.add("flash"); setTimeout(() => b.classList.remove("flash"), 160); };
  const gesture = k => { if (mode === "observer" || !worker) return; send("gesture", k); flash(k); };
  for (let k = 1; k <= 4; k++) $("pad" + k).onclick = () => gesture(k);
  addEventListener("keydown", e => { if (e.target.closest && e.target.closest("input, select, textarea")) return; if (/^[1-4]$/.test(e.key) && !e.repeat) gesture(+e.key); });
  $("autoStart").onclick = () => { if (mode === "observer") return; send("auto_start"); saveSoon(); };
  $("autoStop").onclick = () => { if (mode === "observer") return; send("auto_stop"); saveSoon(); };
  document.querySelectorAll("input[name=mode]").forEach(r => r.onchange = () => { if (r.checked) { send("mode", r.value); saveSoon(); } });
  $("revealBtn").onclick = () => { reveal = !reveal; send("reveal", reveal ? 1 : 0); render(); };
  $("clearStats").onclick = () => send("clear_stats");
  $("reset").onclick = () => { $("resetAsk").hidden = false; $("reset").hidden = true; };
  $("resetNo").onclick = () => { $("resetAsk").hidden = true; $("reset").hidden = false; };
  $("resetYes").onclick = () => { $("resetAsk").hidden = true; $("reset").hidden = false; send("reset", Date.now()); saveSoon(); };
  addEventListener("pagehide", requestSave);
  document.addEventListener("visibilitychange", () => { sendPresence(true); if (document.visibilityState === "hidden") requestSave(); });
  ["pointerdown", "pointermove", "keydown", "wheel", "touchstart"].forEach(t => addEventListener(t, () => { lastInput = Date.now(); if (!present) sendPresence(true); }, { passive: true }));
  addEventListener("focus", () => sendPresence(true)); addEventListener("blur", () => sendPresence(true));
  setInterval(() => sendPresence(false), 1000);
  addEventListener("resize", render);
  new MutationObserver(render).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  boot();
})();
