#!/bin/sh
# Checks formal/*.lean against the build of ~/bridge-protocol without changing it: Agency.lean (not in its
# library) is compiled into formal/.olean, and the lab's files are checked with that on the search path.
# Usage: sh formal/check.sh
set -e
LAB="$(cd "$(dirname "$0")/.." && pwd)"; BP="$HOME/bridge-protocol"; OL="$LAB/formal/.olean"
mkdir -p "$OL"
cd "$BP"
if [ ! -f "$OL/Agency.olean" ] || [ "$BP/formal-experiments/Agency.lean" -nt "$OL/Agency.olean" ]; then
  lake env lean --root="$BP/formal-experiments" -o "$OL/Agency.olean" -i "$OL/Agency.ilean" "$BP/formal-experiments/Agency.lean" > /dev/null
fi
for f in "$LAB"/formal/*.lean; do
  echo "== $(basename "$f")"
  lake env sh -c "LEAN_PATH=\"\$LEAN_PATH:$OL\" lean \"$f\""
done
