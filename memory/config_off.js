// config.js with configural=false (regression wrapper: must reproduce turn.js rev. 2).
const C = require("./config.js");
module.exports = { ...C, newborn: (partner = true, proprio = partner) => C.newborn(partner, proprio, false) };
