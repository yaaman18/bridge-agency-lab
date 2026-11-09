# S3 現行版（bin3＋idle_first＋核の関門）で同じ契約の H・D・N（R-BODY-1 の続き、R-BODY-3 と合わせて）

- 状態: r2（2026-11-06、codex S-R の 1〜5 を反映。I 段へ進むことを受理、最終受け入れは留保）。
- 目的: S2 は元の規則で D が偽だった（README 項番88）。D が真になる現行の L2 の系の規則（bin3＋idle_first＋核の関門、項番75・77 のユーザー決定）で、
  S1・S2 と同じ比較契約（同じ出生状態、同じ法則、保育期の台本だけが違う）のもとで H・D・N を測る。あわせて :swap の腕の試行表を Lean の検査と照合する。
- 対応する要件: R-BODY-1、R-BODY-3。出典: S1・S2 の仕様（r3・r2）、項番74（bin3＋idle の入れ替えの予測なしの報告）、項番77（`results-horizon-gate.json`、`formal/gen/Trials-gate.lean`）。

## 0. 確認した事実
- :std の腕の現行版の結果は既にある（`results-horizon-gate.json`）: H 294・392・588 で 10/10、c1-better→m1・c2-better→m2、D 真、T＝{r2, r8}、N は検定して偽。
  Lean の試行表の一致も項番77 で確認済み（`Trials-gate.lean`、160 の表）。→ R-BODY-3 の :std の腕の型照合はこれで成立していた（requirements を直す）。
- 出生状態 B（第1歩の直前）は規則によらない（規則は step! の引数で、B を作る newborn・init・Mulberry は同じ）。
- `dn_body_swap.jl` の結果は決定的（秒数を含まない。今の出力の sha256 81f617be…）。

## 1. 要件
- S3-1: `dn_body_swap.jl`・`check_dn_body_swap.jl` を規則で切り替えられるようにする（環境変数 `RULE=old|current`、既定 old）。
  current は contrast＝:bin3、idle_first＝真、core_gate＝真（`variant_horizon.jl` の既定と同じ）。育成の照合（S2-1 の S1 手続き）も同じ規則で行う。
  出力は old が今のファイル名、current は `results-dn-body-swap-current.json`。
- S3-2（回帰）: `RULE=old` の出力が今のファイルとバイト一致（sha256 81f617be…）。
- S3-3: current で S2 の契約の検査（S2-1・S2-2・S2-3b・S2-7、負の対照）がすべて通る。
- S3-4（観測と判定の語）: S2 と同じ（N は guard／tested_false／tested_true に分ける。H∧D∧N は D と検定した N がともに真のときだけ）。
- S3-5（Lean 照合、R-BODY-3）: `variant_horizon.jl` を `CUR=swap OUT=experiments/results-horizon-gate-swap.json` で走らせ（既存のコード、規則は既定＝現行）、
  `horizon_lean.jl` を `IN=` その出力で走らせて、Lean の checkSelfProducing・checkValueNeeded が Julia の判定と全一致すること。生成物は `formal/gen/` に書く場所を
  `horizon_lean.jl` の既定から確かめ、既存の `Trials-*.lean` を上書きしないこと。

- S3-6（S1 の条件の継承、codex 2）: S1-1（B の意味）・S1-1b（共有なし）・S1-2（B の一致）・S1-4（台本の差は保育期だけ）は、どれも第1歩の前の構成と台本だけに
  依るので規則に依らない（規則は step! の引数としてだけ入る）。規則に依る S1-5（再現の対照）は、current での S2-1（BodyOrg の育成物と、別に作った
  S1 手続きの 800 歩後のバイト一致）と S2-7（作り直した再評価の一致）が包含する。育成と照合で同じ規則を使うことも記録して確かめる（codex 1）。
- S3-7（報告の分け方、codex 3〜5）: EP3・EP4 の的中は契約の合否と分けて報告する。EP4 が外れても契約不成立にはしないが、「保育期の順序は消える」の推論は
  支持されないと記録し、閾値・種子を後から変えて救わない。Lean の照合の成立は、照合した試行表・条件の範囲に限る。
- S3-5 の実行は claude-lab が行う（`horizon_lean.jl` は `formal/gen/Trials.lean` を上書きするので、退避して走らせ、出力を `Trials-gate-swap.lean` に写し、元に戻す）。

## 2. 非目標
- 規則・数値・既定の変更。アプリ（v3.7 固定）。L3・L3R の解釈。

## 3. 予測（凍結、`experiments/predictions-dn-current.md`）
- EP1（新）: current で S3-3 が 30/30、負の対照は検出。
- EP2（再現）: :std は 3 つの H で 10/10、c1-better→m1・c2-better→m2、D 真、T＝{r2, r8}、N は検定して偽。
- EP3（新）: :swap も各 H で 9/10 以上、c1-better→m1・c2-better→m2、D 真。T が空でない種子では N は検定して偽。
  理由（推論）: bin3 は使われなかった運動の統計を戻すので、学校期（15 歩ごとに区画が入れ替わる）で両方の運動が結び直され、保育期の順序は消える
  （項番74 の予測なしの報告: 入れ替えても学校期は区画を追い、入れ替わり 24〜26 回。ただし種子3 は m2 の確かな入力が残らなかった）。
- EP4（新）: 各 H で 9/10 以上の種子で、二つの腕の D と N の区分が等しい（現行版では保育期の順序は D・N に効かない）。T・生存の表の差は別に報告する。
- EP5（新）: S3-2 の回帰が一致し、S3-5 の Lean 照合が全一致。
- 反証条件: EP1 が偽ならその種子を除外。EP3・EP4 が外れたら、現行版でも育成史が D・N を変えるということで、H∧D∧N の候補として詳しく調べる（外れとして報告）。

## 4. 試験（GATE、[I] に書く）
- 縮めた確認: `RULE=current SEEDS=1 HORIZONS=392`（環境変数で縮められるようにする）。全体は 1 回あたり約 5 分。
