#!/bin/sh
# S15: type-checks formal/gen/AgentBody.lean (the Agent values built by experiments/agent.jl with LabCircuit's agentOf).
# Exit 0 only if every definition elaborates; prints the number of agent definitions and the axioms of each.
set -e
LAB="$(cd "$(dirname "$0")/.." && pwd)"; BP="$HOME/bridge-protocol"; OL="$LAB/formal/.olean"
sh "$LAB/formal/check.sh" > /dev/null
cd "$BP"
lake env sh -c "LEAN_PATH=\"\$LEAN_PATH:$OL\" lean --root=\"$LAB/formal\" -o \"$OL/LabCircuit.olean\" \"$LAB/formal/LabCircuit.lean\"" > /dev/null
F="$LAB/formal/gen/${1:-AgentBody}.lean"; T="$LAB/formal/gen/${1:-AgentBody}-axioms.lean"
cp "$F" "$T"; for d in $(grep -o '^def agent[0-9]*' "$F" | cut -d' ' -f2); do echo "#print axioms $d" >> "$T"; done
lake env sh -c "LEAN_PATH=\"\$LEAN_PATH:$OL\" lean \"$T\"" > "$LAB/formal/gen/lean-output-agent.txt" 2>&1 || { cat "$LAB/formal/gen/lean-output-agent.txt" | head -20; echo "AgentBody: FAILED"; exit 1; }
echo "AgentBody: $(grep -c '^def agent[0-9]' "$F") Agent definitions type-check"; sort "$LAB/formal/gen/lean-output-agent.txt" | uniq -c | sed 's/BridgeLab\.//' | head -5
