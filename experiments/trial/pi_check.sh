#!/bin/sh
# S54 §3 and §4 (discussion/specs/S54-trial-run.md r4): the checks on the Pi. Written on the Pi: /dev/shm/s54-c1/ (RAM;
# the wrapper tests and C1) and /home/pi/s54/ (C2 in c2/, the placed lives in t1/, t2/, rehearsal/, the units in units/).
# BUILD is the dir of experiments/trial/build_d.sh; the inputs and references are in experiments/trial-data.
# Usage: sh experiments/trial/pi_check.sh BUILD MODE
#   wrapper     experiments/trial/wrapper_test.sh on the Pi (/dev/shm/s54-c1/wrapper; Pi fast build), appended to
#               experiments/results-trial-wrapper.out
#   c1-start    C1: pushes (SHA compared on both sides) the wrapper, the Pi fast build, the drives and the two wrapped
#               birth run files with empty audits into /dev/shm/s54-c1/t1 (L2), /dev/shm/s54-c1/t2 (L2SF) and starts each life's
#               wrapper with nohup on the Pi. Started again it pushes nothing and only restarts a life whose wrapper is
#               not running and has not ended (the wrapper goes on from the run file's n); a life that ended stays.
#   c1-status   n of each life (onelife-info on the Pi), running or ended (exit code)
#   c1-verify   C1 verdict: both ended with exit 0; run file and audit copied back (SHA compared); every commit line
#               carries the reference SHA of its n, every n in 1..60480 has a commit; the final run file is
#               byte-identical to Julia's final save wrapped at 60480. Negative control: one changed commit is caught.
#   place       puts the lives (t1, t2, rehearsal: wrapper, production build, drives, run file n = 0, empty audit)
#               and the units (units/, only placed) on the Pi; refuses a dir that has a run file; runs nothing there
#   list        the SHA-256 of the placed files and n of each placed run file
#   c2          C2: the Pi production build, the wrapper, 12 drives (/home/pi/s54/c2): wall time on the Mac's clock >= 110 s, the
#               12 commits carry the reference SHA, n = 12. Negative control: the fast build the same way (/home/pi/s54/c2/neg)
#               takes < 110 s.
# C1 and C2 are appended to experiments/results-trial-pi-check.out. The Pi's clock is not used for any verdict.
set -eu
cd "$(dirname "$0")/../.."
[ $# -eq 2 ] || { echo "usage: pi_check.sh BUILD MODE"; exit 2; }
B=$1; MODE=$2
HOST=pi@bridge-pi.local
SHM=/dev/shm/s54-c1
BASE=/home/pi/s54
D=experiments/trial-data
MBT=$B/mac-prod/release/being-tools
PFB=$B/pi-fast/aarch64-unknown-linux-musl/release
PPB=$B/pi-prod/aarch64-unknown-linux-musl/release
NDR=60480
OUT=experiments/results-trial-pi-check.out
W=$(mktemp -d "${TMPDIR:-/tmp}/s54-pi.XXXXXX")
touch "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
nof() { od -An -t u8 -j 16 -N 8 "$1" | tr -d ' \n'; }
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
pis() { ssh -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=8 "$HOST" "$@"; }
# push LOCAL REMOTE_PATH: copy and compare the SHA-256 on both sides (prints true / false)
push() {
  scp -q -o BatchMode=yes "$1" "$HOST:$2"
  r=$(pis sha256sum "$2" | awk '{print $1}')
  if [ "$r" = "$(fsha "$1")" ]; then echo true; else echo false; fi
}
# fetch REMOTE_PATH LOCAL: copy back and compare the SHA-256 (prints true / false)
fetch() {
  scp -q -o BatchMode=yes "$HOST:$1" "$2"
  r=$(pis sha256sum "$1" | awk '{print $1}')
  if [ "$r" = "$(fsha "$2")" ]; then echo true; else echo false; fi
}
commits() { awk 'NR == FNR { r[$1] = $2; next } $1 == "commit" { if (r[$2] == $3) ok++; else { bad++; if (fb == "") fb = $2 }; if (!($2 in s)) { s[$2] = 1; nd++ } } END { print ok + 0, bad + 0, nd + 0, (fb == "" ? "null" : fb) }' "$1" "$2"; }
tag() { if [ "$1" = t1 ]; then echo L2; else echo L2SF; fi; }

case "$MODE" in
wrapper)
  R=experiments/results-trial-wrapper.out; P=$SHM/wrapper
  pis "mkdir -p $P"
  np=0
  for f in experiments/trial/wrapper_test.sh experiments/trial/s54-run.sh "$PFB/being-tools" "$PFB/onelife-run" "$D/drives-669.txt" "$D/birth-669-L2.save"; do
    [ "$(push "$f" "$P/$(basename "$f")")" = true ] && np=$((np + 1))
  done
  echo "" >> "$R"
  echo "S54 wrapper tests on the Pi ($HOST:$P/w; Pi fast build; pushed files with the same SHA $np of 6), Mac time $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$R"
  c=0; pis "cd $P && sh wrapper_test.sh $P/w $P/s54-run.sh $P/being-tools $P/onelife-run $P/drives-669.txt $P/birth-669-L2.save" > "$W/pi-wrapper.txt" 2>&1 || c=$?
  tee -a "$R" < "$W/pi-wrapper.txt"
  echo "wrapper tests on the Pi: exit $c, pushed $np of 6" | tee -a "$R"
  [ "$c" = 0 ] && [ "$np" = 6 ] ;;

c1-start)
  P=$SHM
  if pis "test -e $P/t1/run"; then
    say "C1 start again ($(date '+%Y-%m-%d %H:%M:%S')): nothing pushed"
  else
    pis "mkdir -p $P/t1 $P/t2"
    np=0
    for t in t1 t2; do
      for f in experiments/trial/s54-run.sh "$PFB/being-tools" "$PFB/onelife-run"; do [ "$(push "$f" "$P/$t/$(basename "$f")")" = true ] && np=$((np + 1)); done
      [ "$(push "$D/drives-669.txt" "$P/$t/drives.txt")" = true ] && np=$((np + 1))
      [ "$(push "$D/run0-669-$(tag $t)" "$P/$t/run")" = true ] && np=$((np + 1))
      pis "chmod 755 $P/$t/being-tools $P/$t/onelife-run && : > $P/$t/run.audit"
    done
    cat > "$W/c1.sh" << 'EOF'
#!/bin/sh
# S54 C1, the Pi side (written by experiments/trial/pi_check.sh): starts each life's wrapper with nohup unless it is
# running (its lock is held) or has ended (t?.exit exists).
P=$(cd "$(dirname "$0")" && pwd)
for t in t1 t2; do
  if [ -e "$P/$t.exit" ]; then echo "$t ended: exit $(cat "$P/$t.exit")"; continue; fi
  if ! flock -n "$P/$t/s54-run.lock" true; then echo "$t running"; continue; fi
  nohup sh -c "sh '$P/$t/s54-run.sh' '$P/$t'; echo \$? > '$P/$t.exit'" >> "$P/$t.log" 2>&1 < /dev/null &
  echo "$t started"
done
EOF
    [ "$(push "$W/c1.sh" "$P/c1.sh")" = true ] && np=$((np + 1))
    say "C1 pushed to $HOST:$P (wrapper, Pi fast build, drives, wrapped birth run files, c1.sh): same SHA $np of 11 ($(date '+%Y-%m-%d %H:%M:%S'))"
    [ "$np" = 11 ] || { say "C1 not started: a pushed file differs"; exit 1; }
  fi
  pis "sh $P/c1.sh" | while read -r l; do say "C1 $l"; done ;;

c1-status)
  P=$SHM
  for t in t1 t2; do
    s=$(pis "cd $P && if [ -e $t.exit ]; then echo ended exit \$(cat $t.exit); elif flock -n $t/s54-run.lock true; then echo not running; else echo running; fi; ./$t/being-tools onelife-info $t/run | cut -c1-40")
    echo "C1 $t: $(echo $s) (Mac time $(date '+%H:%M:%S'))"
  done ;;

c1-verify)
  P=$SHM; ok=true; rows=""
  for t in t1 t2; do
    x=$(tag $t)
    e=$(pis "cat $P/$t.exit 2> /dev/null || echo none")
    f1=$(fetch "$P/$t/run" "$W/$t-run"); f2=$(fetch "$P/$t/run.audit" "$W/$t-run.audit")
    "$MBT" onelife-wrap "$D/final-669-$x.save" $NDR "$W/$t-final"
    set -- $(commits "$D/ref-669-$x.sha" "$W/$t-run.audit")
    fin=false; cmp -s "$W/$t-run" "$W/$t-final" && fin=true
    a=$("$MBT" onelife-audit "$W/$t-run" | cut -c1-260)
    v=false; [ "$e" = 0 ] && [ "$f1" = true ] && [ "$f2" = true ] && [ "$2" = 0 ] && [ "$3" = $NDR ] && [ "$fin" = true ] && v=true
    say "C1 $t ($x): wrapper exit $e; copied back with the same SHA $f1 $f2; n $(nof "$W/$t-run"); commits with the reference SHA $1, other $2 (first $4), distinct n $3 of $NDR; final run file = Julia's final save wrapped $fin; audit $(fsha "$W/$t-run.audit") $a -> $v"
    [ "$v" = true ] || ok=false
  done
  perl -pe 'if (/^commit / && ++$c == 40000) { s/^(commit \d+ )(.)/$1 . ($2 eq "0" ? "1" : "0")/e }' "$W/t1-run.audit" > "$W/neg.audit"
  set -- $(commits "$D/ref-669-L2.sha" "$W/neg.audit"); ng=false; [ "$2" = 1 ] && ng=true
  [ "$ng" = true ] || ok=false
  say "C1: $ok (negative control: one changed commit caught $ng) $(date '+%Y-%m-%d %H:%M:%S')" ;;

c2)
  ok=true
  for k in c2 c2neg; do
    if [ $k = c2 ]; then P=$BASE/c2; X=$PPB; else P=$BASE/c2/neg; X=$PFB; fi
    if pis "test -e $P/run"; then say "C2: $P exists; not run again"; exit 1; fi
    pis "mkdir -p $P"
    head -12 "$D/drives-669.txt" > "$W/drives12.txt"
    np=0
    for f in experiments/trial/s54-run.sh "$X/being-tools" "$X/onelife-run"; do [ "$(push "$f" "$P/$(basename "$f")")" = true ] && np=$((np + 1)); done
    [ "$(push "$W/drives12.txt" "$P/drives.txt")" = true ] && np=$((np + 1))
    [ "$(push "$D/run0-669-L2" "$P/run")" = true ] && np=$((np + 1))
    pis "chmod 755 $P/being-tools $P/onelife-run && : > $P/run.audit"
    t0=$(now); c=0; pis "sh $P/s54-run.sh $P" > /dev/null 2> "$W/$k.err" || c=$?; t1=$(now)
    el=$(echo "$t1 - $t0" | bc)
    f2=$(fetch "$P/run.audit" "$W/$k.audit"); f1=$(fetch "$P/run" "$W/$k.run")
    set -- $(commits "$D/ref-669-L2.sha" "$W/$k.audit")
    if [ $k = c2 ]; then
      ge=$(echo "$el >= 110" | bc)
      v=false; [ "$np" = 5 ] && [ "$c" = 0 ] && [ "$ge" = 1 ] && [ "$1" = 12 ] && [ "$2" = 0 ] && [ "$3" = 12 ] && [ "$(nof "$W/$k.run")" = 12 ] && [ "$f1" = true ] && [ "$f2" = true ] && v=true
      say "C2 production build on the Pi, 12 drives through the wrapper: pushed $np of 5; exit $c; wall time on the Mac ${el} s (>= 110 $ge); commits with the reference SHA $1, other $2, distinct n $3; n $(nof "$W/$k.run") -> $v"
    else
      lt=$(echo "$el < 110" | bc)
      v=false; [ "$c" = 0 ] && [ "$lt" = 1 ] && [ "$1" = 12 ] && [ "$2" = 0 ] && v=true
      say "C2 negative control, the fast build the same way: exit $c; wall time on the Mac ${el} s (< 110 $lt); commits with the reference SHA $1, other $2 -> $v"
    fi
    [ "$v" = true ] || ok=false
  done
  say "C2: $ok $(date '+%Y-%m-%d %H:%M:%S')" ;;

place)
  # the lives of the trial (t1 = 669-L2, t2 = 669-L2SF) and of the stop-and-start rehearsal (rehearsal = 627-L2-D1):
  # the wrapper, the Pi production build, the drives, the wrapped birth run file (n = 0), an empty audit; the units
  # in units/ (only placed; not installed, not enabled, not started). Nothing is run there. Refuses a dir with a run.
  ok=true
  for t in t1 t2 rehearsal; do
    P=$BASE/$t
    if pis "test -e $P/run"; then say "place: $P/run exists; nothing placed there"; ok=false; continue; fi
    case $t in t1) r=$D/run0-669-L2; dr=$D/drives-669.txt ;; t2) r=$D/run0-669-L2SF; dr=$D/drives-669.txt ;; rehearsal) r=$D/rehearsal-run0; dr=$D/rehearsal-drives-D1.txt ;; esac
    pis "mkdir -p $P"
    np=0
    for f in experiments/trial/s54-run.sh "$PPB/being-tools" "$PPB/onelife-run"; do [ "$(push "$f" "$P/$(basename "$f")")" = true ] && np=$((np + 1)); done
    [ "$(push "$dr" "$P/drives.txt")" = true ] && np=$((np + 1))
    [ "$(push "$r" "$P/run")" = true ] && np=$((np + 1))
    pis "chmod 755 $P/being-tools $P/onelife-run && : > $P/run.audit"
    say "place $t: pushed with the same SHA $np of 5 (run from $(basename "$r"), drives $(basename "$dr")); empty run.audit"
    [ "$np" = 5 ] || ok=false
  done
  pis "mkdir -p $BASE/units"
  nu=0
  for u in s54-trial-1 s54-trial-2 s54-rehearsal; do [ "$(push "experiments/trial/$u.service" "$BASE/units/$u.service")" = true ] && nu=$((nu + 1)); done
  say "place units (only placed in $BASE/units): same SHA $nu of 3"
  [ "$nu" = 3 ] || ok=false
  say "place: $ok $(date '+%Y-%m-%d %H:%M:%S')"
  [ "$ok" = true ] ;;

rehearsal-check)
  # S54 §5, read only on the Pi: one copy each of the rehearsal's run file and audit; n and payload SHA against the
  # reference 627-L2-D1; every commit line against the reference; the audit report (breaks, audit behind, starts);
  # boot id, the unit, S52's unit (is-active only), throttled, ext4 errors in the kernel log that remains, tune2fs.
  R=experiments/results-trial-rehearsal.out; P=$BASE/rehearsal; ref=$D/ref-627-L2-D1.sha
  pis "cat $P/run" > "$W/r"; pis "cat $P/run.audit" > "$W/r.audit"
  sys=$(pis 'cat /proc/sys/kernel/random/boot_id; systemctl is-active s54-rehearsal 2> /dev/null || true; systemctl is-active s52-ambient-log 2> /dev/null || true; vcgencmd get_throttled; echo "ext4 errors in dmesg $(sudo -n dmesg 2> /dev/null | grep -ci "ext4-fs error" || true)"; sudo -n tune2fs -l /dev/mmcblk0p2 2> /dev/null | grep -E "^(Filesystem state|FS Error count|Last mount time)" | tr -s " " | tr "\n" ";"')
  i=$("$MBT" onelife-info "$W/r"); n=$(echo "$i" | sed -n 's/^{"n":\([0-9]*\),.*/\1/p'); s=$(echo "$i" | sed -n 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/p')
  m=false; [ -n "$n" ] && [ "$s" = "$(awk -v n="$n" '$1 == n { print $2 }' "$ref")" ] && m=true
  set -- $(commits "$ref" "$W/r.audit")
  a=$("$MBT" onelife-audit "$W/r")
  {
    echo ""
    echo "S54 rehearsal check, Mac time $(date '+%Y-%m-%d %H:%M:%S') (epoch $(date +%s))"
    echo "Pi: $(echo $sys)"
    echo "run file copy $(fsha "$W/r"): n $n, payload SHA = reference at n $m; audit copy $(fsha "$W/r.audit"): commits with the reference SHA $1, other $2 (first $4), distinct n $3"
    echo "audit report $a"
  } | tee -a "$R" ;;

list)
  pis "cd $BASE && find t1 t2 rehearsal units -type f | LC_ALL=C sort | xargs sha256sum; for t in t1 t2 rehearsal; do echo \"\$t: \$(./\$t/being-tools onelife-info \$t/run | cut -c1-120); audit bytes \$(wc -c < \$t/run.audit)\"; done" ;;

*) echo "usage: pi_check.sh BUILD wrapper|c1-start|c1-status|c1-verify|c2|place|list"; exit 2 ;;
esac
