# S34 休みの第二段（体の受容器 rb と生まれつきの配線、α つき）の再現と反転・窓の固定の測定

- 状態: r2（codex 往復1〜2 と I-R 1〜3 を反映）。2026-11-08、ユーザー決定「BP4 はおすすめどおり」「α は認める」。`notes/R-rest2.md` §3〜§6。
- 目的（限定）: 使用済みの種子 1 の凍結なしの診断（§6、規律の逸脱として記録）で見た RA・RB の振る舞いが、未使用の種子で再現するかと、rb の一歩の直接の効果（反転）・窓での効果（固定）を測る。結論は今回の配線・順位の規則・条件に限る。予測は**診断を見た後**に立てた。
- 範囲: 既定 off の変種だけ。既定は変えない。

## 1. 実装（済）
- `core/circuit.jl`: newborn(rest, rest_body ∈ {:A, :B})、受容器 rb（feat −1、step! の body_flag を読む）、rb→m0 の q0＝1（:B は c1・c2→m0 も q0＝1）、α（宛先 patch 4・q0＞0 の全ての辺を全体の減衰から外す）。`core/dc.jl` で feat −1 を α の対象から外す。`variant_horizon.jl`: Q0（試しの始めの体の場所の B の和）、body_quantity、BODY_CLAMP。
- Lean `formal/LabCircuit.lean`: Rest・RestBody（innate_lost）・RestAlpha（exempt_keeps・nonexempt_old・not_stale_of_q）。

## 2. 対象
- SF 版、**種子 421〜430（未使用）**、腕 :std・:swap、生存の予定表 4、H 392。系統 N0（m0 なし）・RA・RB（各 80 走）。

## 3. 測定
- 毎歩（元の軌道、生きた更新）: 免除の辺（宛先 m0・q0＞0）の q（辺の名と値の列）、m0 の候補と行為、rb の前の歩の点灯（old[rb]）、区画運動の行為。
- **反転**（一歩の直接の効果、codex 往復1-6・2-7・2-8）: 毎歩、更新の前に回路の状態と乱数を写し（本走の状態・乱数は進めない）、old[rb] を真にした写しと偽にした写しで同じ一歩の step! を回す（y・body_flag・他の引数は本走と同じ、prev は変えない）。勝者＝その一歩で行為した運動（m0／区画運動／なし、両方の写しの勝者を保存）。prev は変えない（prev が nothing なら止める）。onset は old[u] ∧ ¬prev[u] を含むので、prev[rb] が偽の歩では old[rb] の介入が onset[rb] も変える。**測るのは onset 経由の効果を含む old[rb] の介入の効果**（codex I-R 2-4〜6）。**反転の歩**＝一方の写しで m0 が行為し、他方で m0 が行為しない歩。向き（真で m0 か、偽で m0 か）も数える。評価する歩は元の軌道の生きた更新だけ（死の後は数えない）。評価した歩の数を併記。
- **窓の固定**（RB だけ。RA は m0 が候補にならない見込みなので元の軌道だけ）: 試し 1〜384 の 32 歩の 12 窓。各窓の始めの状態の写しから、窓の全歩で rb の読みを真に固定した分岐と偽に固定した分岐（共通: 窓の始めの状態・予定表・位相・時刻・乱数の状態。分岐の中で体・たまり・他の受容器・回路は再計算）。m0 の行為の数と A を比べる。窓の始めに死んでいる窓は数えない。
- RB の窓ごとに REST_OFF の解除の分岐の A（休みの定義の (i) の記述。区間・再開は S33 と同じ手続きだが、RB は早く死ぬ見込みなので窓の (i) の数だけを記述）。生存（死の時刻）、A の合計（N0・RA・RB）。

## 4. 関門
- G0 既定の不変（core/check 一致、S32 の記録と S33 の種子 1 の煙試験の作り直しがビット単位で同じ: 済）。G1 Lean rc 0・sorry なし。G2 再現（種子 421 :std・最初の予定表の RB の記録が二回で同じ）。G3 反転の写しが本走を変えない（反転の計算あり・なしで本走の記録が同じ、種子 421 :std・最初の予定表の RB）。G4 BODY_CLAMP＝nothing と「本来の読みを返す固定」が同じ（同じ走り）。G5 育ちの写し（RA・RB）が BodyOrg の育ちと一致。どれかが偽なら判定を出さない。
- 凍結: predictions と、この仕様・`rest2.jl`・`check_rest2.jl`・`variant_horizon.jl`・`core/circuit.jl`・`core/dc.jl`・`formal/LabCircuit.lean` の sha を `freeze-rest2.txt` に、走る前に。

## 5. 試験
- `GATE: sh formal/check.sh && sh core/check/run.sh && cd experiments && julia --project=.. rest2.jl && julia --project=.. check_rest2.jl`
