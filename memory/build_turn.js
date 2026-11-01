// Builds engine_turn_src.js (turn_sed.js + life_turn.js, no module lines; turn.js until v3.3) and splices it into index.html.
const fs = require("fs"), strip = s => s.replace(/^module\.exports.*$/m, "");
const src = strip(fs.readFileSync(__dirname + "/turn_sed.js", "utf8")) + "\n" + strip(fs.readFileSync(__dirname + "/life_turn.js", "utf8"));
fs.writeFileSync(__dirname + "/engine_turn_src.js", src);
const html = fs.readFileSync(__dirname + "/index.html", "utf8");
const a = html.indexOf('<script id="engine" type="text/plain">'), z = html.indexOf("</script>", a);
if (a < 0 || z < 0) throw new Error("engine block not found");
fs.writeFileSync(__dirname + "/index.html", html.slice(0, a) + '<script id="engine" type="text/plain">\n' + src + "\n" + html.slice(z));
console.log("engine", src.length, "chars spliced");
