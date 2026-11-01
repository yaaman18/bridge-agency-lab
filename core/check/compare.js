// Compares core/check/out/<A>-<name>.json with <B>-<name>.json (exact equality of every number, string and boolean)
// and prints the first difference of each pair. A, B default to js and jl (rs = the Rust copy of the app's engine).
// Usage: node core/check/compare.js [--a rs] [--b jl] [name ...]  (default: every <A>-*.json).
const fs = require("fs"), path = require("path"), OUT = path.join(__dirname, "out");
function diff(a, b, p) {
  if (a === b) return null;
  if (typeof a === "number" && typeof b === "number" && Number.isNaN(a) && Number.isNaN(b)) return null;
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return `${p}: ${A} ${JSON.stringify(a)} ${B} ${JSON.stringify(b)}`;
  if (Array.isArray(a) !== Array.isArray(b)) return `${p}: array vs object`;
  if (Array.isArray(a)) { if (a.length !== b.length) return `${p}: length js ${a.length} jl ${b.length}`;
    for (let i = 0; i < a.length; i++) { const d = diff(a[i], b[i], `${p}[${i}]`); if (d) return d; } return null; }
  const ka = Object.keys(a).sort(), kb = Object.keys(b).sort();
  if (ka.join() !== kb.join()) return `${p}: keys js [${ka.filter(k => !kb.includes(k))}] jl [${kb.filter(k => !ka.includes(k))}]`;
  for (const k of ka) { const d = diff(a[k], b[k], `${p}.${k}`); if (d) return d; } return null;
}
const argv = process.argv.slice(2); let A = "js", B = "jl";
for (let i = 0; i < argv.length; i++) if (argv[i] === "--a" || argv[i] === "--b") { if (argv[i] === "--a") A = argv[i + 1]; else B = argv[i + 1]; argv.splice(i, 2); i--; }
const names = argv.length ? argv : fs.readdirSync(OUT).filter(f => f.startsWith(A + "-") && f.endsWith(".json")).map(f => f.slice(A.length + 1, -5)).sort();
let bad = 0;
for (const n of names) {
  const jf = path.join(OUT, B + "-" + n + ".json");
  if (!fs.existsSync(jf)) { console.log(n.padEnd(28), "MISSING " + B + ""); bad++; continue; }
  const d = diff(JSON.parse(fs.readFileSync(path.join(OUT, A + "-" + n + ".json"), "utf8")), JSON.parse(fs.readFileSync(jf, "utf8")), "");
  console.log(n.padEnd(28), d ? "DIFFERENT " + d : "identical"); if (d) bad++;
}
console.log(bad ? `${bad} of ${names.length} differ` : `all ${names.length} identical`);
process.exit(bad ? 1 : 0);
