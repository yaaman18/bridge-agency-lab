#!/usr/bin/env bash
# neon-lab が相手の返事を待つ（2026-11-20、Neon オーケストレーター体制、README.md §1.4）。
# agy の turn 方式は「ツールを使った直後」にしか受信箱を見ない。送ったあとに何もしないと返事に気づかないので、
# 送ったらこれを走らせて待つ。届いたら本文を出して終わる（受信箱は既読になる）。
# 使い方: sh discussion/neon-wait.sh [待つ分数 既定 20] [チーム 既定 agency-lab] [席 既定 neon-lab]
set -u
MIN="${1:-20}"; TEAM="${2:-agency-lab}"; NAME="${3:-neon-lab}"
INBOX="$HOME/.agents/skills/agmsg/scripts/inbox.sh"
END=$(( $(date +%s) + MIN * 60 ))
while [ "$(date +%s)" -lt "$END" ]; do
  OUT="$(bash "$INBOX" "$TEAM" "$NAME" 2>&1)"
  if ! printf '%s' "$OUT" | grep -q '^No new messages'; then
    printf '%s\n' "$OUT"
    exit 0
  fi
  sleep 3
done
echo "（${MIN} 分待ったが ${NAME} 宛ての新しいメッセージはない。相手の席が動いているか確かめる）"
