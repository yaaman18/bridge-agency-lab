#!/bin/sh
# S49b (discussion/specs/S49b-single-writer.md r2; predictions experiments/predictions-rust-onelife-b.md PL1-PL5): the
# writer's lock of onelife-run (flock on "<name>.lock" beside the run file; exit 9 when it cannot be taken).
# Usage (from anywhere):
#   sh experiments/onelife_rust_lock_check.sh gates   gates L0 (builds, being-core sha), L1, L2; results in the work dir
#   sh experiments/onelife_rust_lock_check.sh         the gates, then PL1-PL5 on the 8 lives (seeds 627-628 x L2, L2+SF x
#                                                     D1, D3); results in experiments/results-rust-onelife-b.{json,out}
# PL4 runs a copy of experiments/onelife_rust_check.sh whose results go to the work dir (the S49 results files are not
# written; their SHA-256 is compared before and after). sh core/check/run.sh (gate L0) is run by hand.
set -eu
cd "$(dirname "$0")/.."
LAB=$PWD
MODE=${1:-full}
N=10000
N0=1999
K1=10
K2=40
TRIALS=50
NEG_TRIALS=20
W=$(mktemp -d "${TMPDIR:-/tmp}/onelife-lock.XXXXXX")
BT=$PWD/rust/target/release/being-tools
RUN=$PWD/rust/target/release/onelife-run
NT=$W/nolock-target
NRUN=$NT/release/onelife-run
if [ "$MODE" = full ]; then OUT=experiments/results-rust-onelife-b.out; JSONF=experiments/results-rust-onelife-b.json; else OUT=$W/gates.out; JSONF=$W/gates.json; fi
TSV=$W/res.tsv
: > "$OUT"; : > "$TSV"
say() { echo "$*" | tee -a "$OUT"; }
res() { printf '%s\t%s\n' "$1" "$2" >> "$TSV"; }
nof() { od -An -t u8 -j 16 -N 8 "$1" | tr -d ' \n'; }
psha() { "$BT" onelife-info "$1" | sed 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/'; }
info() { "$BT" onelife-info "$1"; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
shaat() { awk -v n="$2" '$1 == n { print $2 }' "$1"; }
LOCKMSG='held by another writer'
say "S49b onelife-run lock check, mode $MODE, work dir $W, $(date '+%Y-%m-%d %H:%M:%S')"

# ---------- L0: builds without warnings, being-core unchanged and without dependencies ----------
touch rust/being-tools/src/bin/onelife-run.rs
(cd rust && cargo build --release -p being-tools) > "$W/build.txt" 2>&1
(cd rust && cargo build --release -p being-tools --features nolock --target-dir "$NT") > "$W/build-nolock.txt" 2>&1
nw=$(grep -c '^warning' "$W/build.txt" || true)
nwn=$(grep -c '^warning' "$W/build-nolock.txt" || true)
ndeps=$(cd rust && cargo tree -p being-core -e normal --prefix none | sort -u | wc -l | tr -d ' ')
ncore=0
for f in onelife.rs matter.rs fdexp.rs sha256.rs; do
  want=$(grep " \.\./rust/being-core/src/$f\$" experiments/freeze-rust-onelife-code.txt | awk '{print $1}')
  [ -n "$want" ] && [ "$(fsha rust/being-core/src/$f)" = "$want" ] && ncore=$((ncore + 1))
done
l0=false; [ "$nw" = 0 ] && [ "$nwn" = 0 ] && [ "$ndeps" = 1 ] && [ "$ncore" = 4 ] && l0=true
say "L0 build: warnings $nw (nolock build $nwn); being-core crates in its tree $ndeps; being-core files with the S49 sha $ncore of 4 -> $l0"
res L0 "{\"warnings\":$nw,\"warnings_nolock\":$nwn,\"being_core_tree\":$ndeps,\"core_files_same\":$ncore,\"pass\":$l0}"

# ---------- L1: the inputs that reach the state (S49 Q2 source check); the lock file is never read ----------
SRC=rust/being-tools/src/bin/onelife-run.rs
PAT='std::env|env::|std::time|SystemTime|Instant|(^|[^A-Za-z0-9_])rand([^A-Za-z0-9_]|$)|std::net|TcpStream|UdpSocket|getenv|env!|option_env!'
srcbad() { sed 's/std::env::args()//g' "$1" | grep -nE "$PAT" || true; }
LPAT='read\(true\)|read_to_end|read_to_string|fs::read\(&?lp|File::open\(&?lp|fs::read_to'
lockread() { grep -nE "$LPAT" "$1" || true; }
nfsread() { grep -o 'std::fs::read(' "$1" | wc -l | tr -d ' '; }
bad=$(srcbad "$SRC"); lr=$(lockread "$SRC"); nr=$(nfsread "$SRC")
nargs=$(grep -o 'std::env::args()' "$SRC" | wc -l | tr -d ' ')
mkdir -p "$W/neg"
cp "$SRC" "$W/neg/a.rs"; echo 'fn _x() { let _ = std::env::var("X"); }' >> "$W/neg/a.rs"
cp "$SRC" "$W/neg/b.rs"; echo 'fn _y(lp: &Path) { let _ = std::fs::read(lp); }' >> "$W/neg/b.rs"
nega=false; [ -n "$(srcbad "$W/neg/a.rs")" ] && nega=true
negb=false
if [ -n "$(lockread "$W/neg/b.rs")" ]; then negb=true; fi
if [ "$(nfsread "$W/neg/b.rs")" != 1 ]; then negb=true; fi
# at run time: a lock file that cannot be read (mode 200) with arbitrary bytes; onelife-run works and the bytes stay
mkdir -p "$W/l1"
julia --project=. core/check/onelife_scenarios.jl drives "$W" $N
D1=$W/D1.txt; D3=$W/D3.txt
"$BT" onelife-birth-run 627 L2 "$W/l1/run"
head -c 100 /dev/urandom > "$W/l1/run.lock"; cp "$W/l1/run.lock" "$W/l1/lock.before"; chmod 200 "$W/l1/run.lock"
cl=0; sed -n 1,3p "$D1" | "$RUN" "$W/l1/run" > /dev/null 2>&1 || cl=$?
chmod 600 "$W/l1/run.lock"
lsame=false; cmp -s "$W/l1/run.lock" "$W/l1/lock.before" && lsame=true
nl1=$(nof "$W/l1/run")
l1=false; [ -z "$bad" ] && [ -z "$lr" ] && [ "$nr" = 1 ] && [ "$nargs" = 1 ] && [ "$cl" = 0 ] && [ "$nl1" = 3 ] && [ "$lsame" = true ] && l1=true
say "L1 sources: forbidden uses '${bad}', reads of the lock file '${lr}', std::fs::read( $nr time(s), std::env::args() $nargs time(s); unreadable lock file with arbitrary bytes: exit $cl, n $nl1, lock bytes unchanged $lsame -> $l1; negative controls caught: std::env::var $nega, fs::read of the lock $negb"
res L1 "{\"forbidden_found\":$( [ -z "$bad" ] && echo 0 || echo 1 ),\"lock_reads_found\":$( [ -z "$lr" ] && echo 0 || echo 1 ),\"fs_read\":$nr,\"env_args\":$nargs,\"unreadable_lock_exit\":$cl,\"unreadable_lock_n\":$nl1,\"lock_bytes_unchanged\":$lsame,\"pass\":$l1,\"negative_control_env_caught\":$nega,\"negative_control_lock_read_caught\":$negb}"

# ---------- the lives: one Rust walk each (saves at n0 and 9999; the payload SHA-256 of every n) ----------
LIVES="627:L2:D1 627:L2:D3 627:L2+SF:D1 627:L2+SF:D3 628:L2:D1 628:L2:D3 628:L2+SF:D1 628:L2+SF:D3"
dfile() { if [ "$1" = D1 ]; then echo "$D1"; else echo "$D3"; fi; }
ofile() { if [ "$1" = D1 ]; then echo "$D3"; else echo "$D1"; fi; }
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  "$BT" onelife-check $seed $law "$(dfile $dr)" $N "$W/rs-$tag" "$N0,9999" > "$W/rs-$tag.json" &
done
wait
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  "$BT" onelife-wrap "$W/rs-$tag-$N0.save" $N0 "$W/base-$tag"
  # the other drive file from n0: the payload SHA-256 of every n (for the second writer's drives)
  "$BT" onelife-continue "$W/rs-$tag-$N0.save" "$(ofile $dr)" $N0 $((N0 + K2)) "$W/co-$tag" > /dev/null
done

# mk_refs DIR BASE DFILE K SHAFILE: the versions of a solo onelife-run fed lines n0+1..n0+K one at a time (DIR/v.j, the
# file SHA-256 of each in DIR/sha.txt); prints whether one run of all K lines gives v.K and v.K's payload is SHAFILE's
mk_refs() {
  d=$1; mkdir -p "$d"; cp "$2" "$d/v.0"; cp "$2" "$d/cur"; cp "$2" "$d/all"
  j=1
  while [ $j -le "$4" ]; do sed -n "$((N0 + j))p" "$3" | "$RUN" "$d/cur" > /dev/null; cp "$d/cur" "$d/v.$j"; j=$((j + 1)); done
  sed -n "$((N0 + 1)),$((N0 + $4))p" "$3" | "$RUN" "$d/all" > /dev/null
  : > "$d/sha.txt"; j=0
  while [ $j -le "$4" ]; do fsha "$d/v.$j" >> "$d/sha.txt"; j=$((j + 1)); done
  ok=false; cmp -s "$d/all" "$d/v.$4" && [ "$(psha "$d/v.$4")" = "$(shaat "$5" $((N0 + $4)))" ] && ok=true
  echo $ok
}

# ---------- PL2 trial: two onelife-run started together on one run file ----------
# trial RUNBIN DIR BASE DFA DFB REFA REFB: both wrappers wait for DIR/go (busy loop on a file test) after marking ready;
# go is made once both are ready; an observer hashes the run file until both have ended. Prints one JSON row.
trial() {
  rb=$1; d=$2; mkdir -p "$d"; f=$d/run; cp "$3" "$f"
  sed -n "$((N0 + 1)),$((N0 + K2))p" "$4" > "$d/inA"
  sed -n "$((N0 + 1)),$((N0 + K2))p" "$5" > "$d/inB"
  (touch "$d/readyA"; while [ ! -e "$d/go" ]; do :; done; exec "$rb" "$f" < "$d/inA" > /dev/null 2> "$d/errA") &
  pa=$!
  (touch "$d/readyB"; while [ ! -e "$d/go" ]; do :; done; exec "$rb" "$f" < "$d/inB" > /dev/null 2> "$d/errB") &
  pb=$!
  while [ ! -e "$d/readyA" ] || [ ! -e "$d/readyB" ]; do :; done
  (i=0; while [ ! -e "$d/stop" ]; do shasum -a 256 < "$f" | awk '{print $1}' >> "$d/obs"; i=$((i + 1)); done; shasum -a 256 < "$f" | awk '{print $1}' >> "$d/obs"; echo $((i + 1)) > "$d/nobs") &
  po=$!
  touch "$d/go"
  ca=0; wait $pa || ca=$?
  cb=0; wait $pb || cb=$?
  touch "$d/stop"; wait $po
  la=false; grep -q "$LOCKMSG" "$d/errA" && la=true
  lb=false; grep -q "$LOCKMSG" "$d/errB" && lb=true
  win=none; ref=""
  if [ "$ca" = 0 ] && [ "$cb" = 9 ] && [ "$lb" = true ] && [ ! -s "$d/errA" ]; then win=A; ref=$6; fi
  if [ "$cb" = 0 ] && [ "$ca" = 9 ] && [ "$la" = true ] && [ ! -s "$d/errB" ]; then win=B; ref=$7; fi
  nobs=$(cat "$d/nobs"); ndist=$(sort -u "$d/obs" | wc -l | tr -d ' ')
  if [ -n "$ref" ]; then
    nout=$(sort -u "$d/obs" | grep -vxFf "$ref/sha.txt" | wc -l | tr -d ' ')
    fin=false; cmp -s "$f" "$ref/v.$K2" && fin=true
  else
    nout=$(sort -u "$d/obs" | grep -vxFf "$6/sha.txt" | grep -vxFf "$7/sha.txt" | wc -l | tr -d ' ')
    fin=false; cmp -s "$f" "$6/v.$K2" && fin=true; cmp -s "$f" "$7/v.$K2" && fin=true
  fi
  tmpleft=false; [ -e "$f.tmp" ] && tmpleft=true
  ok=false; [ "$win" != none ] && [ "$nout" = 0 ] && [ "$fin" = true ] && [ "$tmpleft" = false ] && ok=true
  echo "{\"exitA\":$ca,\"exitB\":$cb,\"lock_msg_A\":$la,\"lock_msg_B\":$lb,\"winner\":\"$win\",\"observations\":$nobs,\"distinct\":$ndist,\"outside_winner_versions\":$nout,\"end_is_winner_solo\":$fin,\"tmp_left\":$tmpleft,\"ok\":$ok}"
}

# pl1_one RUNBIN TAG DRIVE DIR: the first writer is fed K1 drives and blocks on its input; a second writer (the other
# drive file) is started on the same file; then the first gets K1 more drives and its end. One JSON row.
pl1_one() {
  rb=$1; tag=$2; df=$(dfile $3); of=$(ofile $3); d=$4
  mkdir -p "$d"; f=$d/run; cp "$W/base-$tag" "$f"; cp "$W/base-$tag" "$d/solo"
  cs=0; sed -n "$((N0 + 1)),$((N0 + 2 * K1))p" "$df" | "$RUN" "$d/solo" > /dev/null 2>&1 || cs=$?
  mkfifo "$d/fifo"
  "$rb" "$f" < "$d/fifo" > /dev/null 2> "$d/err1" &
  pid=$!
  exec 8> "$d/fifo"
  sed -n "$((N0 + 1)),$((N0 + K1))p" "$df" >&8
  while [ "$(nof "$f")" != $((N0 + K1)) ] && kill -0 $pid 2> /dev/null; do sleep 0.05; done
  cp "$f" "$d/held"
  c2=0; sed -n "$((N0 + 1)),$((N0 + K1))p" "$of" | "$rb" "$f" > /dev/null 2> "$d/err2" || c2=$?
  msg=false; grep -q "$LOCKMSG" "$d/err2" && msg=true
  same=false; cmp -s "$f" "$d/held" && same=true
  sed -n "$((N0 + K1 + 1)),$((N0 + 2 * K1))p" "$df" >&8
  exec 8>&-
  c1=0; wait $pid || c1=$?
  end=false; cmp -s "$f" "$d/solo" && end=true
  pj=false; [ "$(psha "$f")" = "$(shaat "$W/rs-$tag.sha" $((N0 + 2 * K1)))" ] && pj=true
  ok=false; [ "$cs" = 0 ] && [ "$(nof "$d/held")" = $((N0 + K1)) ] && [ "$c2" = 9 ] && [ "$msg" = true ] && [ "$same" = true ] && [ "$c1" = 0 ] && [ "$end" = true ] && [ "$pj" = true ] && ok=true
  echo "{\"second_exit\":$c2,\"lock_message\":$msg,\"file_unchanged\":$same,\"first_exit\":$c1,\"end_same_as_solo\":$end,\"payload_is_walk\":$pj,\"pass\":$ok}"
}

# ---------- L2: the negative control (the nolock build) on one life ----------
tag=627-L2-D1
ra=$(mk_refs "$W/refA-$tag" "$W/base-$tag" "$D1" $K2 "$W/rs-$tag.sha")
rb=$(mk_refs "$W/refB-$tag" "$W/base-$tag" "$D3" $K2 "$W/co-$tag.sha")
nfail=0; nboth=0; k=1
while [ $k -le $NEG_TRIALS ]; do
  t=$(trial "$NRUN" "$W/neg2/$k" "$W/base-$tag" "$D1" "$D3" "$W/refA-$tag" "$W/refB-$tag")
  echo "$t" >> "$W/neg2.rows"
  echo "$t" | grep -q '"ok":true' || nfail=$((nfail + 1))
  echo "$t" | grep -q '"exitA":0,"exitB":0' && nboth=$((nboth + 1))
  k=$((k + 1))
done
# the same trials with the release build (the control of the control)
npass=0; k=1
while [ $k -le $NEG_TRIALS ]; do
  t=$(trial "$RUN" "$W/pos2/$k" "$W/base-$tag" "$D1" "$D3" "$W/refA-$tag" "$W/refB-$tag")
  echo "$t" | grep -q '"ok":true' && npass=$((npass + 1))
  k=$((k + 1))
done
l2=false; [ "$nfail" -ge 1 ] && [ "$npass" = $NEG_TRIALS ] && [ "$ra" = true ] && [ "$rb" = true ] && l2=true
say "L2 negative control ($tag, $NEG_TRIALS trials of PL2): nolock build trials failed $nfail (both exited 0 in $nboth); release build trials passed $npass; references checked $ra / $rb -> $l2"
res L2 "{\"life\":\"$tag\",\"trials\":$NEG_TRIALS,\"nolock_failed\":$nfail,\"nolock_both_exit_0\":$nboth,\"release_passed\":$npass,\"refs\":[$ra,$rb],\"pass\":$l2}"
[ "$l2" = true ] || say "L2: the PL2 trial does not see the lock (or the release build failed it)"
# what the nolock trials show without the lock message: the loser's exit 9 comes from a write error, and the file
# observations and the end are those of the winner by exit code
nwe=$(grep -c '"winner":"none"' "$W/neg2.rows" || true)
nwr=0
for k in $(seq 1 $NEG_TRIALS); do grep -q 'writing the run file' "$W/neg2/$k/errA" "$W/neg2/$k/errB" && nwr=$((nwr + 1)); done
say "L2 detail: nolock trials without a lock-refused side $nwe; trials where a side stopped with a write error (exit 9 is also E_WRITE) $nwr"
res L2detail "{\"nolock_no_lock_refusal\":$nwe,\"nolock_write_error_side\":$nwr}"
# L2b: the PL1 procedure with the nolock build (the second writer is not refused)
l2b_row=$(pl1_one "$NRUN" 627-L2-D1 D1 "$W/neg1")
l2b=false; echo "$l2b_row" | grep -q '"pass":false' && l2b=true
say "L2b negative control (PL1 with the nolock build, 627-L2-D1): $l2b_row; caught $l2b"
res L2b "{\"row\":$l2b_row,\"caught\":$l2b}"

if [ "$MODE" != full ]; then
  julia --project=. experiments/onelife_rust_check.jl report "$TSV" "$JSONF"
  say "gates done: $JSONF"
  exit 0
fi

# ================= PL1: a second writer is refused =================
say "== PL1: a second onelife-run while one holds the run file (blocked on its input after $K1 drives from n = $N0)"
pl1=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  v=$(pl1_one "$RUN" "$tag" $dr "$W/pl1-$tag")
  echo "$v" | grep -q '"pass":true' || pl1=false
  say "PL1 $tag $v"
  res "PL1.$tag" "$v"
done
say "PL1: $pl1"; res PL1 "$pl1"

# ================= PL2: two started together =================
say "== PL2: two onelife-run started together on one run file (n = $N0, $K2 drives each: the life's drive file and the other one), $TRIALS trials per life"
pl2_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); of=$(ofile $dr); R=$W/pl2-$tag.tsv
  if [ ! -d "$W/refA-$tag" ]; then
    ra=$(mk_refs "$W/refA-$tag" "$W/base-$tag" "$df" $K2 "$W/rs-$tag.sha")
    rb=$(mk_refs "$W/refB-$tag" "$W/base-$tag" "$of" $K2 "$W/co-$tag.sha")
  else
    ra=true; rb=true
  fi
  differ=true; cmp -s "$W/refA-$tag/v.$K2" "$W/refB-$tag/v.$K2" && differ=false
  k=1; nok=0; wa=0; wb=0; obs=0; rows=""
  while [ $k -le $TRIALS ]; do
    t=$(trial "$RUN" "$W/pl2/$tag/$k" "$W/base-$tag" "$df" "$of" "$W/refA-$tag" "$W/refB-$tag")
    echo "$t" >> "$W/pl2-$tag.rows"
    echo "$t" | grep -q '"ok":true' && nok=$((nok + 1))
    echo "$t" | grep -q '"winner":"A"' && wa=$((wa + 1))
    echo "$t" | grep -q '"winner":"B"' && wb=$((wb + 1))
    o=$(echo "$t" | sed 's/.*"observations":\([0-9]*\).*/\1/'); obs=$((obs + o))
    k=$((k + 1))
  done
  ok=false; [ "$nok" = $TRIALS ] && [ "$ra" = true ] && [ "$rb" = true ] && [ "$differ" = true ] && ok=true
  printf '%s\t%s\n' "PL2.$tag" "{\"trials\":$TRIALS,\"trials_ok\":$nok,\"won_A\":$wa,\"won_B\":$wb,\"observations\":$obs,\"refs\":[$ra,$rb],\"ends_differ\":$differ,\"pass\":$ok}" > "$R"
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (pl2_life $seed $law $dr) &
done
wait
pl2=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  cat "$W/pl2-$tag.tsv" >> "$TSV"
  v=$(cut -f2 "$W/pl2-$tag.tsv"); say "PL2 $tag $v"
  echo "$v" | grep -q '"pass":true' || pl2=false
done
say "PL2: $pl2"; res PL2 "$pl2"

# ================= PL3: no stale lock after SIGKILL =================
say "== PL3: drives 0..1999, SIGKILL at n = 2000, a new onelife-run with drives 2000..9999 (lock file missing / with arbitrary bytes)"
pl3_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pl3-$tag; mkdir -p "$d"; R=$W/pl3-$tag.tsv
  "$BT" onelife-birth-run $seed $law "$d/u"
  cu=0; "$RUN" "$d/u" < "$df" > /dev/null 2>&1 || cu=$?
  uj=false; [ "$(psha "$d/u")" = "$(shaat "$W/rs-$tag.sha" $N)" ] && [ "$(nof "$d/u")" = $N ] && uj=true
  rows=""; okall=true
  for v in missing arbitrary; do
    f=$d/$v; "$BT" onelife-birth-run $seed $law "$f"
    if [ $v = arbitrary ]; then head -c 333 /dev/urandom > "$f.lock"; cp "$f.lock" "$d/lock-before"; fi
    mkfifo "$d/fifo-$v"
    "$RUN" "$f" < "$d/fifo-$v" > /dev/null 2>&1 &
    pid=$!
    exec 8> "$d/fifo-$v"
    sed -n 1,2000p "$df" >&8
    while [ "$(nof "$f")" != 2000 ] && kill -0 $pid 2> /dev/null; do sleep 0.05; done
    kill -9 $pid 2> /dev/null || true
    ck=0; wait $pid || ck=$?
    exec 8>&-
    nk=$(nof "$f")
    if [ $v = missing ]; then
      # the resumed writer finds no lock file: the run file is taken to a new path
      cp "$f" "$f-2"; f=$f-2
    fi
    lockpre=false; [ -e "$f.lock" ] && lockpre=true
    cr=0; sed -n 2001,${N}p "$df" | "$RUN" "$f" > /dev/null 2>&1 || cr=$?
    same=false; cmp -s "$f" "$d/u" && same=true
    lb=null
    if [ $v = arbitrary ]; then lb=false; cmp -s "$f.lock" "$d/lock-before" && lb=true; fi
    ok=false; [ "$ck" = 137 ] && [ "$nk" = 2000 ] && [ "$cr" = 0 ] && [ "$same" = true ] && ok=true
    [ "$v" = arbitrary ] && [ "$lb" != true ] && ok=false
    [ "$ok" = true ] || okall=false
    rows="$rows{\"lock\":\"$v\",\"lock_file_at_resume\":$lockpre,\"kill_exit\":$ck,\"n_at_kill\":$nk,\"resume_exit\":$cr,\"end_same_as_uninterrupted\":$same,\"lock_bytes_unchanged\":$lb,\"ok\":$ok},"
  done
  ok=false; [ "$cu" = 0 ] && [ "$uj" = true ] && [ "$okall" = true ] && ok=true
  printf '%s\t%s\n' "PL3.$tag" "{\"uninterrupted_exit\":$cu,\"uninterrupted_is_walk\":$uj,\"rows\":[${rows%,}],\"pass\":$ok}" > "$R"
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (pl3_life $seed $law $dr) &
done
wait
pl3=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  cat "$W/pl3-$tag.tsv" >> "$TSV"
  v=$(cut -f2 "$W/pl3-$tag.tsv"); say "PL3 $tag $v"
  echo "$v" | grep -q '"pass":true' || pl3=false
done
say "PL3: $pl3"; res PL3 "$pl3"

# ================= PL5: the input lines, alive and dead =================
say "== PL5: malformed lines (exit 6, nothing saved) and out-of-range drives (alive: exit 8, nothing saved; dead: consumed)"
MALF='abc|1|1 2 3||1.0 2|3 2x|+1 2|9 9 9|0x1 2'
OOR='6 0|-1 3|0 6|99999999999999999999 0|9 9|-99999999999999999999 -1'
pl5=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr; d=$W/pl5-$tag; mkdir -p "$d"
  live=$W/base-$tag
  dead=$d/dead; "$BT" onelife-wrap "$W/rs-$seed-$law-D3-9999.save" 9999 "$dead"
  ld=$(info "$live" | grep -o '"dead":[a-z]*'); dd=$(info "$dead" | grep -o '"dead":[a-z]*')
  nc=0; nok=0; bads=""
  # case STATEFILE LINE WANT KIND
  onecase() {
    nc=$((nc + 1)); f=$d/c$nc; cp "$1" "$f"
    c=0; printf '%s\n' "$2" | "$RUN" "$f" > /dev/null 2>&1 || c=$?
    ok=false
    if [ "$4" = same ]; then
      [ "$c" = "$3" ] && cmp -s "$f" "$1" && [ ! -e "$f.tmp" ] && ok=true
    else
      n0=$(nof "$1"); i1=$(info "$f")
      [ "$c" = "$3" ] && [ "$(nof "$f")" = $((n0 + 1)) ] && [ "$(psha "$f")" = "$(psha "$1")" ] && echo "$i1" | grep -q '"dead":true' && ok=true
    fi
    if [ "$ok" = true ]; then nok=$((nok + 1)); else bads="$bads[$2|$c]"; fi
  }
  IFS='|'; set -f
  for l in $MALF; do onecase "$live" "$l" 6 same; onecase "$dead" "$l" 6 same; done
  for l in $OOR; do onecase "$live" "$l" 8 same; onecase "$dead" "$l" 0 consumed; done
  unset IFS; set +f
  # controls: a valid drive is taken on both (alive: n + 1, a new payload; dead: n + 1, the same payload)
  cl=$d/ctl-live; cp "$live" "$cl"; c=0; echo "3 2" | "$RUN" "$cl" > /dev/null 2>&1 || c=$?
  ctl=false; [ "$c" = 0 ] && [ "$(nof "$cl")" = $((N0 + 1)) ] && [ "$(psha "$cl")" != "$(psha "$live")" ] && ctl=true
  onecase "$dead" "3 2" 0 consumed
  ok=false; [ "$nok" = "$nc" ] && [ "$ctl" = true ] && [ "$ld" = '"dead":false' ] && [ "$dd" = '"dead":true' ] && ok=true
  [ "$ok" = true ] || pl5=false
  say "PL5 $tag: states alive $ld / dead $dd; cases $nc, as expected $nok, failing '$bads'; control (valid drive alive) $ctl -> $ok"
  res "PL5.$tag" "{\"live_state\":\"${ld#*:}\",\"dead_state\":\"${dd#*:}\",\"cases\":$nc,\"cases_ok\":$nok,\"control_live\":$ctl,\"pass\":$ok}"
done
say "PL5: $pl5"; res PL5 "$pl5"

# ================= PL4: the S49 check with the new onelife-run =================
say "== PL4: the whole of experiments/onelife_rust_check.sh (a copy writing its results to the work dir), $(date '+%H:%M:%S')"
S49R="experiments/results-rust-onelife.out experiments/results-rust-onelife.json"
shasum -a 256 $S49R > "$W/s49-results-before.txt"
mkdir -p "$W/s49"
sed -e "s|^cd \"\$(dirname \"\$0\")/..\"\$|cd \"$LAB\"|" \
    -e "s|OUT=experiments/results-rust-onelife.out; JSONF=experiments/results-rust-onelife.json|OUT=$W/s49/results.out; JSONF=$W/s49/results.json|" \
    experiments/onelife_rust_check.sh > "$W/s49/onelife_rust_check.sh"
ncd=$(grep -c "^cd \"$LAB\"\$" "$W/s49/onelife_rust_check.sh" || true)
nout=$(grep -c "OUT=$W/s49/results.out; JSONF=$W/s49/results.json" "$W/s49/onelife_rust_check.sh" || true)
nold=$(grep -v '^#' "$W/s49/onelife_rust_check.sh" | grep -c 'experiments/results-rust-onelife\.' || true)
nlines=$(diff experiments/onelife_rust_check.sh "$W/s49/onelife_rust_check.sh" | grep -c '^>' || true)
if [ "$ncd" = 1 ] && [ "$nout" = 1 ] && [ "$nold" = 0 ] && [ "$nlines" = 2 ]; then
  c4=0; sh "$W/s49/onelife_rust_check.sh" > "$W/s49/stdout.txt" 2>&1 || c4=$?
else
  c4=copy
fi
shasum -a 256 $S49R > "$W/s49-results-after.txt"
s49same=false; cmp -s "$W/s49-results-before.txt" "$W/s49-results-after.txt" && s49same=true
R4=$W/s49/results.out
np=0
for k in 'PR1: true' 'PR2: true' 'PR5: true'; do grep -qx "$k" "$R4" 2> /dev/null && np=$((np + 1)); done
grep -q '^PR3: true ' "$R4" 2> /dev/null && np=$((np + 1))
grep -q '^PR4: true ' "$R4" 2> /dev/null && np=$((np + 1))
grep -q '^PR6: .* -> true$' "$R4" 2> /dev/null && np=$((np + 1))
nq=0
for k in Q1 Q2 Q3 Q4 Q5 Q6; do
  qt=$(grep "^$k " "$R4" 2> /dev/null | grep -c -- '-> true' || true)
  qf=$(grep "^$k " "$R4" 2> /dev/null | grep -c -- '-> false' || true)
  if [ "$qt" -ge 1 ] && [ "$qf" = 0 ]; then nq=$((nq + 1)); fi
done
pl4=false; [ "$c4" = 0 ] && [ "$np" = 6 ] && [ "$nq" = 6 ] && [ "$s49same" = true ] && pl4=true
say "PL4: copy edits (cd $ncd, results path $nout, old paths left $nold, lines changed $nlines); exit $c4; PR1-PR6 true $np of 6; Q1-Q6 true $nq of 6; S49 results files unchanged $s49same -> $pl4 ($(date '+%H:%M:%S'); $W/s49/results.out)"
res PL4 "{\"exit\":\"$c4\",\"pr_true\":$np,\"q_true\":$nq,\"s49_results_unchanged\":$s49same,\"results\":\"$W/s49/results.json\",\"pass\":$pl4}"
cp "$R4" "$W/pl4-results.out" 2> /dev/null || true

julia --project=. experiments/onelife_rust_check.jl report "$TSV" "$JSONF"
say "done $(date '+%Y-%m-%d %H:%M:%S'); $JSONF"
