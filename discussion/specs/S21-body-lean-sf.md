# S21 SF 版での Lean と Julia の判定の照合（gaps G15、R-BODY-3、`notes/G6G15G17.md`）

- 状態: r1・実施済み（README 項番118）（2026-11-08、往復1 の codex 1・2 を反映）。実装の照合。
- 物: SF 版の既定（`variant_horizon.jl`、bin3＋idle_first＋核の関門＋sed_fade＋KC_trial 0.0015）、**種子 171〜180（未使用）**、構造 :constituents・:q、地平 60・294・392・588、腕 CUR＝std・swap（160 走）。
- 照合: 各走りの構造の表を Lean の checkSelfProducing、価値を追う単位がある走りの生存の表を checkValueNeeded に渡し（`horizon_lean.jl`）、Julia の self_producing_L3・value_needed と比べる。
- 報告（codex 2）: 腕・地平・構造ごとの照合の数と、checkValueNeeded の対象外（価値を追う単位なし）の数。対象 0 件は成立の証拠に数えない。一致から言えるのは渡した表での一致まで。
- 予測（凍結、`experiments/predictions-lean-sf.md`）。`GATE: CUR=std と CUR=swap で variant_horizon.jl → horizon_lean.jl`
