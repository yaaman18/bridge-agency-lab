#!/bin/sh
# The automatic audit of the app's being (audit/audit.jl). Usage: sh audit/run.sh audit/in/state-v<version>.json
# The input is the being's record read from the app's db, read-only (Claude: ArtifactData get, collection "being",
# doc "state", out_dir audit/in, then rename to state-v<version>.json). Nothing is written back to the db.
set -e
cd "$(dirname "$0")/.."
[ -n "$1" ] || { echo "usage: sh audit/run.sh audit/in/state-v<version>.json"; exit 1; }
(cd rust && cargo build --release -q -p being-tools)
julia --project=. audit/audit.jl "$1"
