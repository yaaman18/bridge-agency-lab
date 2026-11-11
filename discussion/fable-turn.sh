#!/usr/bin/env bash
# fable-lab（Claude Fable 5.2）に1回だけ問う。読むだけの助言役（2026-11-10 ユーザー決定、discussion/agents/fable-lab.md）。
# 使い方:
#   bash discussion/fable-turn.sh stuck <依頼ファイル> [high|xhigh]   claude-lab が煮詰まったとき（依頼ファイルの形は agents/fable-lab.md）
#   bash discussion/fable-turn.sh user "<質問>" [high|xhigh]          ユーザーの任意の確認（ターミナルから `! bash discussion/fable-turn.sh user "…"`）
#   bash discussion/fable-turn.sh review <依頼ファイル> [high|xhigh]  ユーザーが頼んだ文書の良否の判定（依頼ファイルに対象・観点を書く）
#   --dry を最後に付けると、Fable を呼ばずに指示文だけを出す。
# 守り:
#  1. Pro のサブスクの範囲で走らせる: ANTHROPIC_API_KEY・ANTHROPIC_AUTH_TOKEN を外し、`claude auth status` が claude.ai のログインでなければ走らせない。
#     2026-11-16 を過ぎたら止まる（ユーザー「11月16日まで pro プランならサブスクの範囲内」）。続けるときは FABLE_OK_AFTER=1（ユーザーが確かめてから）。
#  2. 道具は Read・Grep・Glob だけ（--tools）。書けない・コマンドを走らせない・ネットに出ない。答えはこのスクリプトが discussion/fable/ に保存する。
#     MCP（claude.ai のコネクタを含む）は読み込まない（下の claude -p の前の注記）。
#  3. ローカル・ユーザーの設定を読まない（--setting-sources project）: agmsg のフックで新しい席が立つのを防ぐ。
#  4. 前後でラボと ~/bridge-protocol の状態を比べ、discussion/fable/ 以外の変化があれば報告して終了コード 2。
set -euo pipefail
LAB="$HOME/bridge-agency-lab"
MODE="${1:-}"; ARG="${2:-}"; EFFORT="high"; DRY=0
for a in "${@:3}"; do case "$a" in high|xhigh) EFFORT="$a" ;; --dry) DRY=1 ;; *) echo "不明な引数: $a" >&2; exit 1 ;; esac; done
case "$MODE" in
  stuck|review) [ -f "$ARG" ] || { echo "依頼ファイルがない: $ARG" >&2; exit 1; } ;;
  user)  [ -n "$ARG" ] || { echo '質問が空' >&2; exit 1; } ;;
  *) echo 'usage: bash discussion/fable-turn.sh stuck|review <依頼ファイル> | user "<質問>"  [high|xhigh] [--dry]' >&2; exit 1 ;;
esac

if [ "$(date +%Y%m%d)" -gt 20261116 ] && [ "${FABLE_OK_AFTER:-0}" != 1 ]; then
  echo "2026-11-16 を過ぎた。Pro の範囲で使えるかをユーザーが確かめてから FABLE_OK_AFTER=1 で走らせる。" >&2; exit 1
fi
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
claude auth status 2>/dev/null | grep -q '"authMethod": *"claude.ai"' \
  || { echo "claude.ai のサブスクでログインしていない（API の課金で走るおそれ）。走らせない。" >&2; exit 1; }

OUTDIR="$LAB/discussion/fable"; LOG="$LAB/discussion/.fable-turns"; mkdir -p "$OUTDIR" "$LOG"
TS="$(date +%Y%m%d-%H%M%S)"; JSON="$LOG/$TS-$MODE.json"; ANS="$OUTDIR/$TS-$MODE.md"

snap() { (cd "$LAB" && find . -path ./discussion/fable -prune -o -path ./discussion/.fable-turns -prune -o -path ./.git -prune \
            -o -path '*/target' -prune -o -path '*/.lake' -prune -o -path ./experiments/trm-data -prune -o -type f -print0 \
            | xargs -0 shasum -a 256 | awk '{print substr($1,1,16), $2}'; \
          [ -d "$HOME/bridge-protocol/.git" ] && (cd "$HOME/bridge-protocol" && git status --porcelain=v1 -uall | sed 's/^/BP /')) | sort; }

COMMON=$(cat <<'P'
あなたは bridge-agency-lab の fable-lab（Claude Fable 5.2）。この呼び出しは1回きりで、前の記憶はない。作業ディレクトリはラボの根。
役目は読むだけの助言役。議決権はなく、あなたの答えは claude-lab と codex-lab（またはユーザー）が吟味する「提案」として扱われる。
最初に discussion/agents/fable-lab.md を読む。規律の正本は CLAUDE.md、理論の正本は ~/bridge-protocol（読むだけ）。
道具は読むことだけ。必要なら README.md・discussion/decisions-log.md・notes・~/bridge-protocol の該当箇所を広く読んでよい（この席は通読してよい）。
確かめたこと（ファイル:行を付ける）・推論・提案を分ける。提案には反証条件を付ける。phenomenal_claim に触れない。
有限の不在を一般の不可能に昇格しない。答えは日本語で、指示された形で。
P
)
if [ "$MODE" = stuck ]; then
  TASK=$(cat <<P
--- 依頼（煮詰まった論点、claude-lab が書いた: ${ARG#$LAB/}） ---
$(cat "$ARG")
--- 答えの形 ---
1. 見立て（なぜ進まないか。隠れた前提・定義の滑り・問いの立て方のずれを一つか二つ、5行以内）
2. 別の見方（新しい読み・切り分け・反例・測り方。各案に「確かめ方」と「反証条件」。最大3案）
3. いちばん安く試せる次の一手（1案）
4. bridge-protocol の理論そのものに触れる点があれば明記（ラボでは bp-proposals.md と仮定 H で扱う）
全体で 60 行以内。
P
)
elif [ "$MODE" = review ]; then
  TASK=$(cat <<P
--- 依頼（ユーザーの指示で、文書の良否の判定を頼む。claude-lab が書いた: ${ARG#$LAB/}） ---
$(cat "$ARG")
--- 答えの形 ---
1. 判定: 良 / 条件つきで良 / 否 のどれかと、理由を3行以内
2. 良いところ（最大3点）
3. 問題（重さ high/med/low、根拠のファイル:行、直し方）。最大7点
4. 見落とされている視点（あれば最大2点）
5. ユーザーが決めるべき点
全体で 80 行以内。依頼した側（claude-lab・codex-lab）に遠慮しない。
P
)
else
  TASK=$(cat <<P
--- ユーザー（yamaguchi、理論の持ち主）からの確認の質問 ---
$ARG
--- 答えの形 ---
まず結論を3行以内。そのあと根拠（ファイル:行）・懸念・ユーザーが決めるべき点。ユーザーに向けて、ラボの内輪の略語は短く説明して書く。全体で 60 行以内。
P
)
fi
PROMPT="$COMMON

$TASK"

if [ $DRY -eq 1 ]; then printf '%s\n' "$PROMPT"; echo "--- (dry: Fable は呼ばない。effort=$EFFORT)"; exit 0; fi

snap > "$LOG/$TS.before"
TO=""; command -v timeout >/dev/null && TO="timeout ${FABLE_TURN_SECONDS:-1800}"
set +e
# MCP を切る（2026-11-10 の最初の試し走りで、--tools で絞っても claude.ai のコネクタ〈Claude Docs の作成・削除など〉が見えていたと fable-lab 自身が指摘）:
# claude.ai のコネクタを読み込まない環境変数・空の MCP 設定だけを使う・mcp__ の道具を拒否、の三重。
printf '%s' "$PROMPT" | (cd "$LAB" && ENABLE_CLAUDEAI_MCP_SERVERS=false $TO claude -p --model claude-fable-5-2 --effort "$EFFORT" \
  --tools Read,Grep,Glob --permission-mode dontAsk --setting-sources project --no-session-persistence \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disallowedTools 'mcp__*' \
  --add-dir "$HOME/bridge-protocol" --output-format json) > "$JSON" 2> "$LOG/$TS.err"
RC=$?
set -e
snap > "$LOG/$TS.after"

python3 - "$JSON" "$ANS" "$MODE" "$EFFORT" "$RC" "${ARG#$LAB/}" <<'PY'
import json, sys
js, ans, mode, effort, rc, arg = sys.argv[1:]
try: d = json.load(open(js))
except Exception as e:
    print(f"fable-lab の手は失敗（終了コード {rc}、出力を読めない: {e}）。ログ {js}"); sys.exit(1)
if d.get("is_error") or not d.get("result"):
    print(f"fable-lab の手は失敗: {d.get('subtype')} {str(d.get('result',''))[:300]}"); sys.exit(1)
head = f"# fable-lab {mode}（effort {effort}）\n\n- 問い: {arg if mode in ('stuck','review') else arg[:200]}\n- 扱い: 提案（議決権なし）。吟味は claude-lab・codex-lab、決めるのは §3 の手続き\n\n"
open(ans, "w").write(head + d["result"].strip() + "\n")
u = d.get("usage", {})
print(d["result"].strip())
print(f"\n--- fable-lab: 保存 {ans}  手数 {d.get('num_turns')}  入力 {u.get('input_tokens',0):,}+キャッシュ {u.get('cache_read_input_tokens',0):,}  出力 {u.get('output_tokens',0):,}  {d.get('duration_ms',0)//1000} 秒（サブスクの範囲、金額の表示は参考値）")
PY
PYRC=$?

if ! diff -q "$LOG/$TS.before" "$LOG/$TS.after" >/dev/null; then
  echo "警告: discussion/fable/ 以外が変わった（fable-lab は読むだけのはず）:"; diff "$LOG/$TS.before" "$LOG/$TS.after" | head -20; exit 2
fi
exit $PYRC
