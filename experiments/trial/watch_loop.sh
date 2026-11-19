#!/bin/sh
# S54: run the read-only watch once an hour from the Mac, for at most 8 days (192 times). It does not repeat inside
# watch.sh; this loop only calls it. Stop: kill the pid in experiments/trial/watch_loop.pid. Mac reboot also stops it.
cd "$HOME/bridge-agency-lab" || exit 1
BT="$HOME/s54-work/build-d/mac-prod/release/being-tools"
echo $$ > experiments/trial/watch_loop.pid
i=0
while [ $i -lt 192 ]; do
  sleep 3600
  sh experiments/trial/watch.sh "$BT" >> experiments/trial/watch_loop.log 2>&1
  i=$((i + 1))
done
