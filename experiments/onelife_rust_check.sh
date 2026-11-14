#!/bin/sh
# S49 (discussion/specs/S49-rust-onelife.md r2; predictions experiments/predictions-rust-onelife.md PR1-PR6): the Rust
# OneLife (rust/being-core/src/onelife.rs) and the executable onelife-run against the Julia reference core/one_life.jl.
# Usage (from anywhere):
#   sh experiments/onelife_rust_check.sh gates   the gates Q1-Q6 on one check life (seed 627, L2, D3); results in the work dir
#   sh experiments/onelife_rust_check.sh         the gates, then PR1-PR6 on the 8 lives (seeds 627-628 x L2, L2+SF x D1, D3,
#                                                N = 10000); results in experiments/results-rust-onelife.{json,out}
# Q0 (sh core/check/run.sh before and after) is run by hand. core/check/out/math-v8.txt (from run.sh) must exist.
set -eu
cd "$(dirname "$0")/.."
MODE=${1:-full}
N=10000
W=$(mktemp -d "${TMPDIR:-/tmp}/onelife-check.XXXXXX")
BT=$PWD/rust/target/release/being-tools
RUN=$PWD/rust/target/release/onelife-run
CT=$W/crash-target
CRUN=$CT/release/onelife-run
if [ "$MODE" = full ]; then OUT=experiments/results-rust-onelife.out; JSONF=experiments/results-rust-onelife.json; else OUT=$W/gates.out; JSONF=$W/gates.json; fi
TSV=$W/res.tsv
: > "$OUT"; : > "$TSV"
say() { echo "$*" | tee -a "$OUT"; }
res() { printf '%s\t%s\n' "$1" "$2" >> "$TSV"; }
nof() { od -An -t u8 -j 16 -N 8 "$1" | tr -d ' \n'; }
psha() { "$BT" onelife-info "$1" | sed 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/'; }
# the SHA-256 of the save after n drives in a .sha file (line n - from + 1)
shaat() { awk -v n="$2" '$1 == n { print $2 }' "$1"; }
jget() { echo "$1" | sed "s/.*\"$2\":\([^,}]*\).*/\1/"; }
say "S49 OneLife Rust check, mode $MODE, work dir $W, $(date '+%Y-%m-%d %H:%M:%S')"

# ---------- Q4: builds without warnings; being-core without dependencies ----------
touch rust/being-core/src/lib.rs rust/being-tools/src/main.rs rust/being-tools/src/bin/onelife-run.rs
(cd rust && cargo build --release -p being-tools) > "$W/build.txt" 2>&1
(cd rust && cargo build --release -p being-tools --features crashpoint --target-dir "$CT") > "$W/build-crash.txt" 2>&1
nw=$(grep -c '^warning' "$W/build.txt" || true)
nwc=$(grep -c '^warning' "$W/build-crash.txt" || true)
ndeps=$(cd rust && cargo tree -p being-core -e normal --prefix none | sort -u | wc -l | tr -d ' ')
q4=false; [ "$nw" = 0 ] && [ "$nwc" = 0 ] && [ "$ndeps" = 1 ] && q4=true
say "Q4 build: warnings $nw (crashpoint build $nwc); being-core crates in its tree $ndeps -> $q4"
res Q4 "{\"warnings\":$nw,\"warnings_crashpoint\":$nwc,\"being_core_tree\":$ndeps,\"pass\":$q4}"

# ---------- Q3: SHA-256 vectors (and the exact sqrt / floor used at birth) ----------
st=$("$BT" onelife-selftest)
q3=false; echo "$st" | grep -q '"sha_vectors":\[true, true, true, true\],"sqrt_mismatch":0,"floor_mismatch":0' && q3=true
say "Q3 sha256 / sqrt / floor: $st -> $q3"
res Q3 "{\"selftest\":$st,\"pass\":$q3}"

# ---------- drives (from the Julia definitions ol_drive / drive_D3) ----------
julia --project=. core/check/onelife_scenarios.jl drives "$W" $N
D1=$W/D1.txt; D3=$W/D3.txt

# ---------- Q1 / PR6: fdlibm exp against Julia's jsexp ----------
ei=$("$BT" onelife-exp core/check/out/math-v8.txt "$D1" "$D3" $N 100 "$W/exp.txt")
ej=$(julia --project=. core/check/onelife_scenarios.jl exp "$W/exp.txt")
fdm=$(jget "$ej" fd_mismatch); stdm=$(jget "$ej" std_mismatch); nin=$(jget "$ej" inputs)
q1=false; [ "$fdm" = 0 ] && [ "$nin" -ge 400000 ] && q1=true
say "Q1 exp: inputs $ei; Julia: $ej -> $q1 (negative control: Rust f64::exp differs from jsexp on $stdm inputs)"
res Q1 "{\"rust\":$ei,\"julia\":$ej,\"pass\":$q1,\"negative_control_std_differs\":$stdm}"

# ---------- Q2: the inputs that reach the state (source check) ----------
SRCS="rust/being-tools/src/bin/onelife-run.rs rust/being-core/src/onelife.rs rust/being-core/src/matter.rs rust/being-core/src/fdexp.rs rust/being-core/src/sha256.rs"
PAT='std::env|env::|std::time|SystemTime|Instant|(^|[^A-Za-z0-9_])rand([^A-Za-z0-9_]|$)|std::net|TcpStream|UdpSocket|getenv|env!|option_env!'
srcbad() { for f in "$@"; do sed 's/std::env::args()//g' "$f" | grep -nE "$PAT" | sed "s|^|$f:|" || true; done; }
bad=$(srcbad $SRCS)
nargs=$(cat $SRCS | grep -o 'std::env::args()' | wc -l | tr -d ' ')
c0=0; "$RUN" > /dev/null 2>&1 || c0=$?
c2=0; "$RUN" a b > /dev/null 2>&1 || c2=$?
mkdir -p "$W/neg"; cp rust/being-tools/src/bin/onelife-run.rs "$W/neg/onelife-run.rs"
echo 'fn _x() { let _ = std::env::var("X"); }' >> "$W/neg/onelife-run.rs"
negbad=$(srcbad "$W/neg/onelife-run.rs")
q2=false; [ -z "$bad" ] && [ "$nargs" = 1 ] && [ "$c0" = 2 ] && [ "$c2" = 2 ] && q2=true
negq2=false; [ -n "$negbad" ] && negq2=true
say "Q2 sources: forbidden uses '${bad}', std::env::args() $nargs time(s), exit with 0 / 2 arguments $c0 / $c2 -> $q2; negative control (std::env::var added) caught: $negq2"
res Q2 "{\"forbidden_found\":$( [ -z "$bad" ] && echo 0 || echo 1 ),\"env_args\":$nargs,\"exit_no_arg\":$c0,\"exit_two_args\":$c2,\"pass\":$q2,\"negative_control_caught\":$negq2}"

# ---------- Q6 (source/binary part): no crash path without the feature ----------
m0=$(strings "$RUN" | grep -c ONELIFE-CRASHPOINT || true)
m1=$(strings "$CRUN" | grep -c ONELIFE-CRASHPOINT || true)
nfeat=$(grep -c 'crashpoint' rust/being-tools/src/bin/onelife-run.rs || true)
ncfg=$(grep -c 'cfg(feature = "crashpoint")' rust/being-tools/src/bin/onelife-run.rs || true)
ncfgn=$(grep -c 'cfg(not(feature = "crashpoint"))' rust/being-tools/src/bin/onelife-run.rs || true)
say "Q6 binaries: crash marker in onelife-run $m0, in the crashpoint build $m1 (negative control); lines naming crashpoint $nfeat = cfg lines $ncfg + $ncfgn + messages"
res Q6bin "{\"marker_release\":$m0,\"marker_crashpoint\":$m1}"

# ---------- one Rust walk for the gates ----------
# life_saves TAG SEED LAW DFILE NSTEPS POINTS: Rust saves of a check life
GPTS="1999,2000,2001,2019,2150,2151,2152,2170"
"$BT" onelife-check 627 L2 "$D3" 2200 "$W/g-627-L2-D3" "$GPTS" > "$W/g.json"

# crash TAG PREFIX DFILE N0: the four crash points at the 2nd save of a run from n0, then the continuation to n0 + 20
crash() {
  tag=$1; pre=$2; df=$3; n0=$4; okall=true; rows=""
  for s in 1 2 3 4; do
    f=$W/c-$tag-$n0-$s; rm -f "$f" "$f.tmp"
    "$BT" onelife-wrap "$pre-$n0.save" "$n0" "$f"
    code=0; sed -n "$((n0 + 1)),$((n0 + 20))p" "$df" | "$CRUN" "$f" --crash $s 2 > /dev/null 2>&1 || code=$?
    if [ $s -lt 4 ]; then want=$((n0 + 1)); else want=$((n0 + 2)); fi
    ref=$W/ref-$tag-$want; [ -f "$ref" ] || "$BT" onelife-wrap "$pre-$want.save" "$want" "$ref"
    same=false; cmp -s "$f" "$ref" && same=true
    n=$(nof "$f")
    c2=0; sed -n "$((n + 1)),$((n0 + 20))p" "$df" | "$RUN" "$f" > /dev/null 2>&1 || c2=$?
    ref20=$W/ref-$tag-$((n0 + 20)); [ -f "$ref20" ] || "$BT" onelife-wrap "$pre-$((n0 + 20)).save" "$((n0 + 20))" "$ref20"
    end=false; cmp -s "$f" "$ref20" && end=true
    ok=false; [ "$code" = 134 ] && [ "$same" = true ] && [ "$c2" = 0 ] && [ "$end" = true ] && ok=true
    [ "$ok" = true ] || okall=false
    rows="$rows{\"stage\":$s,\"abort_exit\":$code,\"file_is_version\":$want,\"complete_version\":$same,\"continue_exit\":$c2,\"end_same\":$end},"
  done
  echo "{\"life\":\"$tag\",\"n0\":$n0,\"rows\":[${rows%,}],\"pass\":$okall}"
}
r1=$(crash g-627-L2-D3 "$W/g-627-L2-D3" "$D3" 1999)
r2=$(crash g-627-L2-D3 "$W/g-627-L2-D3" "$D3" 2150)
q6=false; echo "$r1$r2" | grep -q '"pass":false' || q6=true
[ "$m0" = 0 ] && [ "$m1" -ge 1 ] || q6=false
say "Q6 crash points (627 L2 D3, alive at 1999, dead at 2150): $r1 $r2 -> $q6"
res Q6 "{\"alive\":$r1,\"dead\":$r2,\"marker_release\":$m0,\"marker_crashpoint\":$m1,\"pass\":$q6}"

# ---------- Q5 / PR5 (gate part): refusals on one life ----------
"$BT" onelife-wrap "$W/g-627-L2-D3-1999.save" 1999 "$W/g-live"
"$BT" onelife-wrap "$W/g-627-L2-D3-2150.save" 2150 "$W/g-dead"
rt=$("$BT" onelife-roundtrip "$W/g-live"); rtd=$("$BT" onelife-roundtrip "$W/g-dead")
mf=$(julia --project=. experiments/onelife_rust_check.jl malformed "$RUN" "$W/g-live" "$W/g-dead" "$W/g-work")
q5=false; [ "$rt" = '{"payload_same":true,"file_same":true}' ] && [ "$rtd" = "$rt" ] && echo "$mf" | grep -q '"all_ok":true' && q5=true
say "Q5 run file: round trip $rt / $rtd; cases $mf -> $q5"
res Q5 "{\"roundtrip_live\":$rt,\"roundtrip_dead\":$rtd,\"cases\":$mf,\"pass\":$q5}"

if [ "$MODE" != full ]; then
  julia --project=. experiments/onelife_rust_check.jl report "$TSV" "$JSONF"
  say "gates done: $JSONF"
  exit 0
fi

# ================= PR1-PR6 on the 8 lives =================
PTS="0,1,1999,2000,2001,2019,9970,9971,9972,9990,9999"
LIVES="627:L2:D1 627:L2:D3 627:L2+SF:D1 627:L2+SF:D3 628:L2:D1 628:L2:D3 628:L2+SF:D1 628:L2+SF:D3"
dfile() { if [ "$1" = D1 ]; then echo "$D1"; else echo "$D3"; fi; }
say "== PR1: Julia and Rust, every save n = 0..$N"
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  echo "life $seed $law $(dfile $dr) $N $W/jl-$tag $PTS" > "$W/job-$tag.txt"
  julia --project=. core/check/onelife_scenarios.jl jobs "$W/job-$tag.txt" > "$W/jl-$tag.json" &
  "$BT" onelife-check $seed $law "$(dfile $dr)" $N "$W/rs-$tag" "$PTS" > "$W/rs-$tag.json" &
done
wait
pr1=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  diffs=$(paste -d' ' "$W/jl-$tag.sha" "$W/rs-$tag.sha" | awk '$1 != $3 || $2 != $4 { c++; if (f == "") f = $1 } END { print c + 0, (f == "" ? "null" : f) }')
  lines=$(wc -l < "$W/rs-$tag.sha" | tr -d ' '); jlines=$(wc -l < "$W/jl-$tag.sha" | tr -d ' ')
  fin=false; cmp -s "$W/jl-$tag-$N.save" "$W/rs-$tag-$N.save" && fin=true
  jd=$(jget "$(cat "$W/jl-$tag.json")" dead_at); rd=$(jget "$(cat "$W/rs-$tag.json")" dead_at)
  nd=${diffs%% *}; ok=false; [ "$nd" = 0 ] && [ "$lines" = $((N + 1)) ] && [ "$jlines" = "$lines" ] && [ "$fin" = true ] && [ "$jd" = "$rd" ] && ok=true
  [ "$ok" = true ] || pr1=false
  say "PR1 $tag: saves compared $lines, differing ${diffs} (count, first n), final save same $fin, dead after n = $jd (Julia) / $rd (Rust) -> $ok"
  res "PR1.$tag" "{\"saves\":$lines,\"differing\":${diffs%% *},\"first_differing\":${diffs#* },\"final_same\":$fin,\"dead_at_julia\":$jd,\"dead_at_rust\":$rd,\"pass\":$ok}"
  echo "$rd" > "$W/d-$tag"
done
say "PR1: $pr1"; res PR1 "$pr1"

say "== PR2: cross loading (Julia save -> Rust, Rust save -> Julia) and continuation to $N"
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr; df=$(dfile $dr); d=$(cat "$W/d-$tag")
  pts="0 1999 2000 9999"
  if [ "$d" != null ]; then
    echo "life $seed $law $df $((d + 1)) $W/jl2-$tag $((d - 1)),$d" > "$W/job2-$tag.txt"
    julia --project=. core/check/onelife_scenarios.jl jobs "$W/job2-$tag.txt" > /dev/null
    "$BT" onelife-check $seed $law "$df" $((d + 1)) "$W/rs2-$tag" "$((d - 1)),$d" > /dev/null
    pts="0 1999 2000 $((d - 1)) $d $((d + 1)) 9999"
  fi
  echo "$pts" > "$W/pts-$tag"
  : > "$W/job3-$tag.txt"
  for p in $pts; do
    jf=$W/jl-$tag-$p.save; [ -f "$jf" ] || jf=$W/jl2-$tag-$p.save
    rf=$W/rs-$tag-$p.save; [ -f "$rf" ] || rf=$W/rs2-$tag-$p.save
    echo "continue $rf $law $df $p $N $W/x-jr-$tag-$p" >> "$W/job3-$tag.txt"
  done
  (julia --project=. core/check/onelife_scenarios.jl jobs "$W/job3-$tag.txt" > /dev/null) &
  (for p in $pts; do
     jf=$W/jl-$tag-$p.save; [ -f "$jf" ] || jf=$W/jl2-$tag-$p.save
     "$BT" onelife-continue "$jf" "$df" $p $N "$W/x-rj-$tag-$p" > /dev/null
   done) &
done
wait
pr2=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr; rows=""; ok=true
  for p in $(cat "$W/pts-$tag"); do
    jf=$W/jl-$tag-$p.save; [ -f "$jf" ] || jf=$W/jl2-$tag-$p.save
    rf=$W/rs-$tag-$p.save; [ -f "$rf" ] || rf=$W/rs2-$tag-$p.save
    same0=false; cmp -s "$jf" "$rf" && same0=true
    a=false; tail -n +$((p + 1)) "$W/jl-$tag.sha" | cmp -s - "$W/x-rj-$tag-$p.sha" && cmp -s "$W/x-rj-$tag-$p-$N.save" "$W/jl-$tag-$N.save" && a=true
    b=false; tail -n +$((p + 1)) "$W/rs-$tag.sha" | cmp -s - "$W/x-jr-$tag-$p.sha" && cmp -s "$W/x-jr-$tag-$p-$N.save" "$W/rs-$tag-$N.save" && b=true
    [ "$same0" = true ] && [ "$a" = true ] && [ "$b" = true ] || ok=false
    rows="$rows{\"n\":$p,\"saves_same\":$same0,\"julia_save_in_rust\":$a,\"rust_save_in_julia\":$b},"
  done
  [ "$ok" = true ] || pr2=false
  say "PR2 $tag: points $(cat "$W/pts-$tag") -> $ok"
  res "PR2.$tag" "{\"rows\":[${rows%,}],\"pass\":$ok}"
done
say "PR2: $pr2"; res PR2 "$pr2"

say "== PR3 / PR4: onelife-run uninterrupted and interrupted (SIGKILL after n = 1, 1999, 2000, 6000, 9998; normal ends between)"
SEGS="1:K 1999:K 2000:K 2500:E 3000:E 3500:E 4000:E 4500:E 5000:E 5500:E 6000:K 6500:E 7000:E 7500:E 8000:E 8500:E 9000:E 9500:E 9998:K 10000:E"
life_run() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$(cat "$W/d-$tag")
  u=$W/u-$tag; i=$W/i-$tag; R=$W/pr3-$tag.tsv; : > "$R"
  "$BT" onelife-birth-run $seed $law "$u"; "$BT" onelife-birth-run $seed $law "$i"
  cu=0; "$RUN" "$u" < "$df" > /dev/null 2>&1 || cu=$?
  nu=$(nof "$u"); pu=$(psha "$u")
  kills=0; killok=0; eok=0; enum=0; post=0; postok=0; startok=0; nseg=0
  for sg in $SEGS; do
    to=${sg%%:*}; mode=${sg#*:}; from=$(nof "$i"); nseg=$((nseg + 1))
    if [ "$mode" = K ]; then
      fifo=$W/fifo-$tag; rm -f "$fifo"; mkfifo "$fifo"
      "$RUN" "$i" < "$fifo" > /dev/null 2>&1 &
      pid=$!
      exec 9> "$fifo"
      sed -n "$((from + 1)),${to}p" "$df" >&9
      while [ "$(nof "$i")" != "$to" ] && kill -0 $pid 2> /dev/null; do sleep 0.05; done
      kill -9 $pid 2> /dev/null || true
      code=0; wait $pid || code=$?
      exec 9>&-
      rm -f "$fifo"
      kills=$((kills + 1)); [ "$code" = 137 ] && [ "$(nof "$i")" = "$to" ] && killok=$((killok + 1))
    else
      code=0; sed -n "$((from + 1)),${to}p" "$df" | "$RUN" "$i" > /dev/null 2>&1 || code=$?
      enum=$((enum + 1)); [ "$code" = 0 ] && [ "$(nof "$i")" = "$to" ] && eok=$((eok + 1))
    fi
    p=$(psha "$i")
    [ "$p" = "$(shaat "$W/jl-$tag.sha" "$to")" ] && startok=$((startok + 1))
    if [ "$d" != null ] && [ "$to" -ge "$d" ]; then
      post=$((post + 1)); [ "$p" = "$(shaat "$W/jl-$tag.sha" "$d")" ] && postok=$((postok + 1))
    fi
  done
  same=false; cmp -s "$i" "$u" && same=true
  fin=false; [ "$pu" = "$(shaat "$W/jl-$tag.sha" $N)" ] && fin=true
  ok3=false; [ "$cu" = 0 ] && [ "$nu" = $N ] && [ "$same" = true ] && [ "$fin" = true ] && [ "$kills" = 5 ] && [ "$killok" = 5 ] && [ "$eok" = "$enum" ] && [ "$startok" = "$nseg" ] && ok3=true
  printf '%s\t%s\n' "PR3.$tag" "{\"uninterrupted_exit\":$cu,\"uninterrupted_n\":$nu,\"uninterrupted_payload_is_julia\":$fin,\"kills\":$kills,\"kills_ok\":$killok,\"normal_ends\":$enum,\"normal_ends_ok\":$eok,\"segments_payload_is_julia\":$startok,\"segments\":$nseg,\"final_file_same\":$same,\"pass\":$ok3}" >> "$R"
  if [ "$d" != null ]; then
    pud=false; [ "$pu" = "$(shaat "$W/jl-$tag.sha" "$d")" ] && pud=true
    ok4=false; [ "$cu" = 0 ] && [ "$nu" = $N ] && [ "$pud" = true ] && [ "$post" -gt 0 ] && [ "$postok" = "$post" ] && [ "$eok" = "$enum" ] && ok4=true
    printf '%s\t%s\n' "PR4.$tag" "{\"dead_at\":$d,\"uninterrupted_end_payload_is_dead_payload\":$pud,\"checks_after_death\":$post,\"payload_unchanged\":$postok,\"final_n\":$nu,\"pass\":$ok4}" >> "$R"
  fi
}
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}
  (life_run $seed $law $dr) &
done
wait
pr3=true; pr4=true; n4=0
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  cat "$W/pr3-$tag.tsv" >> "$TSV"
  while IFS="$(printf '\t')" read -r k v; do
    say "$k $v"
    case "$k" in
      PR3.*) echo "$v" | grep -q '"pass":true' || pr3=false ;;
      PR4.*) n4=$((n4 + 1)); echo "$v" | grep -q '"pass":true' || pr4=false ;;
    esac
  done < "$W/pr3-$tag.tsv"
done

say "== PR3 (crash points): all 8 lives, from n0 = 1999 and 9970"
pr3c=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  for n0 in 1999 9970; do
    c=$(crash "$tag" "$W/rs-$tag" "$(dfile $dr)" $n0)
    echo "$c" | grep -q '"pass":true' || pr3c=false
    say "PR3c $c"
    res "PR3c.$tag.$n0" "$c"
  done
done
[ "$pr3c" = true ] || pr3=false
say "PR3: $pr3 (crash part $pr3c)"; res PR3 "$pr3"
if [ "$n4" = 0 ]; then say "PR4: not checked (no D3 life died)"; res PR4 '"not checked"'; else say "PR4: $pr4 ($n4 D3 lives died)"; res PR4 "$pr4"; fi

say "== PR5: 200 one-bit flips per life (at n = 1999), and the refusals of Q5 on every life"
pr5=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  "$BT" onelife-wrap "$W/rs-$tag-1999.save" 1999 "$W/b-$tag"
  # a dead state for the control "out-of-range drive on a dead state is consumed": the D3 life of the same seed and law
  "$BT" onelife-wrap "$W/rs-$seed-$law-D3-9999.save" 9999 "$W/e-$tag"
  fl=$(julia --project=. experiments/onelife_rust_check.jl flips "$RUN" "$W/b-$tag" $seed "$W/f-$tag")
  mf=$(julia --project=. experiments/onelife_rust_check.jl malformed "$RUN" "$W/b-$tag" "$W/e-$tag" "$W/m-$tag")
  ok=false; echo "$fl" | grep -q '"refused":200' && echo "$fl" | grep -q '"unchanged":200' && ok=true
  ctrl=$(echo "$mf" | grep -o '"all_ok":[a-z]*')
  say "PR5 $tag: flips $fl; Q5 cases on this life $ctrl -> $ok"
  res "PR5.$tag" "{\"flips\":$fl,\"cases\":$mf,\"pass\":$ok}"
  [ "$ok" = true ] || pr5=false
  [ "$ctrl" = '"all_ok":true' ] || pr5=false
done
say "PR5: $pr5"; res PR5 "$pr5"

pr6=$q1; [ "$pr1" = true ] || pr6=false
say "PR6: exp on the 400,000 inputs and the sampled life arguments $q1; every exp argument of the 8 lives (implied by PR1) $pr1 -> $pr6"
res PR6 "$pr6"
julia --project=. experiments/onelife_rust_check.jl report "$TSV" "$JSONF"
say "done $(date '+%Y-%m-%d %H:%M:%S'); $JSONF"
