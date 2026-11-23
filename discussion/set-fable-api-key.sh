#!/usr/bin/env bash
# Fable 用 Anthropic API キーをリポジトリ外（~/.config/anthropic/fable.env, chmod 600）へ安全に保存する。
# 入力は画面にも履歴にも残らない（read -rs）。
set -euo pipefail

DIR="$HOME/.config/anthropic"
FILE="$DIR/fable.env"

mkdir -p "$DIR"
chmod 700 "$DIR"

printf 'Anthropic API key (sk-ant-...) を貼り付けて Enter（画面には表示されません）: '
IFS= read -rs KEY
printf '\n'

if [ -z "$KEY" ]; then
  echo "エラー: 空のため保存しませんでした。" >&2
  exit 1
fi

umask 077
printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" > "$FILE"
chmod 600 "$FILE"

echo "保存完了: $FILE (mode=600, length=${#KEY})"
