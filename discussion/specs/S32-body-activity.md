# S32 BODY の活動は規則で最大に保たれるか（P1〜P3、`notes/R-rest-def.md` §3）

- 状態: r2（codex 往復1〜2 と I-R 4〜6 を反映）。2026-11-08、ユーザー「じゃあ (a) をコーデックスと議論しながらやって」。
- 範囲: 形式と照合。規則・数値・既定は変えない。core は変えない。
- 答えの範囲（codex 往復1-1）: 「前提を満たす歩では活動は最大（A＝窓長）、指定した実走でその前提を検査した」まで。**到達しうる全状態で活動が最大かは未証明のまま**残す。実走の数を全到達状態へ一般化しない。

## 1. 命題（Lean、`formal/LabCircuit.lean` namespace Activity）
- 単位の点灯: 一歩の後の単位 u は total(u)≥θ(u)（core_gate の対象の区画運動は核からの駆動も要る）。辺 k が駆動する（drove）⇔ 源が前の歩で点き sil でない ∧（q≥1 ∨ sg≥1 ∨ stale(宛先) ∨ onset）。重みは 1。
- **A1 核の持続**（条件つきの帰納）: 核 u が前の歩で点き、自己の辺の q≥1、u が sil でない、θ(u)＝1 ⇒ u はこの歩で点く。
- **A2 S ⇒ 候補**: S(m)＝「m の核 c が前の歩で点き sil でない ∧ q(c→m)≥1 ∧ 前の歩で点いていて sil でない受容器 r からの辺 r→m で q≥1 か sg≥1」⇒ m は候補（θ(m)＝2 に届き、核からの駆動がある）。S は十分条件で、S が偽でも候補はありうる（S の不成立の数を候補なしの数と混同しない）。stale・idle・onset による候補 S_x は未証明で、E で記述だけ。
- **A3 P2**（Lean が示すのは pool の最大元の一意な存在まで。行為する集合＝{勝者} は E で照合: 行為した区画運動が、記録から計算した順位の最大と一致するか）: 候補の集合が空でなく sil がなければ、選び方（idle の優先の集合があればその中、なければ候補全体から、辞書式の順位〈key・前の歩の点灯・patch の小さい方〉の最大）で勝者が**一意に存在**し、行為する区画運動の集合＝{勝者}。順位は patch が互いに違うので全順序（同点でも一意）。
- **A4 P3**: 有限の窓 W の全歩で、生存・sil なし・候補が空でない・A3 が成り立つなら、A(W)＝Σ_歩 |行為する区画運動|＝|W|。
- Lean のモデルは選択の一歩の抽象で、Julia の実装との一致は E の照合で確かめる（証明ではない）。

## 2. 照合（E、Julia）
- 対象: SF 版（bin3、idle_first、core_gate、sed_fade、KC_trial 0.0015）、**種子 401〜410（未使用）**、腕 :std・:swap、生存の予定表 4、H 392（80 走）。試しは無介入（sil なし）。
- 育ち: 各種子・腕の台本（保育期と学校、`curriculum`）を写しで走らせ、終わりの状態（回路の全欄・乱数）が BodyOrg の育ちとビット単位で一致することを関門 G0 にする。統計は「写した台本の実走」として報告する（途中の各歩の BodyOrg との対応は検査していない、codex 往復2-5）。
- 各歩の記録（core を変えない）: step! の前の active・q・sg、step! の返す drove・acting・choice。候補は drove から計算: total(m)＝m に入る drove の辺の数、core(m)＝核からの drove の辺がある、候補 ⇔ total≥2 ∧ core（`core/circuit.jl:116–128` と同じ式）。関門 G1: 計算した候補と、step! の choice（候補が二つ以上の歩で記録される cand）が一致。
- 各歩で数える: 核 c1・c2 の点灯、A1 の前提の成立、S(m1)・S(m2)、候補の集合、行為する区画運動の数、候補が空の歩の内訳（m ごとに total・core のどちらが欠けたか）、S が偽で候補だった歩の S_x の内訳（stale＝入る辺が全部 q＝sg＝0、idle＝100 歩より長く行為していない、onset＝点いたばかりの受容器の q＝sg＝h＝0 の辺、どれでもない＝stale・idle・onset の和集合の補集合。三つは重なりうるので四つの和は件数と一致しない）。
- 予測（凍結、`experiments/predictions-activity.md`）は試しだけ。育ちは予測なしの記述（成否に数えない）。

## 3. 関門
- Lean: statement → `sh formal/check.sh` → 証明（sorry なし）。
- G0 育ちの写しの一致、G1 候補の計算の一致、G2 再現（種子 401 :std・最初の予定表を二回）。どれかが偽なら予測の判定を出さない。
- 凍結: predictions と、この仕様・`activity.jl`・`check_activity.jl`・`variant_horizon.jl`・`core/circuit.jl`・`formal/LabCircuit.lean` の sha を `freeze-activity.txt` に、走る前に。

## 4. 試験
- `GATE: sh formal/check.sh && cd experiments && julia --project=.. activity.jl && julia --project=.. check_activity.jl`
