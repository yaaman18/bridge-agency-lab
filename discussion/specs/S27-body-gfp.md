# S27 構造の価値を νΦ の最大不動点で数える版（gaps G9、`notes/gapsC.md`）

- 状態: r1・実施済み（README 項番126）（2026-11-08、gaps C 往復1 の codex 4〜6 を反映）。
- 形式（証明済み、`formal/LabCircuit.lean`）: `GFP.X_card_eq_nu`（有限の C の上で単調な F を全体から Nat.card C 回繰り返すと `Closure.nu F`。下降・k≤nK で X_k＝X_{k+1}・最大性の順）、`Window.phiFin_coe`・`Window.nuFin_eq`（窓の Φ の計算できる版と、その nK 回の反復が `Closure.nu (Phi piRel rhoRel)`）、`Window.valueGfp`、`agentOfGfp`（νΦ を nuFin にした `agentOf`）。
- Julia: `core/dc.jl` の `phi_fin`・`nu_fin`・`value_gfp`・`value_kappa`（判定の側、回路の規則は変えない）。
- 対象: S17 と同じ契約（基準の試し B1＝p1-high・比較 B2＝p2-high、窓＝B1 の更新 33〜64、T_struct＝窓で構造の価値が正の受容器、tab＝生存の予定表 4 つで T_struct を更新 1 から黙らせた生存）。**種子 321〜330（未使用）**、両腕の 20 物。価値を κ（S17 と同じ）と νΦ_gfp の二通りで数え、それぞれ T_struct・tab・証人・Agent の構成を独立に行う。
- **定理と予測を分ける**（codex 6）: 同じ窓では、DC が成り立つなら κ⊆νΦ（LS1）なので受容器ごとに value_gfp ≥ value_kappa（包含に単調）。これは照合で確かめる対象で、予測ではない。T_struct・tab・Agent は価値の数え方で変わりうるので、その結果は予測。
- GP1 の成功条件は「κ⊆nu_fin かつ nu_fin に受容器→運動の辺がある」（非 DC の窓でも包含を測る、分母 20）。GP3 では、Agent ごとに tab が gfp の T_struct を更新 1 から黙らせて得たものであることを生成物の注記と結果ファイルで追えるようにする（`agentOfGfp` の型はこの対応を拘束しない、codex 3・4）。
- 予測（凍結、`experiments/predictions-gfp.md`）。`GATE: cd experiments && VALUE=both julia --project=.. agent_gfp.jl && sh agent_lean.sh AgentBodyGfp`
