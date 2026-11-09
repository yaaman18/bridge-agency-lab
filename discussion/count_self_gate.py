"""deepseek-turn.sh helper: how many times the agent itself ran a GATE's full run (julia commands of the GATE lines,
without the SEEDS=/HORIZONS= shortening). Usage: python3 count_self_gate.py <turn.jsonl> <gate lines>"""
import json, sys
gates = [g.strip() for g in sys.argv[2].splitlines() if g.strip()]
keys = set()
for g in gates:
    for part in g.split("&&"):
        part = part.strip()
        if "julia" in part:
            keys.add(part.split("julia", 1)[1].strip())
n = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get("type") == "tool_call":
        c = json.dumps(e.get("input"), ensure_ascii=False)
        if any(k and k in c for k in keys) and "SEEDS=" not in c and "HORIZONS=" not in c:
            n += 1
print(n)
