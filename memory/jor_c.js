// surprise3.js with jorient="c" (stage 29 wrapper).
const S = require("./surprise3.js");
module.exports = { ...S, step: (st, b, y, opts) => S.step(st, b, y, { ...opts, jorient: "c" }) };
