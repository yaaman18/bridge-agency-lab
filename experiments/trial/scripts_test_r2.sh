#!/bin/sh
# S54 I-R r2 (codex 2026-11-16 19:25, points 2-5): tests of watch.sh, pi_check.sh (place, rehearsal-check) and
# end_check.sh on the Mac only, with fake ssh / scp / sudo / dmesg / tune2fs / vcgencmd / systemctl / flock in PATH.
# The fake ssh runs the remote command locally with /home/pi/s54 -> a temp dir; nothing is sent to the Pi.
# The scripts run from a copy of the tree in a temp dir (experiments/trial-data is a symlink, only read), so their
# outputs do not touch the repo's results files.
# Usage: sh experiments/trial/scripts_test_r2.sh BUILD [OLD_DIR]
#   BUILD    ~/s54-work/build-d (mac-prod/mac-fast for the Mac, pi-prod for the pushed files)
#   OLD_DIR  optional dir with the previous watch.sh / pi_check.sh (freeze 1), run as the controls that show the bugs
# Writes experiments/results-trial-scripts-r2.out (last line ALL PASS or FAILED).
set -u
cd "$(dirname "$0")/../.."
REPO=$(pwd)
B=$1; OLD=${2:-}
MBT=$B/mac-prod/release/being-tools; FBT=$B/mac-fast/release/being-tools; FRUN=$B/mac-fast/release/onelife-run
D=$REPO/experiments/trial-data
R=$REPO/experiments/results-trial-scripts-r2.out
T=$(mktemp -d "${TMPDIR:-/tmp}/s54-r2.XXXXXX")
: > "$R"
allok=true
say() { echo "$*" | tee -a "$R"; }
chk() { if [ "$2" = true ]; then say "PASS $1"; else say "FAIL $1"; allok=false; fi; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
jv() { echo "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p"; }
say "S54 scripts r2 tests, Mac time $(date '+%Y-%m-%d %H:%M:%S'); temp $T"

# ---- fakes ----
FB=$T/bin; mkdir -p "$FB"
export FAKE_LOG=$T/fake.log FAKE_ROOT=$T/pi
cat > "$FB/ssh" <<'EOF'
#!/bin/sh
echo "ssh $*" >> "$FAKE_LOG"
while [ $# -gt 0 ]; do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done
shift
cmd="$*"
case ${FAKE_SSH:-local} in
  fail) exit 255 ;;
  garbage) echo hello; exit 0 ;;
  flaky) case $cmd in *"test -e"*) exit 255 ;; esac ;;
esac
cmd=$(printf '%s\n' "$cmd" | sed -e "s#/home/pi/s54#$FAKE_ROOT/s54#g" -e "s#/proc/sys/kernel/random/boot_id#$FAKE_ROOT/boot_id#g")
exec sh -c "$cmd"
EOF
cat > "$FB/scp" <<'EOF'
#!/bin/sh
echo "scp $*" >> "$FAKE_LOG"
while [ $# -gt 0 ]; do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done
[ "${FAKE_SSH:-local}" = local ] || [ "${FAKE_SSH:-local}" = flaky ] || exit 1
s=$(echo "$1" | sed -e 's#^[^/]*:##' -e "s#^/home/pi/s54#$FAKE_ROOT/s54#"); d=$(echo "$2" | sed -e 's#^[^/]*:##' -e "s#^/home/pi/s54#$FAKE_ROOT/s54#")
cp "$s" "$d"
EOF
cat > "$FB/sudo" <<'EOF'
#!/bin/sh
[ "${FAKE_SUDO:-refuse}" = ok ] || { echo "sudo: a password is required" >&2; exit 1; }
[ "$1" = -n ] && shift
exec "$@"
EOF
printf '#!/bin/sh\necho "[    1.0] EXT4-fs (mmcblk0p2): mounted"\necho "[    2.0] EXT4-fs error (device mmcblk0p2): test one"\necho "[    3.0] ext4-fs error (device mmcblk0p2): test two"\n' > "$FB/dmesg"
printf '#!/bin/sh\necho "Filesystem state:         clean"\necho "Last mount time:          Mon Nov 16 10:00:00 2026"\n' > "$FB/tune2fs"
printf '#!/bin/sh\necho throttled=0x0\n' > "$FB/vcgencmd"
printf '#!/bin/sh\necho active\n' > "$FB/systemctl"
printf '#!/bin/sh\nexit 0\n' > "$FB/flock"
chmod 755 "$FB"/*
PATH=$FB:$PATH; export PATH
echo "boot-id-fake-0001" > "$T/boot_id"
mktree() {  # mktree DIR SRC: a copy of experiments/trial from SRC (a dir with watch.sh, pi_check.sh) in DIR
  mkdir -p "$1/experiments/trial"; cp "$REPO"/experiments/trial/*.sh "$REPO"/experiments/trial/*.service "$1/experiments/trial/"
  cp "$2/watch.sh" "$2/pi_check.sh" "$1/experiments/trial/"; ln -s "$D" "$1/experiments/trial-data"
}
mktree "$T/new" "$REPO/experiments/trial"
[ -n "$OLD" ] && mktree "$T/old" "$OLD"
pilives() {  # the placed run files on the fake Pi
  rm -rf "$FAKE_ROOT"; mkdir -p "$FAKE_ROOT/s54/t1" "$FAKE_ROOT/s54/t2" "$FAKE_ROOT/s54/rehearsal"
  cp "$D/run0-669-L2" "$FAKE_ROOT/s54/t1/run"; cp "$D/run0-669-L2SF" "$FAKE_ROOT/s54/t2/run"; cp "$D/rehearsal-run0" "$FAKE_ROOT/s54/rehearsal/run"
  : > "$FAKE_ROOT/s54/t1/run.audit"; : > "$FAKE_ROOT/s54/t2/run.audit"; : > "$FAKE_ROOT/s54/rehearsal/run.audit"
}
col() { awk -F'\t' -v c="$2" 'NR == 2 { print $c }' "$1"; }
nfs() { awk -F'\t' '{ printf "%s ", NF }' "$1"; }

# ---- 3, 4: watch.sh ----
pilives
export FAKE_SSH=local FAKE_SUDO=ok
o=$T/w1.tsv; sh "$T/new/experiments/trial/watch.sh" "$MBT" trial "$o" > /dev/null 2>&1
say "W1 sudo ok: columns per line $(nfs "$o"); ext4 $(col "$o" 5) fs $(col "$o" 6) $(col "$o" 7); t1 n $(col "$o" 9) match $(col "$o" 11); t2 n $(col "$o" 14) match $(col "$o" 16)"
chk "W1 header and row 17 columns, ext4 2, clean, 0, both lives match" "$([ "$(nfs "$o")" = "17 17 " ] && [ "$(col "$o" 5)" = 2 ] && [ "$(col "$o" 6)" = clean ] && [ "$(col "$o" 7)" = 0 ] && [ "$(col "$o" 11)" = true ] && [ "$(col "$o" 16)" = true ] && echo true || echo false)"
export FAKE_SUDO=refuse
o=$T/w2.tsv; sh "$T/new/experiments/trial/watch.sh" "$MBT" trial "$o" > /dev/null 2>&1
say "W2 sudo refused: columns $(nfs "$o"); ext4 $(col "$o" 5) fs $(col "$o" 6) $(col "$o" 7)"
chk "W2 negative control: sudo refused -> ERR ERR ERR, 17 columns" "$([ "$(nfs "$o")" = "17 17 " ] && [ "$(col "$o" 5)" = ERR ] && [ "$(col "$o" 6)" = ERR ] && [ "$(col "$o" 7)" = ERR ] && echo true || echo false)"
if [ -n "$OLD" ]; then
  o=$T/w2old.tsv; sh "$T/old/experiments/trial/watch.sh" "$MBT" trial "$o" > /dev/null 2>&1
  say "W2-old (freeze 1 watch.sh, sudo refused): columns $(nfs "$o"); ext4 $(col "$o" 5) fs '$(col "$o" 6)' $(col "$o" 7)"
  chk "W2-old control: the old script reports the refused dmesg as 0" "$([ "$(col "$o" 5)" = 0 ] && echo true || echo false)"
fi
export FAKE_SSH=fail
o=$T/w3.tsv; sh "$T/new/experiments/trial/watch.sh" "$MBT" trial "$o" > /dev/null 2>&1
say "W3 ssh fails: columns $(nfs "$o"); boot $(col "$o" 3); t1 unit $(col "$o" 8) n $(col "$o" 9) match $(col "$o" 11)"
chk "W3 ssh fails -> unreachable, 17 columns, no match claimed" "$([ "$(nfs "$o")" = "17 17 " ] && [ "$(col "$o" 3)" = unreachable ] && [ "$(col "$o" 11)" != true ] && echo true || echo false)"
export FAKE_SSH=local FAKE_SUDO=ok
o=$T/w4.tsv; sh "$T/new/experiments/trial/watch.sh" "$MBT" rehearsal "$o" > /dev/null 2>&1
sh "$T/new/experiments/trial/watch.sh" "$MBT" rehearsal "$o" > /dev/null 2>&1
chk "W4 rehearsal mode: header and 2 rows 12 columns ($(nfs "$o"))" "$([ "$(nfs "$o")" = "12 12 12 " ] && echo true || echo false)"

# ---- 4: pi_check.sh rehearsal-check ----
for m in ok refuse; do
  export FAKE_SUDO=$m
  sh "$T/new/experiments/trial/pi_check.sh" "$B" rehearsal-check > "$T/rc-$m.txt" 2>&1; echo "exit $?" >> "$T/rc-$m.txt"
  say "RC sudo $m: $(grep '^Pi:' "$T/rc-$m.txt" | cut -c1-220)"
done
chk "RC sudo ok: ext4 count 2 and tune2fs read" "$(grep -q 'ext4 errors in dmesg 2 ' "$T/rc-ok.txt" && grep -q 'Filesystem state: clean' "$T/rc-ok.txt" && echo true || echo false)"
chk "RC negative control: sudo refused -> dmesg ERR, tune2fs ERR" "$(grep -q 'ext4 errors in dmesg ERR' "$T/rc-refuse.txt" && grep -q 'tune2fs ERR' "$T/rc-refuse.txt" && echo true || echo false)"
export FAKE_SUDO=ok

# ---- 5: pi_check.sh place ----
placecase() {  # placecase TREE NAME MODE: place with FAKE_SSH=MODE; prints exit code; log in $T/p-NAME.log
  : > "$FAKE_LOG"; c=0; FAKE_SSH=$3 sh "$1/experiments/trial/pi_check.sh" "$B" place > "$T/p-$2.txt" 2>&1 || c=$?
  cp "$FAKE_LOG" "$T/p-$2.log"; echo "$c"
}
writes() { grep -cE '^scp|mkdir|chmod|: >' "$1" || true; }
rm -rf "$FAKE_ROOT"; mkdir -p "$FAKE_ROOT"
c=$(placecase "$T/new" fail fail)
say "P1 ssh fails, empty Pi: exit $c; ssh/scp calls $(wc -l < "$T/p-fail.log" | tr -d ' '), writing calls $(writes "$T/p-fail.log"); $(tail -1 "$T/p-fail.txt")"
chk "P1 negative control: ssh fails -> non-zero exit, no writing call, nothing on the Pi" "$([ "$c" != 0 ] && [ "$(writes "$T/p-fail.log")" = 0 ] && [ ! -e "$FAKE_ROOT/s54" ] && echo true || echo false)"
pilives; cp "$D/run0-669-L2" "$T/t1-before"; echo "commit 1 x y z" > "$FAKE_ROOT/s54/t1/run.audit"; a0=$(fsha "$FAKE_ROOT/s54/t1/run.audit")
c=$(placecase "$T/new" flaky flaky)
say "P2 ssh fails only on the existence test, lives in place: exit $c; writing calls $(writes "$T/p-flaky.log"); t1 audit kept $([ "$(fsha "$FAKE_ROOT/s54/t1/run.audit")" = "$a0" ] && echo true || echo false)"
chk "P2 flaky ssh: non-zero exit, no writing call, run and audit unchanged" "$([ "$c" != 0 ] && [ "$(writes "$T/p-flaky.log")" = 0 ] && [ "$(fsha "$FAKE_ROOT/s54/t1/run.audit")" = "$a0" ] && cmp -s "$FAKE_ROOT/s54/t1/run" "$T/t1-before" && echo true || echo false)"
if [ -n "$OLD" ]; then
  c=$(placecase "$T/old" flaky-old flaky)
  say "P2-old (freeze 1 pi_check.sh, same flaky ssh): exit $c; writing calls $(writes "$T/p-flaky-old.log"); t1 audit size now $(wc -c < "$FAKE_ROOT/s54/t1/run.audit" | tr -d ' ')"
  chk "P2-old control: the old script overwrites the existing life (audit emptied)" "$([ ! -s "$FAKE_ROOT/s54/t1/run.audit" ] && echo true || echo false)"
fi
rm -rf "$FAKE_ROOT"; mkdir -p "$FAKE_ROOT"
c=$(placecase "$T/new" garbage garbage)
chk "P3 unexpected answer (exit $c): non-zero exit, no writing call" "$([ "$c" != 0 ] && [ "$(writes "$T/p-garbage.log")" = 0 ] && echo true || echo false)"
c=$(placecase "$T/new" ok local)
say "P4 empty fake Pi, ssh works: exit $c; $(grep -c 'pushed with the same SHA 5 of 5' "$T/p-ok.txt") lives 5 of 5; $(grep 'place units' "$T/p-ok.txt")"
chk "P4 positive: exit 0, three lives 5 of 5, units 3 of 3" "$([ "$c" = 0 ] && [ "$(grep -c 'pushed with the same SHA 5 of 5' "$T/p-ok.txt")" = 3 ] && grep -q 'same SHA 3 of 3' "$T/p-ok.txt" && echo true || echo false)"
s0=$(find "$FAKE_ROOT/s54" -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256)
c=$(placecase "$T/new" again local)
s1=$(find "$FAKE_ROOT/s54" -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256)
chk "P5 placed again on the placed lives: exit $c (non-zero), $(grep -c 'exists; nothing placed' "$T/p-again.txt") refused, files unchanged" "$([ "$c" != 0 ] && [ "$(grep -c 'exists; nothing placed' "$T/p-again.txt")" = 3 ] && [ "$s0" = "$s1" ] && echo true || echo false)"

# ---- 2: the real onelife-run at n = 60480 with empty input (Mac fast build) ----
E=$T/e; mkdir -p "$E"
cp "$FBT" "$FRUN" "$REPO/experiments/trial/s54-run.sh" "$E/"; cp "$D/drives-669.txt" "$E/drives.txt"
"$FBT" onelife-wrap "$D/final-669-L2.save" 60480 "$E/run"; cp "$D/mac-fast-669-L2.audit" "$E/run.audit"
cp "$E/run" "$T/run60480"; cp "$E/run.audit" "$T/audit60480"
l0=$(wc -l < "$E/run.audit" | tr -d ' '); r0=$(fsha "$E/run")
c=0; sh "$E/s54-run.sh" "$E" > "$T/e1.out" 2> "$T/e1.err" || c=$?
l1=$(wc -l < "$E/run.audit" | tr -d ' ')
say "E1 wrapper (fake flock) at n 60480, drives exhausted: exit $c; run file unchanged $([ "$(fsha "$E/run")" = "$r0" ] && echo true || echo false); stdout $(wc -c < "$T/e1.out" | tr -d ' ') B, stderr $(wc -c < "$T/e1.err" | tr -d ' ') B; audit +$((l1 - l0)) lines: $(tail -n +$((l0 + 1)) "$E/run.audit" | awk '{ printf "%s %s %s; ", $1, $2, ($1 == "end" ? $3 : "") }')"
c2=0; "$E/onelife-run" "$E/run" < /dev/null > /dev/null 2>&1 || c2=$?
l2=$(wc -l < "$E/run.audit" | tr -d ' ')
a=$("$FBT" onelife-audit "$E/run")
say "E2 onelife-run again with /dev/null: exit $c2; run unchanged $([ "$(fsha "$E/run")" = "$r0" ] && echo true || echo false); audit +$((l2 - l1)) lines; onelife-audit: chain_ok $(jv "$a" chain_ok) starts $(jv "$a" starts) ends $(jv "$a" ends) commits $(jv "$a" commits) breaks $(jv "$a" breaks) audit_behind $(jv "$a" audit_behind) errors $(jv "$a" errors) run_vs_last_commit $(jv "$a" run_vs_last_commit)"
chk "E at n 60480: exit 0 twice, run file unchanged, 3 audit lines each (start, wait, end eof), no commit added" "$([ "$c" = 0 ] && [ "$c2" = 0 ] && [ "$(fsha "$E/run")" = "$r0" ] && [ $((l1 - l0)) = 3 ] && [ $((l2 - l1)) = 3 ] && [ "$(jv "$a" commits)" = 60480 ] && [ "$(jv "$a" chain_ok)" = true ] && echo true || echo false)"
cp "$E/run.audit" "$T/audit60480-after"

# ---- end_check.sh ----
EC=$REPO/experiments/trial/end_check.sh; RF=$D/ref-669-L2.sha
ec() { n=$1; shift; c=0; sh "$EC" "$FBT" "$@" > "$T/ec-$n.txt" 2>&1 || c=$?; say "EC$n exit $c: $(cut -c 160-520 "$T/ec-$n.txt" | tr '\n' ' ')"; echo "$c" > "$T/ec-$n.c"; }
ecc() { cat "$T/ec-$1.c"; }
ec 1 "$T/run60480" "$T/audit60480" "$RF" 0
chk "EC1 the reference run 60480 and its audit: PASS, missing 0, starts 1 <= boots 0 + 1" "$([ "$(ecc 1)" = 0 ] && grep -q 'missing in 1..60480 0,' "$T/ec-1.txt" && grep -q 'starts 1 ' "$T/ec-1.txt" && echo true || echo false)"
ec 2 "$T/run60480" "$T/audit60480-after" "$RF" 2
chk "EC2 after the two empty feeds, given as if each were a boot (starts 3, BOOTS 2; two process starts in one OS boot, no real boot shown): PASS" "$([ "$(ecc 2)" = 0 ] && grep -q 'starts 3 ' "$T/ec-2.txt" && echo true || echo false)"
awk '$1 == "commit" && $2 == 30000 { $3 = "0000000000000000000000000000000000000000000000000000000000000000" } { print }' "$T/audit60480" > "$T/audit-bad"
ec 3 "$T/run60480" "$T/audit-bad" "$RF"
chk "EC3 negative control: one commit SHA changed -> FAIL, first n 30000" "$([ "$(ecc 3)" != 0 ] && grep -q 'first n 30000' "$T/ec-3.txt" && echo true || echo false)"
: > "$T/audit-empty"
ec 4 "$T/run60480" "$T/audit-empty" "$RF"
chk "EC4 negative control: empty audit -> FAIL" "$([ "$(ecc 4)" != 0 ] && grep -q 'audit-empty' "$T/ec-4.txt" && echo true || echo false)"
head -n 181000 "$T/audit60480" > "$T/audit-tail"
ec 5 "$T/run60480" "$T/audit-tail" "$RF"
chk "EC5 audit tail lost (first 181000 lines kept): commit lines missing counted, not a miss -> PASS" "$([ "$(ecc 5)" = 0 ] && ! grep -q 'missing in 1..60480 0,' "$T/ec-5.txt" && echo true || echo false)"
ec 6 "$T/run60480" "$T/audit60480" "$D/ref-669-L2SF.sha"
chk "EC6 negative control: the L2SF reference for the L2 life -> FAIL" "$([ "$(ecc 6)" != 0 ] && echo true || echo false)"
ec 7 "$T/run60480" "$T/audit60480-after" "$RF" 0
sed 's/^commit 60480 /commit 60481 /' "$T/audit60480" > "$T/audit-beyond"
ec 8 "$T/run60480" "$T/audit-beyond" "$RF"
chk "EC8 negative control: a commit line with n beyond the run's n -> FAIL" "$([ "$(ecc 8)" != 0 ] && grep -q 'commit-beyond-run-n' "$T/ec-8.txt" && echo true || echo false)"
chk "EC7 negative control: the same audit with BOOTS 0 (two starts within one boot) -> FAIL" "$([ "$(ecc 7)" != 0 ] && grep -q 'starts>boots+1' "$T/ec-7.txt" && echo true || echo false)"

if [ "$allok" = true ]; then say "ALL PASS"; else say "FAILED"; exit 1; fi
