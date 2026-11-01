# bridge-agency-lab 作業指針

`~/bridge-protocol` の AGENCY-001 試作基体を使う実験場。経緯と現況は README.md を最初に読む。
理論と規律の正本は `~/bridge-protocol/CLAUDE.md` と `~/bridge-protocol/START_HERE.md` で、ここでもそれに従う。

## 必須の規律

- `~/bridge-protocol` のファイルは変更しない（判定、fixtures、登録物、logs/gates を含む）。判定を変える案は
  `experiments/variant_*.jl` として書き、`@eval AgencySubstrate` で上書きして比べる。採用はユーザーが決める。
- 新しい設計や試算版は、走らせる前に予測を TOML のコメントとラベルに書き、`shasum -a 256` を
  `experiments/freeze-*.txt` に記録する。結果を見たあとで予測を書き換えない。外れた予測は外れたと報告する。
- 「確認した事実」「推論」「提案」を分け、重要な案には反証条件を付ける。
- 数値（収量、減衰周期、閾値、seed）を無断で変えない。基体の側を変える案はユーザー判断。
- `phenomenal_claim` に関わる主張をしない。通訳（LLM の語り）は読み取り専用に限り、系への入力にしない。
- git の commit / push は依頼されたときだけ。
- 規則の正本は Julia の `core/`（2026-10-31 ユーザー決定）。新しい規則や変更は Julia で先に書く。アプリに入れるときは Rust の
  `rust/being-core`（no_std、将来は小型の計算機・マイコンへ）に同じ変更を入れ、`sh core/check/run.sh` で全場面のビット単位の一致を
  確かめてから `sh rust/build.sh` でページを作る。JavaScript（`memory/`・`matter/`）は v3.5 までの来歴の写しで、新しい規則は書かない。
  ページの JavaScript は `app/bridge.js` の橋渡しだけにする。実装言語を変えるときは先にユーザーに確認する（`core/README.md`）。

## 進め方

- 実行: `cd experiments && julia --project=.. <script>.jl`
- Lean: `formal/` に statement を先に書き、`sh formal/check.sh` で型検査（bridge-protocol は変えない）。証明の後に Julia を書く。
- 監査: アプリの db の存在を ArtifactData で読むだけにして `audit/in/state-v<版>.json` に置き、`sh audit/run.sh <file>`（`audit/README.md`）。db には書かない。
- 報告は日本語で、作業の途中報告を挟まず最後に一回だけ返す。
- 結果は README.md の「実験の経緯」「確認した事実」「未決」を更新して残す。
