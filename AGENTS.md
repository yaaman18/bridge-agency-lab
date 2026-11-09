# AGENTS.md — bridge-agency-lab（Codex 向け作業指針）

`~/bridge-protocol` の AGENCY-001 試作基体を使う実験場。経緯と現況は `README.md`（長いので「未決」と必要な項番から）。
理論と規律の正本は `~/bridge-protocol/CLAUDE.md`・`~/bridge-protocol/START_HERE.md`（読むだけ）。Claude 向けの同じ規律は `CLAUDE.md`。

このリポジトリでの Codex の席は **agmsg チーム `agency-lab` の `codex-lab`**。役目は `discussion/agents/codex-lab.md`、
共同作業の取り決めは `discussion/README.md`、いまの作業は `discussion/STATE.md`。
（bridge-protocol の AGENTS.md にある「10往復で停止」の上限はここでは適用しない。ここではユーザーの指示により、レート制限まで続ける。）

## 必須の規律（CLAUDE.md と同じ）

- `~/bridge-protocol` のファイルは変更しない（判定、fixtures、登録物、logs/gates を含む）。
- 新しい設計や試算版は、走らせる前に予測をラベルとして書き、`shasum -a 256` を `experiments/freeze-*.txt` に記録する。結果を見たあとで予測を書き換えない。外れた予測は外れたと報告する。
- 「確認した事実」「推論」「提案」を分け、重要な案には反証条件を付ける。
- 数値（収量、減衰周期、閾値、seed）・既定の規則を、記録なしに変えない（変えるのは `discussion/README.md` §3 の手続きで、`discussion/decisions-log.md` に記録したときだけ）。
- `phenomenal_claim` に関わる主張をしない。通訳（LLM の語り）は読み取り専用に限り、系への入力にしない。
- git の commit / push はしない。ファイルを消さない。
- 規則の正本は Julia の `core/`。アプリは Rust の `rust/being-core`（no_std）。JavaScript（`memory/`・`matter/`）は来歴の写し。実装言語を変えない。
- 順番は Lean の statement → `sh formal/check.sh` → 証明 → Julia → 照合（`sh core/check/run.sh`）。
- 切り出しの約束（`discussion/promise-cutout.md`）を守る。いまの作業は系統の側。切り出しはユーザーの決定で、約束はユーザーだけが変える。
- Julia・Rust・試験のコードは claude-lab が書く（2026-11-07 ユーザー決定「今後はあなたがコードを書く担当にしよう。節約より速さと正確さが欲しい」）。deepseek-lab の席は休止。I 段のレビューでは、claude-lab の点検とは独立に、差分と関門の結果を見る。
- Codex が書いてよいのは `discussion/reviews/`・`discussion/notes/` だけ（`discussion/agents/codex-lab.md`）。deepseek-lab の休止により `--codex-fix` の例外は使わない（2026-11-07）。

## トークン節約（2026-11-05 ユーザー決定、discussion/README.md §4.1）

- 1手ごとに新しい会話で起動される（`discussion/codex-turn.sh`）。前の往復の記憶はない前提で、`discussion/STATE.md` と受信箱の本文だけを文脈にする。
- 読むのはメッセージに指定された箇所だけ（`sed -n 'a,bp'`、`grep -n`）。README.md などの大きいファイルを通読しない。足りないときだけ追加で読み、コマンドは1手5回まで。長い出力は `head` で切る。
- 受信箱は指示に貼られ、返信は最後の答えをスクリプトが送る。agmsg のスクリプトとスキル（SKILL.md）は使わない。コマンドは1手3回まで。
- 返信は15行以内。`discussion/notes/` への追記は challenge・clarify の論点だけ（1手 2KB 目安）。返信の控えのファイルは作らない。

## 走らせ方

- 実験: `cd experiments && julia --project=.. <script>.jl`
- 照合: `sh core/check/run.sh`、Lean: `sh formal/check.sh`、監査: `sh audit/run.sh <file>`（db は読むだけ、書かない）
- 論文: `papers/index.tsv`、本文は `papers/text/<番号>.txt`（153件中30件）

報告とメッセージは日本語で。
