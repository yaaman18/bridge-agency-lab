#!/bin/sh
# S51 (discussion/specs/S51-other-machine.md r2; predictions experiments/predictions-other-machine.md PM1-PM5): OneLife
# and onelife-run on a Raspberry Pi 5 (aarch64, musl static build cross-compiled on the Mac) against the Mac.
# Usage (from anywhere):
#   sh experiments/other_machine_check.sh smoke   gates F, M0, M1, M2 and the smoke (627-L2-D1, N = 50); results in the work dir
#   sh experiments/other_machine_check.sh         the gates, then PM1-PM5 on the 8 lives (seeds 627-628 x L2, L2+SF x D1, D3,
#                                                 N = 10000); appended to experiments/results-other-machine.out, one block
#                                                 per PM; a PM whose result line is already in that file is skipped
# The executables are built outside the work tree (spec section 2) in $B and are not rebuilt here; their SHA-256 and
# the script's are in experiments/freeze-other-machine-code.txt. Nothing is compiled on the Pi; on the Pi only
# /home/pi/s51/<run> is written.
set -eu
cd "$(dirname "$0")/.."
MODE=${1:-full}
N=10000
B=/var/folders/82/qvmvqs01469ck832bd6f4k280000gn/T/s51-build.0qj5Ke
MBT=$B/target-mac/release/being-tools
MRUN=$B/target-mac/release/onelife-run
PBT=$B/target-pi/aarch64-unknown-linux-musl/release/being-tools
PRUN=$B/target-pi/aarch64-unknown-linux-musl/release/onelife-run
SPEC=discussion/specs/S51-other-machine.md
PRED=experiments/predictions-other-machine.md
FRZ=experiments/freeze-other-machine.txt
CFRZ=experiments/freeze-other-machine-code.txt
BFRZ=experiments/freeze-rust-onelife-b-code.txt
HOST=pi@bridge-pi.local
W=$(mktemp -d "${TMPDIR:-/tmp}/s51-om.XXXXXX")
P=/home/pi/s51/$(basename "$W")
if [ "$MODE" = full ]; then OUT=experiments/results-other-machine.out; else OUT=$W/smoke.out; fi
touch "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
pis() { ssh -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=8 "$HOST" "$@"; }
pi() { pis sh "$P/pi.sh" "$@"; }
info() { "$MBT" onelife-info "$1"; }
nof() { info "$1" | sed 's/^{"n":\([0-9]*\),.*/\1/'; }
jget() { echo "$1" | sed "s/.*\"$2\":\([^,}]*\).*/\1/"; }
# push LOCAL REMOTE_NAME: copy to $P and compare the SHA-256 on both sides (prints true / false)
push() {
  scp -q -o BatchMode=yes "$1" "$HOST:$P/$2"
  r=$(pis sha256sum "$P/$2" | awk '{print $1}')
  if [ "$r" = "$(fsha "$1")" ]; then echo true; else echo false; fi
}
# fetch REMOTE_SUBDIR LOCAL_DIR: copy every regular file of $P/REMOTE_SUBDIR; stop if any SHA-256 differs after the copy
fetch() {
  mkdir -p "$2"
  scp -q -o BatchMode=yes "$HOST:$P/$1/*" "$2/"
  pis "cd $P/$1 && find . -maxdepth 1 -type f | sed 's|^\./||' | LC_ALL=C sort | xargs sha256sum" > "$W/fetch-remote.txt"
  (cd "$2" && awk '{print $2}' "$W/fetch-remote.txt" | xargs shasum -a 256) > "$W/fetch-local.txt"
  if ! cmp -s "$W/fetch-remote.txt" "$W/fetch-local.txt"; then
    say "copy back from the Pi ($1): SHA-256 differ after the copy; stopping (no PM result written)"
    exit 1
  fi
}
# cont RUNFILE DFILE FROM TO (Mac): onelife-run fed lines FROM+1..TO; prints the exit code
cont() { c=0; sed -n "$(($3 + 1)),$4p" "$2" | "$MRUN" "$1" > /dev/null 2> "$1.err" || c=$?; echo $c; }
# cmpwalk A B N: two onelife-check prefixes; "differing_lines first_differing_n lines_A lines_B sha_files_identical"
cmpwalk() {
  d=$(paste -d' ' "$1.sha" "$2.sha" | awk '$1 != $3 || $2 != $4 { c++; if (f == "") f = $1 } END { print c + 0, (f == "" ? "null" : f) }')
  la=$(wc -l < "$1.sha" | tr -d ' '); lb=$(wc -l < "$2.sha" | tr -d ' ')
  id=false; cmp -s "$1.sha" "$2.sha" && id=true
  echo "$d $la $lb $id"
}
# flip1 IN OUT OFFSET: a copy of IN with the byte at OFFSET changed (+1 mod 256)
flip1() {
  cp "$1" "$2"
  b=$(od -An -t u1 -j "$3" -N 1 "$1" | tr -d ' ')
  printf "\\$(printf '%03o' $(((b + 1) % 256)))" | dd of="$2" bs=1 seek="$3" conv=notrunc 2> /dev/null
}
done_pm() { grep -q "^$1: " experiments/results-other-machine.out 2> /dev/null; }
LIVES="627:L2:D1 627:L2:D3 627:L2+SF:D1 627:L2+SF:D3 628:L2:D1 628:L2:D3 628:L2+SF:D1 628:L2+SF:D3"
say ""
say "S51 other-machine check, mode $MODE, Mac work dir $W, Pi work dir $P, Mac time $(date '+%Y-%m-%d %H:%M:%S')"

# ---------- the Pi side (copied to $P/pi.sh; its SHA-256 is compared in M1) ----------
cat > "$W/pi.sh" << 'PIEOF'
#!/bin/sh
# S51: the Pi side of experiments/other_machine_check.sh (written by it). Writes only under its own directory.
set -eu
P=$(cd "$(dirname "$0")" && pwd)
BT=$P/being-tools
RUN=$P/onelife-run
nof() { "$BT" onelife-info "$1" | sed 's/^{"n":\([0-9]*\),.*/\1/'; }
# cont RUNFILE DFILE FROM TO: onelife-run fed lines FROM+1..TO; prints the exit code
cont() { c=0; sed -n "$(($3 + 1)),$4p" "$2" | "$RUN" "$1" > /dev/null 2> "$1.err" || c=$?; echo $c; }
# killat RUNFILE DFILE FROM TO: lines FROM+1..TO through a fifo; SIGKILL once onelife-info shows n = TO; "exit n"
killat() {
  rf=$1; fifo=$rf.fifo; rm -f "$fifo"; mkfifo "$fifo"
  "$RUN" "$rf" < "$fifo" > /dev/null 2>&1 &
  pid=$!
  exec 9> "$fifo"
  sed -n "$(($3 + 1)),$4p" "$2" >&9
  while [ "$(nof "$rf")" != "$4" ] && kill -0 $pid 2> /dev/null; do sleep 0.05; done
  kill -9 $pid 2> /dev/null || true
  c=0; wait $pid || c=$?
  exec 9>&-
  rm -f "$fifo"
  echo "$c $(nof "$rf")"
}
ns() { date +%s%N; }
cmd=$1; shift
case "$cmd" in
  # m2 DIR: the gate M2 / smoke life 627-L2-D1, N = 50 (onelife-check with both laws; onelife-run timed)
  m2)
    d=$1; mkdir -p "$d"
    t0=$(ns); "$BT" onelife-check 627 L2 "$P/D1.txt" 50 "$d/w-L2" "0,49" > "$d/w-L2.json"; t1=$(ns)
    "$BT" onelife-check 627 L2+SF "$P/D1.txt" 50 "$d/w-SF" "0,49" > "$d/w-SF.json"
    "$BT" onelife-birth-run 627 L2 "$d/run"
    t2=$(ns); c=$(cont "$d/run" "$P/D1.txt" 0 50); t3=$(ns)
    echo "{\"run_exit\":$c,\"check_ns\":$((t1 - t0)),\"run_ns\":$((t3 - t2))}" > "$d/m2.json"
    mkdir -p "$d.aux"; mv "$d/run.err" "$d/run.lock" "$d.aux/"
    ;;
  # pm1 DIR
  pm1)
    d=$1; mkdir -p "$d"
    "$BT" onelife-selftest > "$d/selftest.json"
    "$BT" onelife-exp "$P/math-v8.txt" "$P/D1.txt" "$P/D3.txt" 10000 100 "$d/exp.txt" > "$d/exp.json"
    ;;
  # pm2 DIR N PTS LIVES...: onelife-check of each life, and the two 3000-drive lives of the Julia reference (in parallel)
  pm2)
    d=$1; n=$2; pts=$3; shift 3; mkdir -p "$d"
    for L in "$@"; do
      seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
      ("$BT" onelife-check $seed $law "$P/$dr.txt" $n "$d/$tag" "$pts" > "$d/$tag.json") &
    done
    for law in L2 L2+SF; do
      ("$BT" onelife-check 627 $law "$P/D3-3000.txt" 3000 "$d/jl3000-627-$law-D3" > "$d/jl3000-627-$law-D3.json") &
    done
    wait
    ;;
  # pm3 DIR N LIVES...: per life, onelife-run uninterrupted (u-) and SIGKILLed at n = 2000 then resumed (i-)
  pm3)
    d=$1; n=$2; shift 2; mkdir -p "$d" "$d.aux"
    for L in "$@"; do
      seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
      (
        u=$d/u-$tag; i=$d/i-$tag
        "$BT" onelife-birth-run $seed $law "$u"; "$BT" onelife-birth-run $seed $law "$i"
        cu=$(cont "$u" "$P/$dr.txt" 0 $n)
        k=$(killat "$i" "$P/$dr.txt" 0 2000)
        cr=$(cont "$i" "$P/$dr.txt" 2000 $n)
        mv "$u.err" "$u.lock" "$i.err" "$i.lock" "$d.aux/" 2> /dev/null || true
        echo "{\"uninterrupted_exit\":$cu,\"kill_exit\":${k% *},\"n_at_kill\":${k#* },\"resume_exit\":$cr}" > "$d.aux/pm3-$tag.json"
      ) &
    done
    wait
    mv "$d.aux"/pm3-*.json "$d/"
    ;;
  # pm4a DIR N LIVES...: the Mac's run files at n = 2000 (DIR/m-TAG) continued to N on the Pi
  pm4a)
    d=$1; n=$2; shift 2; mkdir -p "$d.aux"
    for L in "$@"; do
      seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
      (c=$(cont "$d/m-$tag" "$P/$dr.txt" 2000 $n); echo "$c" > "$d.aux/exit-$tag"; mv "$d/m-$tag.err" "$d/m-$tag.lock" "$d.aux/" 2> /dev/null || true) &
    done
    wait
    ;;
  # pm4b DIR LIVES...: births on the Pi run to n = 2000 (DIR/p-TAG)
  pm4b)
    d=$1; shift; mkdir -p "$d" "$d.aux"
    for L in "$@"; do
      seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
      ("$BT" onelife-birth-run $seed $law "$d/p-$tag"; c=$(cont "$d/p-$tag" "$P/$dr.txt" 0 2000); echo "$c" > "$d.aux/exit-$tag"; mv "$d/p-$tag.err" "$d/p-$tag.lock" "$d.aux/" 2> /dev/null || true) &
    done
    wait
    ;;
  # pm5 DIR: 627-L2-D1 to n = 1999; a first writer fed 10 drives (blocked on its input at n = 2009); a second writer
  # on the same file (D3 lines 2000-2009); then the first gets 10 more drives and its end
  pm5)
    d=$1; mkdir -p "$d"; f=$d/run
    "$BT" onelife-birth-run 627 L2 "$f"
    c0=$(cont "$f" "$P/D1.txt" 0 1999)
    fifo=$d/fifo; mkfifo "$fifo"
    "$RUN" "$f" < "$fifo" > /dev/null 2> "$d/err1" &
    pid=$!
    exec 8> "$fifo"
    sed -n 2000,2009p "$P/D1.txt" >&8
    while [ "$(nof "$f")" != 2009 ] && kill -0 $pid 2> /dev/null; do sleep 0.05; done
    cp "$f" "$d/held"
    nh=$(nof "$d/held")
    c2=0; sed -n 2000,2009p "$P/D3.txt" | "$RUN" "$f" > /dev/null 2> "$d/err2" || c2=$?
    msg=false; grep -q 'held by another writer' "$d/err2" && msg=true
    same=false; cmp -s "$f" "$d/held" && same=true
    sed -n 2010,2019p "$P/D1.txt" >&8
    exec 8>&-
    c1=0; wait $pid || c1=$?
    rm -f "$fifo"
    mkdir -p "$d/end"; cp "$f" "$d/end/run"
    echo "{\"to_1999_exit\":$c0,\"held_n\":$nh,\"second_exit\":$c2,\"lock_message\":$msg,\"file_unchanged\":$same,\"first_exit\":$c1,\"end_n\":$(nof "$f")}" > "$d/end/pm5.json"
    ;;
  *) echo "pi.sh: unknown command $cmd" >&2; exit 2 ;;
esac
PIEOF

# ---------- F: the spec and the predictions are those of freeze 1 ----------
f1() { awk '/^# S51 freeze 1/ { f = 1; next } /^#/ { f = 0 } f' "$FRZ" | grep " $1\$" | awk '{print $1}'; }
fs=$(f1 ../discussion/specs/S51-other-machine.md); fp=$(f1 predictions-other-machine.md)
gf=false; [ -n "$fs" ] && [ "$fs" = "$(fsha $SPEC)" ] && [ -n "$fp" ] && [ "$fp" = "$(fsha $PRED)" ] && gf=true
say "F spec $(fsha $SPEC) (freeze 1 $fs), predictions $(fsha $PRED) (freeze 1 $fp) -> $gf"

# ---------- M0: sources, builds, the Pi executables ----------
mkdir -p "$W/src"
git archive d5a7f6d rust | tar -x -C "$W/src"
srcsame=false; diff -r "$W/src/rust" "$B/rust" > /dev/null && srcsame=true
ncore=0
for f in onelife.rs matter.rs fdexp.rs sha256.rs; do
  want=$(grep " \.\./rust/being-core/src/$f\$" "$BFRZ" | awk '{print $1}')
  [ -n "$want" ] && [ "$(fsha "$B/rust/being-core/src/$f")" = "$want" ] && ncore=$((ncore + 1))
done
want=$(grep " \.\./rust/being-tools/src/bin/onelife-run.rs\$" "$BFRZ" | awk '{print $1}')
runsrc=false; [ -n "$want" ] && [ "$(fsha "$B/rust/being-tools/src/bin/onelife-run.rs")" = "$want" ] && runsrc=true
nwm=$(grep -c '^warning' "$B/build-mac.txt" || true)
nwp=$(grep -c '^warning' "$B/build-pi.txt" || true)
fin_m=false; grep -q 'Finished `release`' "$B/build-mac.txt" && fin_m=true
fin_p=false; grep -q 'Finished `release`' "$B/build-pi.txt" && fin_p=true
nelf=0
for x in "$PBT" "$PRUN"; do
  ft=$(file -b "$x")
  mach=$(od -An -t u2 -j 18 -N 2 "$x" | tr -d ' ')
  case "$ft" in "ELF 64-bit LSB executable, ARM aarch64"*"statically linked"*) [ "$mach" = 183 ] && nelf=$((nelf + 1)) ;; esac
done
# the executables and this script against the code freeze (written before the one run)
cf() { grep " $1\$" "$CFRZ" 2> /dev/null | awk '{print $1}'; }
nbin=0
for x in mac/being-tools:$MBT mac/onelife-run:$MRUN pi/being-tools:$PBT pi/onelife-run:$PRUN; do
  k=${x%%:*}; v=${x#*:}; want=$(cf "$k")
  [ -n "$want" ] && [ "$(fsha "$v")" = "$want" ] && nbin=$((nbin + 1))
done
scr=false; [ "$(cf other_machine_check.sh)" = "$(fsha experiments/other_machine_check.sh)" ] && scr=true
m0=false
if [ "$srcsame" = true ] && [ "$ncore" = 4 ] && [ "$runsrc" = true ] && [ "$nwm" = 0 ] && [ "$nwp" = 0 ] && [ "$fin_m" = true ] && [ "$fin_p" = true ] && [ "$nelf" = 2 ]; then m0=true; fi
m0f=$m0
if [ "$nbin" != 4 ]; then m0f=false; fi
if [ "$scr" != true ]; then m0f=false; fi
say "M0 source = git archive d5a7f6d $srcsame; being-core files with the S49b sha $ncore of 4; onelife-run.rs $runsrc; build warnings Mac $nwm / Pi $nwp (finished $fin_m / $fin_p); Pi executables aarch64 static ELF $nelf of 2 -> $m0; executables with the code-freeze sha $nbin of 4, script $scr -> with the code freeze $m0f"
if [ "$MODE" = full ]; then m0=$m0f; fi

# ---------- inputs (Mac) ----------
mkdir -p "$W/in" "$W/jl"
julia --project=. core/check/onelife_scenarios.jl drives "$W/in" $N
cp core/check/out/math-v8.txt "$W/in/math-v8.txt"
cp core/check/out/onelife-drives/D3.txt "$W/in/D3-3000.txt"
for law in L2 L2+SF; do
  cp "core/check/out/onelife-jl-627-$law-D3.sha" "$W/jl/627-$law-D3.sha"
  cp "core/check/out/onelife-jl-627-$law-D3-3000.save" "$W/jl/627-$law-D3-3000.save"
done
nin=0
for x in in/D1.txt in/D3.txt in/math-v8.txt in/D3-3000.txt jl/627-L2-D3.sha jl/627-L2-D3-3000.save jl/627-L2+SF-D3.sha jl/627-L2+SF-D3-3000.save; do
  want=$(cf "input/$x"); [ -n "$want" ] && [ "$(fsha "$W/$x")" = "$want" ] && nin=$((nin + 1))
done
d3pre=false; head -n 3000 "$W/in/D3.txt" | cmp -s - "$W/in/D3-3000.txt" && d3pre=true

# ---------- M1: copies to the Pi, SHA-256 on both sides ----------
pis "mkdir -p $P"
ok1=0; rows=""
for x in "$PBT:being-tools" "$PRUN:onelife-run" "$W/pi.sh:pi.sh" "$W/in/D1.txt:D1.txt" "$W/in/D3.txt:D3.txt" "$W/in/math-v8.txt:math-v8.txt" "$W/in/D3-3000.txt:D3-3000.txt"; do
  s=${x%%:*}; t=${x#*:}; r=$(push "$s" "$t"); rows="$rows $t:$r"
  [ "$r" = true ] && ok1=$((ok1 + 1))
done
pis "chmod 755 $P/being-tools $P/onelife-run"
m1=false; [ "$ok1" = 7 ] && m1=true
m1f=$m1; [ "$nin" = 8 ] || m1f=false
say "M1 copies (Mac sha = Pi sha after the copy):$rows -> $m1; inputs with the code-freeze sha $nin of 8 -> with the code freeze $m1f (observation: the reference D3 of 3000 lines is the head of D3 $d3pre)"
if [ "$MODE" = full ]; then m1=$m1f; fi

# ---------- M2: the comparisons catch a difference (one byte, the law) ----------
pi m2 "$P/m2"
fetch m2 "$W/pi/m2"
mkdir -p "$W/mac/m2"
"$MBT" onelife-check 627 L2 "$W/in/D1.txt" 50 "$W/mac/m2/w-L2" "0,49" > "$W/mac/m2/w-L2.json"
"$MBT" onelife-birth-run 627 L2 "$W/mac/m2/run"
cm=$(cont "$W/mac/m2/run" "$W/in/D1.txt" 0 50)
pos=$(cmpwalk "$W/mac/m2/w-L2" "$W/pi/m2/w-L2")
possv=0; for p in 0 49 50; do cmp -s "$W/mac/m2/w-L2-$p.save" "$W/pi/m2/w-L2-$p.save" && possv=$((possv + 1)); done
posrun=false; cmp -s "$W/mac/m2/run" "$W/pi/m2/run" && posrun=true
pj=$(cat "$W/pi/m2/m2.json")
# negative 1: one byte changed in copies of the Pi's per-step SHA file (line 26), save (n = 49) and run file
awk 'NR == 26 { c = substr($2, 64, 1); $2 = substr($2, 1, 63) (c == "0" ? "1" : "0") } { print }' "$W/pi/m2/w-L2.sha" > "$W/neg-w.sha"
nb_sha=$(cmp -l "$W/pi/m2/w-L2.sha" "$W/neg-w.sha" | wc -l | tr -d ' ')
neg1=$(cmpwalk "$W/mac/m2/w-L2" "$W/neg-w")
flip1 "$W/pi/m2/w-L2-49.save" "$W/neg-49.save" 100
nb_sv=$(cmp -l "$W/pi/m2/w-L2-49.save" "$W/neg-49.save" | wc -l | tr -d ' ')
negsv=false; cmp -s "$W/mac/m2/w-L2-49.save" "$W/neg-49.save" || negsv=true
flip1 "$W/pi/m2/run" "$W/neg-run" 40
nb_run=$(cmp -l "$W/pi/m2/run" "$W/neg-run" | wc -l | tr -d ' ')
negrun=false; cmp -s "$W/mac/m2/run" "$W/neg-run" || negrun=true
# negative 2: the Pi's walk with L2+SF compared with the Mac's L2
neg2=$(cmpwalk "$W/mac/m2/w-L2" "$W/pi/m2/w-SF")
neg2sv=false; cmp -s "$W/mac/m2/w-L2-50.save" "$W/pi/m2/w-SF-50.save" || neg2sv=true
set -- $pos; posok=false; [ "$1" = 0 ] && [ "$3" = 51 ] && [ "$4" = 51 ] && [ "$5" = true ] && [ "$possv" = 3 ] && [ "$posrun" = true ] && [ "$cm" = 0 ] && posok=true
set -- $neg1; n1ok=false; [ "$1" = 1 ] && [ "$2" = 25 ] && [ "$5" = false ] && [ "$nb_sha" = 1 ] && n1ok=true
n1b=false; [ "$negsv" = true ] && [ "$nb_sv" = 1 ] && [ "$negrun" = true ] && [ "$nb_run" = 1 ] && n1b=true
set -- $neg2; n2ok=false; [ "$1" -ge 1 ] && [ "$5" = false ] && [ "$neg2sv" = true ] && n2ok=true
m2=false; [ "$posok" = true ] && [ "$n1ok" = true ] && [ "$n1b" = true ] && [ "$n2ok" = true ] && m2=true
rjs=$(jget "$pj" run_ns); cjs=$(jget "$pj" check_ns)
say "M2 627-L2-D1 N = 50: Mac vs Pi (differing, first n, lines, lines, sha file identical) $pos, saves same $possv of 3, run files same $posrun -> match $posok; one byte changed in the Pi's copy: sha file $neg1 (bytes changed $nb_sha) caught $n1ok, save and run file caught $n1b (bytes changed $nb_sv / $nb_run); law L2+SF on the Pi vs L2 on the Mac $neg2, end save differs $neg2sv, caught $n2ok -> $m2"
say "smoke timing on the Pi (Pi's own clock, durations only): onelife-check 50 steps $((cjs / 1000000)) ms; onelife-run 50 drives $((rjs / 1000000)) ms ($((rjs / 50000)) us per drive); Pi run file exit $(jget "$pj" run_exit)"

gates=false; [ "$gf" = true ] && [ "$m0" = true ] && [ "$m1" = true ] && [ "$m2" = true ] && gates=true
say "gates F M0 M1 M2: $gf $m0 $m1 $m2 -> $gates"
if [ "$MODE" != full ]; then say "smoke done $(date '+%Y-%m-%d %H:%M:%S'): $OUT"; exit 0; fi
if [ "$gates" != true ]; then say "a gate failed: PM1-PM5 not run"; exit 1; fi

dfile() { echo "$W/in/$1.txt"; }

# ================= PM1 =================
if done_pm PM1; then
  say "== PM1: skipped on this run (its result line is already in this file)"
else
  say "== PM1: onelife-selftest on the Pi; onelife-exp (math-v8, D1, D3, N = $N, every 100) Pi vs Mac, $(date '+%H:%M:%S')"
  pi pm1 "$P/pm1"
  fetch pm1 "$W/pi/pm1"
  mkdir -p "$W/mac/pm1"
  "$MBT" onelife-exp "$W/in/math-v8.txt" "$W/in/D1.txt" "$W/in/D3.txt" $N 100 "$W/mac/pm1/exp.txt" > "$W/mac/pm1/exp.json"
  st=$(cat "$W/pi/pm1/selftest.json")
  stok=false; echo "$st" | grep -q '"sha_vectors":\[true, true, true, true\],"sqrt_mismatch":0,"floor_mismatch":0' && stok=true
  ep=$(cat "$W/pi/pm1/exp.json"); em=$(cat "$W/mac/pm1/exp.json")
  lp=$(wc -l < "$W/pi/pm1/exp.txt" | tr -d ' '); lm=$(wc -l < "$W/mac/pm1/exp.txt" | tr -d ' ')
  cut -d' ' -f1,2 "$W/pi/pm1/exp.txt" > "$W/pi/pm1/fd.txt"; cut -d' ' -f1,2 "$W/mac/pm1/exp.txt" > "$W/mac/pm1/fd.txt"
  fdsame=false; cmp -s "$W/pi/pm1/fd.txt" "$W/mac/pm1/fd.txt" && fdsame=true
  stdd=$(paste -d' ' "$W/pi/pm1/exp.txt" "$W/mac/pm1/exp.txt" | awk '$3 != $6 { c++ } END { print c + 0 }')
  whole=false; cmp -s "$W/pi/pm1/exp.txt" "$W/mac/pm1/exp.txt" && whole=true
  ok=false; [ "$stok" = true ] && [ "$(jget "$ep" inputs)" = 780553 ] && [ "$(jget "$em" inputs)" = 780553 ] && [ "$lp" = 780553 ] && [ "$lm" = 780553 ] && [ "$fdsame" = true ] && ok=true
  say "PM1 selftest on the Pi $st -> $stok"
  say "PM1 onelife-exp Pi $ep; Mac $em; lines $lp / $lm; columns x and fdexp identical $fdsame; observation: std exp column differs on $stdd inputs (whole files identical $whole)"
  say "PM1: $ok"
fi

# ================= PM2 =================
PTS="0,1999,2000,9999"
if done_pm PM2; then
  say "== PM2: skipped on this run (its result line is already in this file)"
else
  say "== PM2: onelife-check on the 8 lives, every step, Pi vs Mac; 627 x D3 x 3000 Pi vs Julia, $(date '+%H:%M:%S')"
  mkdir -p "$W/mac/pm2"
  (pi pm2 "$P/pm2" $N "$PTS" $LIVES) &
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
    "$MBT" onelife-check $seed $law "$(dfile $dr)" $N "$W/mac/pm2/$tag" "$PTS" > "$W/mac/pm2/$tag.json" &
  done
  wait
  fetch pm2 "$W/pi/pm2"
  pm2=true
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
    c=$(cmpwalk "$W/mac/pm2/$tag" "$W/pi/pm2/$tag")
    nsv=0; for p in 0 1999 2000 9999 $N; do cmp -s "$W/mac/pm2/$tag-$p.save" "$W/pi/pm2/$tag-$p.save" && nsv=$((nsv + 1)); done
    jm=$(cat "$W/mac/pm2/$tag.json"); jp=$(cat "$W/pi/pm2/$tag.json")
    set -- $c
    ok=false; [ "$1" = 0 ] && [ "$3" = $((N + 1)) ] && [ "$4" = $((N + 1)) ] && [ "$5" = true ] && [ "$nsv" = 5 ] && [ "$jm" = "$jp" ] && ok=true
    [ "$ok" = true ] || pm2=false
    say "PM2 $tag: (differing, first differing n, lines Mac, lines Pi, sha files identical) $c; saves 0,1999,2000,9999,$N same $nsv of 5; Mac $jm Pi $jp -> $ok"
    if [ "$ok" != true ] && [ "$2" != null ]; then
      f=$2; [ "$f" -ge 1 ] || f=1
      "$MBT" onelife-check $seed $law "$(dfile $dr)" "$f" "$W/mac/pm2/first-$tag" "$((f - 1)),$f" > /dev/null
      say "PM2 $tag: first differing n = $2; the Mac saves at n - 1 and n kept in $W/mac/pm2/first-$tag-*.save (the Pi's are in the Pi's .sha only up to the points)"
    fi
  done
  for law in L2 L2+SF; do
    t=jl3000-627-$law-D3
    a=false; cmp -s "$W/jl/627-$law-D3.sha" "$W/pi/pm2/$t.sha" && a=true
    b=false; cmp -s "$W/jl/627-$law-D3-3000.save" "$W/pi/pm2/$t-3000.save" && b=true
    c=$(cmpwalk "$W/jl/627-$law-D3" "$W/pi/pm2/$t")
    ok=false; [ "$a" = true ] && [ "$b" = true ] && ok=true
    [ "$ok" = true ] || pm2=false
    say "PM2 Julia 627-$law-D3 3000: Pi sha file = Julia's $a ($c), Pi save at 3000 = Julia's $b -> $ok"
  done
  say "PM2: $pm2"
fi

# the Mac's uninterrupted onelife-run of each life (for PM3 and PM4)
mac_u() {
  mkdir -p "$W/mac/u"
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
    [ -f "$W/mac/u/u-$tag" ] && continue
    ("$MBT" onelife-birth-run $seed $law "$W/mac/u/u-$tag"; cont "$W/mac/u/u-$tag" "$(dfile $dr)" 0 $N > "$W/mac/u/exit-$tag") &
  done
}

# ================= PM3 =================
if done_pm PM3; then
  say "== PM3: skipped on this run (its result line is already in this file)"
else
  say "== PM3: onelife-run on the Pi (uninterrupted; SIGKILL after n = 2000 is seen with onelife-info, then resumed) vs the Mac's uninterrupted run, $(date '+%H:%M:%S')"
  (pi pm3 "$P/pm3" $N $LIVES) &
  mac_u
  wait
  fetch pm3 "$W/pi/pm3"
  pm3=true
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
    j=$(cat "$W/pi/pm3/pm3-$tag.json"); mu=$W/mac/u/u-$tag; ce=$(cat "$W/mac/u/exit-$tag")
    us=false; cmp -s "$W/pi/pm3/u-$tag" "$mu" && us=true
    is=false; cmp -s "$W/pi/pm3/i-$tag" "$mu" && is=true
    ok=false; [ "$ce" = 0 ] && [ "$(nof "$mu")" = $N ] && [ "$j" = '{"uninterrupted_exit":0,"kill_exit":137,"n_at_kill":2000,"resume_exit":0}' ] && [ "$us" = true ] && [ "$is" = true ] && ok=true
    [ "$ok" = true ] || pm3=false
    say "PM3 $tag: Pi $j; Mac exit $ce n $(nof "$mu"); Pi uninterrupted = Mac $us; Pi killed and resumed = Mac $is -> $ok"
  done
  say "PM3: $pm3"
fi

# ================= PM4 =================
if done_pm PM4; then
  say "== PM4: skipped on this run (its result line is already in this file)"
else
  say "== PM4: run files at n = 2000 moved between the machines (an operator's check intervention) and continued to $N, $(date '+%H:%M:%S')"
  mac_u
  mkdir -p "$W/mac/pm4"
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
    ("$MBT" onelife-birth-run $seed $law "$W/mac/pm4/m-$tag"; cont "$W/mac/pm4/m-$tag" "$(dfile $dr)" 0 2000 > "$W/mac/pm4/mexit-$tag") &
  done
  (pi pm4b "$P/pm4b" $LIVES) &
  wait
  pis "mkdir -p $P/pm4a"
  npush=0
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
    [ "$(push "$W/mac/pm4/m-$tag" "pm4a/m-$tag")" = true ] && npush=$((npush + 1))
  done
  fetch pm4b "$W/pi/pm4b"
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
    mkdir -p "$W/mac/pm4/pi2mac"; cp "$W/pi/pm4b/p-$tag" "$W/mac/pm4/pi2mac/p-$tag"
    (cont "$W/mac/pm4/pi2mac/p-$tag" "$(dfile $dr)" 2000 $N > "$W/mac/pm4/pi2mac/exit-$tag") &
  done
  (pi pm4a "$P/pm4a" $N $LIVES) &
  wait
  fetch pm4a "$W/pi/pm4a"
  fetch pm4b.aux "$W/pi/pm4b.aux"
  fetch pm4a.aux "$W/pi/pm4a.aux"
  pm4=true
  for L in $LIVES; do
    seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr; mu=$W/mac/u/u-$tag
    e1=$(cat "$W/mac/pm4/mexit-$tag"); e2=$(cat "$W/pi/pm4a.aux/exit-$tag"); e3=$(cat "$W/pi/pm4b.aux/exit-$tag"); e4=$(cat "$W/mac/pm4/pi2mac/exit-$tag")
    n1=$(nof "$W/mac/pm4/m-$tag"); n3=$(nof "$W/pi/pm4b/p-$tag")
    a=false; cmp -s "$W/pi/pm4a/m-$tag" "$mu" && a=true
    b=false; cmp -s "$W/mac/pm4/pi2mac/p-$tag" "$mu" && b=true
    iu=$(info "$mu"); ia=$(info "$W/pi/pm4a/m-$tag"); ib=$(info "$W/mac/pm4/pi2mac/p-$tag")
    dd=true; [ "$dr" = D3 ] && { [ "$(jget "$iu" dead)" = true ] || dd=false; }
    ok=false; [ "$e1$e2$e3$e4" = 0000 ] && [ "$n1" = 2000 ] && [ "$n3" = 2000 ] && [ "$a" = true ] && [ "$b" = true ] && [ "$ia" = "$iu" ] && [ "$ib" = "$iu" ] && [ "$dd" = true ] && ok=true
    [ "$ok" = true ] || pm4=false
    say "PM4 $tag: Mac->Pi (exits $e1, $e2; n at the copy $n1) end = Mac uninterrupted $a; Pi->Mac (exits $e3, $e4; n at the copy $n3) end = Mac uninterrupted $b; end info Mac $iu, Mac->Pi death $(jget "$ia" death), Pi->Mac death $(jget "$ib" death); D3 dead $dd -> $ok"
  done
  [ "$npush" = 8 ] || pm4=false
  say "PM4: copies to the Pi with the same sha $npush of 8; $pm4"
  say "PM4: $pm4"
fi

# ================= PM5 =================
if done_pm PM5; then
  say "== PM5: skipped on this run (its result line is already in this file)"
else
  say "== PM5: the lock on the Pi (627-L2-D1, a second onelife-run while the first holds the run file at n = 2009), $(date '+%H:%M:%S')"
  pi pm5 "$P/pm5"
  fetch pm5/end "$W/pi/pm5"
  j=$(cat "$W/pi/pm5/pm5.json")
  mkdir -p "$W/mac/pm5"; "$MBT" onelife-birth-run 627 L2 "$W/mac/pm5/solo"; cs=$(cont "$W/mac/pm5/solo" "$W/in/D1.txt" 0 2019)
  es=false; cmp -s "$W/pi/pm5/run" "$W/mac/pm5/solo" && es=true
  ok=false; [ "$j" = '{"to_1999_exit":0,"held_n":2009,"second_exit":9,"lock_message":true,"file_unchanged":true,"first_exit":0,"end_n":2019}' ] && ok=true
  say "PM5 627-L2-D1: Pi $j -> $ok; observation: the end equals the Mac's solo run of 2019 drives $es (Mac exit $cs)"
  say "PM5: $ok"
fi
say "done $(date '+%Y-%m-%d %H:%M:%S'); Mac work dir $W, Pi work dir $P"
