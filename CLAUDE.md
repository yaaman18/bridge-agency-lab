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
  ページの JavaScript は `app/bridge.js` の橋渡しだけにする。アプリの存在の規則は v3.7 で固定（2026-11-05 ユーザー決定）。新しい規則は
  変種として Julia に足し、照合の場面を保つためだけに Rust へ入れ、アプリの既定は変えない。実装言語を変えるときは先にユーザーに確認する（`core/README.md`）。

## 判断の委任（2026-11-04 ユーザー決定、2026-11-05 改訂）

- agmsg のチーム `agency-lab` での連続作業（`discussion/README.md`）では次のとおり。agency-lab の席 `claude-lab` に着いたら
  `discussion/agents/claude-lab.md` を読む。Codex 側の指針は `AGENTS.md`。
- **理論の持ち主はユーザー、抽象論理は bridge-protocol で解く。** bridge-protocol の理論そのもの（M1〜M4、DC、AGENCY-001 の述語の定義、
  Φ・D・層分離、圏論的仕様、凍結 statement）に触れる点は `discussion/bp-proposals.md` に出してユーザーの事前承認を待つ。
  ラボの作業に要るときは仮定 `H<番号>` として明示して先へ進む。
- **ラボの側の哲学・論理と実装上の判断は委任。** 理論をこの基体でどう読むか・ラボの用語の定義・要件・判定の運用・論文の読みの取り込み・方針、
  および上の「採用はユーザーが決める」「数値を無断で変えない」「基体の側を変える案はユーザー判断」に当たる実装上の判断は、
  claude-lab と codex-lab の**両者の合意**で決めてよい（割れたら保守的な案）。すべて `discussion/decisions-log.md` に
  元に戻す方法とともに記録し、ユーザーが事後承認する（差し戻されたら戻す）。
- **実装の分担**（2026-11-07 ユーザー決定、2026-11-06 の分担を改める）: Lean の statement と証明、Julia・Rust・試験のコードは **Claude（claude-lab）が書く**。
  Claude は書いたあと自分で関門（FILE:・GATE:、負の対照）を走らせ、Codex がレビューする（I-R）。deepseek-lab の席は休止（`discussion/agents/deepseek-lab.md`、
  `deepseek-turn.sh` は記録として残す）。理由: 節約より速さと正確さを優先（S2〜S5 で deepseek-lab の手は 26〜30 分・打ち切り・崩れた下書き、Claude は数分）。
- **fable-lab**（2026-11-10 ユーザー決定）: Claude Fable 5.2 は「煮詰まったときの啓示」と「ユーザーの任意の確認」にだけ使う、読むだけ・議決権なしの助言役。
  呼び方は `discussion/fable-turn.sh`（Pro のサブスクの範囲、2026-11-16 まで）、指針は `discussion/agents/fable-lab.md`、取り決めは `discussion/README.md` §1.2。
- **切り出しの約束**（2026-11-05、`discussion/promise-cutout.md`）: いまの作業はすべて「系統」の側（個体は試作）。系統から一体を切り出して
  法則を凍結するのはユーザーの決定で、切り出した個体の法則・db には誰も触れず、救わない。約束を変えるのはユーザーだけ。
- 委任しないもの: `~/bridge-protocol` への書き込み、アプリの db への書き込みと artifact の公開、git の commit / push、ファイルの削除、
  外部への送信、`phenomenal_claim` に触れる主張。予測の凍結・外れの報告・事実/推論/提案の区別はそのまま守る。

## 進め方

- 実行: `cd experiments && julia --project=.. <script>.jl`
- Lean: `formal/` に statement を先に書き、`sh formal/check.sh` で型検査（bridge-protocol は変えない）。証明の後に Julia を書く。
  新しい Lean は切り出しの臨界経路に要る statement に限る（`discussion/dev-guidelines.md` §3、2026-11-10 ユーザー決定「r3でやって」）。
- 監査: アプリの db の存在を ArtifactData で読むだけにして `audit/in/state-v<版>.json` に置き、`sh audit/run.sh <file>`（`audit/README.md`）。db には書かない。
- 報告は日本語で、作業の途中報告を挟まず最後に一回だけ返す。
- 結果は README.md の「実験の経緯」「確認した事実」「未決」を更新して残す。項番は段の区切りで足す（`discussion/dev-guidelines.md` §5）。
- 作業の正本の手順は `discussion/procedure-cutout.md`（切り出しまで、r3）、指針は `discussion/dev-guidelines.md`。
