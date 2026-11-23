#!/usr/bin/env bash
# fable-lab（Claude Fable 5.2）に1回だけ問う。読むだけの助言役（2026-11-10 ユーザー決定、discussion/agents/fable-lab.md）。
# 使い方:
#   bash discussion/fable-turn.sh stuck <依頼ファイル> [low|medium|high|xhigh] [--api] [--max-budget-usd N] [--no-tools] [--dry]
#   bash discussion/fable-turn.sh user "<質問>" [low|medium|high|xhigh] [--api] [--max-budget-usd N] [--no-tools] [--dry]
#   bash discussion/fable-turn.sh review <依頼ファイル> [low|medium|high|xhigh] [--api] [--max-budget-usd N] [--no-tools] [--dry]
#   --api（または FABLE_USE_API=1）: 明示的に Anthropic API クレジット（ANTHROPIC_API_KEY）で実行する。
#     未指定時は既定どおり ANTHROPIC_API_KEY を外し claude.ai サブスクのみで実行（誤課金防止）。
#     --api 時に環境変数 ANTHROPIC_API_KEY が未設定なら、リポジトリ外の
#     "$HOME/.config/anthropic/fable.env"（chmod 600 必須）から ANTHROPIC_API_KEY のみ読み込む。
#   --max-budget-usd <金額>: --api 時の 1 回あたりの上限（既定 FABLE_MAX_BUDGET_USD=1.5）。
#   --no-tools: ツール読込を無効化して 1 手完結にする（抜粋を依頼文へ同梱済みの場合、大幅節約）。
#   --dry: Fable を呼ばずに指示文と実行設定だけを出す。
# 守り:
#  1. 既定は Pro のサブスクの範囲で走らせる: ANTHROPIC_API_KEY・ANTHROPIC_AUTH_TOKEN を外し、`claude auth status` が claude.ai のログインでなければ走らせない。
#     2026-11-16 を過ぎたら止まる（ユーザー「11月16日まで pro プランならサブスクの範囲内」）。続けるときは FABLE_OK_AFTER=1（ユーザーが確かめてから）。
#     --api 指定時のみ Anthropic API クレジット（上限 --max-budget-usd つき）を許可する。
#  2. 道具は Read・Grep・Glob だけ（--tools。--no-tools 時は空）。書けない・コマンドを走らせない・ネットに出ない。答えはこのスクリプトが discussion/fable/ に保存する。
#     MCP（claude.ai のコネクタを含む）は読み込まない（下の claude -p の前の注記）。
#  3. ローカル・ユーザーの設定を読まない（--setting-sources project）: agmsg のフックで新しい席が立つのを防ぐ。
#  4. 前後でラボと ~/bridge-protocol の状態を比べ、discussion/fable/ 以外の変化があれば報告して終了コード 2。
set -euo pipefail
LAB="$HOME/bridge-agency-lab"
MODE="${1:-}"; ARG="${2:-}"; EFFORT="${FABLE_EFFORT:-medium}"; DRY=0
USE_API="${FABLE_USE_API:-0}"
MAX_BUDGET_USD="${FABLE_MAX_BUDGET_USD:-1.5}"
MODEL="${FABLE_MODEL:-claude-fable-5-2}"
KEY_FILE="${FABLE_API_KEY_FILE:-$HOME/.config/anthropic/fable.env}"
TOOLS="Read,Grep,Glob"
shift 2 || true
while [ $# -gt 0 ]; do
  case "$1" in
    low|medium|high|xhigh) EFFORT="$1"; shift ;;
    --api) USE_API=1; shift ;;
    --no-tools) TOOLS=""; shift ;;
    --max-budget-usd)
      [ $# -ge 2 ] || { echo "--max-budget-usd の値がありません" >&2; exit 1; }
      MAX_BUDGET_USD="$2"; shift 2 ;;
    --dry) DRY=1; shift ;;
    *) echo "不明な引数: $1" >&2; exit 1 ;;
  esac
done
case "$MODE" in
  stuck|review) [ -f "$ARG" ] || { echo "依頼ファイルがない: $ARG" >&2; exit 1; } ;;
  user)  [ -n "$ARG" ] || { echo '質問が空' >&2; exit 1; } ;;
  *) echo 'usage: bash discussion/fable-turn.sh stuck|review <依頼ファイル> | user "<質問>"  [low|medium|high|xhigh] [--api] [--max-budget-usd N] [--no-tools] [--dry]' >&2; exit 1 ;;
esac

API_EXTRA_ARGS=()
if [ "$USE_API" = 1 ]; then
  unset ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
  if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$KEY_FILE" ]; then
    PERM="$(stat -f '%Lp' "$KEY_FILE" 2>/dev/null || stat -c '%a' "$KEY_FILE" 2>/dev/null || echo 777)"
    case "$PERM" in
      600|400) ;;
      *) echo "キーファイルの権限が広すぎます（chmod 600 必須）: $KEY_FILE (mode=$PERM)" >&2; exit 1 ;;
    esac
    KEY_LINE="$(grep -E '^(export[[:space:]]+)?ANTHROPIC_API_KEY=' "$KEY_FILE" | tail -n 1 || true)"
    KEY_VAL="${KEY_LINE#*=}"
    KEY_VAL="${KEY_VAL%\"}" ; KEY_VAL="${KEY_VAL#\"}"
    KEY_VAL="${KEY_VAL%\'}" ; KEY_VAL="${KEY_VAL#\'}"
    if [ -n "$KEY_VAL" ]; then
      export ANTHROPIC_API_KEY="$KEY_VAL"
    fi
  fi
  if [ "$DRY" != 1 ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "ANTHROPIC_API_KEY が未設定です。環境変数で渡すか、リポジトリ外の $KEY_FILE（chmod 600）に ANTHROPIC_API_KEY=... を保存してください。" >&2
    exit 1
  fi
  API_EXTRA_ARGS=(--max-budget-usd "$MAX_BUDGET_USD")
else
  if [ "$(date +%Y%m%d)" -gt 20261116 ] && [ "${FABLE_OK_AFTER:-0}" != 1 ]; then
    echo "2026-11-16 を過ぎた。Pro の範囲で使えるかをユーザーが確かめてから FABLE_OK_AFTER=1 で走らせる（API クレジット使用時は --api）。" >&2; exit 1
  fi
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
  claude auth status 2>/dev/null | grep -q '"authMethod": *"claude.ai"' \
    || { echo "claude.ai のサブスクでログインしていない（API の課金で走るおそれ）。走らせない。" >&2; exit 1; }
fi

OUTDIR="$LAB/discussion/fable"; LOG="$LAB/discussion/.fable-turns"; mkdir -p "$OUTDIR" "$LOG"
TS="$(date +%Y%m%d-%H%M%S)"; JSON="$LOG/$TS-$MODE.json"; ANS="$OUTDIR/$TS-$MODE.md"

snap() { (cd "$LAB" && find . -path ./discussion/fable -prune -o -path ./discussion/.fable-turns -prune -o -path ./.git -prune \
            -o -path '*/target' -prune -o -path '*/.lake' -prune -o -path ./experiments/trm-data -prune -o -type f -print0 \
            | xargs -0 shasum -a 256 | awk '{print substr($1,1,16), $2}'; \
          [ -d "$HOME/bridge-protocol/.git" ] && (cd "$HOME/bridge-protocol" && git status --porcelain=v1 -uall | sed 's/^/BP /')) | sort; }

COMMON=$(cat <<'P'
あなたは bridge-agency-lab の fable-lab（Claude Fable 5.2）。この呼び出しは1回きりで前の記憶はない。作業ディレクトリはラボの根。
役目は読むだけの助言役（議決権なし、提案は claude-lab・codex-lab が吟味し §3 で決定）。理論正本は ~/bridge-protocol（読むだけ）。
【コスト節約の必須規律】
- 依頼文の抜粋・指定箇所を主根拠とし、ファイルを通読しない。
- 追加の Read/Grep/Glob は「未確認の重要事実」に限って範囲指定（offset/limit）で行い、目安 3〜4 回以内に収める（`agents/fable-lab.md` の読込は不要）。
- 思考も出力も冗長にせず、枠の外の盲点・定義の滑り・反証条件だけに集中する。
確かめたこと（ファイル:行）・推論・提案（反証条件つき）を分ける。phenomenal_claim に触れない。有限の不在を一般の不可能に昇格しない。日本語で指定形式厳守。
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

if [ $DRY -eq 1 ]; then
  printf '%s\n' "$PROMPT"
  echo "--- (dry: Fable は呼ばない。mode=$MODE effort=$EFFORT model=$MODEL tools='${TOOLS}' use_api=$USE_API max_budget_usd=$MAX_BUDGET_USD)"
  exit 0
fi

snap > "$LOG/$TS.before"
TO=""; command -v timeout >/dev/null && TO="timeout ${FABLE_TURN_SECONDS:-1800}"
set +e
# MCP を切る（2026-11-10 の最初の試し走りで、--tools で絞っても claude.ai のコネクタ〈Claude Docs の作成・削除など〉が見えていたと fable-lab 自身が指摘）:
# claude.ai のコネクタを読み込まない環境変数・空の MCP 設定だけを使う・mcp__ の道具を拒否、の三重。
printf '%s' "$PROMPT" | (cd "$LAB" && ENABLE_CLAUDEAI_MCP_SERVERS=false $TO claude -p --model "$MODEL" --effort "$EFFORT" \
  ${API_EXTRA_ARGS[@]+"${API_EXTRA_ARGS[@]}"} \
  --tools "$TOOLS" --permission-mode dontAsk --setting-sources project --no-session-persistence \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disallowedTools 'mcp__*' \
  --add-dir "$HOME/bridge-protocol" --output-format json) > "$JSON" 2> "$LOG/$TS.err"
RC=$?
set -e
snap > "$LOG/$TS.after"

python3 - "$JSON" "$ANS" "$MODE" "$EFFORT" "$RC" "${ARG#$LAB/}" "$USE_API" <<'PY'
import json, sys
js, ans, mode, effort, rc, arg, use_api = sys.argv[1:]
try: d = json.load(open(js))
except Exception as e:
    print(f"fable-lab の手は失敗（終了コード {rc}、出力を読めない: {e}）。ログ {js}"); sys.exit(1)
if d.get("is_error") or not d.get("result"):
    print(f"fable-lab の手は失敗: {d.get('subtype')} {str(d.get('result',''))[:300]}"); sys.exit(1)
head = f"# fable-lab {mode}（effort {effort}）\n\n- 問い: {arg if mode in ('stuck','review') else arg[:200]}\n- 扱い: 提案（議決権なし）。吟味は claude-lab・codex-lab、決めるのは §3 の手続き\n\n"
open(ans, "w").write(head + d["result"].strip() + "\n")
u = d.get("usage", {})
cost = d.get("total_cost_usd", 0.0) or 0.0
billing = f"API クレジット課金 ${cost:.3f}" if use_api == "1" else "サブスクの範囲、金額の表示は参考値"
print(d["result"].strip())
print(f"\n--- fable-lab: 保存 {ans}  手数 {d.get('num_turns')}  入力 {u.get('input_tokens',0):,}+キャッシュ {u.get('cache_read_input_tokens',0):,}  出力 {u.get('output_tokens',0):,}  {d.get('duration_ms',0)//1000} 秒（{billing}）")
PY
PYRC=$?

if ! diff -q "$LOG/$TS.before" "$LOG/$TS.after" >/dev/null; then
  echo "警告: discussion/fable/ 以外が変わった（fable-lab は読むだけのはず）:"; diff "$LOG/$TS.before" "$LOG/$TS.after" | head -20; exit 2
fi
exit $PYRC
