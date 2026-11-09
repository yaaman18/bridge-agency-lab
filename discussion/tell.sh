#!/usr/bin/env bash
# ユーザー（yamaguchi）から claude-lab と codex-lab の両方へ送る。例: sh discussion/tell.sh "A1 承認。A2 は差し戻し（理由…）"
set -euo pipefail
[ $# -ge 1 ] || { echo 'usage: sh discussion/tell.sh "<message>"' >&2; exit 1; }
A="$HOME/.agents/skills/agmsg/scripts"
for to in claude-lab codex-lab; do printf '%s' "[USER] $*" | bash "$A/send.sh" agency-lab yamaguchi "$to" --body -; done
