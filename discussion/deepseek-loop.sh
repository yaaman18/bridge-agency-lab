#!/usr/bin/env bash
# deepseek-lab に、関門が通るまで自分で直させる繰り返し（2026-11-15 ユーザーの提案「harness 自身に再帰的な修正をさせる」）。
# 使い方: bash discussion/deepseek-loop.sh <依頼文.md> [最大の回数=5]
#   依頼文は deepseek-turn.sh と同じ形（[I]、FILE:、GATE:、QUICK:）に、読むだけのファイルを `PROTECT: <パス>`（glob 可）で足す。
# 一回 = deepseek-turn.sh --msg-file の一手（その中で FILE:・GATE: の独立の検証が走る）。
# 合格 = 手が完了し、落ちた関門がなく、PROTECT のファイルが変わっていない。FILE: の外の変化は数えずに報告する
#        （ほかの席が同時に書いていることがあるため。ただし core/・rust/・formal/ の変化はその場で止める）。
# 不合格なら、規約＋もとの依頼＋前の手の結果（検証の行、落ちた関門の出力の末尾、席の返信）を次の手に渡す。
# 止まる条件: 合格／席が BLOCKED: を返した／同じ落ち方が続けて 2 回（→ codex-lab に一度だけ直させ、それでも落ちたら止まる）／最大の回数。
# 終了コード: 合格 0、BLOCKED 3、行き詰まり 4、回数切れ 5、保護した場所の変化 6。要約は最後の十数行だけ読めば足りる。
set -uo pipefail
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8   # 日本語の後ろに変数を置く行と cut -c のため
LAB="$HOME/bridge-agency-lab"; cd "$LAB"
REQ="${1:?依頼文}"; MAX="${2:-5}"
RULES="$LAB/discussion/agents/deepseek-coding-rules.md"
LOG="$LAB/discussion/.deepseek-turns"; TS="$(date +%Y%m%d-%H%M%S)"; W="$LOG/loop-$TS"; mkdir -p "$W/protect"
cp "$REQ" "$W/request.md"
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
# PROTECT: 写しと sha を取っておく
PROT=$(sed -n 's/^[[:space:]]*PROTECT:[[:space:]]*//p' "$REQ" | sed 's/[[:space:]]*$//')
: > "$W/protect.list"
for pat in $PROT; do for f in $pat; do [ -f "$f" ] || continue
  d="$W/protect/$(printf '%s' "$f" | tr '/' '_')"; cp "$f" "$d"; echo "$(sha "$f")  $f  $d" >> "$W/protect.list"; done; done
check_protect() { local bad=""; while read -r h f d; do [ -n "$f" ] || continue
    if [ ! -f "$f" ] || [ "$(sha "$f")" != "$h" ]; then cp "$d" "$f"; bad="$bad $f"; fi; done < "$W/protect.list"; printf '%s' "$bad"; }
guard() { git status --porcelain=v1 -- core rust/being-core formal 2>/dev/null | awk '{print $2}' | sort; }
G0="$(guard)"
PREV_SIG=""; CODEX_USED=0; N=0; FEEDBACK=""
summary() { echo "==== deepseek-loop: $1（$N 回、記録 ${W#$LAB/}）"; cat "$W/rounds.txt" 2>/dev/null; }
while [ "$N" -lt "$MAX" ]; do
  N=$((N+1)); M="$W/msg-$N.md"
  { echo "[I] （deepseek-loop $N 回め／最大 $MAX 回。下の規約に従う）"; echo; cat "$RULES"; echo; echo "--- 依頼 ---"; cat "$REQ"
    [ -n "$FEEDBACK" ] && { echo; echo "--- 前の手の結果（これを直す。もとの依頼と規約は変わらない） ---"; printf '%s\n' "$FEEDBACK"; }; } > "$M"
  AGENT_FLAG="--msg-file"; WHO=dsh
  if [ "$CODEX_USED" -eq 1 ] && [ "${USE_CODEX_NOW:-0}" -eq 1 ]; then AGENT_FLAG="--codex-fix"; WHO=codex; USE_CODEX_NOW=0; fi
  bash discussion/deepseek-turn.sh "$AGENT_FLAG" "$M" > "$W/out-$N.txt" 2>&1; RC=$?
  GATES=$(sed -n 's/.*関門の出力は \(discussion\/\.deepseek-turns\/[0-9-]*\.gates\).*/\1/p' "$W/out-$N.txt" | head -1)
  FAILED=$(grep -c "関門 失敗" "$W/out-$N.txt"); INCOMPLETE=$(grep -c "完了していない" "$W/out-$N.txt")
  TAMPER="$(check_protect)"
  BLOCKED=$(awk '/自己申告/{f=1;next} f' "$W/out-$N.txt" | grep -m1 "^BLOCKED:" || true)
  OUTSIDE=$(sed -n 's/^  FILE: にない変化: //p' "$W/out-$N.txt")
  echo "  $N ($WHO): 落ちた関門 ${FAILED}、未完了 ${INCOMPLETE}、保護の変更 [${TAMPER# }]、FILE の外 [${OUTSIDE}]${BLOCKED:+、$BLOCKED}" >> "$W/rounds.txt"
  if [ "$(guard)" != "$G0" ]; then summary "保護した場所（core/・rust/being-core・formal/）が変わった。止める"; exit 6; fi
  if [ -n "$BLOCKED" ]; then summary "席が止まった"; awk '/自己申告/{f=1;next} f' "$W/out-$N.txt" | head -20 | cut -c1-400; exit 3; fi
  if [ "$FAILED" -eq 0 ] && [ "$INCOMPLETE" -eq 0 ] && [ -z "$TAMPER" ]; then
    summary "合格"; awk '/自己申告/{f=1;next} f' "$W/out-$N.txt" | head -12 | cut -c1-300; exit 0; fi
  # 次の手に渡す結果
  FEEDBACK=$( { grep -E "検証|関門 |完了していない" "$W/out-$N.txt" | cut -c1-300
      [ -n "$TAMPER" ] && echo "規約違反: PROTECT のファイルを変えた（元に戻した）:${TAMPER}。試験や正解を変えず、実装を直す。"
      if [ -n "$GATES" ] && [ -f "$GATES" ]; then echo "--- 落ちた関門の出力（末尾） ---"
        awk '/^=== GATE:/{blk=$0; buf=""; next} /^=== exit /{ if ($3!="0") print blk "\n" buf "\n" $0; next} {buf=buf $0 "\n"}' "$GATES" | tail -70 | cut -c1-300; fi
      echo "--- 前の手の返信 ---"; awk '/自己申告/{f=1;next} f' "$W/out-$N.txt" | head -18 | cut -c1-400; } )
  SIG=$(printf '%s' "$FEEDBACK" | grep -v "discussion/.deepseek-turns" | sed -n '/落ちた関門の出力/,/前の手の返信/p' | shasum -a 256 | awk '{print $1}')
  if [ "$SIG" = "$PREV_SIG" ]; then
    if [ "$CODEX_USED" -eq 0 ]; then CODEX_USED=1; USE_CODEX_NOW=1; echo "  （同じ落ち方が 2 回。次の手は codex-lab に直させる）" >> "$W/rounds.txt"
    else summary "行き詰まり（codex-lab の直しの後も同じ落ち方）"; printf '%s\n' "$FEEDBACK" | tail -30; exit 4; fi
  fi
  PREV_SIG="$SIG"
done
summary "回数切れ"; printf '%s\n' "$FEEDBACK" | tail -30; exit 5
