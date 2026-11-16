#!/bin/sh
# S60 gate G-ii (spec discussion/specs/S60-trm-det.md §3): on the Mac, the canonical Julia (run_det.jl) and the Rust
# copy (rust/trm-det, release) give byte-identical outputs for the six bundles; negative controls m1..m4 and a
# type-tag control must be caught. Writes experiments/results-trm-det-ii.out; exit 1 on any failure.
# r2 (codex I-R 4): every output goes to a fresh run directory; every generating step's exit code is checked and a
# control counts only if its generation succeeded. GATE_SELFTEST=1 makes the m1 generation fail on purpose (missing
# bundle); the gate must then end FAILED (results go to results-trm-det-ii-selftest.out).
set -u
cd "$(dirname "$0")"
D=$(pwd)
R=$D/../../../rust/trm-det
SELF=${GATE_SELFTEST:-0}
if [ "$SELF" = 1 ]; then RES=$D/../../results-trm-det-ii-selftest.out; else RES=$D/../../results-trm-det-ii.out; fi
JL="julia --project=$D/../../.."
NAMES="a_W0 a_W1 b_W0 b_W1 e_W0 e_W1"
RUN=out/run-$(date +%Y%m%d-%H%M%S)-$$
[ ! -e "$RUN" ] || { echo "run dir exists"; exit 1; }
mkdir -p "$RUN"
: > "$RES"
log() { echo "$*" | tee -a "$RES"; }
fail=0
log "S60 G-ii r2: Julia det vs Rust (Mac $(uname -m)), byte and element identity; run dir $RUN; selftest $SELF; $(date '+%Y-%m-%d %H:%M:%S')"
(cd "$R" && cargo build --release) > "$RUN/build-mac.txt" 2>&1 || { log "cargo build FAILED"; exit 1; }
nw=$(grep -c '^warning' "$RUN/build-mac.txt" || true)
BIN=$R/target/release/trm-det
log "rust build warnings $nw; binary sha $(shasum -a 256 "$BIN" | awk '{print $1}')"
[ "$nw" = 0 ] || fail=1
args=""
for n in $NAMES; do args="$args bundles/$n.bin $RUN/$n.jl.bin"; done
$JL run_det.jl $args 2> "$RUN/julia.time" || { log "run_det.jl FAILED"; fail=1; }
cat "$RUN/julia.time" >> "$RES"
for n in $NAMES; do
  "$BIN" "bundles/$n.bin" "$RUN/$n.rs.bin" 2> "$RUN/$n.rs.time" || { log "rust $n FAILED"; fail=1; }
  log "rust mac $n: $(tr '\n' ' ' < "$RUN/$n.rs.time")"
done
trip=""
for n in $NAMES; do trip="$trip bundles/$n.bin $RUN/$n.jl.bin $RUN/$n.rs.bin"; done
$JL compare_bin.jl $trip > "$RUN/compare-mac.txt"
rc=$?
tee -a "$RES" < "$RUN/compare-mac.txt"
[ "$rc" = 0 ] || fail=1
for n in $NAMES; do log "sha256 $n jl $(shasum -a 256 "$RUN/$n.jl.bin" | awk '{print $1}') rs $(shasum -a 256 "$RUN/$n.rs.bin" | awk '{print $1}')"; done
# negative controls: generation must succeed, then the comparison must report differing elements (structure intact), exit 1
caught=0
ctl() { # label generation-rc bundle-for-layout reference candidate
  if [ "$2" != 0 ]; then log "$1 generation FAILED (rc $2): not counted"; fail=1; return; fi
  o=$($JL compare_bin.jl "$3" "$4" "$5"); c=$?
  echo "$o" | sed -n 1p | sed "s/^/$1: /" | tee -a "$RES"
  if [ "$c" = 1 ] && echo "$o" | grep -q 'differing [1-9]' && ! echo "$o" | grep -q 'FAILED structure'; then
    log "$1 caught"; caught=$((caught + 1)); else log "$1 NOT CAUGHT"; fi
}
M1B=bundles/a_W1.bin
[ "$SELF" = 1 ] && M1B=$RUN/missing-on-purpose.bin
"$BIN" "$M1B" "$RUN/m1.rs.bin" --mutate linear_rev 2> /dev/null; g=$?
ctl "m1 linear_rev (a_W1)" "$g" bundles/a_W1.bin "$RUN/a_W1.jl.bin" "$RUN/m1.rs.bin"
"$BIN" bundles/a_W1.bin "$RUN/m2.rs.bin" --mutate softmax_rev 2> /dev/null; g=$?
ctl "m2 softmax_rev (a_W1)" "$g" bundles/a_W1.bin "$RUN/a_W1.jl.bin" "$RUN/m2.rs.bin"
$JL mutate_bin.jl m3 bundles/a_W1.bin "$RUN/a_W1.m3.bin" > "$RUN/m3.txt"; g=$?
cat "$RUN/m3.txt" >> "$RES"
[ "$g" = 0 ] && { "$BIN" "$RUN/a_W1.m3.bin" "$RUN/m3.rs.bin" 2> /dev/null; g=$?; }
ctl "m3 rope.cos[1,0] +1ulp (a_W1)" "$g" bundles/a_W1.bin "$RUN/a_W1.jl.bin" "$RUN/m3.rs.bin"
$JL mutate_bin.jl m4 bundles/b_W1.bin "$RUN/b_W1.m4.bin" > "$RUN/m4.txt"; g=$?
cat "$RUN/m4.txt" >> "$RES"
[ "$g" = 0 ] && { "$BIN" "$RUN/b_W1.m4.bin" "$RUN/m4.rs.bin" 2> /dev/null; g=$?; }
ctl "m4 embed_tokens[t,0] +1ulp (b_W1)" "$g" bundles/b_W1.bin "$RUN/b_W1.jl.bin" "$RUN/m4.rs.bin"
log "negative controls caught: $caught/4"
[ "$caught" = 4 ] || fail=1
# type-tag control (codex S-R 3): same payload, logits marked i32 -> structure failure, exit 1
$JL mutate_bin.jl settag "$RUN/a_W1.jl.bin" "$RUN/a_W1.settag.bin" step1.logits > "$RUN/settag.txt"; g=$?
cat "$RUN/settag.txt" >> "$RES"
if [ "$g" = 0 ]; then
  o=$($JL compare_bin.jl bundles/a_W1.bin "$RUN/a_W1.jl.bin" "$RUN/a_W1.settag.bin"); c=$?
  echo "$o" | sed -n 1p | tee -a "$RES"
  if [ "$c" = 1 ] && echo "$o" | grep -q 'FAILED structure'; then log "type-tag control caught"; else log "type-tag control NOT CAUGHT"; fail=1; fi
else
  log "type-tag generation FAILED"; fail=1
fi
[ "$fail" = 0 ] && log "ALL PASS" || log "FAILED"
exit $fail
