#!/bin/sh
# The whole check (about 2 minutes). The canonical rules are Julia (core/); checked against them bit for bit:
#   the app's engine in Rust (rust/being-core, native and as the WebAssembly module the page runs), and
#   the JavaScript copies (memory/, matter/: the history of results and app versions up to v3.5).
# Also: V8's arithmetic, the stage 42 results file, and that app/index.html embeds the module built from rust/.
# Run from anywhere: sh core/check/run.sh
set -e
# compare A B: every pair must be identical (prints the summary line, or every line on a difference)
compare() { if out=$(node core/check/compare.js --a "$1" --b "$2" $3); then echo "$out" | tail -1; else echo "$out"; exit 1; fi; }
cd "$(dirname "$0")/../.."
node core/check/math.js > /dev/null
julia --project=. core/check/math.jl
node core/check/js_scenarios.js > /dev/null
julia --project=. core/check/jl_scenarios.jl > /dev/null
echo "== JavaScript copies against Julia"
compare js jl
echo "== Rust (the app's engine) against Julia"
rm -f core/check/out/rs-*.json   # the Rust scenarios are written afresh (names change with the app rule)
(cd rust && cargo build --release -q -p being-tools && cargo build --release -q -p being-wasm --target wasm32-unknown-unknown)
rust/target/release/being-tools check
compare rs jl
node core/check/wasm_equiv.js
compare wasm native wasm-equiv
node core/check/app_embed.js
julia --project=. core/check/reproduce_body_org.jl
echo "== OneLife (S49): Rust (rust/being-core/src/onelife.rs) against Julia (core/one_life.jl), seed 627, L2 and L2+SF, D3, 3000 drives"
julia --project=. core/check/onelife_scenarios.jl scene > /dev/null
for law in L2 L2+SF; do
  r=$(rust/target/release/being-tools onelife-check 627 $law core/check/out/onelife-drives/D3.txt 3000 core/check/out/onelife-rs-627-$law-D3)
  cmp core/check/out/onelife-jl-627-$law-D3.sha core/check/out/onelife-rs-627-$law-D3.sha
  cmp core/check/out/onelife-jl-627-$law-D3-3000.save core/check/out/onelife-rs-627-$law-D3-3000.save
  echo "$law: the saves after n = 0..3000 drives identical; $r"
done
