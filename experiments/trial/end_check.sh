#!/bin/sh
# S54 §6 (discussion/specs/S54-trial-run.md r4) and PT1, PT3 (experiments/predictions-trial-run.md): the check of one
# life at the end of the trial, on the Mac, on copies only (one copy of the run file, one copy of its audit).
# Usage: sh experiments/trial/end_check.sh BEING_TOOLS RUN AUDIT REF [BOOTS]
#   REF    the reference lines "n sha" (experiments/trial-data/ref-669-L2.sha or ref-669-L2SF.sha)
#   BOOTS  the number of OS boots after the trial was started: distinct boot ids in the watch file (and S52's log) minus
#          the boot id at the start. When given, PT3's "starts <= boots + 1": the + 1 is the one start by hand at the
#          beginning; each boot starts the enabled unit once (Restart=no, experiments/trial/s54-trial-1.service and -2),
#          This checks only the total (starts > BOOTS + 1 is FAIL). It does not detect an extra start within one boot
#          when another boot had no start (e.g. 0 starts in one boot and 2 in the next pass); that would need the start
#          lines matched to boots, which this script does not do.
# Prints one line of counts and a verdict line. Exit 1 (FAIL) when: the run file is not read, its payload SHA is not
# the reference SHA of its n, the audit is empty or has no commit line, a commit line carries another SHA than the
# reference of its n (PT1 miss, reported with the first n), the audit chain is broken, starts > BOOTS + 1, or a commit
# line has an n beyond the run file's n (the audit says a step was committed that the run file does not hold; r4
# reading (i) excuses only missing commit lines, so this is counted as a miss, the conservative reading).
# Not a miss (r4 reading (i)): commit lines missing in 1..n (counted, "missing"), after a power cut or a correct stop.
# Reported only: breaks, audit_behind, errors, unfinished steps, unknown stops (from being-tools onelife-audit).
set -eu
[ $# -ge 4 ] || { echo "usage: end_check.sh BEING_TOOLS RUN AUDIT REF [BOOTS]"; exit 2; }
BT=$1; RUN=$2; AUD=$3; REF=$4; BOOTS=${5:-}
W=$(mktemp -d "${TMPDIR:-/tmp}/s54-end.XXXXXX")
cp "$RUN" "$W/r"; cp "$AUD" "$W/r.audit"
jv() { echo "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p"; }
fail=""
i=$("$BT" onelife-info "$W/r" 2> /dev/null) || i=""
n=$(echo "$i" | sed -n 's/^{"n":\([0-9]*\),.*/\1/p'); s=$(echo "$i" | sed -n 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/p')
[ -n "$n" ] || fail="$fail run-unreadable"
rs=$(awk -v n="$n" '$1 == n { print $2 }' "$REF")
rm=false; [ -n "$n" ] && [ -n "$s" ] && [ "$s" = "$rs" ] && rm=true
[ "$rm" = true ] || fail="$fail run-sha"
# commit lines: with the reference SHA, other (first n), distinct n, missing n in 1..n of the run, beyond the run's n
set -- $(awk -v nr="${n:-0}" 'NR == FNR { r[$1] = $2; next } $1 == "commit" { if (r[$2] == $3) ok++; else { bad++; if (fb == "") fb = $2 }; if (!($2 in s)) { s[$2] = 1; nd++; if ($2 + 0 > nr) bey++ } }
  END { m = 0; for (k = 1; k <= nr; k++) if (!(k in s)) m++; print ok + 0, bad + 0, nd + 0, (fb == "" ? "null" : fb), m, bey + 0 }' "$REF" "$W/r.audit")
cok=$1; cbad=$2; nd=$3; fb=$4; miss=$5; bey=$6
lines=$(wc -l < "$W/r.audit" | tr -d ' ')
[ "$lines" -gt 0 ] || fail="$fail audit-empty"
[ "$cok" -gt 0 ] || fail="$fail no-commit"
[ "$cbad" = 0 ] || fail="$fail commit-sha(first n $fb)"
[ "$bey" = 0 ] || fail="$fail commit-beyond-run-n"
a=$("$BT" onelife-audit "$W/r" 2> /dev/null) || a=""
chain=$(jv "$a" chain_ok); starts=$(jv "$a" starts); breaks=$(jv "$a" breaks); behind=$(jv "$a" audit_behind)
errs=$(jv "$a" errors); unf=$(jv "$a" unfinished_steps); unk=$(jv "$a" unknown_stops)
[ "$chain" = true ] || fail="$fail chain"
st3=-
if [ -n "$BOOTS" ]; then st3=false; [ -n "$starts" ] && [ "$starts" -le $((BOOTS + 1)) ] && st3=true; [ "$st3" = true ] || fail="$fail starts>boots+1"; fi
echo "end_check run $(shasum -a 256 "$RUN" | awk '{print $1}') audit $(shasum -a 256 "$AUD" | awk '{print $1}'): n $n, run SHA = reference $rm; audit lines $lines; commits with the reference SHA $cok, other $cbad (first $fb), distinct n $nd, missing in 1..$n $miss, beyond n $bey; chain_ok ${chain:-?}; starts ${starts:-?} (boots ${BOOTS:--}, <= boots+1 $st3); breaks ${breaks:-?}; audit_behind ${behind:-?}; errors ${errs:-?}; unfinished ${unf:-?}; unknown stops ${unk:-?}"
if [ -z "$fail" ]; then echo "end_check: PASS"; else echo "end_check: FAIL:$fail"; exit 1; fi
