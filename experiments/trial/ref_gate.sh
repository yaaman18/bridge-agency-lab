#!/bin/sh
# S54 §2 (discussion/specs/S54-trial-run.md r4): the reference gate of the two rehearsal lives and of the life of the
# stop-and-start rehearsal (§5), on the Mac. Needs experiments/trial-data from experiments/trial/make_trial.jl and the
# S49d builds in BUILD (build_d.sh).
#   R1 the Julia birth saves wrapped by "being-tools onelife-wrap" (n = 0): the run file's payload SHA = Julia's at n = 0
#      (lives 669-L2 -> run0-669-L2, 669-L2SF -> run0-669-L2SF, 627-L2-D1 -> rehearsal-run0); for the rehearsal life
#      also: byte-identical to "being-tools onelife-birth-run 627 L2" (the S49 comparison life)
#   R2 the Mac fast build (fastinterval) from the wrapped run file with an empty audit, all 60480 drives: every commit
#      line carries Julia's SHA of its n, every n in 1..60480 has exactly one commit, the final run file is
#      byte-identical to Julia's final save wrapped at n = 60480; all three lives
#   negative controls: one hex digit of one commit SHA changed in a copy of the audit is caught; the L2 audit against
#      the L2SF reference is caught
# Usage: sh experiments/trial/ref_gate.sh BUILD     (lines appended to experiments/results-trial-ref.out)
set -eu
cd "$(dirname "$0")/../.."
[ $# -eq 1 ] || { echo "usage: ref_gate.sh BUILD"; exit 2; }
B=$1
BT=$B/mac-prod/release/being-tools
FRUN=$B/mac-fast/release/onelife-run
D=experiments/trial-data
OUT=experiments/results-trial-ref.out
NDR=60480
W=$(mktemp -d "${TMPDIR:-/tmp}/s54-ref.XXXXXX")
touch "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
psha() { "$BT" onelife-info "$1" | sed 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/'; }
nof() { od -An -t u8 -j 16 -N 8 "$1" | tr -d ' \n'; }
# commits REF AUDIT: "ok bad distinct_n first_bad_n"
commits() { awk 'NR == FNR { r[$1] = $2; next } $1 == "commit" { if (r[$2] == $3) ok++; else { bad++; if (fb == "") fb = $2 }; if (!($2 in s)) { s[$2] = 1; nd++ } } END { print ok + 0, bad + 0, nd + 0, (fb == "" ? "null" : fb) }' "$1" "$2"; }
# per life: the tag of the Julia files, the run0 name, the drives file
run0() { case $1 in 627-L2-D1) echo rehearsal-run0 ;; *) echo "run0-$1" ;; esac; }
drv() { case $1 in 627-L2-D1) echo "$D/rehearsal-drives-D1.txt" ;; *) echo "$D/drives-669.txt" ;; esac; }
LIVES="669-L2 669-L2SF 627-L2-D1"
say ""
say "S54 reference gate, build $B, work dir $W, $(date '+%Y-%m-%d %H:%M:%S'); drives-669.txt $(fsha $D/drives-669.txt) ($(wc -l < $D/drives-669.txt | tr -d ' ') lines); rehearsal-drives-D1.txt $(fsha $D/rehearsal-drives-D1.txt) ($(wc -l < $D/rehearsal-drives-D1.txt | tr -d ' ') lines; first 3000 lines = core/check/out/onelife-drives/D1.txt $(head -3000 "$D/rehearsal-drives-D1.txt" | cmp -s - core/check/out/onelife-drives/D1.txt && echo true || echo false)); make_trial.json $(cat $D/make_trial.json)"
ok=true
for t in $LIVES; do
  r=$D/$(run0 $t)
  "$BT" onelife-wrap "$D/birth-$t.save" 0 "$r"
  "$BT" onelife-wrap "$D/final-$t.save" $NDR "$W/final-$t"
  r0=$(awk '$1 == 0 { print $2 }' "$D/ref-$t.sha")
  r1=false; [ "$(psha "$r")" = "$r0" ] && [ "$(nof "$r")" = 0 ] && r1=true
  ex=""
  if [ "$t" = 627-L2-D1 ]; then
    "$BT" onelife-birth-run 627 L2 "$W/birth-run-627"
    br=false; cmp -s "$W/birth-run-627" "$r" && br=true
    [ "$br" = true ] || r1=false
    ex="; = onelife-birth-run 627 L2 $br"
  fi
  say "R1 $t: wrapped run file $(basename "$r") $(fsha "$r") n $(nof "$r"), payload SHA $(psha "$r") = Julia's at n = 0 ($r0)$ex: $r1"
  [ "$r1" = true ] || ok=false
done
for t in $LIVES; do
  cp "$D/$(run0 $t)" "$W/r-$t"; : > "$W/r-$t.audit"
  (c=0; "$FRUN" "$W/r-$t" < "$(drv $t)" > /dev/null 2> "$W/err-$t" || c=$?; echo $c > "$W/exit-$t") &
done
wait
for t in $LIVES; do
  c=$(cat "$W/exit-$t"); set -- $(commits "$D/ref-$t.sha" "$W/r-$t.audit")
  fin=false; cmp -s "$W/r-$t" "$W/final-$t" && fin=true
  r2=false; [ "$c" = 0 ] && [ "$1" = $NDR ] && [ "$2" = 0 ] && [ "$3" = $NDR ] && [ "$fin" = true ] && r2=true
  a=$("$BT" onelife-audit "$W/r-$t" | cut -c1-200)
  say "R2 $t: exit $c; commits with Julia's SHA $1, other $2 (first $4), distinct n $3 of $NDR; final run file = Julia's final save wrapped $fin ($(fsha "$W/r-$t")); audit $(fsha "$W/r-$t.audit") ($a): $r2"
  [ "$r2" = true ] || ok=false
done
perl -pe 'if (/^commit / && ++$c == 30000) { s/^(commit \d+ )(.)/$1 . ($2 eq "0" ? "1" : "0")/e }' "$W/r-669-L2.audit" > "$W/neg.audit"
set -- $(commits "$D/ref-669-L2.sha" "$W/neg.audit"); n1=false; [ "$2" = 1 ] && n1=true
set -- $(commits "$D/ref-669-L2SF.sha" "$W/r-669-L2.audit"); n2=false; [ "$2" != 0 ] && n2=true
say "negative controls: one changed commit caught $n1; L2 audit against the L2SF reference caught $n2 (other $2, first $4)"
[ "$n1" = true ] && [ "$n2" = true ] || ok=false
for t in $LIVES; do cp "$W/r-$t.audit" "$D/mac-fast-$t.audit"; done
say "reference gate: $ok ($(date '+%Y-%m-%d %H:%M:%S'))"
[ "$ok" = true ]
