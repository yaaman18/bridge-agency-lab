#!/usr/bin/env bash
# claude-lab（Opus 5.5）の I 段（Lean・Julia・Rust 実装と関門実行）を非対話で走らせる。
# 使い方: sh discussion/claude-code-turn.sh <medium|high> <prompt_file>
set -euo pipefail
EFFORT="${1:-high}"
PROMPT_FILE="${2:?prompt_file required}"
case "$EFFORT" in low|medium|high) ;; *) echo "effort は low|medium|high" >&2; exit 1;; esac
[ -f "$PROMPT_FILE" ] || { echo "prompt_file がない: $PROMPT_FILE" >&2; exit 1; }

unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
claude auth status 2>/dev/null | grep -q '"authMethod": *"claude.ai"' \
  || { echo "claude.ai のサブスクでログインしていないため走らせない。" >&2; exit 1; }

LAB="$HOME/bridge-agency-lab"
LOG="$LAB/discussion/.claude-turns"; mkdir -p "$LOG"
TS="$(date +%Y%m%d-%H%M%S)"
JSON="$LOG/$TS-code-$EFFORT.json"
LAST="$LOG/$TS-code-$EFFORT.last"
BODY="$(cat "$PROMPT_FILE")"

BP_BEFORE="$(git -C "$HOME/bridge-protocol" status --porcelain)"

PROMPT=$(cat <<P
あなたは bridge-agency-lab の claude-lab（Opus 5.5、I 段コーダー）。
必須規律:
- ~/bridge-protocol のファイルは絶対に読み取り専用。1 バイトも書き換えない。
- 許可された FILE: 範囲外のファイル（core/, rust/, 既存 formal/*.lean, 凍結ファイル等）は絶対に編集しない。
- git commit / git push / ファイル削除をしない。
- 予測ファイルを書き換えない。外れた予測は外れたまま報告する。
- phenomenal_claim に関わる主張をしない。
- 順番は必ず Lean（statement → sh formal/check.sh でエラー 0・sorry 0・標準公理のみ確認）→ Julia → 関門実行。

--- 依頼（neon-lab から） ---
$BODY
P
)

set +e
printf '%s' "$PROMPT" | (cd "$LAB" && ENABLE_CLAUDEAI_MCP_SERVERS=false claude -p --model opus --effort "$EFFORT" \
  --tools Read,Edit,Write,Bash,Grep,Glob --permission-mode bypassPermissions --setting-sources project --no-session-persistence \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disallowedTools 'mcp__*' \
  --add-dir "$HOME/bridge-protocol" --output-format json) > "$JSON" 2> "$LOG/$TS-code.err"
RC=$?
set -e

BP_AFTER="$(git -C "$HOME/bridge-protocol" status --porcelain)"
if [ "$BP_BEFORE" != "$BP_AFTER" ]; then
  echo "ERROR: ~/bridge-protocol status changed during claude-code-turn!" >&2
  exit 99
fi

python3 - "$JSON" "$LAST" "$RC" <<'PY'
import json, sys
js, last, rc = sys.argv[1:]
try:
    d = json.load(open(js))
except Exception as e:
    print(f"claude-code-turn 失敗（rc={rc}: {e}）ログ {js}", file=sys.stderr); sys.exit(1)
if d.get("is_error") or not d.get("result"):
    print(f"claude-code-turn 失敗: {d.get('subtype')} {str(d.get('result',''))[:300]}", file=sys.stderr); sys.exit(1)
res = d["result"].strip()
open(last, "w").write(res + "\n")
u = d.get("usage", {})
print(f"claude-lab(I) の手: 手数 {d.get('num_turns')}、入力 {u.get('input_tokens',0):,}+キャッシュ {u.get('cache_read_input_tokens',0):,}、出力 {u.get('output_tokens',0):,}、{d.get('duration_ms',0)//1000} 秒  ログ {js}")
PY
echo "--- claude-lab(I) report ---"
cat "$LAST"
