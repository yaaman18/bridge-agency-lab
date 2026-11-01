#!/bin/sh
# Evaluates Lean's own Window.checkDC (and each clause) on the windows exported by audit/dc_run.jl and compares them with
# the Julia verdicts (formal/gen/expected.json). Compiles formal/LabCircuit.lean to formal/.olean first.
set -e
LAB="$(cd "$(dirname "$0")/.." && pwd)"; BP="$HOME/bridge-protocol"; OL="$LAB/formal/.olean"
sh "$LAB/formal/check.sh" > /dev/null
cd "$BP"
lake env sh -c "LEAN_PATH=\"\$LEAN_PATH:$OL\" lean --root=\"$LAB/formal\" -o \"$OL/LabCircuit.olean\" \"$LAB/formal/LabCircuit.lean\"" > /dev/null
lake env sh -c "LEAN_PATH=\"\$LEAN_PATH:$OL\" lean \"$LAB/formal/gen/Windows.lean\"" > "$LAB/formal/gen/lean-output.txt"
node -e '
const fs = require("fs"), dir = process.argv[1];
const got = fs.readFileSync(dir + "/lean-output.txt", "utf8").trim().split("\n").map(l => JSON.parse(l));
const exp = JSON.parse(fs.readFileSync(dir + "/expected.json", "utf8"));
const same = got.length === exp.length && got.every((g, i) => JSON.stringify(g) === JSON.stringify(exp[i]));
console.log(`Lean checkDC on ${got.length} windows: ${same ? "identical to Julia" : "DIFFERENT from Julia"}; verdicts (self, smc, act, bound, dc) ${JSON.stringify(got)}`);
process.exit(same ? 0 : 1);' "$LAB/formal/gen"
