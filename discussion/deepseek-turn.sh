#!/usr/bin/env bash
# deepseek-lab（DeepSeek Harness `dsh` ＋ OpenRouter 経由の DeepSeek モデル）の1手を、新しい会話で非対話に走らせる。
# 使い方: bash discussion/deepseek-turn.sh [--dry | --msg-file <path>]
#   --dry: 受信箱を読まず、ファイルを書かない試し走り。--msg-file: 受信箱の代わりにそのファイルを [I] メッセージとして使う（送信もしない）。
# 前提: claude-lab が先に deepseek-lab へ [I] メッセージ（仕様番号・書いてよいファイル・コマンド・受け入れ条件）を送っておく。
#
# 守りの層:
#  1. dsh の headless を --permission-mode workspace-write --approval-policy never で走らせる。
#     macOS では Seatbelt で、書き込みはラボ（作業ディレクトリ）と一時ディレクトリだけに閉じる。承認待ちで止まらない（要承認の呼び出しは拒否）。
#  2. 受信箱の読み取りと返信の送信はこのスクリプトがやる（agmsg の db はサンドボックスの外にあるので、dsh には書かせない）。
#  3. 走らせる前後でラボと ~/bridge-protocol の状態を比べ、書いてはいけない場所の変化を報告する（自動では戻さない。claude-lab が見る）。
#  4. 関門（2026-11-06 ユーザー指示: モデルの自己申告を信じず、テストと関門で覆う）。手のあと、このスクリプトがサンドボックスの外で独立に確かめる:
#     - [I] メッセージの `FILE: <パス>`（glob 可）にない場所が変わっていたら不合格。書いてはいけない場所（formal/ など）も不合格。
#     - [I] メッセージの `GATE: <コマンド>` を一つずつラボの根で走らせ、終了コードが 0 でなければ不合格。
#     - core/ か rust/ が変わっていたら `sh core/check/run.sh`（Julia と Rust のビット単位の照合）を必ず足す。
#     判定（合格／不合格）と各関門の終了コードを返信の先頭に付け、deepseek-lab の文は「自己申告（未検証）」として後ろに付ける。終了コード: 合格 0、不合格 2。
set -euo pipefail
LAB="$HOME/bridge-agency-lab"
AG="$HOME/.agents/skills/agmsg/scripts"
DSH="$(command -v dsh || true)"
[ -n "$DSH" ] || { echo "dsh が見つからない（discussion/README.md §1.1 の準備を先に）" >&2; exit 1; }
DRY=0; MSGFILE=""; AGENT=dsh
# --codex-fix <file>（2026-11-06 ユーザー決定「レビューと修正は codex にやらせる」）: deepseek-lab の手が不合格のあと、codex-lab が
# 差分をレビューして直す手を、同じ前後比較・FILE:・GATE: の関門で走らせる。<file> は claude-lab が書いた修正依頼（FILE:/GATE: 付き）。
case "${1:-}" in --dry) DRY=1 ;; --msg-file) MSGFILE="${2:?}" ;; --codex-fix) MSGFILE="${2:?}"; AGENT=codex ;; esac
CODEX="$HOME/.local/bin/codex"; [ -x "$CODEX" ] || CODEX="$(command -v codex || true)"
LOG="$LAB/discussion/.deepseek-turns"; mkdir -p "$LOG"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$LOG/$TS.jsonl"; ERR="$LOG/$TS.err"

snap() { (cd "$LAB" && find . -path ./discussion/.deepseek-turns -prune -o -path ./.git -prune -o -path '*/target' -prune -o -path '*/.lake' -prune -o -type f -print0 \
            | xargs -0 shasum -a 256 | awk '{print substr($1,1,16), $2}'; \
          [ -d "$HOME/bridge-protocol/.git" ] && (cd "$HOME/bridge-protocol" && git status --porcelain=v1 -uall | sed 's/^/BP /')) | sort; }
snap > "$LOG/$TS.before"
# 1手の打ち切り（2026-11-06）: 既定 30 分。DSH_TURN_SECONDS で変えられる。打ち切られたら dsh の手は未完了として不合格。
TO_TURN=""; command -v timeout >/dev/null && TO_TURN="timeout ${DSH_TURN_SECONDS:-1800}"

if [ $DRY -eq 1 ]; then
  MSG="（試し走り）ファイルを一つも書かず、次だけをして答える: (1) core/ にある .jl ファイルの数、(2) discussion/agents/deepseek-lab.md の「してはいけないこと」の項目数。"
elif [ -n "$MSGFILE" ]; then
  MSG="$(cat "$MSGFILE")"
else
  MSG="$(bash "$AG/inbox.sh" agency-lab deepseek-lab 2>&1 || true)"
  printf '%s' "$MSG" | grep -qE '\[I[] ]' || { echo "deepseek-lab の受信箱に [I] メッセージがない。走らせない。"; exit 1; }
fi

PROMPT=$(cat <<P
あなたは bridge-agency-lab の deepseek-lab（実装の席）。この手は新しい会話で、前の手の記憶はない。作業ディレクトリはラボの根。
最初に discussion/agents/deepseek-lab.md（この席の役目と禁止事項）を読む。そのあと下の claude-lab からのメッセージに答える。
メッセージに書かれたファイルだけを書き、書かれたコマンドだけを走らせる。読むのは指定された仕様と関係する関数の範囲だけ。
ネットワーク・git・削除・agmsg の操作はしない（返信はこのスクリプトが送る）。
最後の答えが claude-lab への返信になる: 15行以内、日本語で、変えたファイル、走らせたコマンドと結果（通った／落ちた、落ちたら最初のエラー）、質問。
GATE: の行のコマンドは、あなたが終えたあとにスクリプトが独立に走らせて合否を決める。
書き方（席の指針「進め方」、claude-lab と同じ）: 範囲で読む → 計画を決める（返信の1行目に「計画: ファイル:行 → 要点」）→ 一度に書く →
QUICK: の行だけを走らせて確かめる（3 回まで）。**GATE: の行は走らせない**（全体の実行はこのスクリプトが手のあとに行う）。
道具の呼び出しは 25 回、時間は 20 分まで（30 分で打ち切られる）。同じエラーが 2 回続いたら質問で返す。

--- claude-lab からのメッセージ ---
$MSG
P
)

if [ "$AGENT" = codex ]; then
PROMPT=$(cat <<P
あなたは bridge-agency-lab の codex-lab。この手は修正の手（ユーザー決定 2026-11-06: deepseek-lab の手が不合格のとき、レビューと修正は codex-lab が行う）。
規律は AGENTS.md と同じ。スキル（SKILL.md）は読まず、agmsg も使わない（返信はこのスクリプトが送る）。
下の修正依頼に書かれた FILE: のファイルだけを直し、GATE: のコマンドで確かめる。直すのは不合格の原因に限り、仕様・数値・凍結・既存の判定は変えない。
先に原因の箇所を範囲で読み、まとめて直す。確かめるのは QUICK: の行だけ（3 回まで）。GATE: の行（全体の実行）は走らせない（手のあとにこのスクリプトが走らせる）。コマンドは 20 回まで。
最後の答えが claude-lab への返信になる: 15 行以内、日本語。レビューで見つけた問題（番号つき）、直した箇所（ファイル:行）、走らせた GATE と結果。

--- claude-lab からの修正依頼 ---
$MSG
P
)
fi

set +e
if [ "$AGENT" = codex ]; then
  [ -n "$CODEX" ] || { echo "codex が見つからない" >&2; exit 1; }
  printf '%s' "$PROMPT" | ${TO_TURN:-} "$CODEX" exec -C "$LAB" -s workspace-write -c 'model_reasoning_effort="medium"' --json -o "$OUT.last" - > "$OUT" 2> "$ERR"
  RC=$?
else
  ( cd "$LAB" && printf '%s' "$PROMPT" | ${TO_TURN:-} "$DSH" --profile headless --permission-mode workspace-write --approval-policy never --json - ) > "$OUT" 2> "$ERR"
  RC=$?
fi
set -e

snap > "$LOG/$TS.after"
CHANGED=$(comm -13 "$LOG/$TS.before" "$LOG/$TS.after" | awk '{print $NF}' | sed 's#^\./##' | sort -u)
GONE=$(comm -23 <(awk '{print $NF}' "$LOG/$TS.before" | sort -u) <(awk '{print $NF}' "$LOG/$TS.after" | sort -u) | sed 's#^\./##')

if [ "$AGENT" = codex ]; then
ANSWER=$( if [ $RC -eq 0 ] && [ -s "$OUT.last" ]; then echo "[reason=completed tool_calls=$(grep -c '"command_execution"' "$OUT" || true)]"; cat "$OUT.last"; else echo "(final なし) codex の終了コード $RC"; fi )
else
ANSWER=$(python3 - "$OUT" <<'PY'
import json,sys
fin=None; err=None; tools=0
for line in open(sys.argv[1],encoding='utf-8',errors='replace'):
    try: e=json.loads(line)
    except Exception: continue
    t=e.get('type')
    if t=='final': fin=e
    elif t=='error': err=e.get('message')
    elif t=='tool_call': tools+=1
if fin is None:
    print(f"(final なし) error: {err}"); sys.exit(0)
r=(fin.get('reason') or {}).get('kind')
print(f"[reason={r} tool_calls={tools}]")
print(fin.get('text') or fin.get('answer') or json.dumps({k:v for k,v in fin.items() if k!='type'},ensure_ascii=False)[:2000])
PY
)
fi

# ---- 関門 ----
GATES_LOG="$LOG/$TS.gates"; : > "$GATES_LOG"
FAIL=0; VERDICT_LINES=()
FINAL_KIND=$(printf '%s\n' "$ANSWER" | head -1 | sed -n 's/^\[reason=\([a-z_]*\).*/\1/p')
[ "$RC" -eq 0 ] && [ "$FINAL_KIND" = "completed" ] || { FAIL=1; VERDICT_LINES+=("dsh の手が完了していない（終了コード ${RC}、reason=${FINAL_KIND:-なし}）"); }

ALLOWED=$(printf '%s\n' "$MSG" | sed -n 's/^[[:space:]]*FILE:[[:space:]]*//p' | sed 's/[[:space:]]*$//')
OUTSIDE=""
for f in $CHANGED $GONE; do
  ok=0
  while IFS= read -r pat; do [ -n "$pat" ] && case "$f" in $pat) ok=1 ;; esac; done <<< "$ALLOWED"
  [ $ok -eq 1 ] || OUTSIDE="$OUTSIDE $f"
done
[ -z "$OUTSIDE" ] || { FAIL=1; VERDICT_LINES+=("FILE: にない変化:$OUTSIDE"); }
if printf '%s\n' $CHANGED $GONE | grep -qE '^(formal/|discussion/|README\.md|CLAUDE\.md|AGENTS\.md|experiments/freeze-)'; then
  FAIL=1; VERDICT_LINES+=("書いてはいけない場所（formal/・discussion/・README・CLAUDE/AGENTS・freeze）に変化")
fi
if ! diff -q <(grep '^BP ' "$LOG/$TS.before") <(grep '^BP ' "$LOG/$TS.after") >/dev/null; then
  FAIL=1; VERDICT_LINES+=("~/bridge-protocol に変化（BLOCK 相当）")
fi

# GATE の行: `GATE: <cmd>` は順に走る組 main。`GATE[<名>]: <cmd>` は名ごとの組で、組は**並べて**走らせ、組の中は書いた順に走らせる
# （2026-11-06 ユーザー指示: 関門を並べて走らせて速くする。依存のある関門は同じ組に入れる）。
GATELINES=$(printf '%s\n' "$MSG" | sed -n 's/^[[:space:]]*GATE\(\[[A-Za-z0-9_-]*\]\)\{0,1\}:[[:space:]]*//p')
GATES="$GATELINES"
GROUPED=$(printf '%s\n' "$MSG" | sed -n 's/^[[:space:]]*GATE\[\([A-Za-z0-9_-]*\)\]:[[:space:]]*\(.*\)$/\1	\2/p; s/^[[:space:]]*GATE:[[:space:]]*\(.*\)$/main	\1/p')
if printf '%s\n' $CHANGED $GONE | grep -qE '^(core/|rust/)' && ! printf '%s\n' "$GATES" | grep -qF 'sh core/check/run.sh'; then
  GATES=$(printf '%s\n%s' "$GATES" 'sh core/check/run.sh'); GROUPED=$(printf '%s\n%s' "$GROUPED" 'corecheck	sh core/check/run.sh')
fi
TO=""; command -v timeout >/dev/null && TO="timeout 3600"
GDIR="$LOG/$TS.gatedir"; mkdir -p "$GDIR"
i=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  i=$((i+1)); grp="${line%%	*}"; cmd="${line#*	}"
  printf '%s\t%s\n' "$i" "$cmd" >> "$GDIR/group-$grp"
done <<< "$GROUPED"
for gf in "$GDIR"/group-*; do
  [ -e "$gf" ] || continue
  (
    set +e
    while IFS= read -r ln; do
      n="${ln%%	*}"; c="${ln#*	}"
      { echo "=== GATE: $c"; ( cd "$LAB" && $TO bash -c "$c" ) 2>&1; rc=$?; echo "=== exit $rc"; } > "$GDIR/out-$n"
      rc=$(tail -1 "$GDIR/out-$n" | sed 's/=== exit //'); printf '%s\t%s\n' "$rc" "$c" > "$GDIR/rc-$n"
    done < "$gf"
  ) &
done
wait
for ((k=1; k<=i; k++)); do
  [ -e "$GDIR/rc-$k" ] || continue
  cat "$GDIR/out-$k" >> "$GATES_LOG"
  GRC="$(cut -f1 "$GDIR/rc-$k")"; g="$(cut -f2- "$GDIR/rc-$k")"
  if [ "$GRC" = 0 ]; then VERDICT_LINES+=("関門 通過: $g")
  else FAIL=1; VERDICT_LINES+=("関門 失敗（終了 ${GRC}）: $g"); fi
done
[ -n "$GATES" ] || VERDICT_LINES+=("関門（GATE:）の指定なし")

# 書き方の規律（2026-11-06）: deepseek-lab が GATE: の全体の実行を自分で走らせた回数を記録から数える（不合格にはしない、報告する）。
if [ "$AGENT" = dsh ] && [ -n "$GATES" ]; then
  SELF_GATE=$(python3 "$LAB/discussion/count_self_gate.py" "$OUT" "$GATES" 2>/dev/null || echo "?")
  VERDICT_LINES+=("書き方: GATE の全体の実行を自分で走らせた回数 ${SELF_GATE}（規律は 0）")
fi
if [ $FAIL -eq 0 ]; then VERDICT="合格"; else VERDICT="不合格"; fi
REPLY=$( { echo "[検証] ${VERDICT}（deepseek-turn.sh が独立に確認。関門の出力は discussion/.deepseek-turns/$TS.gates）"
           printf '  %s\n' "${VERDICT_LINES[@]}"
           [ -n "$CHANGED$GONE" ] && echo "  変化: $(printf '%s ' $CHANGED $GONE)"
           echo "[${AGENT} の自己申告（未検証）]"
           printf '%s\n' "$ANSWER"; } )

echo "$AGENT の手（deepseek-lab または codex-lab の修正）: 終了コード $RC  ログ ${OUT}（stderr は ${ERR}）"
echo "$REPLY"
[ -n "$CHANGED$GONE" ] || echo "この手で変わったファイルはない。"

if [ $DRY -eq 0 ] && [ -z "$MSGFILE" ]; then
  printf '%s' "$REPLY" | bash "$AG/send.sh" agency-lab deepseek-lab claude-lab --body - >/dev/null && echo "返信を claude-lab に送った。"
elif [ "$AGENT" = codex ]; then
  printf '%s' "$REPLY" | bash "$AG/send.sh" agency-lab codex-lab claude-lab --body - >/dev/null && echo "返信を claude-lab に送った（codex-lab の修正の手）。"
fi
[ $FAIL -eq 0 ] && exit 0 || exit 2
