#!/usr/bin/env bash
# codex-lab の1手を、新しい会話で非対話に走らせる（トークン節約、README.md §4.1）。
# 使い方: sh discussion/codex-turn.sh [low|medium|high]   既定 medium。点検・確認だけの手は low。
# 前提: claude-lab が先に codex-lab へメッセージを送っておく（根拠の抜粋つき。抜粋を貼れば Codex は読み直さない）。
set -euo pipefail
EFFORT="${1:-medium}"
case "$EFFORT" in low|medium|high) ;; *) echo "effort は low|medium|high" >&2; exit 1;; esac
LAB="$HOME/bridge-agency-lab"
CODEX="$HOME/.local/bin/codex"; [ -x "$CODEX" ] || CODEX="$(command -v codex)"
LOG="$LAB/discussion/.codex-turns"; mkdir -p "$LOG"
OUT="$LOG/$(date +%Y%m%d-%H%M%S)-$EFFORT.jsonl"

# 2026-11-06 節約の改訂: 受信箱の読み取りと返信の送信はこのスクリプトがやる。Codex に agmsg を触らせると、
# 毎手 agmsg の SKILL.md（約20〜43KB）と agmsg-spec-challenge の SKILL.md を読み込み、それが後の呼び出しのたびに再送されていた。
MSG="$(bash "$HOME/.agents/skills/agmsg/scripts/inbox.sh" agency-lab codex-lab 2>&1 || true)"
printf '%s' "$MSG" | grep -q 'claude-lab' || { echo "codex-lab の受信箱に claude-lab からのメッセージがない。走らせない。"; exit 1; }
LAST="$OUT.last"
PROMPT=$(cat <<P
あなたは bridge-agency-lab の codex-lab（レビューの席）。この手は新しい会話で、前の往復の記憶はない。
規律は AGENTS.md と同じ（bridge-protocol に書かない、数値を変えない、git しない、削除しない、phenomenal_claim に触れない）。AGENTS.md は読まなくてよい。
スキル（SKILL.md）は読まない。agmsg のスクリプトも走らせない（受信箱は下に貼ってあり、返信はこのスクリプトが送る）。
下の claude-lab のメッセージに指定された箇所（ファイル:行）だけを sed -n / grep で範囲を切って読む。メッセージに抜粋があれば読み直さない。コマンドは全部で 3 回まで。
書いてよいのは discussion/reviews/・discussion/notes/ だけ（challenge・clarify の論点だけ、2KB 目安）。
最後の答えがそのまま claude-lab への返信になる: 15 行以内、命題番号つき、accept/challenge/clarify/defer、同意だけはしない。日本語。

--- 受信箱（codex-lab 宛て） ---
$MSG
P
)
set +e
printf '%s' "$PROMPT" | "$CODEX" exec -C "$LAB" -s workspace-write -c "model_reasoning_effort=\"$EFFORT\"" --json -o "$LAST" - > "$OUT"
RC=$?
set -e
if [ $RC -eq 0 ] && [ -s "$LAST" ]; then
  bash "$HOME/.agents/skills/agmsg/scripts/send.sh" agency-lab codex-lab claude-lab --body - < "$LAST" >/dev/null && echo "返信を claude-lab に送った。"
fi

python3 - "$OUT" <<'PY'
import json,sys
u={}
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    if e.get('type')=='turn.completed': u=e.get('usage',{})
n=sum(1 for l in open(sys.argv[1]) if '"command_execution"' in l and 'item.completed' in l)
i=u.get('input_tokens',0); c=u.get('cached_input_tokens',0)
errs=[json.loads(l).get('message','') for l in open(sys.argv[1]) if l.startswith('{"type":"error"')]
if errs: print('codex-lab の手は失敗:', errs[-1]); sys.exit(1)
print(f"codex-lab の手: コマンド {n} 回、入力 {i:,}（キャッシュ外 {i-c:,}）、出力 {u.get('output_tokens',0):,}  ログ {sys.argv[1]}")
PY
