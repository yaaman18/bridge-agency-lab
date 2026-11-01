// Builds engine_partner_src.js (partner.js + life_partner.js, no module lines) and splices it into index.html.
const fs = require("fs"), strip = s => s.replace(/^module\.exports.*$/m, "");
const src = strip(fs.readFileSync(__dirname + "/partner.js", "utf8")) + "\n" + strip(fs.readFileSync(__dirname + "/life_partner.js", "utf8"));
fs.writeFileSync(__dirname + "/engine_partner_src.js", src);
const html = fs.readFileSync(__dirname + "/index.html", "utf8");
const a = html.indexOf('<script id="engine" type="text/plain">'), z = html.indexOf("</script>", a);
if (a < 0 || z < 0) throw new Error("engine block not found");
fs.writeFileSync(__dirname + "/index.html", html.slice(0, a) + '<script id="engine" type="text/plain">\n' + src + "\n" + html.slice(z));
console.log("engine", src.length, "chars spliced");
