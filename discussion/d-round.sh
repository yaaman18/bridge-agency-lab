#!/usr/bin/env bash
# 3者議論の1往復を1コマンドで実行・回収する（2026-11-20 時間短縮策）。
# 既定（--parallel）: D 段向けに claude-turn.sh と codex-turn.sh を非対話で完全並列実行する（最速・監視切れなし）。
# --pane: 常駐の claude-lab ペインを使う従来方式。
# 使い方: sh discussion/d-round.sh <low|medium|high> <msg_file> [--pane]
set -euo pipefail
EFFORT="${1:-low}"
MSG_FILE="${2:?msg_file required}"
MODE="${3:---parallel}"
SCRIPTS="$HOME/.agents/skills/agmsg/scripts"
LAB="$HOME/bridge-agency-lab"

T0=$(date +%s)

if [ "$MODE" = "--pane" ]; then
  bash "$SCRIPTS/send.sh" agency-lab neon-lab claude-lab --body - < "$MSG_FILE" >/dev/null
  bash "$SCRIPTS/send.sh" agency-lab neon-lab codex-lab --body - < "$MSG_FILE" >/dev/null
  echo "[d-round:pane] sent (+$(( $(date +%s) - T0 ))s)"
  sh "$LAB/discussion/codex-turn.sh" "$EFFORT" neon-lab,claude-lab
  echo "[d-round:pane] codex-turn done (+$(( $(date +%s) - T0 ))s)"
  COLLECTED=""; GOT_CLAUDE=0; GOT_CODEX=0; END=$(( T0 + 180 ))
  while [ "$(date +%s)" -lt "$END" ]; do
    OUT="$(bash "$SCRIPTS/inbox.sh" agency-lab neon-lab 2>&1 || true)"
    if ! printf '%s' "$OUT" | grep -q '^No new messages'; then
      COLLECTED="${COLLECTED}${OUT}
"
      printf '%s' "$OUT" | grep -q 'claude-lab:' && GOT_CLAUDE=1
      printf '%s' "$OUT" | grep -q 'codex-lab:' && GOT_CODEX=1
      [ "$GOT_CLAUDE" -eq 1 ] && [ "$GOT_CODEX" -eq 1 ] && break
    fi
    sleep 3
  done
  echo "[d-round:pane] collected claude=$GOT_CLAUDE codex=$GOT_CODEX (total $(( $(date +%s) - T0 ))s)"
  printf '%s\n' "$COLLECTED"
  exit 0
fi

# --parallel (default): send to codex inbox, then launch claude-turn.sh and codex-turn.sh in parallel.
TMPDIR_RUN="$(mktemp -d /tmp/dround.XXXXXX)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

bash "$SCRIPTS/send.sh" agency-lab neon-lab codex-lab --body - < "$MSG_FILE" >/dev/null
echo "[d-round:parallel] launching claude-lab & codex-lab in parallel (effort=$EFFORT, +$(( $(date +%s) - T0 ))s)"

sh "$LAB/discussion/claude-turn.sh" "$EFFORT" "$MSG_FILE" none > "$TMPDIR_RUN/claude.out" 2>&1 &
PID_C=$!
sh "$LAB/discussion/codex-turn.sh" "$EFFORT" neon-lab > "$TMPDIR_RUN/codex.out" 2>&1 &
PID_X=$!

RC_C=0; RC_X=0
wait "$PID_C" || RC_C=$?
wait "$PID_X" || RC_X=$?

echo "[d-round:parallel] both done (rc_claude=$RC_C rc_codex=$RC_X, total $(( $(date +%s) - T0 ))s)"
echo "=== claude-lab ==="
cat "$TMPDIR_RUN/claude.out"
echo "=== codex-lab ==="
cat "$TMPDIR_RUN/codex.out"
bash "$SCRIPTS/inbox.sh" agency-lab neon-lab 2>&1 || true
