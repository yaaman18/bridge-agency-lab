#!/bin/sh
# S54 (f) (discussion/notes/S54-start-procedure.md):
# Separate-copy n=60480 EOF safety check on the Raspberry Pi using the product build and real flock,
# WITHOUT touching the live trial directories (/home/pi/s54/t1, /home/pi/s54/t2) or systemd units.
# Usage: sh experiments/trial/eof_check_pi.sh [BUILD_DIR]
#   Default BUILD_DIR: ~/s54-work/build-d
set -eu
cd "$(dirname "$0")/../.."
B="${1:-$HOME/s54-work/build-d}"
HOST="pi@bridge-pi.local"
BT="$B/mac-prod/release/being-tools"
D="experiments/trial-data"
P="/tmp/s54-eof-check-$$"
OUT="experiments/results-trial-eof-pi.out"

[ -x "$BT" ] || { echo "missing mac being-tools: $BT" >&2; exit 2; }
[ -f "$D/final-669-L2.save" ] || { echo "missing $D/final-669-L2.save" >&2; exit 2; }

pis() { ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" "$@"; }

if ! pis true 2>/dev/null; then
  echo "Pi unreachable ($HOST) at $(date '+%Y-%m-%dT%H:%M:%S%z'); live trial untouched." >&2
  exit 3
fi

W="$(mktemp -d "${TMPDIR:-/tmp}/s54-eof.XXXXXX")"
trap 'rm -rf "$W"; pis "rm -rf $P" 2>/dev/null || true' EXIT

# Build a wrapped n=60480 run file from Julia's final-669-L2.save on Mac
"$BT" onelife-wrap "$D/final-669-L2.save" 60480 "$W/run"
PRE_SHA="$(shasum -a 256 "$W/run" | awk '{print $1}')"

# Prepare isolated scratch copy on Pi using ONLY the installed product binaries (read-only copy from /home/pi/s54/t1)
pis "mkdir -p '$P' && cp /home/pi/s54/t1/being-tools /home/pi/s54/t1/onelife-run /home/pi/s54/t1/s54-run.sh /home/pi/s54/t1/drives.txt '$P/' && : > '$P/run.audit'"
scp -q -o BatchMode=yes "$W/run" "$HOST:$P/run"

# Run the real wrapper (real flock + product onelife-run) at n=60480 (EOF)
RC=0
pis "sh '$P/s54-run.sh' '$P'" > "$W/run.log" 2>&1 || RC=$?

POST_SHA="$(pis "sha256sum '$P/run'" | awk '{print $1}')"
scp -q -o BatchMode=yes "$HOST:$P/run.audit" "$W/run.audit"
CHAIN="$(pis "'$P/being-tools' onelife-audit '$P/run'" 2>&1 || true)"
COMMITS="$(grep -c '^commit ' "$W/run.audit" || true)"

{
  echo "=== S54 (f) Pi separate-copy n=60480 EOF check ($(date '+%Y-%m-%dT%H:%M:%S%z')) ==="
  echo "exit_code=$RC"
  echo "pre_sha=$PRE_SHA"
  echo "post_sha=$POST_SHA"
  echo "run_unchanged=$([ "$PRE_SHA" = "$POST_SHA" ] && echo true || echo false)"
  echo "commits_added=$COMMITS"
  echo "audit_lines:"
  cat "$W/run.audit"
  echo "audit_check: $CHAIN"
  if [ "$RC" = 0 ] && [ "$PRE_SHA" = "$POST_SHA" ] && [ "$COMMITS" = 0 ] && printf '%s' "$CHAIN" | grep -q 'ok'; then
    echo "VERDICT: PASS"
  else
    echo "VERDICT: FAIL"
  fi
} | tee -a "$OUT"
