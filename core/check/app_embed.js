// Checks that the app page (app/index.html, v3.6) embeds exactly the WebAssembly module built from rust/ (the module
// whose engine being-tools check and wasm_equiv.js compared with Julia). Usage: node core/check/app_embed.js
const fs = require("fs"), path = require("path"), LAB = path.join(__dirname, "..", "..");
const html = fs.readFileSync(path.join(LAB, "app", "index.html"), "utf8");
const m = html.match(/<script id="wasm" type="application\/octet-stream">\n([A-Za-z0-9+/=]+)\n<\/script>/);
const built = fs.readFileSync(path.join(LAB, "rust/target/wasm32-unknown-unknown/release/being_wasm.wasm"));
const ok = !!m && Buffer.from(m[1], "base64").equals(built);
console.log(ok ? "app/index.html embeds the WebAssembly module built from rust/ exactly" : "app/index.html DIFFERS from the module built from rust/");
process.exit(ok ? 0 : 1);
