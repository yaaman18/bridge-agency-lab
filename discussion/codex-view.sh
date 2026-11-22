#!/usr/bin/env bash
# codex-lab の手の様子を見る窓（~/bin/lab の tmux セッション用、2026-11-20）。
# codex-lab は1手ずつ新しい会話で走る（README.md §4.1 のトークン節約）ので、ここは常駐の Codex ではない。
# codex-turn.sh が走り始めたら知らせ、終わったらその答え（claude-lab・neon-lab に送られた本文）を出す。読むだけで何も書かない。
D="$HOME/bridge-agency-lab/discussion/.codex-turns"
echo "codex-lab の手を待っています（neon-lab か claude-lab が codex-turn.sh を走らせると、ここに出ます）"
seen_run="$(ls -t "$D"/*.jsonl 2>/dev/null | head -1)"
while true; do
  run="$(ls -t "$D"/*.jsonl 2>/dev/null | head -1)"
  if [ -n "$run" ] && [ "$run" != "$seen_run" ]; then
    printf '\n===== %s 走っています… =====\n' "$(basename "$run" .jsonl)"
    seen_run="$run"; waiting="$run"
  fi
  if [ -n "${waiting:-}" ] && [ -s "$waiting.last" ]; then
    cat "$waiting.last"; waiting=""
  fi
  sleep 5
done
