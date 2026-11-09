# S33 休む運動 m0 の第一段（`notes/R-rest.md` §3・§5 r3、定義 `notes/R-rest-def.md` §3 r2）

- 状態: r2（codex 往復1〜2 と I-R 1〜5 を反映）。2026-11-08、ユーザー「じゃあ第一段の実装もコーデックスと議論しながらやって」。
- 範囲: 既定 off の変種の実装と測定。既定（m0 なし）は変えない。アプリ・Rust・G 版（grow）には入れない。採用はユーザー判断。「維持のための休み」は立証の対象外。
- 窓の訂正: R-rest-def §3 の「T の窓 16」は記憶違いで、T の DC の窓は DC_L＝32（`core/dc.jl:19`）。窓は 32。

## 1. 実装（済、照合は §4）
- Lean（`formal/LabCircuit.lean` namespace Rest）: `admits_same`・`admits_off`・`rest_no_offer`・`rest_edges_zero`（m0 への辺が全更新で確かめも弱めもされないことを前提に q＝sg＝0、前提は記録で照合）。
- `core/circuit.jl`: `newborn(...; rest = false)`、core_gate と候補に patch 4、`step!(...; rest_off = false)`（m0 の nw も偽にする）、m0 の lastM は m0 が acting のときだけ更新、FORGET の統計の初期化は patch≤2 のまま。`core/dc.jl` に `"m0" => Int[]`。`experiments/variant_horizon.jl`: `BodyOrg(...; rest = false)`（grow の版には通さない）、`REST_OFF`（st → Bool、既定 nothing）。

## 2. 対象
- SF 版（bin3、idle_first、core_gate、sed_fade、KC_trial 0.0015）、**種子 411〜420（未使用）**、腕 :std・:swap、生存の予定表 4、H 392。二系統: **N0**＝m0 なし（今の版）、**R**＝m0 あり（生まれつき、同じ種子・同じ台本）。

## 3. 測定（R、N0 は記述の比較だけ）
- 窓: 試し 1〜384 を 32 歩で敷き詰めた 12 窓 w1..w12（385〜392 は使わない）。I は窓の単位の区間で、歩の単位の開始・終了とは区別する。
- A(w)＝窓の中で区画運動（patch≤2）が行為した歩の数。
- (i): 窓の始めの状態の写し（w1 は試しの初めの状態）から、窓の全 32 歩で REST_OFF の分岐を作り、その A が元の軌道の A より大きい。
- (ii): 元の軌道で、窓の 32 歩すべての更新の後に身体が生きていて、その窓の 32 記録の dc_window で check_dc が真。窓の途中で死んだ窓は (ii) 偽として数え、除外しない。
- I＝(i)(ii) がともに真の窓の極大の連続区間。(iii) 再開: I の終わりの後の完全な窓のうち最初の 3 窓（H_r＝96 歩、窓の終端で測る）のどれかで、A が I の最後の窓の A より大きく、かつ (ii) が真。3 窓のうちに見つかれば「再開を観測」、3 窓がそろっていて見つからなければ「H_r の中で未観測」、3 窓がそろわず見つからなければ「未判定」、I が w12 まで続けば「区間継続中」。どれも「戻らない」とは言わない。
- m0 の行為の歩の分類（前の状態と drove から S32 と同じ式で）: (a) 区画運動の候補なし（m0 だけが候補）、(b) idle の優先で勝った（区画運動の候補があり、m0 は idle で、候補の区画運動に idle のものがない）、(c) 順位で勝った（それ以外）。
- α の照合（宣言 α(m0)＝∅）: 元の軌道で歩 u に m0 が唯一の候補で行為した事象のうち、各走りの最初の 3 件（走りの記録だけで決める）。u−1 の更新の後の写しから、対照 C（u を通常）と B（u で m0 を sil）を 2 歩。記録: C で u に m0 が行為したか、B で u に行為した運動、u の後の二つのたまり・体の A と B と場所・乱数の状態。**P18 の照合**: C で u に m0 が行為し、B で u に何も行為せず（sil が効いた）、u に他の運動の行為が両方で同じ（ともに区画運動なし）、u の後のたまり・体・乱数が同じ。満たす事象だけで、u＋1 の更新の後の受容器の状態を比べる。sil は候補の選択の後に効く（`circuit.jl` の acting の式）。
- 関門の前提の照合: m0 への辺の confirmed（`confirmed_patch`）と弱め（q・sg の減り）が全歩で起きないこと（Lean `rest_edges_zero` の前提）。

## 4. 関門
- G0 既定の不変: `sh core/check/run.sh` 一致、S32 の記録（種子 401・402）の作り直しがビット単位で同じ（済、2026-11-08）。
- G1 Lean `sh formal/check.sh` rc 0、sorry なし。
- G2 再現: 種子 411 :std・最初の予定表の R の記録が二回で同じ。
- G3 REST_OFF の口の既定: REST_OFF を常に偽にした R の走りが REST_OFF＝nothing の走りと同じ。
- G4 育ちの写し（m0 あり）が BodyOrg と一致。G5 α の照合の写し（窓の写しから u−1 まで再生）が元の軌道と一致（u の行為、u の後のたまり・体・乱数）。
- どれかが偽なら判定を出さない。凍結: predictions と、この仕様・`rest.jl`・`check_rest.jl`・`variant_horizon.jl`・`core/circuit.jl`・`core/dc.jl`・`formal/LabCircuit.lean` の sha を `freeze-rest.txt` に、走る前に。

## 5. 試験
- `GATE: sh formal/check.sh && sh core/check/run.sh && cd experiments && julia --project=.. rest.jl && julia --project=.. check_rest.jl`
