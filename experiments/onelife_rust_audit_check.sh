#!/bin/sh
# S49c (discussion/specs/S49c-interval-audit.md r2; predictions experiments/predictions-rust-onelife-c.md PI1-PI6): the
# step interval of onelife-run (10 s; 0 in the test build, feature fastinterval) and its audit ("<name>.audit", append
# only, chained), read back by "being-tools onelife-audit".
# Usage (from anywhere):
#   sh experiments/onelife_rust_audit_check.sh gates   gates F, I0 (with sh core/check/run.sh), I1, I2; results in the work dir
#   sh experiments/onelife_rust_audit_check.sh smoke   the gates, then PI1 and PI3-PI6 on one life with a short drive (N = 40);
#                                                      results in the work dir (a check of this script, not the evaluation)
#   sh experiments/onelife_rust_audit_check.sh         the gates, then PI1-PI6 on the 8 lives (seeds 627-628 x L2, L2+SF x D1,
#                                                      D3); lines appended to experiments/results-rust-onelife-c.out
# The full mode can be started again after a cut: a PI whose verdict line ("PIk: ...") is already in the results file is
# skipped; every start appends its header (with the PIs skipped) to the file. The gates are run at every start.
# PI2 runs copies of experiments/onelife_rust_check.sh and experiments/onelife_rust_lock_check.sh with their results in
# the work dir and onelife-run from the fast build (the copies' edits are counted and reported).
set -eu
cd "$(dirname "$0")/.."
LAB=$PWD
MODE=${1:-full}
W=$(mktemp -d "${TMPDIR:-/tmp}/onelife-audit.XXXXXX")
BT=$PWD/rust/target/release/being-tools
RUN=$PWD/rust/target/release/onelife-run
FT=$W/fast-target; FRUN=$FT/release/onelife-run
CT=$W/crash-target; CRUN=$CT/release/onelife-run
OLDREV=d5a7f6d
OT=$W/old-target; ORUN=$OT/release/onelife-run
SRC=rust/being-tools/src/bin/onelife-run.rs
GEN=0000000000000000000000000000000000000000000000000000000000000000
case "$MODE" in
  full) OUT=experiments/results-rust-onelife-c.out; N=10000; N0=1999; K=20
        LIVES="627:L2:D1 627:L2:D3 627:L2+SF:D1 627:L2+SF:D3 628:L2:D1 628:L2:D3 628:L2+SF:D1 628:L2+SF:D3" ;;
  smoke) OUT=$W/smoke.out; N=40; N0=10; K=20; LIVES="627:L2:D1" ;;
  gates) OUT=$W/gates.out; N=40; N0=10; K=20; LIVES="627:L2:D1" ;;
  *) echo "usage: onelife_rust_audit_check.sh [gates|smoke]"; exit 2 ;;
esac
touch "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
nof() { od -An -t u8 -j 16 -N 8 "$1" | tr -d ' \n'; }
psha() { "$BT" onelife-info "$1" | sed 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/'; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
shaat() { awk -v n="$2" '$1 == n { print $2 }' "$1"; }
jv() { echo "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p"; }
jvs() { echo "$1" | sed -n "s/.*\"$2\":\(\[[^]]*\]\).*/\1/p"; }
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
done_pi() { [ "$MODE" = full ] && grep -q "^$1: " "$OUT"; }
skipped=""
for p in PI1 PI2 PI3 PI4 PI5 PI6; do if done_pi $p; then skipped="$skipped $p"; fi; done
nstart=$(grep -c '^S49c onelife-run interval and audit check' "$OUT" || true)
say "S49c onelife-run interval and audit check, mode $MODE, start $((nstart + 1)) on this file, work dir $W, $(date '+%Y-%m-%d %H:%M:%S'); PIs already done (skipped):${skipped:- none}"

# ---------- F: the freeze ----------
FZ=experiments/freeze-rust-onelife-c.txt
fs=$(grep ' \.\./discussion/specs/S49c-interval-audit.md$' "$FZ" | tail -1 | awk '{print $1}')
fp=$(grep ' predictions-rust-onelife-c.md$' "$FZ" | tail -1 | awk '{print $1}')
f1=false; [ "$fs" = "$(fsha discussion/specs/S49c-interval-audit.md)" ] && [ "$fp" = "$(fsha experiments/predictions-rust-onelife-c.md)" ] && f1=true
CF=experiments/freeze-rust-onelife-c-code.txt
cfn=0; cfok=0
if [ -f "$CF" ]; then
  while read -r h p; do
    case "$h" in ''|'#'*) continue ;; esac
    cfn=$((cfn + 1)); [ "$(fsha "experiments/$p")" = "$h" ] && cfok=$((cfok + 1))
  done < "$CF"
fi
fg=false
if [ "$f1" = true ]; then fg=true; fi
if [ "$MODE" = full ]; then
  if [ "$cfn" = 0 ] || [ "$cfok" != "$cfn" ]; then fg=false; fi
fi
say "F freeze: spec and predictions as in freeze 1 $f1; code freeze $CF files $cfn, matching $cfok (required in the full mode) -> $fg"

# ---------- I0: builds without warnings, being-core unchanged and without dependencies, sh core/check/run.sh ----------
(cd rust && cargo build --release -p being-tools) > "$W/build.txt" 2>&1
(cd rust && cargo build --release -p being-tools --features fastinterval --target-dir "$FT") > "$W/build-fast.txt" 2>&1
(cd rust && cargo build --release -p being-tools --features crashpoint,fastinterval --target-dir "$CT") > "$W/build-crash.txt" 2>&1
nw=$(grep -c '^warning' "$W/build.txt" || true)
nwf=$(grep -c '^warning' "$W/build-fast.txt" || true)
nwc=$(grep -c '^warning' "$W/build-crash.txt" || true)
ndeps=$(cd rust && cargo tree -p being-core -e normal --prefix none | sort -u | wc -l | tr -d ' ')
ncore=0
for f in onelife.rs matter.rs fdexp.rs sha256.rs; do
  want=$(grep " \.\./rust/being-core/src/$f\$" experiments/freeze-rust-onelife-code.txt | awk '{print $1}')
  [ -n "$want" ] && [ "$(fsha rust/being-core/src/$f)" = "$want" ] && ncore=$((ncore + 1))
done
crs=0; sh core/check/run.sh > "$W/runsh.txt" 2>&1 || crs=$?
i0=false; [ "$nw" = 0 ] && [ "$nwf" = 0 ] && [ "$nwc" = 0 ] && [ "$ndeps" = 1 ] && [ "$ncore" = 4 ] && [ "$crs" = 0 ] && i0=true
say "I0 build: warnings $nw (fastinterval build $nwf, crashpoint+fastinterval build $nwc); being-core crates in its tree $ndeps; being-core files with the S49 sha $ncore of 4; sh core/check/run.sh exit $crs ($W/runsh.txt) -> $i0"

# ---------- I1: the sources (S49 Q2 revised by S49c §1; S49b L1; the audit's tail reaches only the next audit line) ----------
PAT='std::env|env::|SystemTime|Instant|(^|[^A-Za-z0-9_])rand([^A-Za-z0-9_]|$)|std::net|TcpStream|UdpSocket|getenv|env!|option_env!'
LPAT='read\(true\)|read_to_end|read_to_string|fs::read\(&?lp|File::open\(&?lp|fs::read_to'
OKOUT='let mut audit = match Audit::open\(path\) \{$|if let Err\(e\) = audit\.log\(&format!\("(start|wait|begin|end|commit) [^"]*"[^;]*\)\) \{$|return stop\(&mut audit, n, E_[A-Z]+\);$'
INBAD='onelife::|step\(|run_encode|replace\(|(^|[^A-Za-z0-9_])s2([^A-Za-z0-9_]|$)|saves|payload|crash'
# src1 FILE: one line per finding (empty when the file passes)
src1() {
  f=$1
  sed 's/std::env::args()//g' "$f" | grep -nE "$PAT" | sed 's/^/forbidden:/' || true
  grep -vE '^ *//' "$f" > "$W/code.rs"
  grep -oE '[A-Za-z0-9_:]*time::[A-Za-z_]+' "$W/code.rs" | grep -vx 'std::time::Duration' | sed 's/^/time:/' || true
  grep -oE 'thread::[^;]*' "$W/code.rs" | grep -vx 'thread::sleep(INTERVAL)' | sed 's/^/thread:/' || true
  [ "$(grep -o 'thread::sleep(INTERVAL)' "$f" | wc -l | tr -d ' ')" = 1 ] || echo "sleep:count"
  [ "$(grep -o 'std::env::args()' "$f" | wc -l | tr -d ' ')" = 1 ] || echo "args:count"
  grep -nE "$LPAT" "$f" | sed 's/^/lockread:/' || true
  [ "$(grep -oE 'std::fs::read\([^)]*\)' "$f" | sort | tr '\n' ' ')" = 'std::fs::read(&ap) std::fs::read(path) ' ] || echo "fsread:targets"
  [ "$(grep -c '^// ---- audit begin' "$f")" = 1 ] && [ "$(grep -c '^// ---- audit end' "$f")" = 1 ] || echo "region:markers"
  sed '/^\/\/ ---- audit begin/,/^\/\/ ---- audit end/d' "$f" > "$W/outside.rs"
  sed -n '/^\/\/ ---- audit begin/,/^\/\/ ---- audit end/p' "$f" > "$W/inside.rs"
  grep -nE 'tail|chain_tail|audit_line|GENESIS' "$W/outside.rs" | grep -vE '^[0-9]+: *//' | sed 's/^/outside-tail:/' || true
  grep -nE 'audit|Audit' "$W/outside.rs" | grep -vE '^[0-9]+: *//' | sed 's/^[0-9]*: *//' | grep -vE "$OKOUT" | sed 's/^/outside-use:/' || true
  grep -nE "$INBAD" "$W/inside.rs" | grep -vE '^[0-9]+: *//' | sed 's/^/inside-state:/' || true
  [ "$(grep -c 'fn log(&mut self, record: &str) -> Result<(), String> {' "$W/inside.rs")" = 1 ] || echo "log:signature"
}
b1=$(src1 "$SRC")
mkdir -p "$W/neg"
neg() { cp "$SRC" "$W/neg/$1.rs"; }
neg a; echo 'fn _x() { let _ = std::env::var("X"); }' >> "$W/neg/a.rs"
neg b; echo 'fn _x() -> std::time::Instant { std::time::Instant::now() }' >> "$W/neg/b.rs"
neg c; echo 'fn _z(a: &Audit) -> u64 { a.tail.len() as u64 }' >> "$W/neg/c.rs"
neg d; perl -pe 's|^// ---- audit end ----$|fn _w(s: &onelife::OneLife) -> bool { s.dead }\n// ---- audit end ----|' "$SRC" > "$W/neg/d.rs"
neg e; echo 'fn _y(lp: &Path) { let _ = std::fs::read(lp); }' >> "$W/neg/e.rs"
neg f; echo 'fn _v() { std::thread::sleep(Duration::from_secs(1)); }' >> "$W/neg/f.rs"
neg g; sed 's|^        n += 1;$|        n += audit.tail.len() as u64 * 0 + 1;|' "$SRC" > "$W/neg/g.rs"
ncaught=0; negrows=""
for k in a b c d e f g; do
  r=$(src1 "$W/neg/$k.rs" | head -1)
  dif=$(diff "$SRC" "$W/neg/$k.rs" | grep -c '^[<>]' || true)
  if [ -n "$r" ] && [ "$dif" -ge 1 ]; then ncaught=$((ncaught + 1)); fi
  negrows="$negrows $k:[$r]"
done
i1=false; [ -z "$b1" ] && [ "$ncaught" = 7 ] && i1=true
say "I1 sources: findings '$(echo $b1)'; negative controls caught $ncaught of 7 (a std::env::var, b Instant, c tail read outside the audit, d state inside the audit, e fs::read of the lock, f a second sleep, g tail into n):$negrows -> $i1"

# ---------- I2: no fastinterval or crashpoint path in the production build ----------
m0=$(strings "$RUN" | grep -c ONELIFE-CRASHPOINT || true)
m1=$(strings "$CRUN" | grep -c ONELIFE-CRASHPOINT || true)
ndef=$(grep -cE '^default *=' rust/being-tools/Cargo.toml || true)
ncf=$(grep -c '^#\[cfg(feature = "fastinterval")\]$' "$SRC" || true)
ncn=$(grep -c '^#\[cfg(not(feature = "fastinterval"))\]$' "$SRC" || true)
nfa=$(grep -c 'fastinterval' "$SRC" || true)
mkdir -p "$W/i2"
cp rust/being-tools/Cargo.toml "$W/i2/Cargo.toml"; echo 'default = ["fastinterval"]' >> "$W/i2/Cargo.toml"
negdef=false; [ "$(grep -cE '^default *=' "$W/i2/Cargo.toml")" != 0 ] && negdef=true
"$BT" onelife-birth-run 627 L2 "$W/i2/p"; "$BT" onelife-birth-run 627 L2 "$W/i2/f"; "$BT" onelife-birth-run 627 L2 "$W/i2/c"
cc=0; echo "3 2" | "$RUN" "$W/i2/p" --crash 1 1 > /dev/null 2>&1 || cc=$?
ccn=$(nof "$W/i2/p")
t0=$(now); cp0=0; echo "3 2" | "$RUN" "$W/i2/p" > /dev/null 2>&1 || cp0=$?; t1=$(now)
tf0=$(now); cf0=0; echo "3 2" | "$FRUN" "$W/i2/f" > /dev/null 2>&1 || cf0=$?; tf1=$(now)
ck=0; (echo "3 2" | "$CRUN" "$W/i2/c" --crash 1 1 > /dev/null 2>&1) 2> /dev/null || ck=$?
dp=$(echo "$t1 - $t0" | bc); df=$(echo "$tf1 - $tf0" | bc)
slow=$(echo "$dp >= 10" | bc); fast=$(echo "$df < 1" | bc)
i2=false; [ "$m0" = 0 ] && [ "$m1" -ge 1 ] && [ "$ndef" = 0 ] && [ "$ncf" = 1 ] && [ "$ncn" = 1 ] && [ "$cc" = 2 ] && [ "$ccn" = 0 ] && [ "$cp0" = 0 ] && [ "$slow" = 1 ] && [ "$cf0" = 0 ] && [ "$fast" = 1 ] && [ "$ck" = 134 ] && [ "$negdef" = true ] && i2=true
say "I2 production build: crash marker $m0 (crashpoint build $m1); default features in Cargo.toml $ndef (negative control with default = [fastinterval] caught $negdef); cfg lines fastinterval $ncf / not $ncn (lines naming it $nfa); --crash 1 1 refused with exit $cc, n $ccn; one drive in ${dp} s exit $cp0 (fast build ${df} s exit $cf0; crashpoint build --crash 1 1 exit $ck) -> $i2"

if [ "$f1" != true ] || [ "$i0" != true ] || [ "$i1" != true ] || [ "$i2" != true ] || [ "$fg" != true ]; then
  say "gates not all true: the PIs are not run ($(date '+%Y-%m-%d %H:%M:%S'))"
  exit 1
fi
if [ "$MODE" = gates ]; then say "gates done $(date '+%Y-%m-%d %H:%M:%S'); $OUT"; exit 0; fi

# ================= the lives: drives and the Julia reference =================
julia --project=. core/check/onelife_scenarios.jl drives "$W" $N
D1=$W/D1.txt; D3=$W/D3.txt
dfile() { if [ "$1" = D1 ]; then echo "$D1"; else echo "$D3"; fi; }
ofile() { if [ "$1" = D1 ]; then echo "$D3"; else echo "$D1"; fi; }
PTS=$(seq -s, $N0 $((N0 + K)))
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  echo "life $seed $law $(dfile $dr) $N $W/jl-$tag $PTS" > "$W/job-$tag.txt"
  julia --project=. core/check/onelife_scenarios.jl jobs "$W/job-$tag.txt" > "$W/jl-$tag.json" &
done
wait
# ref TAG N: the run file of the Julia save after N drives
ref() { f=$W/ref-$1-$2; [ -f "$f" ] || "$BT" onelife-wrap "$W/jl-$1-$2.save" "$2" "$f"; echo "$f"; }
# commits_ok AUDIT TAG: every commit line's payload SHA-256 is Julia's for its n (prints "ok bad")
commits_ok() { awk '$1 == "commit" { print $2, $3 }' "$1" | while read -r n h; do if [ "$h" = "$(shaat "$W/jl-$2.sha" "$n")" ]; then echo ok; else echo bad; fi; done | sort | uniq -c | awk '{a[$2] = $1} END {print a["ok"] + 0, a["bad"] + 0}'; }
lastfield() { tail -1 "$1" | awk '{print $NF}'; }

# ================= PI1: the interval (production build) =================
if done_pi PI1; then say "skip PI1 (verdict already in $OUT)"; else
say "== PI1: 6 drives at once to the production onelife-run (wall time by this script), saved bytes against the $OLDREV build"
mkdir -p "$W/old"
git archive "$OLDREV" rust | tar -x -C "$W/old"
oldsrc=$(fsha "$W/old/rust/being-tools/src/bin/onelife-run.rs")
oldwant=$(grep ' \.\./rust/being-tools/src/bin/onelife-run.rs$' experiments/freeze-rust-onelife-b-code.txt | awk '{print $1}')
(cd "$W/old/rust" && cargo build --release -p being-tools --target-dir "$OT") > "$W/build-old.txt" 2>&1
oldok=false; [ "$oldsrc" = "$oldwant" ] && [ -x "$ORUN" ] && oldok=true
pi1_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi1/$tag; mkdir -p "$d"
  "$BT" onelife-birth-run $seed $law "$d/r"; : > "$d/r.audit"; "$BT" onelife-birth-run $seed $law "$d/o"
  sed -n 1,6p "$df" > "$d/in"
  t0=$(now); c=0; "$RUN" "$d/r" < "$d/in" > /dev/null 2>&1 || c=$?; t1=$(now)
  co=0; "$ORUN" "$d/o" < "$d/in" > /dev/null 2>&1 || co=$?
  same=false; cmp -s "$d/r" "$d/o" && same=true
  el=$(echo "$t1 - $t0" | bc); ge=$(echo "$el >= 60" | bc); lt=$(echo "$el < 63" | bc)
  a=$("$BT" onelife-audit "$d/r")
  aok=false; [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" starts)" = 1 ] && [ "$(jv "$a" waits)" = 7 ] && [ "$(jv "$a" commits)" = 6 ] && [ "$(jv "$a" ends)" = 1 ] && aok=true
  ok=false; [ "$c" = 0 ] && [ "$co" = 0 ] && [ "$ge" = 1 ] && [ "$same" = true ] && [ "$(nof "$d/r")" = 6 ] && ok=true
  echo "PI1 $tag {\"exit\":$c,\"wall_s\":$el,\"at_least_60\":$ge,\"below_63_observation\":$lt,\"old_build_exit\":$co,\"bytes_same_as_old_build\":$same,\"audit_counts_ok\":$aok,\"pass\":$ok}" > "$d/row"
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (pi1_life $seed $law $dr) &
done
wait
pi1=$oldok
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  v=$(cat "$W/pi1/$tag/row"); say "$v"
  echo "$v" | grep -q '"pass":true' || pi1=false
done
# negative control: the fast build on the same 6 drives is well below 60 s
L1=${LIVES%% *}; seed=${L1%%:*}; r=${L1#*:}; law=${r%%:*}; dr=${r#*:}
"$BT" onelife-birth-run $seed $law "$W/pi1/neg"
t0=$(now); sed -n 1,6p "$(dfile $dr)" | "$FRUN" "$W/pi1/neg" > /dev/null 2>&1; t1=$(now)
eln=$(echo "$t1 - $t0" | bc); negc=$(echo "$eln < 60" | bc)
[ "$negc" = 1 ] || pi1=false
say "PI1: $pi1 (old build $OLDREV source as in freeze-rust-onelife-b-code $oldok; negative control: fast build ${eln} s, below 60 $negc)"
fi

# ================= PI3: the audit chain of an uninterrupted run =================
if done_pi PI3; then say "skip PI3 (verdict already in $OUT)"; else
say "== PI3: an uninterrupted run of N = $N drives from birth (fast build; an empty audit made beside the birth run file)"
pi3_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi3/$tag; mkdir -p "$d"
  "$BT" onelife-birth-run $seed $law "$d/u"; : > "$d/u.audit"
  c=0; sed -n "1,${N}p" "$df" | "$FRUN" "$d/u" > /dev/null 2>&1 || c=$?
  a=$("$BT" onelife-audit "$d/u")
  co=$(commits_ok "$d/u.audit" "$tag")
  fin=false; [ "$(psha "$d/u")" = "$(shaat "$W/jl-$tag.sha" $N)" ] && [ "$(nof "$d/u")" = $N ] && fin=true
  ok=false
  [ "$c" = 0 ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" starts)" = 1 ] && [ "$(jv "$a" waits)" = $((N + 1)) ] && [ "$(jv "$a" begins)" = $N ] && [ "$(jv "$a" commits)" = $N ] && [ "$(jv "$a" ends)" = 1 ] && [ "$(jv "$a" errors)" = 0 ] && [ "$(jv "$a" breaks)" = 0 ] && [ "$co" = "$N 0" ] && [ "$fin" = true ] && [ "$(jv "$a" run_vs_last_commit)" = '"match"' ] && ok=true
  first=$(head -1 "$d/u.audit" | awk '{print $1, $2, $3}')
  echo "PI3 $tag {\"exit\":$c,\"lines\":$(jv "$a" lines),\"chain_ok\":$(jv "$a" chain_ok),\"starts\":$(jv "$a" starts),\"waits\":$(jv "$a" waits),\"begins\":$(jv "$a" begins),\"commits\":$(jv "$a" commits),\"ends\":$(jv "$a" ends),\"errors\":$(jv "$a" errors),\"breaks\":$(jv "$a" breaks),\"commits_julia_ok_bad\":\"$co\",\"final_is_julia\":$fin,\"run_vs_last_commit\":$(jv "$a" run_vs_last_commit),\"first_line\":\"$first\",\"pass\":$ok}" > "$d/row"
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (pi3_life $seed $law $dr) &
done
wait
pi3=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  v=$(cat "$W/pi3/$tag/row"); say "$v"
  echo "$v" | grep -q '"pass":true' || pi3=false
done
# negative controls: one hex digit of the 2nd commit's payload SHA changed (the chain and the Julia comparison catch it);
# the audit compared with the other drive file's Julia reference
tag=$seed-$law-$dr; nd=$W/pi3/neg; mkdir -p "$nd"; cp "$W/pi3/$tag/u" "$nd/u"
perl -pe 'if (/^commit / && ++$c == 2) { s/^(commit \d+ )(.)/$1 . ($2 eq "0" ? "1" : "0")/e }' "$W/pi3/$tag/u.audit" > "$nd/u.audit"
an=$("$BT" onelife-audit "$nd/u"); con=$(commits_ok "$nd/u.audit" "$tag")
neg1=false; [ "$(jv "$an" chain_ok)" = false ] && [ "$con" != "$N 0" ] && neg1=true
otag=$seed-$law-D3; [ "$dr" = D3 ] && otag=$seed-$law-D1
neg2=skipped
if [ -f "$W/jl-$otag.sha" ]; then cob=$(commits_ok "$W/pi3/$tag/u.audit" "$otag"); neg2=false; [ "$cob" != "$N 0" ] && neg2=true; fi
[ "$neg1" = true ] || pi3=false
[ "$neg2" = false ] && pi3=false
say "PI3: $pi3 (negative controls on $tag: changed commit caught $neg1 (chain_ok $(jv "$an" chain_ok), commits $con); against the other drive's reference caught $neg2)"
fi

# ================= PI4: unfinished steps and stops =================
if done_pi PI4; then say "skip PI4 (verdict already in $OUT)"; else
say "== PI4: from n = $N0: crash points 1-4 at the 2nd save, a SIGKILL while waiting for input, then the run to n = $((N0 + K))"
pi4_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi4/$tag; mkdir -p "$d"
  f=$d/run; cp "$(ref $tag $N0)" "$f"; : > "$f.audit"
  end=$((N0 + K)); rows=""; okall=true
  for s in 1 2 3 4; do
    n=$(nof "$f")
    c=0; sed -n "$((n + 1)),${end}p" "$df" | "$CRUN" "$f" --crash $s 2 > /dev/null 2>&1 || c=$?
    if [ $s -lt 4 ]; then want=$((n + 1)); else want=$((n + 2)); fi
    same=false; cmp -s "$f" "$(ref $tag $want)" && same=true
    [ "$c" = 134 ] && [ "$same" = true ] || okall=false
    rows="$rows{\"stage\":$s,\"exit\":$c,\"n\":$(nof "$f"),\"file_is_version\":$want,\"complete_version\":$same},"
  done
  n=$(nof "$f"); fifo=$d/fifo; mkfifo "$fifo"
  "$FRUN" "$f" < "$fifo" > /dev/null 2>&1 &
  pid=$!
  exec 9> "$fifo"
  sed -n "$((n + 1)),$((n + 2))p" "$df" >&9
  i=0
  while [ $i -lt 2000 ]; do
    if [ "$(nof "$f")" = $((n + 2)) ] && tail -1 "$f.audit" | grep -q "^wait $((n + 3)) "; then break; fi
    sleep 0.05; i=$((i + 1))
  done
  kill -9 $pid 2> /dev/null || true
  ck=0; wait $pid || ck=$?
  exec 9>&-
  rm -f "$fifo"
  kn=$(nof "$f")
  [ "$ck" = 137 ] && [ "$kn" = $((n + 2)) ] || okall=false
  n=$(nof "$f")
  cr=0; sed -n "$((n + 1)),${end}p" "$df" | "$FRUN" "$f" > /dev/null 2>&1 || cr=$?
  fin=false; cmp -s "$f" "$(ref $tag $end)" && fin=true
  a=$("$BT" onelife-audit "$f"); co=$(commits_ok "$f.audit" "$tag")
  ok=false
  [ "$okall" = true ] && [ "$cr" = 0 ] && [ "$fin" = true ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" breaks)" = 0 ] && [ "$(jv "$a" starts)" = 6 ] && [ "$(jv "$a" unfinished_steps)" = 3 ] && [ "$(jv "$a" audit_behind)" = 1 ] && [ "$(jv "$a" unknown_stops)" = 1 ] && [ "$(jv "$a" stops_without_end)" = 5 ] && [ "$(jv "$a" ends)" = 1 ] && [ "$(jv "$a" errors)" = 0 ] && [ "$(jv "$a" unclassified)" = 0 ] && [ "$(jv "$a" open)" = false ] && [ "$(jv "$a" run_vs_last_commit)" = '"match"' ] && [ "${co#* }" = 0 ] && ok=true
  # control: the same drives uninterrupted; the tool reports no unfinished step and no stop
  u=$d/u; cp "$(ref $tag $N0)" "$u"; : > "$u.audit"
  cu=0; sed -n "$((N0 + 1)),${end}p" "$df" | "$FRUN" "$u" > /dev/null 2>&1 || cu=$?
  au=$("$BT" onelife-audit "$u")
  ctl=false; [ "$cu" = 0 ] && [ "$(jv "$au" unfinished_steps)" = 0 ] && [ "$(jv "$au" unknown_stops)" = 0 ] && [ "$(jv "$au" stops_without_end)" = 0 ] && [ "$(jv "$au" audit_behind)" = 0 ] && cmp -s "$u" "$f" && ctl=true
  [ "$ctl" = true ] || ok=false
  echo "PI4 $tag {\"crashes\":[${rows%,}],\"kill_while_waiting_exit\":$ck,\"n_at_kill\":$kn,\"resume_exit\":$cr,\"end_same_as_uninterrupted\":$fin,\"audit\":{\"chain_ok\":$(jv "$a" chain_ok),\"breaks\":$(jv "$a" breaks),\"starts\":$(jv "$a" starts),\"unfinished_steps\":$(jv "$a" unfinished_steps),\"audit_behind\":$(jv "$a" audit_behind),\"unknown_stops\":$(jv "$a" unknown_stops),\"stops_without_end\":$(jv "$a" stops_without_end),\"ends\":$(jv "$a" ends),\"unclassified\":$(jv "$a" unclassified),\"sequence\":$(jvs "$a" sequence)},\"commits_julia_ok_bad\":\"$co\",\"control_uninterrupted_clean\":$ctl,\"pass\":$ok}" > "$d/row"
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (pi4_life $seed $law $dr) &
done
wait
pi4=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  v=$(cat "$W/pi4/$tag/row"); say "$v"
  echo "$v" | grep -q '"pass":true' || pi4=false
done
say "PI4: $pi4"
fi

# ================= PI5: rollback and tampering; two audits with different tails =================
if done_pi PI5; then say "skip PI5 (verdict already in $OUT)"; else
say "== PI5: from n = $N0, 10 drives, the tampering, then the run to n = $((N0 + K)) (fast build)"
pi5_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi5/$tag; mkdir -p "$d"
  end=$((N0 + K)); mid=$((N0 + 10)); R=$(ref $tag $end); rows=""; okall=true
  for v in rollback bitflip delete_line delete_file unreadable; do
    f=$d/$v; cp "$(ref $tag $N0)" "$f"; : > "$f.audit"
    c1=0; sed -n "$((N0 + 1)),${mid}p" "$df" | "$FRUN" "$f" > /dev/null 2>&1 || c1=$?
    case $v in
      rollback) rm -f "$f"; cp "$(ref $tag $((N0 + 5)))" "$f" ;;
      bitflip) perl -e 'local $/; open(F, "+<", $ARGV[0]) or die; $b = <F>; @l = split(/\n/, $b); $o = 0; $o += length($l[$_]) + 1 for 0 .. 3; $o += 2; seek(F, $o, 0); $c = substr($b, $o, 1); print F chr(ord($c) ^ 1); close F' "$f.audit" ;;
      delete_line) sed '3d' "$f.audit" > "$d/tmp"; cat "$d/tmp" > "$f.audit" ;;
      delete_file) rm -f "$f.audit" ;;
      unreadable) chmod 200 "$f.audit" ;;
    esac
    b=$("$BT" onelife-audit "$f")
    n=$(nof "$f")
    c2=0; sed -n "$((n + 1)),${end}p" "$df" | "$FRUN" "$f" > /dev/null 2>&1 || c2=$?
    chmod 600 "$f.audit"
    a=$("$BT" onelife-audit "$f")
    fin=false; cmp -s "$f" "$R" && fin=true
    brk=$(grep '^break ' "$f.audit" | awk '{print $2 ":" ($3 == "'$GEN'" ? "genesis" : "chained")}' | tr '\n' ' ')
    det=false
    case $v in
      rollback) [ "$(jv "$b" run_vs_last_commit)" = '"rollback or audit behind"' ] && [ "$(jv "$a" starts_below_last_commit)" = 1 ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" breaks)" = 0 ] && det=true ;;
      bitflip|delete_line) [ "$(jv "$b" chain_ok)" = false ] && [ "$(jv "$a" chain_ok)" = false ] && [ "$(jv "$a" chain_failures)" = "$(jv "$b" chain_failures)" ] && [ "$brk" = "mismatch:genesis " ] && det=true ;;
      delete_file) [ "$(jv "$b" audit)" = '"missing"' ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$brk" = "missing:genesis " ] && [ "$(head -1 "$f.audit" | awk '{print $1}')" = break ] && det=true ;;
      unreadable) [ "$(jv "$b" audit)" = '"unreadable"' ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$brk" = "unreadable:genesis " ] && det=true ;;
    esac
    ok=false; [ "$c1" = 0 ] && [ "$c2" = 0 ] && [ "$fin" = true ] && [ "$det" = true ] && ok=true
    [ "$ok" = true ] || okall=false
    rows="$rows{\"case\":\"$v\",\"before\":{\"audit\":$(jv "$b" audit),\"chain_ok\":$(jv "$b" chain_ok),\"chain_failures\":$(jv "$b" chain_failures),\"run_vs_last_commit\":$(jv "$b" run_vs_last_commit)},\"run_exit\":$c2,\"after\":{\"chain_ok\":$(jv "$a" chain_ok),\"chain_failures\":$(jv "$a" chain_failures),\"breaks\":\"$brk\",\"starts_below_last_commit\":$(jv "$a" starts_below_last_commit)},\"end_same_as_untampered\":$fin,\"reported\":$det,\"ok\":$ok},"
  done
  # control: no tampering (the tool reports a clean chain and a match)
  f=$d/ctl; cp "$(ref $tag $N0)" "$f"; : > "$f.audit"
  cc=0; sed -n "$((N0 + 1)),${end}p" "$df" | "$FRUN" "$f" > /dev/null 2>&1 || cc=$?
  a=$("$BT" onelife-audit "$f")
  ctl=false; [ "$cc" = 0 ] && cmp -s "$f" "$R" && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" breaks)" = 0 ] && [ "$(jv "$a" run_vs_last_commit)" = '"match"' ] && [ "$(jv "$a" starts_below_last_commit)" = 0 ] && ctl=true
  # two audits with different valid tails (empty; the control's audit) from the same run file and drives
  A=$d/niA; B=$d/niB; cp "$(ref $tag $N0)" "$A"; cp "$(ref $tag $N0)" "$B"; : > "$A.audit"; cp "$f.audit" "$B.audit"
  t0a=$GEN; t0b=$(lastfield "$B.audit")
  sed -n "$((N0 + 1)),${mid}p" "$df" > "$d/in1"; sed -n "$((mid + 1)),${end}p" "$df" > "$d/in2"
  ca=0; "$FRUN" "$A" < "$d/in1" > /dev/null 2>&1 || ca=$?
  cb=0; "$FRUN" "$B" < "$d/in1" > /dev/null 2>&1 || cb=$?
  s1=false; cmp -s "$A" "$B" && cmp -s "$A" "$(ref $tag $mid)" && s1=true
  "$FRUN" "$A" < "$d/in2" > /dev/null 2>&1 || ca=$?
  "$FRUN" "$B" < "$d/in2" > /dev/null 2>&1 || cb=$?
  s2=false; cmp -s "$A" "$B" && cmp -s "$A" "$R" && s2=true
  aA=$("$BT" onelife-audit "$A"); aB=$("$BT" onelife-audit "$B")
  tails=false; [ "$t0a" != "$t0b" ] && [ "$(lastfield "$A.audit")" != "$(lastfield "$B.audit")" ] && tails=true
  ni=false; [ "$ca" = 0 ] && [ "$cb" = 0 ] && [ "$s1" = true ] && [ "$s2" = true ] && [ "$tails" = true ] && [ "$(jv "$aA" breaks)" = 0 ] && [ "$(jv "$aB" breaks)" = 0 ] && [ "$(jv "$aB" chain_ok)" = true ] && ni=true
  ok=false; [ "$okall" = true ] && [ "$ctl" = true ] && [ "$ni" = true ] && ok=true
  echo "PI5 $tag {\"cases\":[${rows%,}],\"control_untampered\":$ctl,\"two_tails\":{\"tails_differ\":$tails,\"same_after_10\":$s1,\"same_after_$K\":$s2,\"exits\":[$ca,$cb],\"pass\":$ni},\"pass\":$ok}" > "$d/row"
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (pi5_life $seed $law $dr) &
done
wait
pi5=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  v=$(cat "$W/pi5/$tag/row"); say "$v"
  echo "$v" | grep -q '"pass":true$\|"pass":true}$' || pi5=false
  echo "$v" | grep -q '"ok":false' && pi5=false
done
say "PI5: $pi5"
fi

# ================= PI6: the audit cannot be written =================
if done_pi PI6; then say "skip PI6 (verdict already in $OUT)"; else
say "== PI6: the audit not writable (valid read-only, broken read-only, mode 000, missing in a read-only directory): exit and the run file"
pi6_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi6/$tag; mkdir -p "$d"
  B=$(ref $tag $N0); sed -n "$((N0 + 1)),$((N0 + 3))p" "$df" > "$d/in"; rows=""; okall=true
  for v in readonly broken_readonly mode000 missing_rodir; do
    dd=$d/$v; mkdir -p "$dd"; f=$dd/run; cp "$B" "$f"; touch "$f.lock"
    case $v in
      readonly) : > "$f.audit"; chmod 400 "$f.audit" ;;
      broken_readonly) echo "not an audit line" > "$f.audit"; chmod 400 "$f.audit" ;;
      mode000) : > "$f.audit"; chmod 000 "$f.audit" ;;
      missing_rodir) chmod 500 "$dd" ;;
    esac
    c=0; "$FRUN" "$f" < "$d/in" > /dev/null 2> "$d/err-$v" || c=$?
    msg=false; grep -q 'audit' "$d/err-$v" && msg=true
    chmod 700 "$dd"; [ -e "$f.audit" ] && chmod 600 "$f.audit"
    same=false; cmp -s "$f" "$B" && same=true
    tmp=false; [ -e "$f.tmp" ] && tmp=true
    ok=false; [ "$c" != 0 ] && [ "$msg" = true ] && [ "$same" = true ] && [ "$tmp" = false ] && ok=true
    [ "$ok" = true ] || okall=false
    rows="$rows{\"case\":\"$v\",\"exit\":$c,\"stopped_on_the_audit\":$msg,\"run_file_unchanged\":$same,\"tmp_left\":$tmp,\"ok\":$ok},"
  done
  # control: a writable audit, the same drives
  dd=$d/control; mkdir -p "$dd"; f=$dd/run; cp "$B" "$f"; : > "$f.audit"
  cc=0; "$FRUN" "$f" < "$d/in" > /dev/null 2>&1 || cc=$?
  ctl=false; [ "$cc" = 0 ] && [ "$(nof "$f")" = $((N0 + 3)) ] && ctl=true
  ok=false; [ "$okall" = true ] && [ "$ctl" = true ] && ok=true
  echo "PI6 $tag {\"cases\":[${rows%,}],\"control_writable\":$ctl,\"pass\":$ok}" > "$d/row"
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (pi6_life $seed $law $dr) &
done
wait
pi6=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  v=$(cat "$W/pi6/$tag/row"); say "$v"
  echo "$v" | grep -q '"pass":true}$' || pi6=false
done
say "PI6: $pi6"
fi

if [ "$MODE" != full ]; then say "smoke done (PI2 not run in this mode) $(date '+%Y-%m-%d %H:%M:%S'); $OUT"; exit 0; fi

# ================= PI2: S49 and S49b with the fast build =================
if done_pi PI2; then say "skip PI2 (verdict already in $OUT)"; else
say "== PI2: copies of experiments/onelife_rust_check.sh (whole) and experiments/onelife_rust_lock_check.sh (without its PL4, which is the S49 run) with onelife-run from the fast build, $(date '+%H:%M:%S')"
P=$W/pi2; mkdir -p "$P"; F2=$P/fast-target
RES="experiments/results-rust-onelife.out experiments/results-rust-onelife.json experiments/results-rust-onelife-b.out"
shasum -a 256 $RES > "$P/results-before.txt"
sed -e "s|^cd \"\$(dirname \"\$0\")/..\"\$|cd \"$LAB\"|" \
    -e "s|OUT=experiments/results-rust-onelife.out; JSONF=experiments/results-rust-onelife.json|OUT=$P/s49.out; JSONF=$P/s49.json|" \
    -e "s|^RUN=\$PWD/rust/target/release/onelife-run\$|RUN=$F2/release/onelife-run|" \
    -e "s|cargo build --release -p being-tools) > \"\$W/build.txt\"|cargo build --release -p being-tools --features fastinterval --target-dir \"$F2\") > \"\$W/build.txt\"|" \
    -e "s|--features crashpoint --target-dir \"\$CT\"|--features crashpoint,fastinterval --target-dir \"\$CT\"|" \
    experiments/onelife_rust_check.sh > "$P/onelife_rust_check.sh"
sed -e "s|^cd \"\$(dirname \"\$0\")/..\"\$|cd \"$LAB\"|" \
    -e "s|OUT=experiments/results-rust-onelife-b.out; JSONF=experiments/results-rust-onelife-b.json|OUT=$P/s49b.out; JSONF=$P/s49b.json|" \
    -e "s|^RUN=\$PWD/rust/target/release/onelife-run\$|RUN=$F2/release/onelife-run|" \
    -e "s|cargo build --release -p being-tools) > \"\$W/build.txt\"|cargo build --release -p being-tools --features fastinterval --target-dir \"$F2\") > \"\$W/build.txt\"|" \
    -e "s|--features nolock --target-dir \"\$NT\"|--features nolock,fastinterval --target-dir \"\$NT\"|" \
    -e '/^# ================= PL4/,/^cp "\$R4"/d' \
    experiments/onelife_rust_lock_check.sh > "$P/onelife_rust_lock_check.sh"
e49=$(diff experiments/onelife_rust_check.sh "$P/onelife_rust_check.sh" | grep -c '^>' || true)
e49d=$(diff experiments/onelife_rust_check.sh "$P/onelife_rust_check.sh" | grep -c '^<' || true)
e49b=$(diff experiments/onelife_rust_lock_check.sh "$P/onelife_rust_lock_check.sh" | grep -c '^>' || true)
e49bd=$(diff experiments/onelife_rust_lock_check.sh "$P/onelife_rust_lock_check.sh" | grep -c '^<' || true)
p4a=$(grep -n '^# ================= PL4' experiments/onelife_rust_lock_check.sh | cut -d: -f1)
p4b=$(grep -n '^cp "\$R4"' experiments/onelife_rust_lock_check.sh | cut -d: -f1)
left=$(cat "$P/onelife_rust_check.sh" "$P/onelife_rust_lock_check.sh" | grep -v '^#' | grep -c 'rust/target/release/onelife-run\|experiments/results-rust-onelife\.\|experiments/results-rust-onelife-b\.\|onelife_rust_check\.sh"' || true)
cpok=false; [ "$e49" = 5 ] && [ "$e49d" = 5 ] && [ "$e49b" = 5 ] && [ "$e49bd" = $((5 + p4b - p4a + 1)) ] && [ "$left" = 0 ] && cpok=true
say "PI2 copies: S49 lines changed $e49 (removed $e49d); S49b lines changed $e49b (removed $e49bd = 5 + PL4 lines $p4a-$p4b); old paths left $left -> $cpok"
c49=copy; c49b=copy
if [ "$cpok" = true ]; then
  c49=0; sh "$P/onelife_rust_check.sh" > "$P/s49-stdout.txt" 2>&1 || c49=$?
  say "PI2 S49 copy: exit $c49 ($(date '+%H:%M:%S'); $P/s49.out)"
  c49b=0; sh "$P/onelife_rust_lock_check.sh" > "$P/s49b-stdout.txt" 2>&1 || c49b=$?
  say "PI2 S49b copy: exit $c49b ($(date '+%H:%M:%S'); $P/s49b.out)"
fi
shasum -a 256 $RES > "$P/results-after.txt"
rsame=false; cmp -s "$P/results-before.txt" "$P/results-after.txt" && rsame=true
cp "$P/s49.out" experiments/results-rust-onelife-c-pi2-s49.out 2> /dev/null || true
cp "$P/s49b.out" experiments/results-rust-onelife-c-pi2-s49b.out 2> /dev/null || true
R4=$P/s49.out; R5=$P/s49b.out
npr=0
for k in 'PR1: true' 'PR2: true' 'PR5: true'; do grep -qx "$k" "$R4" 2> /dev/null && npr=$((npr + 1)); done
grep -q '^PR3: true ' "$R4" 2> /dev/null && npr=$((npr + 1))
grep -q '^PR4: true ' "$R4" 2> /dev/null && npr=$((npr + 1))
pr6=false; grep -q '^PR6: .* -> true$' "$R4" 2> /dev/null && pr6=true
qs=""
for k in Q1 Q2 Q3 Q4 Q5 Q6; do
  qt=$(grep "^$k " "$R4" 2> /dev/null | grep -c -- '-> true' || true)
  qf=$(grep "^$k " "$R4" 2> /dev/null | grep -c -- '-> false' || true)
  if [ "$qt" -ge 1 ] && [ "$qf" = 0 ]; then qs="$qs $k:true"; else qs="$qs $k:false"; fi
done
npl=0
for k in 'PL1: true' 'PL2: true' 'PL3: true' 'PL5: true'; do grep -qx "$k" "$R5" 2> /dev/null && npl=$((npl + 1)); done
ls=""
for k in 'L0:-> true$' 'L1:-> true;' 'L2:-> true$' 'L2b:caught true$'; do
  g=${k%%:*}; e=${k#*:}
  if grep "^$g " "$R5" 2> /dev/null | grep -q -- "$e"; then ls="$ls $g:true"; else ls="$ls $g:false"; fi
done
# PL4 (the S49 check with the new onelife-run) read from the S49 copy: Q2 as revised by S49c §1 is gate I1 of this run
q_other=true
for k in Q1 Q3 Q4 Q5 Q6; do echo "$qs" | grep -q " $k:true" || q_other=false; done
pl4=false; [ "$c49" = 0 ] && [ "$npr" = 5 ] && [ "$pr6" = true ] && [ "$q_other" = true ] && [ "$i1" = true ] && [ "$rsame" = true ] && pl4=true
pi2=false; [ "$cpok" = true ] && [ "$c49" = 0 ] && [ "$c49b" = 0 ] && [ "$npr" = 5 ] && [ "$npl" = 4 ] && [ "$pl4" = true ] && [ "$rsame" = true ] && pi2=true
say "PI2 detail: S49 PR1-PR5 true $npr of 5, PR6 $pr6; gates$qs (Q2 is the S49 pattern, which names std::time: superseded by I1); S49b PL1 PL2 PL3 PL5 true $npl of 4; gates$ls (L1 is the S49b pattern: superseded by I1); PL4 from the S49 copy (Q1 Q3-Q6 true, Q2 by I1) $pl4; S49 and S49b results files unchanged $rsame"
say "PI2: $pi2 ($(date '+%H:%M:%S'))"
fi

say "done $(date '+%Y-%m-%d %H:%M:%S'); $OUT"
