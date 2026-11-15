#!/bin/sh
# S54 §4 (discussion/specs/S54-trial-run.md r4): the tests of the wrapper s54-run.sh. POSIX sh; runs on the Mac and on
# the Pi (in a prep dir). Writes only under DIR.
# Usage: sh wrapper_test.sh DIR WRAPPER BEING_TOOLS ONELIFE_RUN DRIVES SAVE
#   T0 source: outside comments, the wrapper reads nothing but n (commands: exec/flock on the marker, being-tools
#      onelife-info, tail of the drives into onelife-run); negative control: an added "cat run" is caught
#   T1-T3 the lines piped to onelife-run (a capturing stand-in) are byte-identical to the drives from line n+1, at
#      n = 0, 30240 and 60480 (run files: SAVE wrapped at that n)
#   T4 the real onelife-run (fast build) from n = 60477: 3 drives, exit 0, n = 60480
#   N1 a malformed onelife-info output (a stand-in printing {"n":12x,...}, one printing two lines, one printing
#      {"m":0,...}): exit 73, nothing piped; N2 n = 60481: exit 74, nothing piped; N3 a second wrapper while the first
#      holds the lock: exit 75, nothing piped by the second
# Without the flock command (the Mac) a stand-in written in perl takes the lock (flock -n FD only).
set -u
[ $# -eq 6 ] || { echo "usage: wrapper_test.sh DIR WRAPPER BEING_TOOLS ONELIFE_RUN DRIVES SAVE"; exit 2; }
T=$1; WR=$2; BT=$3; RUN=$4; DRV=$5; SAVE=$6
mkdir -p "$T/bin"
if ! command -v flock > /dev/null 2>&1; then
  cat > "$T/bin/flock" << 'EOF'
#!/usr/bin/perl
# stand-in of util-linux "flock -n FD" (test only)
use Fcntl qw(:flock);
$ARGV[0] eq "-n" && $ARGV[1] =~ /^\d+$/ or exit 64;
open(my $f, ">&=", $ARGV[1]) or exit 66;
flock($f, LOCK_EX | LOCK_NB) or exit 1;
exit 0;
EOF
  chmod 755 "$T/bin/flock"; PATH=$T/bin:$PATH; export PATH; FL=stand-in
else
  FL=$(command -v flock)
fi
res=true
say() { echo "$*"; }
# mk NAME N [BT]: a wrapper dir with the run file at n = N, the drives, the wrapper, being-tools, a capturing onelife-run
mk() {
  d=$T/$1; mkdir -p "$d"; cp "$WR" "$d/s54-run.sh"; cp "$DRV" "$d/drives.txt"
  "$BT" onelife-wrap "$SAVE" "$2" "$d/run"
  if [ $# -ge 3 ]; then cp "$3" "$d/being-tools"; else cp "$BT" "$d/being-tools"; fi
  printf '#!/bin/sh\ncat > "$(dirname "$0")/piped"\n' > "$d/onelife-run"; chmod 755 "$d/onelife-run" "$d/being-tools"
}
# T0
src=$(grep -v '^ *#' "$WR")
bad=$(printf '%s\n' "$src" | grep -nE '(^|[^A-Za-z_])(cat|sed|awk|od|head|read|dd|grep|cut|xxd|hexdump|strings|perl|python)([^A-Za-z_]|$)|< *"|<"' || true)
cmds=$(printf '%s\n' "$src" | grep -cE 'onelife-info "\$D/run"|tail -n \+\$\(\(num \+ 1\)\) "\$D/drives.txt" \| "\$D/onelife-run" "\$D/run"' || true)
cp "$WR" "$T/neg-wrapper.sh"; echo 'cat "$D/run" > /dev/null' >> "$T/neg-wrapper.sh"
nbad=$(grep -v '^ *#' "$T/neg-wrapper.sh" | grep -cE '(^|[^A-Za-z_])(cat|sed|awk|od|head|read|dd|grep|cut|xxd|hexdump|strings|perl|python)([^A-Za-z_]|$)|< *"|<"' || true)
t0=false; [ -z "$bad" ] && [ "$cmds" = 2 ] && [ "$nbad" -ge 1 ] && t0=true
say "T0 wrapper source: other reads '$(echo $bad)'; the two expected commands $cmds of 2; negative control (cat run added) caught $nbad -> $t0"
[ "$t0" = true ] || res=false
# T1-T3
for c in 0 30240 60480; do
  mk "t$c" $c
  e=0; sh "$T/t$c/s54-run.sh" "$T/t$c" 2> "$T/t$c/err" || e=$?
  sed -n "$((c + 1)),\$p" "$DRV" > "$T/t$c/expect"
  same=false; [ -f "$T/t$c/piped" ] && cmp -s "$T/t$c/piped" "$T/t$c/expect" && same=true
  nl=$(wc -l < "$T/t$c/piped" 2> /dev/null | tr -d ' ')
  ok=false; [ "$e" = 0 ] && [ "$same" = true ] && [ "$nl" = $((60480 - c)) ] && ok=true
  say "T n=$c: exit $e; piped lines $nl, byte-identical to drives from line $((c + 1)) $same (first piped line '$(head -1 "$T/t$c/piped" 2> /dev/null)') -> $ok"
  [ "$ok" = true ] || res=false
done
# T4 the real onelife-run
mk t4 60477; cp "$RUN" "$T/t4/onelife-run"
e=0; sh "$T/t4/s54-run.sh" "$T/t4" 2> "$T/t4/err" || e=$?
n4=$("$BT" onelife-info "$T/t4/run" | sed 's/^{"n":\([0-9]*\),.*/\1/')
t4=false; [ "$e" = 0 ] && [ "$n4" = 60480 ] && t4=true
say "T4 real onelife-run from n = 60477: exit $e, n $n4 -> $t4"
[ "$t4" = true ] || res=false
# N1 malformed outputs
nn=0
for k in 1 2 3; do
  case $k in
    1) body='{"n":12x,"payload_sha":"0"}' ;;
    2) body='{"n":12,"payload_sha":"0"}
{"n":13,"payload_sha":"0"}' ;;
    3) body='{"m":0,"n":0,"payload_sha":"0"}' ;;
  esac
  printf '#!/bin/sh\ncat << '"'"'EOF'"'"'\n%s\nEOF\n' "$body" > "$T/stub-bt-$k"; chmod 755 "$T/stub-bt-$k"
  mk "n1-$k" 0 "$T/stub-bt-$k"
  e=0; sh "$T/n1-$k/s54-run.sh" "$T/n1-$k" 2> "$T/n1-$k/err" || e=$?
  p=false; [ -e "$T/n1-$k/piped" ] && p=true
  [ "$e" = 73 ] && [ "$p" = false ] && nn=$((nn + 1))
  say "N1.$k malformed onelife-info output: exit $e, piped $p ($(cat "$T/n1-$k/err"))"
done
# N2 n outside the range
mk n2 60481
e2=0; sh "$T/n2/s54-run.sh" "$T/n2" 2> "$T/n2/err" || e2=$?
p2=false; [ -e "$T/n2/piped" ] && p2=true
say "N2 n = 60481: exit $e2, piped $p2 ($(cat "$T/n2/err"))"
# N3 a second wrapper while the first holds the lock (the first's onelife-run waits 4 s after reading its input)
mk n3 100; printf '#!/bin/sh\ncat > "$(dirname "$0")/piped"\nsleep 4\n' > "$T/n3/onelife-run"
sh "$T/n3/s54-run.sh" "$T/n3" 2> "$T/n3/err1" &
p1=$!
i=0; while [ $i -lt 100 ] && [ ! -e "$T/n3/piped" ]; do sleep 0.1; i=$((i + 1)); done
mv "$T/n3/piped" "$T/n3/piped-first"
e3=0; sh "$T/n3/s54-run.sh" "$T/n3" 2> "$T/n3/err2" || e3=$?
p3=false; [ -e "$T/n3/piped" ] && p3=true
e31=0; wait $p1 || e31=$?
say "N3 second wrapper: exit $e3, piped $p3 ($(cat "$T/n3/err2")); the first wrapper exit $e31"
neg=false; [ "$nn" = 3 ] && [ "$e2" = 74 ] && [ "$p2" = false ] && [ "$e3" = 75 ] && [ "$p3" = false ] && [ "$e31" = 0 ] && neg=true
say "negative controls N1 (3 of 3: $nn) N2 N3: $neg (flock: $FL)"
[ "$neg" = true ] || res=false
say "wrapper tests: $res"
[ "$res" = true ]
