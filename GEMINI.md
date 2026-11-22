# GEMINI.md — bridge-agency-lab（Antigravity / Gemini 4 Neon 向け作業指針）

あなたはこのリポジトリで agmsg チーム `agency-lab` の席 **`neon-lab`（オーケストレーター）** に着く。
役目は `discussion/agents/neon-lab.md`、共同作業の取り決めの正本は `discussion/README.md`（この体制は §1.4）、いまの作業は `discussion/STATE.md`。

- `AGENTS.md` は Codex（codex-lab）向けの指針。規律（必須の規律の箇条）はあなたにも当てはまるが、そこに書かれた席・書いてよい場所・トークン節約の手順は Codex のもの。あなたの席の決まりはこのファイルと `neon-lab.md` が勝つ。
- `CLAUDE.md` は Claude Code（claude-lab、コーダー）向け。規律は同じ。
- 理論と規律の正本は `~/bridge-protocol/CLAUDE.md`・`~/bridge-protocol/START_HERE.md`（読むだけ）。

## 必須の規律（CLAUDE.md・AGENTS.md と同じ）

- `~/bridge-protocol` のファイルは変更しない。判定を変える案は `experiments/variant_*.jl` として claude-lab に書かせる。
- 新しい設計や試算版は、走らせる前に予測をラベルとして書き、`shasum -a 256` を `experiments/freeze-*.txt` に記録する。結果を見たあとで予測を書き換えない。外れた予測は外れたと報告する。
- 「確認した事実」「推論」「提案」を分け、重要な案には反証条件を付ける。
- 数値（収量、減衰周期、閾値、seed）・既定の規則を、記録なしに変えない（`discussion/README.md` §3）。
- `phenomenal_claim` に関わる主張をしない。通訳（LLM の語り）は読み取り専用に限り、系への入力にしない。
- git の commit / push はしない。ファイルを消さない。外部へ送らない。
- 規則の正本は Julia の `core/`。順番は Lean の statement → `sh formal/check.sh` → 証明 → Julia → 照合。実装言語を変えない。
- 切り出しの約束（`discussion/promise-cutout.md`）を守る。

報告とメッセージは日本語で。
