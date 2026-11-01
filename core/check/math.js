// Writes 400,000 inputs in the ranges the rules use, with V8's exp, tanh, log, cos and hypot of them, as hex bits
// (out/math-v8.txt); math.jl checks core/jsmath.jl against them. Usage: node core/check/math.js
const fs = require("fs"), path = require("path");
let s = 12345; const r = () => { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648; };
const dv = new DataView(new ArrayBuffer(8)), hx = x => { dv.setFloat64(0, x); return dv.getBigUint64(0).toString(16).padStart(16, "0"); };
const lines = [];
for (let i = 0; i < 400000; i++) {
  const a = (r() - 0.5) * 60, b = (r() - 0.5) * 8, c = r() + 1e-12, d = 2 * Math.PI * r(), e = Math.round((r() - 0.5) * 8), f = Math.round((r() - 0.5) * 8);
  lines.push([a, Math.exp(a), b, Math.tanh(b), c, Math.log(c), d, Math.cos(d), e, f, Math.hypot(e, f)].map(hx).join(" "));
}
fs.mkdirSync(path.join(__dirname, "out"), { recursive: true });
fs.writeFileSync(path.join(__dirname, "out", "math-v8.txt"), lines.join("\n"));
console.log("wrote", lines.length, "lines");
