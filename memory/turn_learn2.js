// turn_learn2.js (2026-10-31, stage 50): turn_sed.js with opts.contrast = "learn2" by default, so that the harnesses of
// the organization layer that take a core by CORE=... (test_scaffold.js, ...) can run the contrast rule unchanged.
const T = require("./turn_sed.js");
module.exports = { ...T, step: (st, b, y, opts = {}) => T.step(st, b, y, { ...opts, contrast: opts.contrast ?? "learn2" }) };
