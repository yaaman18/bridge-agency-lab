#!/bin/sh
# S54 §4 (discussion/specs/S54-trial-run.md r4): the wrapper of one rehearsal life. POSIX sh (dash on the Pi).
# Usage: s54-run.sh DIR      DIR holds run (the run file), drives.txt (60480 lines), onelife-run, being-tools.
# Inside one exclusive lock (flock -n on DIR/s54-run.lock, a marker file never read): reads n from
# "being-tools onelife-info DIR/run" (used only when the output is one line starting {"n":<decimal>,), then feeds
# the lines n+1.. of drives.txt unchanged to onelife-run. The only value read from the state is n.
# Refuses (nothing fed, non-zero exit): the lock held by another wrapper (75), onelife-info refused (72), its output
# not of the form (73), n outside 0..60480 (74). Otherwise the exit is onelife-run's.
set -u
NMAX=60480
[ $# -eq 1 ] || { echo "usage: s54-run.sh DIR" >&2; exit 2; }
D=$1
exec 8>> "$D/s54-run.lock" || exit 71
flock -n 8 || { echo "s54-run: $D/s54-run.lock is held by another wrapper" >&2; exit 75; }
info=$("$D/being-tools" onelife-info "$D/run") || { echo "s54-run: onelife-info refused the run file" >&2; exit 72; }
nl='
'
case $info in
  *"$nl"*) echo "s54-run: onelife-info output is not one line" >&2; exit 73 ;;
esac
rest=${info#'{"n":'}
[ "$rest" != "$info" ] || { echo "s54-run: onelife-info output does not start with {\"n\":" >&2; exit 73; }
num=${rest%%,*}
[ "$num" != "$rest" ] || { echo "s54-run: onelife-info output has no comma after n" >&2; exit 73; }
case $num in
  ''|*[!0-9]*) echo "s54-run: n is not a decimal number" >&2; exit 73 ;;
  0) ;;
  0*) echo "s54-run: n has a leading zero" >&2; exit 73 ;;
esac
[ ${#num} -le 5 ] && [ "$num" -le $NMAX ] || { echo "s54-run: n = $num is outside 0..$NMAX" >&2; exit 74; }
tail -n +$((num + 1)) "$D/drives.txt" | "$D/onelife-run" "$D/run"
