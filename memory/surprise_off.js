// surprise.js with surprise=false (regression wrapper: must reproduce turn.js rev. 2).
const S = require("./surprise.js");
module.exports = { ...S, step: (st, b, y, opts) => S.step(st, b, y, { ...opts, surprise: false }) };
