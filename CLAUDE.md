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
- **実装の席 lab-coder**（2026-11-13 ユーザー決定、上の 2026-11-07 の分担を改める）: Lean・Julia・Rust・試験のコードは、Claude Code のサブエージェント `lab-coder`（Opus 5.5、
  `.claude/agents/lab-coder.md`）が合意済みの S 仕様に沿って書き、関門を走らせて報告する。claude-lab は仕様・予測の凍結・差分の点検・記録、Codex がレビュー（I-R）。
  理由: claude-lab が Fable で動く回は、コードを書かせるとトークンがもったいない。Lean も同じ席に書かせる（Claude の系統の中にとどまる）。
- **deepseek-lab の一部再開**（2026-11-15 ユーザー決定）: 公式 TRM（Python）の Julia への移植（S56 とその続き）のコーディングは、`discussion/deepseek-turn.sh`（OpenRouter 経由の `deepseek/deepseek-v4.1-flash-1017`）に書かせ、claude-lab は仕様・手の割り付け・関門・記録、Codex がレビューする。書いてよい場所は `experiments/trm/` だけ。理由: Claude のトークンの節約。ほかのコードは lab-coder のまま。
- **deepseek-lab の停止と移植の書き手の交代**（2026-11-16 ユーザー決定）: DeepSeek の席を止める。S56 の残り（r5 の試験と実装）は **codex-lab が書く**。書いてよい場所は `experiments/trm/` だけ。書き手とレビューが同じ席にならないよう、codex が書いた分のレビューは Claude の側（Opus 5.5 のサブエージェント）が行い、claude-lab は仕様・関門・記録。ほかのコードは lab-coder のまま。理由: DeepSeek は移植で空の合格・配線の誤り・壊れた写しを繰り返した。
- **Fable のいない間の理論作業**（2026-11-16 ユーザー決定）: 理論は Opus 5.5 と codex-lab の議論で続ける。結論は〔暫定〕、Fable の見直しまで仕様・コードの根拠にしない。§0 問いの分離・基点 7329135 の固定・〔判断点 O<番号>〕の印・用語の取り決めの先読み（正本は `discussion/README.md` §1.3、一覧は `discussion/notes/OPUS-PERIOD.md`）。
- **fable-lab**（2026-11-10 ユーザー決定）: Claude Fable 5.2 は「煮詰まったときの啓示」と「ユーザーの任意の確認」にだけ使う、読むだけ・議決権なしの助言役。
  呼び方は `discussion/fable-turn.sh`（Pro のサブスクの範囲、2026-11-16 まで）、指針は `discussion/agents/fable-lab.md`、取り決めは `discussion/README.md` §1.2。
- **Neon オーケストレーター体制**（2026-11-20 ユーザー決定「Neon がオーケストレーターで ClaudeCode がコーダー、codex がレビュワー」。上の lab-coder と claude-lab の仕切りの分担を改める）:
  仕切り役は agmsg の席 `neon-lab`（Antigravity CLI の Gemini 4 Neon、指針は `discussion/agents/neon-lab.md`・`GEMINI.md`）。claude-lab は**コーダー**で、Opus 5.5 で起動し、
  Lean・Julia・Rust・試験を自分で書く（lab-coder は起こさない）。レビューは codex-lab。概念設計は当分ユーザーと neon-lab の壁打ちで、課題は3者で議論する。上の「両者の合意」は3者の合意と読む。
  Fable と lab-coder の形（2026-11-13）と fable-lab は休止として残し、Fable を再び使うときに戻す（`discussion/README.md` §1.4）。
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
- **/compact と /clear の通知**（2026-11-16 ユーザー決定）: 主の会話は、作業の一区切りが済んで次が関係ない話に移るとき「/clear してよい区切り」、同じ作業の途中で会話が長くなったとき「/compact してよい」、1 時間を超えて間があきそうで続きを使わないとき「休む前に /clear を」と、返事の最後に一行でユーザーに伝える。lab-coder の報告の最後の行の「通知:」も読んで伝える（`.claude/agents/lab-coder.md`）。/clear の前に `discussion/STATE.md` に続きの入口を書く。
- 結果は README.md の「実験の経緯」「確認した事実」「未決」を更新して残す。項番は段の区切りで足す（`discussion/dev-guidelines.md` §5）。
- 作業の正本の手順は `discussion/procedure-cutout.md`（切り出しまで、r3）、指針は `discussion/dev-guidelines.md`。
