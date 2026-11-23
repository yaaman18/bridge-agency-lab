# D-BOOL-MAPPING: Lab の Bool 定義と意味論マッピングの脆弱性分析・対策メモ（2026-11-23）

- **出典**: `~/bridge-protocol/aue-bool-mapping-vulnerability.md`（2026-11-23、Muse との検討下書き）の一次コード照合・責務切り分け・対策設計。
- **一次コード照合対象（読み取り専用）**:
  - `core/dc.jl:21-96`（`ALPHA_FEATURES`, `DCStep`, `dc_record`, `lab_gate`, `dc_window`）
  - `core/circuit.jl:13-26, 151-172`（`FEATURES`, `CROSS`, `cross!`, 単一勝者選択 `win`）
  - `formal/LabCircuit.lean:48-159`（`Net`, `Window`, `kappa/rhoRel/piRel/sigmaRel/alphaRel/epsilon`, `ElemDC`, `checkDC`）
  - `~/bridge-protocol/formal/ERIEC/DC.lean:6-62`（`DC` 構造体：関係と集合を外から受ける抽象仕様）
- **責務分離（`discussion/README.md` §1.5）**:
  - 脆弱性メモの中身の大半（§4.1〜§4.5）は **Lab 側の具体マッピング層** の課題であり、本メモおよび `audit/dc_mapping_audit.jl`（読み取り専用監査）で Lab 側に対策を置く。
  - BP 正本側へ引き継ぐべき一般原則のみを `discussion/bp-proposals.md` に **BP11（仮定 H8）** として起票する（`~/bridge-protocol` は Lab 作業から変更しない）。`phenomenal_claim = :not_certified`。

---

## 1. 一次コード照合で確認した事実（メモの精密化）

1. **§4.1（`perm cross` の不可視性）は 31 歩の「窓跨ぎ混在」を実際に引き起こす**
   - `core/dc.jl:78-96` の `dc_window` は直近 `DC_L = 32` 歩の `r.repro`・`r.via` を OR 集約する一方、`aff` は窓末尾 `recs[end]` の時点の `b.perm` で計算する（`dc.jl:91: f = b.perm[b.feat[u]]`）。
   - よって `cross!(perm)` を跨ぐ 31 歩の窓では、**反転前の受容器意味で記録された `via`（および `repro`）と、反転後の `b.perm` で計算された `aff` が同一 `DCWindow` 内に混在する**。
2. **§4.2（`π` の過大帰属）は現行 `L2` 単一勝者では実質起きていない**
   - `core/circuit.jl:156-169` は `length(cand) > 1` のとき単一勝者 `win` のみを残し他の運動を消すため、現行 `L2` では全歩で `length(onpatch) <= 1` が成り立つ（S63 G2 でも 710,358 更新歩すべて `<= 1` を全数確認済み）。
   - したがって `core/dc.jl:47` の `for m in onpatch; push!(repro, (m, k)); end` は現行回路では `m1`・`m2` 間の誤帰属を起こさない。
   - 実際に粗いのは、(a) `core/dc.jl:44-48` の `via` がその歩に発火した全駆動受容器（非結合な雑音 `r5`・時計 `r6` を含む）へ全確かめ辺を一括帰属させる点、(b) 将来 `length(onpatch) >= 2` の多運動系へ拡張した瞬間に `repro` が誤帰属する点である。
3. **§4.3（`α` の宣言依存）は介入監査で外側から回帰検査できる**
   - `ALPHA_FEATURES`（`dc.jl:24`）＋`lab_gate`（`dc.jl:64-67`）の正当性は、`core/body_org.jl` の世界相／非世界相および `y[p] > 0` / `y[p] == 0` 条件での実体介入（S62b P-04 と同系統）と照合することで回帰関門化できる。
4. **§4.4（`S = Unit`・`SHARED-TICK`）と S52 3:1 多周期**
   - S52 電波（30 秒周期）× OneLife（10 秒歩）は 3 歩一定保持の限り 10 秒刻みの単一クロックに収まるが、複数周期の非同期結合へ進む場合は `SHARED-TICK` 仮定の再検討が要る。
5. **§4.5（意味論ドリフト）と §5 クリティカル 3 条件**
   - 現行の第一号 AUE（固定法則・固定 `FEATURES`）ではクリティカル条件 #3「系自身の定義変更権」は発火しない。
   - ただし定義ハッシュと `perm` 状態を窓監査・`gen` 出力へ刻んでいない現状では、定義変更や反転跨ぎの前後比較が追跡しにくい。

---

## 2. 優先度別対策と反証条件

1. **【高・即時実装】マッピング定義ハッシュ＋`perm` 窓跨ぎ監査（`audit/dc_mapping_audit.jl`、読み取り専用・`core/` 無変更）**
   - `core/circuit.jl`・`core/dc.jl`・`formal/LabCircuit.lean` の SHA-256 および `FEATURES`/`ALPHA_FEATURES`/`lab_gate`/`dc_record`/`dc_window` の正規化定義ハッシュ（`mapping_spec_hash`）を算出・刻印する。
   - 実体 `body_org.jl` の反転あり走り（`REVR` あり）で各歩の `perm` を記録し、`cross_boundary = true` の 31 窓について「現行 `dc_window`」対「反転境界で切断した `dc_window_split`」を比較する。
   - *反証条件*: 31 窓すべてで `check_dc`・`value_gfp` が 1 件も変わらないなら、窓跨ぎ分離は記録注記のみで足り、`core/dc.jl` 改変は不要。
2. **【高・統治整理】BP11（仮定 H8）起票**
   - BP 正本への一般原則（「具体 `DC` 実装は外部 `mapping_spec_hash` を帯同し、自己改変系では死・維持費会計・境界定義を書換不能の床として分離する」）を `discussion/bp-proposals.md` へ起票する。
   - `~/bridge-protocol/aue-bool-mapping-vulnerability.md` 自体は BP ライン側の未追跡下書きのため Lab からは削除・移動しない。
3. **【中・回帰関門化】`α` 宣言の介入照合監査（`audit/dc_mapping_audit.jl` 内）**
   - `world` 相（`y[p]>0` / `y[p]==0`）と `nursery`/`school` 相で `m1`/`m2` の行為介入を行い、実際に変化する受容器集合が `ALPHA_FEATURES`＋`lab_gate`（`dc.jl:24, 64-67`）と 100% 一致することを検証する（負対照：`ALPHA_FEATURES` 1 項目改変で不一致検出）。
4. **【中・単一勝者保証＆`via` 感度監査】（`audit/dc_mapping_audit.jl` 内）**
   - 全歩で `length(onpatch) <= 1` を明示アサートする（将来の多運動拡張時に `dc_record:47` 改訂を強制する安全網）。
   - `via` から非結合受容器（`r5`, `r6`）を除外した版と現行版の `value_gfp`（結合受容器のみ・全受容器）を比較する。
   - *反証条件*: 結合受容器の `value_gfp` 値・順位が 1 件も変わらないなら、`core/dc.jl` の `via` 改変は急がない。
5. **【保留・進化導入前ゲート】自己改変の「床」凍結＋系譜スパン刻印**
   - 系自身が受容器・定義を変更する設計に入る前に、死・維持費会計・境界定義を書換不能の床として分離し、定義変更事象を S61 Stage 1 系譜スパン（`formal/NestingLineage.lean`）と外部監査鎖へ刻む。第一号 AUE（固定法則）では未発火。

---

## 3. 読み取り専用監査の実測結果（`audit/dc_mapping_audit.jl` → `audit/results-dc-mapping-audit.json`、2026-11-23）

`core/`・`formal/`・`~/bridge-protocol` は一切変更せず、読み取り専用で実行した確認済み事実：

1. **正規化マッピング定義ハッシュ（対策 #1）**:
   - `mapping_spec_hash`: `f69709ffc7722385b183fbadf6ab52466af64b002210e6d245068cb08d9fd61c`
   - `core/circuit.jl`: `295a6e17b4d99f90...` / `core/dc.jl`: `05eb8b60c1640f87...` / `formal/LabCircuit.lean`: `fd40717258d52eba...`
2. **`perm cross!` 31 歩窓跨ぎ監査（対策 #1 反証テスト）**:
   - 反転歩 `REVR = 2000` を跨ぐ **31 窓**で現行 `dc_window` と境界切断版を比較した結果：
     - **`elem_self` が `21 / 31` 窓で変化**（`dc` 総合判定差 `0`、`smc/act/bound` 差 `0`）。
     - **結合受容器の `value_gfp` が `84` 件変化**（全受容器 `156` 件、最大絶対差 `8`）。
   - **結論**: 反証条件（「1 件も変わらないなら注記のみで足りる」）は不成立。`cross!` 跨ぎ窓は実際に `elem_self` と `value_gfp` を変えるため、窓メタデータへの `cross_boundary` 刻印（および必要に応じた境界切断）が有効。
3. **`α` 宣言の介入照合監査（対策 #3 — 実バグ発見！）**:
   - `world` / 非 `world` × `ypos ∈ {T,F}^2` × `m1/m2` の 16 ケースを実体介入で全数照合し、`14/16` 一致・負対照（特徴 1 削除）検出成功、**2 ケースで真の不一致を検出**：
     - `(m1, in_world=true, y1>0, y2==0)`: 宣言 `[1, 3, 7, 8]` 対 実測 `[1, 3, 7]`（`y2 == 0` では特徴 8 `y2 > y1` は行為前後とも恒偽で到達不能）。
     - `(m2, in_world=true, y1==0, y2>0)`: 宣言 `[2, 4, 7, 8]` 対 実測 `[2, 4, 8]`（`y1 == 0` では特徴 7 `y1 > y2` は行為前後とも恒偽で到達不能）。
   - **影響範囲の確認**: 当該条件では `r8`（`y2==0` 時）または `r7`（`y1==0` 時）は必ず `on = false` となるため `epsilon` には入らず既存の `check_dc` 真偽は崩れないが、`w.affects` の真偽表としては過剰宣言である（将来 `core/dc.jl` 改訂時の明確な修正候補）。
4. **`length(onpatch) <= 1` 保証＆`via` 感度監査（対策 #4）**:
   - 全 3,000 歩で `max_onpatch_per_step = 1`（`PASS`）。
   - 非結合受容器 `r5`/`r6` は `2,200 / 2,200` 世界窓で `via` に非ゼロ値を持つが、これらを `via` から除外しても **結合受容器の `value_gfp` 差は `0` 件・順位差も `0` 件**（反証条件成立：`core/dc.jl` の `via` 改変は急がず、`value_gfp` の読み取り対象を結合受容器に限定すれば足りる）。
