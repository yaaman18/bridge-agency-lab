#!/bin/sh
# S54 garden export gate (viewer/s54-of/tools/export-spec.md r1 §5): negative controls N1-N3 (short, --max-steps 50,
# in a mktemp directory), then the full export of both lives into viewer/s54-of/data (E1, E2) and the read-back (E3).
# N4: a failure injected while publishing leaves an existing pair unchanged; N5: also when taking back fails.
# Usage: sh viewer/s54-of/tools/export_gate.sh   (from anywhere; the record goes to viewer/s54-of/tools/export-gate.out)
LAB=$(cd "$(dirname "$0")/../../.." && pwd)
TOOLS="$LAB/viewer/s54-of/tools"
OUT="$TOOLS/export-gate.out"
DATA="$LAB/viewer/s54-of/data"
T=$(mktemp -d)
cd "$LAB/experiments" || exit 2
EXP="julia --project=.. $TOOLS/export_body.jl"
RD="julia --project=.. $TOOLS/read_body.jl"
START=$(date +%s)
{
echo "export gate $(date '+%Y-%m-%d %H:%M:%S') tmp $T"

# short positive run (the source of the N2/N3 copies)
$EXP --max-steps 50 "$T/short" && $RD "$T/short/body-669-L2.json" "$T/short/body-669-L2SF.json"
SHORT=$?
echo "short positive run (max-steps 50): exit $SHORT"

# N1: one hex character of the reference line n = 20 changed
mkdir -p "$T/n1ref" "$T/n1out"
awk 'NR == 21 { c = substr($2, 1, 1); $2 = (c == "0" ? "1" : "0") substr($2, 2) } { print }' \
  "$LAB/experiments/trial-data/ref-669-L2.sha" > "$T/n1ref/ref-669-L2.sha"
NDIFF=$(cmp -l "$LAB/experiments/trial-data/ref-669-L2.sha" "$T/n1ref/ref-669-L2.sha" | wc -l | tr -d ' ')
$EXP --max-steps 50 --ref "$T/n1ref/ref-669-L2.sha" "$T/n1out"
N1RC=$?
N1FILES=$(ls -A "$T/n1out" | wc -l | tr -d ' ')
N1=FAIL
[ "$NDIFF" = 1 ] && [ "$N1RC" != 0 ] && [ "$N1FILES" = 0 ] && N1=ok
echo "N1 changed bytes $NDIFF, export exit $N1RC, files left $N1FILES: $N1"

# N2: one byte of C in frame 2 (n = 6) of a copy changed
mkdir -p "$T/n2"
cp "$T/short/body-669-L2.json" "$T/short/body-669-L2.bin" "$T/n2/"
FB=$(sed -n 's/.*"frame_bytes": \([0-9]*\).*/\1/p' "$T/n2/body-669-L2.json")
OFF=$((FB + 4 + 32 + 4 + 8 + 8 + 1 + 100))
B0=$(od -An -tu1 -j $OFF -N1 "$T/n2/body-669-L2.bin" | tr -d ' ')
printf "\\$(printf '%03o' $(( (B0 + 1) % 256 )))" | dd of="$T/n2/body-669-L2.bin" bs=1 seek=$OFF conv=notrunc 2>/dev/null
B1=$(od -An -tu1 -j $OFF -N1 "$T/n2/body-669-L2.bin" | tr -d ' ')
$RD "$T/n2/body-669-L2.json"
N2RC=$?
N2=FAIL
[ "$B0" != "$B1" ] && [ "$N2RC" != 0 ] && N2=ok
echo "N2 C byte at offset $OFF $B0 -> $B1, read exit $N2RC: $N2"

# N3: a copy one byte short
mkdir -p "$T/n3"
cp "$T/short/body-669-L2.json" "$T/n3/"
SZ=$(wc -c < "$T/short/body-669-L2.bin" | tr -d ' ')
head -c $((SZ - 1)) "$T/short/body-669-L2.bin" > "$T/n3/body-669-L2.bin"
$RD "$T/n3/body-669-L2.json"
N3RC=$?
N3=FAIL
[ "$N3RC" != 0 ] && N3=ok
echo "N3 size $SZ -> $((SZ - 1)), read exit $N3RC: $N3"

# N4: a failure injected during publishing (after the first .bin is placed, before its .json) over an existing pair;
# the new run has --max-steps 44, so its files differ from the existing (max-steps 50) pair
mkdir -p "$T/n4"
cp "$T/short/"body-669-* "$T/n4/"
S54_EXPORT_FAIL_AT=publish_json $EXP --max-steps 44 "$T/n4" 2> "$T/n4.err"
N4RC=$?
cat "$T/n4.err"
N4SAME=yes
for f in body-669-L2.bin body-669-L2.json body-669-L2SF.bin body-669-L2SF.json; do
  cmp -s "$T/short/$f" "$T/n4/$f" || N4SAME=no
done
N4LEFT=$(ls -A "$T/n4" | grep -v '^body-669-' | wc -l | tr -d ' ')
N4=FAIL
[ "$N4RC" != 0 ] && grep -q "placed: body-669-L2.bin" "$T/n4.err" && [ "$N4SAME" = yes ] && [ "$N4LEFT" = 0 ] && N4=ok
echo "N4 export exit $N4RC, old pair unchanged $N4SAME, other entries left $N4LEFT: $N4"

# N5: as N4, and taking back the placed files also fails; the old pair must still be restored byte for byte
mkdir -p "$T/n5"
cp "$T/short/"body-669-* "$T/n5/"
S54_EXPORT_FAIL_AT=restore_placed $EXP --max-steps 44 "$T/n5" 2> "$T/n5.err"
N5RC=$?
cat "$T/n5.err"
N5SAME=yes
for f in body-669-L2.bin body-669-L2.json body-669-L2SF.bin body-669-L2SF.json; do
  cmp -s "$T/short/$f" "$T/n5/$f" || N5SAME=no
done
N5=FAIL
[ "$N5RC" != 0 ] && grep -q "could not take back body-669-L2.bin" "$T/n5.err" && [ "$N5SAME" = yes ] && N5=ok
echo "N5 export exit $N5RC, old pair restored $N5SAME: $N5"

# E1, E2: the full export of both lives
T1=$(date +%s)
$EXP "$DATA"
E12RC=$?
T2=$(date +%s)
echo "E1/E2 full export: exit $E12RC ($((T2 - T1)) s)"

# E3: read-back
$RD "$DATA/body-669-L2.json" "$DATA/body-669-L2SF.json"
E3RC=$?
echo "E3 read-back: exit $E3RC ($(( $(date +%s) - T2 )) s)"

echo "--- summary"
[ "$SHORT" = 0 ] && echo "short positive run: ok" || echo "short positive run: FAIL"
[ "$E12RC" = 0 ] && echo "E1 sha every step, E2 dead_at: ok" || echo "E1/E2: FAIL"
[ "$E3RC" = 0 ] && echo "E3 read-back: ok" || echo "E3: FAIL"
echo "N1 $N1, N2 $N2, N3 $N3, N4 $N4, N5 $N5"
for f in "$DATA"/body-669-L2.bin "$DATA"/body-669-L2SF.bin "$DATA"/body-669-L2.json "$DATA"/body-669-L2SF.json; do
  [ -f "$f" ] && echo "$(basename "$f") $(wc -c < "$f" | tr -d ' ') bytes sha256 $(shasum -a 256 "$f" | cut -d' ' -f1)"
done
echo "total $(( $(date +%s) - START )) s"
ALL=FAIL
[ "$SHORT" = 0 ] && [ "$E12RC" = 0 ] && [ "$E3RC" = 0 ] && [ "$N1" = ok ] && [ "$N2" = ok ] && [ "$N3" = ok ] && [ "$N4" = ok ] && [ "$N5" = ok ] && ALL=PASS
echo "GATE $ALL"
} 2>&1 | tee "$OUT"
grep -q "^GATE PASS$" "$OUT"
