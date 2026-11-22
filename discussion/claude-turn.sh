#!/usr/bin/env bash
# claude-lab（Opus 5.5）の D 段議論の1手を非対話・読み取り専用で走らせる（2026-11-20 時間短縮策）。
# I 段（コーディング）は常駐の claude-lab ペインを使い、D 段（議論）の並列高速化だけに使う。
# 使い方: sh discussion/claude-turn.sh <low|medium|high> <msg_file> [reply_to 既定 none]
set -euo pipefail
EFFORT="${1:-low}"
MSG_FILE="${2:?msg_file required}"
REPLY_TO="${3:-none}"
case "$EFFORT" in low|medium|high) ;; *) echo "effort は low|medium|high" >&2; exit 1;; esac
[ -f "$MSG_FILE" ] || { echo "msg_file がない: $MSG_FILE" >&2; exit 1; }

unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
claude auth status 2>/dev/null | grep -q '"authMethod": *"claude.ai"' \
  || { echo "claude.ai のサブスクでログインしていないため走らせない。" >&2; exit 1; }

LAB="$HOME/bridge-agency-lab"
LOG="$LAB/discussion/.claude-turns"; mkdir -p "$LOG"
TS="$(date +%Y%m%d-%H%M%S)"
JSON="$LOG/$TS-$EFFORT.json"
LAST="$LOG/$TS-$EFFORT.last"
MSG="$(cat "$MSG_FILE")"

PROMPT=$(cat <<P
あなたは bridge-agency-lab の claude-lab（Opus 5.5、D 段議論の非対話1手）。前の会話記憶はない。
規律: ~/bridge-protocol に書かない、数値を変えない、git しない、phenomenal_claim に触れない。
道具は読むことだけ（Read/Grep/Glob）。メッセージに抜粋があれば追加読込しない（最速・低トークン優先）。
返信は 15 行以内、命題番号つき、確認した事実・推論・提案（反証条件つき）を分ける。日本語。
ただしメッセージに "[FMT:SYM]" が含まれる場合は、ハイブリッド記号記法（英語テレグラフィック＋標準論理記号＋固定タグ P<n>[ACC|CHG|CLR|DEF], FACT:, INF:, PROP:, CE:, FALS:, REF:, U?:）で 12 行以内に圧縮して返答する（独自暗号は禁止）。

--- 依頼（neon-lab から） ---
$MSG
P
)

set +e
printf '%s' "$PROMPT" | (cd "$LAB" && ENABLE_CLAUDEAI_MCP_SERVERS=false claude -p --model opus --effort "$EFFORT" \
  --tools Read,Grep,Glob --permission-mode dontAsk --setting-sources project --no-session-persistence \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disallowedTools 'mcp__*' \
  --add-dir "$HOME/bridge-protocol" --output-format json) > "$JSON" 2> "$LOG/$TS.err"
RC=$?
set -e

python3 - "$JSON" "$LAST" "$RC" <<'PY'
import json, sys
js, last, rc = sys.argv[1:]
try:
    d = json.load(open(js))
except Exception as e:
    print(f"claude-lab の手は失敗（rc={rc}: {e}）ログ {js}", file=sys.stderr); sys.exit(1)
if d.get("is_error") or not d.get("result"):
    print(f"claude-lab の手は失敗: {d.get('subtype')} {str(d.get('result',''))[:200]}", file=sys.stderr); sys.exit(1)
res = d["result"].strip()
open(last, "w").write(res + "\n")
u = d.get("usage", {})
print(f"claude-lab の手: 手数 {d.get('num_turns')}、入力 {u.get('input_tokens',0):,}+キャッシュ {u.get('cache_read_input_tokens',0):,}、出力 {u.get('output_tokens',0):,}、{d.get('duration_ms',0)//1000} 秒  ログ {js}")
PY

if [ "$REPLY_TO" != "none" ] && [ -s "$LAST" ]; then
  for TO in $(printf '%s' "$REPLY_TO" | tr ',' ' '); do
    bash "$HOME/.agents/skills/agmsg/scripts/send.sh" agency-lab claude-lab "$TO" --body - < "$LAST" >/dev/null
  done
fi
echo "--- claude-lab reply ---"
cat "$LAST"
