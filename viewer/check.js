// Parity check of sim.js against the Julia reference trajectory (experiments/reference_trace.txt).
const SIM = require("./sim.js"), TYPES = require("./types.js"), fs = require("fs");
const ref = fs.readFileSync(__dirname + "/../experiments/reference_trace.txt", "utf8").trim().split("\n").map(l => l.split(" "));
const season = t => t <= 300 ? [3, 2] : t <= 600 ? [0, 5] : [5, 0];
let bad = 0, n = 0;
for (const name of ["selfloop-pair-agent", "omnivore", "alternator"]) {
  const s = SIM.build(TYPES.find(t => t.name === name)); const st = SIM.init(s); let R = [50, 50];
  const rows = ref.filter(r => r[0] === name);
  for (let t = 1; t <= 1000; t++) {
    const y = [Math.min(R[0], 5), Math.min(R[1], 5)];
    const out = SIM.step(st, s, y, new Set());
    const g = season(t); R = [0, 1].map(i => Math.min(50, R[i] - out.digested[i] + g[i]));
    const mine = [st.active.map(a => a ? 1 : 0).join(""), st.strength.join(","), R.join(",")];
    const theirs = rows[t - 1].slice(2);
    n++; if (mine.join(" ") !== theirs.join(" ")) { if (bad < 5) console.log("MISMATCH", name, t, mine.join(" "), "vs", theirs.join(" ")); bad++; }
  }
}
console.log(`parity: ${n - bad}/${n} steps identical`);
