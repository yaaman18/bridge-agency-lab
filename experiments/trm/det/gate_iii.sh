#!/bin/sh
# S60 gate G-iii (spec discussion/specs/S60-trm-det.md §3): the Rust copy cross-built on the Mac for
# aarch64-unknown-linux-musl (static, rust-lld) runs on the Pi 5 and gives outputs with the same SHA-256 as the Mac Rust.
# Nothing is compiled on the Pi; only /home/pi/s60/ is written. Exit 3 if the Pi is not safe to use.
# Writes experiments/results-trm-det-iii.out; exit 1 on any failure.
# r2 (codex I-R 5): fresh run directories on both sides (the Mac Rust outputs are made in this run); every build, copy,
# remote run and generation exit code is checked; p1 must succeed and be structurally valid. GATE_SELFTEST=1 makes the
# remote a_W0 run read a missing bundle on purpose; the gate must then end FAILED (results-trm-det-iii-selftest.out).
set -u
cd "$(dirname "$0")"
D=$(pwd)
R=$D/../../../rust/trm-det
SELF=${GATE_SELFTEST:-0}
if [ "$SELF" = 1 ]; then RES=$D/../../results-trm-det-iii-selftest.out; else RES=$D/../../results-trm-det-iii.out; fi
JL="julia --project=$D/../../.."
PI="pi@bridge-pi.local"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 $PI"
NAMES="a_W0 a_W1 b_W0 b_W1 e_W0 e_W1"
T=aarch64-unknown-linux-musl
TS=$(date +%Y%m%d-%H%M%S)-$$
RUN=pi/run-$TS
RD=/home/pi/s60/run-$TS
[ ! -e "$RUN" ] || { echo "run dir exists"; exit 1; }
mkdir -p "$RUN"
: > "$RES"
log() { echo "$*" | tee -a "$RES"; }
fail=0
log "S60 G-iii r2: Pi 5 Rust vs Mac Rust, SHA-256 and element identity; run dirs $RUN and $RD; selftest $SELF; $(date '+%Y-%m-%d %H:%M:%S')"
(cd "$R" && cargo build --release) > "$RUN/build-mac.txt" 2>&1 || { log "mac build FAILED"; exit 1; }
(cd "$R" && CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld cargo build --release --target $T) > "$RUN/build-pi.txt" 2>&1 || { log "cross build FAILED"; exit 1; }
nw=$(cat "$RUN/build-mac.txt" "$RUN/build-pi.txt" | grep -c '^warning' || true)
MB=$R/target/release/trm-det
B=$R/target/$T/release/trm-det
bsha=$(shasum -a 256 "$B" | awk '{print $1}')
ft=$(file -b "$B")
log "build warnings $nw; mac sha $(shasum -a 256 "$MB" | awk '{print $1}'); pi elf sha $bsha; $(echo "$ft" | cut -c1-100)"
[ "$nw" = 0 ] || fail=1
echo "$ft" | grep -q 'ARM aarch64.*statically linked' || { log "not an aarch64 static ELF"; exit 1; }
for n in $NAMES; do
  "$MB" "bundles/$n.bin" "$RUN/$n.rs.bin" 2> /dev/null || { log "mac rust $n FAILED"; exit 1; }
done
# Pi safety (spec §3): throttled must be 0x0 and no trial run active; otherwise stop before any heavy work
th=$($SSH vcgencmd get_throttled) || { log "Pi unreachable"; exit 3; }
pg=$($SSH 'pgrep onelife-run || true') || { log "Pi unreachable"; exit 3; }
log "pi before: $th; pgrep onelife-run: '${pg}'"
[ "$th" = "throttled=0x0" ] || { log "STOP: Pi throttled flag not 0x0"; exit 3; }
[ -z "$pg" ] || { log "STOP: onelife-run is running on the Pi"; exit 3; }
$SSH "mkdir -p /home/pi/s60 && mkdir $RD" || { log "remote mkdir FAILED"; exit 1; }
scp -q -o BatchMode=yes "$B" "$PI:$RD/trm-det" || { log "scp binary FAILED"; exit 1; }
for n in $NAMES; do scp -q -o BatchMode=yes "bundles/$n.bin" "$PI:$RD/$n.bin" || { log "scp $n FAILED"; exit 1; }; done
$SSH "cd $RD && sha256sum trm-det *.bin" > "$RUN/remote-inputs.sha" || { log "remote sha FAILED"; exit 1; }
ok_in=0
grep -q "^$bsha  trm-det\$" "$RUN/remote-inputs.sha" && ok_in=$((ok_in + 1))
for n in $NAMES; do
  s=$(shasum -a 256 "bundles/$n.bin" | awk '{print $1}')
  grep -q "^$s  $n.bin\$" "$RUN/remote-inputs.sha" && ok_in=$((ok_in + 1))
done
log "copies with the Mac sha on the Pi: $ok_in of 7"
[ "$ok_in" = 7 ] || { log "copy check FAILED"; exit 1; }
A0=a_W0.bin
[ "$SELF" = 1 ] && A0=missing-on-purpose.bin
$SSH "cd $RD && chmod +x trm-det && uname -a && for n in $NAMES; do in=\$n.bin; [ \$n = a_W0 ] && in=$A0; t0=\$(date +%s.%N); ./trm-det \$in \$n.pi.bin 2> \$n.pi.time; rc=\$?; t1=\$(date +%s.%N); echo \"run \$n rc=\$rc wall_start=\$t0 wall_end=\$t1 \$(tr '\n' ' ' < \$n.pi.time)\"; done; ./trm-det a_W1.bin p1.pi.bin --mutate softmax_rev 2> /dev/null; echo p1rc=\$?; sha256sum *.pi.bin" > "$RUN/remote-run.txt" 2>&1
src=$?
tee -a "$RES" < "$RUN/remote-run.txt"
[ "$src" = 0 ] || { log "remote run session FAILED (rc $src)"; fail=1; }
nrc=$(grep -c '^run .* rc=0 ' "$RUN/remote-run.txt" || true)
log "remote runs with rc=0: $nrc of 6"
[ "$nrc" = 6 ] || fail=1
nsha=0
for n in $NAMES; do
  m=$(shasum -a 256 "$RUN/$n.rs.bin" | awk '{print $1}')
  p=$(grep " $n.pi.bin\$" "$RUN/remote-run.txt" | awk '{print $1}')
  if [ -n "$p" ] && [ "$m" = "$p" ]; then r=SAME; nsha=$((nsha + 1)); else r=DIFFERENT; fi
  log "sha256 $n mac $m pi $p $r"
done
log "SHA-256 identical: $nsha of 6"
[ "$nsha" = 6 ] || fail=1
nf=0
for n in $NAMES p1; do scp -q -o BatchMode=yes "$PI:$RD/$n.pi.bin" "$RUN/$n.pi.bin" && nf=$((nf + 1)) || log "fetch $n FAILED"; done
log "fetched $nf of 7"
[ "$nf" = 7 ] || fail=1
trip=""
for n in $NAMES; do trip="$trip bundles/$n.bin $RUN/$n.rs.bin $RUN/$n.pi.bin"; done
$JL compare_bin.jl $trip > "$RUN/compare.txt"
rc=$?
tee -a "$RES" < "$RUN/compare.txt"
[ "$rc" = 0 ] || fail=1
caught=0
# p1: the mutated run on the Pi must succeed, be structurally valid and differ from the normal Mac output
p1=$(grep " p1.pi.bin\$" "$RUN/remote-run.txt" | awk '{print $1}')
m=$(shasum -a 256 "$RUN/a_W1.rs.bin" | awk '{print $1}')
o=$($JL compare_bin.jl bundles/a_W1.bin "$RUN/a_W1.rs.bin" "$RUN/p1.pi.bin"); c=$?
echo "$o" | sed -n 1p | sed 's/^/p1: /' | tee -a "$RES"
if grep -q '^p1rc=0$' "$RUN/remote-run.txt" && [ -n "$p1" ] && [ "$p1" != "$m" ] && [ "$c" = 1 ] && echo "$o" | grep -q 'differing [1-9]' && ! echo "$o" | grep -q 'FAILED structure'; then
  log "p1 softmax_rev on the Pi: sha $p1 != mac $m caught"; caught=$((caught + 1)); else log "p1 NOT CAUGHT"; fi
# p2: one payload bit flipped in a copy of the fetched Pi output -> 'differing 1', exit 1
$JL mutate_bin.jl flipbit "$RUN/a_W1.pi.bin" "$RUN/a_W1.pi.flip.bin" step4.logits 0 0 > "$RUN/flip.txt"; g=$?
cat "$RUN/flip.txt" >> "$RES"
if [ "$g" = 0 ]; then
  o=$($JL compare_bin.jl bundles/a_W1.bin "$RUN/a_W1.rs.bin" "$RUN/a_W1.pi.flip.bin"); c=$?
  echo "$o" | sed -n 1p | tee -a "$RES"
  if [ "$c" = 1 ] && echo "$o" | grep -q 'differing 1 ' && ! echo "$o" | grep -q 'FAILED structure'; then log "p2 caught"; caught=$((caught + 1)); else log "p2 NOT CAUGHT"; fi
else
  log "p2 generation FAILED: not counted"
fi
log "negative controls caught: $caught/2"
[ "$caught" = 2 ] || fail=1
log "pi after: $($SSH vcgencmd get_throttled)"
[ "$fail" = 0 ] && log "ALL PASS" || log "FAILED"
exit $fail
