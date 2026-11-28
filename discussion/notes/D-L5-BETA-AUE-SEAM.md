# D-L5-BETA-AUE-SEAM（r2・3 者 D-round 合意版）: L5 `(β)` 実身体 `aue_seam` / `OneLife` への `[memory]` 接続

- **改訂履歴**:
  - **r1**（2026-11-28、`neon-lab` 起草）: 既存資産精査（`aue_seam`, `onestep`, `core/matter.jl`）とギャップ B1〜B5・判断点 L5B-1〜L5B-3 を起草。
  - **r2**（2026-11-28、3 者並列 D-round 2 往復合意）:
    - Round 1（`.claude-turns/20261128-142552-medium.json`, `.codex-turns/20261128-142551-medium.jsonl`）→ 実ファイル確認（`mem_core.jl`, `core/matter.jl`, `core/circuit.jl`, `bed.jl`, `adapter_aue_b.jl`, 種子素集合性）→ Round 2（`.claude-turns/20261128-143332-medium.json`, `.codex-turns/20261128-143331-medium.jsonl`、両者 `MINOR_FIX`・`BLOCK 0`）の全指摘を反映。
    - 主な確定変更: (1) 架空支払い・`B_before` 水増しを構造的に封じる **`bed_mem` 独立 2 相スナップショット契約**（codex R2 P1–P2）、(2) 演算予算の厳密整数算式（`OPS_MEM_SETTLE_WORST(C, 576) = 2349 + 38047*C`・`OPS_PRED_WORST = 64`・共通 `B_max = 6_000_000`）と S90 同一容量集合 `{C0_B8, C0_B9, C1, C2, C130}`（`C16` 棄却）、(3) `mem_core.jl` 無変更 `include` と非創造下丸め保存則・`port > 2^40` 時の `run invalid` 扱い、(4) `old`（`b.perm` 適用済み前歩受容器）6-bit `ctx_key`＋S91 単独 53-bit 厳密 `<` 抽選、(5) **二段分割（S91a = 既存 `TracePred`＋`[memory]`、S91b = オンライン学習器）**、(6) ユーザー承認票を **L5B-1〜L5B-5** へ整備。
- **状態**: **3 者合意済み設計草案（未凍結・ユーザー承認票 L5B-1〜L5B-5 待ち）**。
- **前提・厳守境界**:
  - 紙上型仕様: `discussion/specs/L2L-TRM-draft-memory-type.md`（r7、`decisions-log.md` #90）。
  - オフライン先行試験（完了済み）: `discussion/notes/S90-results.md`（全関門・NC1–NC7 PASS、E1 `hit` / E2 `miss` / E3 `miss`［全容量・全層 `init/switch/steady`・全歩で `ΔBrier < 0`］、`mem_core.jl` I-R 指摘 0）。
  - **凍結資産の非破壊（J3 厳守）**: `~/bridge-protocol`、`core/`、`rust/`、`experiments/aue_seam/`、`experiments/onestep/`、S64〜S69（`S64 C0`・`S66`〜`S68`・`S69 r3`）および `experiments/s90_l2l_trm/mem_core.jl` は 1 行も改変しない。L5 `(β)`（S91a）は新規隔離ディレクトリ `experiments/s91_aue_memory/` に構築する。
  - 最良容量 $C$ の採択禁止（#89）、`phenomenal_claim = :not_certified` 固定、R1 / R-MID / `K-UNIQ-CLEAR` / D1 規則の無断変更禁止。

---

## §0 問いの分離
- **新しく記述可能になる問い／観測可能になる現象**:
  - S90（L5 `(α)`、オフライン固定入力・十分残高）では不可視だった **「断片記憶の維持費（$K_{\text{mem}} = 0.002$）が実身体 `OneLife` の残高 `w.B[body_post]` を実際に引き落とし、枯渇時に最古枠から自動退去が起き、かつ断片読み出し（`R-MID` → U4 $\pi_a$）が行為選択を変えて次歩の環境入力・資源獲得・存続へ還流する閉ループ物理現象」** を、4 シーム共通床＋外部ハッシュ鎖監査の上で記述・観測可能にする。
- **S91a（本設計の第 1 段）が問うこと**:
  1. `bed.jl` の種非依存不変条件（ZERO species-specific logic）を破らずに、独立 2 相スナップショットにより架空支払い・`B_before` 水増し・非選択歩の無料保持を構造的に拒否する `[memory]` シーム（`bed_mem.jl`）が閉じるか（既存 `adapter_aue_b.jl` は無変更回帰通過）。
  2. `core/` および `experiments/s90_l2l_trm/mem_core.jl` を無変更 `include` したまま、`OneLife`＋既存 `TracePred`（`P_DECAY = 8`, `K_win = 0.002`）＋`[memory]` の閉ループで全関門（`GB-M1`〜`GB-M6`）および全負の対照（`NC-M1`〜`NC-M5`）を通過できるか。
  3. 3 環境（定常・季節反転・枯渇ストレス、独立種子区画 `910101..`）上で、`C0_B8 / C0_B9 / C1 / C2 / C130` を同一種子ペア比較したとき、実維持費による淘汰・閉ループ行為変化・資源獲得・寿命の挙動がどう現れるか（全容量報告、最良容量は採択しない）。
- **S91a が問わないこと**:
  - オンライン学習器（`TabL` / `TrmL` / `C2` 頭）の閉ループ統合（**S91b** へ分離）、S64 C0 凍結 TRM 重みの確定（J3 凍結維持）、Rust 実機配備、`phenomenal_claim`。

---

## 1. 実ファイル照合で確認した事実（Round 1–2 で確定）
1. **`mem_core.jl` 無変更 `include` 互換（`experiments/s90_l2l_trm/mem_core.jl:337-418`）**:
   - `settle_upkeep!(cfg, M, B_vec, body_post, port_ref; cand, use_naive_add)` は `Vector{Float64}`・`Vector{Int}`・`Ref{Float64}` を受け取り、スロット 1 個ごとに `port_arg` で `target_port <= 2^40` を事前検査（超過時は `B_vec` も `M` も変更せず即 `InvalidResourceError` で停止＝クランプ禁止）し、`B_vec[body_post]` と `port_ref[]` をスロット単位で原子的に更新する。
   - 算術規則（r7 §3.3 の有向丸め `sub_up` / `sub_down` / `add_down` / `port_arg`）により、厳密な片側保存（**非創造則**）が成立する：
     $$0 \le \mathrm{port\_delta} \le \mathrm{paid\_lo} \le \mathrm{exact\_E}(B_{\text{before}}, B_{\text{after}})$$
     （物質創造は厳密 0。下丸めにより $\mathrm{exact\_E} - \mathrm{port\_delta} \ge 0$ に微小な有界丸め落ちが生じうる）。
2. **`w.port` への反映と `outflow` の意味（`core/matter.jl:9-20`）**:
   - `port_take!(p, x)` は `p.reservoir -= t; p.inflow += t`（ポート→世界・身体）、`port_give!(p, x)` は `p.reservoir += x; p.outflow += x`（世界・身体→ポート）。
   - したがって `p_ref = Ref(w.port.reservoir)` で `settle_upkeep!` を実行後、**`w.port.reservoir = p_ref[]` かつ `w.port.outflow += st.port_delta`** とすれば（`port_give!` の重複呼び出しをしない）、`mem_core.jl` 無変更のまま逐次加算の 1 ulp ずれも二重加算も符号誤りも起きない。
3. **`old` 受容器フレームと `b.perm`（`core/circuit.jl:22-26, 119-156`）**:
   - `step!` L138 は `nw[u] = feature(b.perm, b.feat[u])(ys, now, noise)`。したがって draw hook 実行時点の `old = st.active` の 6 パッチ受容器 `R1IDX = (1, 2, 3, 4, 7, 8)`（`y1>=3, y2>=3, y1==0, y2==0, y1>y2, y2>y1`）は **すでに `b.perm` 適用済みの個体受容器フレーム（body-frame）の前歩 $t-1$ 状態** であり、当歩の `y = [y1, y2]` および $Y_t$ からの未来漏れは厳密ゼロである。
4. **演算上限の厳密整数式（`mem_core.jl:54-59`）**:
   - `OPS_CTX_KEY = 16`, `OPS_MEM_READ_WORST(C) = 8C + 8`, `OPS_MEM_WRITE_WORST(C) = 8C + 16`。
   - `N_max = 576`（`torus_lenia_matter_24x24` の物理絶対上界）のとき：
     $$\mathrm{OPS\_MEM\_SETTLE\_WORST}(C, 576) = 4\cdot 576 + 45 + C(66\cdot 576 + 31) = 2349 + 38047\,C$$
     - `C=1`: `40,396`、`C=2`: `78,443`、`C=130`: `4,948,459`。
   - `C=130` の必須＋任意書込予約合計：`OPS_MEM_MANDATORY(130, 576) + OPS_MEM_WRITE_WORST(130) = (16 + 1048 + 4,948,459) + 1056 = 4,950,579`。
   - ベース予測器 `TracePred`（`predict` + `update` + `pi_u4` + 53-bit draw）の 1 歩最悪演算上限を **`OPS_PRED_WORST = 64`** と厳密定義（単体関門で毎歩実測 `<= 64` 検証）。合計最悪必要枠は **`4,950,643`**。
5. **既存種互換（`experiments/aue_seam/adapter_aue_b.jl`）と種子素集合性**:
   - `adapter_aue_b.jl` は `[memory]` 未指定・`StepCost(ops, upkeep, act, dorm)` のみ返却。デフォルト `C_spec = 0` で無変更通過可能。
   - 新規種子区画 `910101..` は既存全実験・`discussion/` 全文書および未使用主列（`1600–1617`, `2860–2899`）と重複 0 件（完全素集合）。

---

## 2. 確定設計（6 論点 B1〜B6 の合意事項）

### B1. `bed_mem.jl` の種非依存性と「独立 2 相スナップショット」監査（〔判断点 L5B-1〕）
- **責務分離**: `bed_mem.jl`（隔離ディレクトリ `experiments/s91_aue_memory/` に配置）は種固有ロジックゼロを厳守する。`ctx_key`・`R-MID`・`K-UNIQ-CLEAR`・`TracePred` は 100% アダプタ側に置く。
- **後方互換**: `[memory]` セクション未指定の種（既存 `adapter_aue_b.jl` 等）は `reserved_bytes = 8, header_bytes = 8, slot_bytes = 16, C_spec = 0` とみなし、従来通りの単相 `step_species`・4 引数 `StepCost` で 1 行も変えず回帰通過する。
- **架空支払い・`B_before` 水増しを構造的に封じる 2 相決済プロトコル（`C_spec > 0` 種で必須）**:
  1. アダプタが **Phase 1（通常身体更新＋書込候補準備、`settle_upkeep!` 実行前）** を終え、決済前の中間状態 `mid_state` を `bed_mem` へ返す。
  2. **`bed_mem` が `mid_state` から独立に `B_pre = body_balances(adapter, mid_state)` と `port_pre = port_balance(adapter, mid_state)` と `mem_pre = memory_bytes(adapter, mid_state)` を直接スナップショット**する（アダプタの自己申告を信用しない）。
  3. アダプタが **Phase 2（`settle_upkeep!` のみ実行）** を行い、`next_state` と決済 `StepCost` を返す。
  4. **`bed_mem` が `next_state` から独立に `B_post = body_balances(adapter, next_state)`、`port_post = port_balance(adapter, next_state)`、`mem_post = memory_bytes(adapter, next_state)` を直接スナップショット**し、以下を全歩（選択歩・非選択歩を問わず）検証する：
     - **バイト形式**: `length(mem_post) == spec.memory_reserved_bytes`、ヘッダ `pad_h == 0`、空枠・余剰バイト全 `0x00`、ヘッダ読取 `kept = get_le(UInt32, mem_post, 0) <= C_spec`、かつ `kept == cost.memory_slots_kept`。
     - **生存歩（`alive == true`）**:
       - `cost.memory_upkeep_paid >= kept * K_mem`（**許容誤差ゼロ**；既存 `K_mem = 0.002`、S90/KC と同一）。
       - 独立スナップショット上の厳密差 `port_delta = exact(port_post - port_pre)` および `exact_E = exact_sum(B_pre .- B_post)`（`BigFloat` 2400-bit）が **非創造保存則** `0 <= port_delta <= cost.memory_upkeep_paid <= exact_E` を満たし、`exact_E - port_delta` が r7 §3.3 の有界下丸め幅以内であり、かつ全系物質 `total_post <= total_pre`（創造ゼロ）であること。
       - 非選択歩であっても `kept > 0` なら同様に `cost.memory_upkeep_paid >= kept * K_mem` と実引落 `exact_E >= kept * K_mem` が必須（無料保持禁止）。
     - **死亡歩（`alive == false`）**: `cost.memory_upkeep_paid == 0.0`、`port_delta == 0.0`、`cost.memory_settle_ops == 0`、かつ **`B_post === B_pre`・`port_post === port_pre`・`mem_post == mem_pre`**（死亡歩での記憶・残高の完全凍結）。
- **監査鎖**: `state_digest` に `mem_post`（固定長 $B$ バイト）を含め、`commit` 行へ `mem_kept`・`mem_paid`・`mem_ops` を記録し、`replay_from_audit` が入力テキスト行のみから全行ハッシュ一致と全 2 相保存則を再検証する。

### B2. 演算予算と検査容量集合（〔判断点 L5B-2〕）
- **検査容量集合**: S90 と完全同一の 5 点 **`{C0_B8 (B=8, C=0), C0_B9 (B=9, C=0), C1 (B=24, C=1), C2 (B=40, C=2), C130 (B=2088, C=130)}`**（`C16` は S90 事後中央値由来のため採用しない、#89 厳守）。
- **共通プリミティブ演算予算**:
  - `N_max = 576` 固定、`OPS_PRED_WORST = 64` 固定、`K_mem = 0.002`（既存値）。
  - 全 5 容量共通の `B_max` として **`ops_per_step = 6_000_000`**、`ops_per_hour = 360 * 6_000_000 = 2_160_000_000`（`step_granularity_sec = 10.0`）を新種仕様 `species_aue_a_mem.toml` に定義する（`4,950,643 <= 6,000,000` を余裕をもって充足）。
  - ロード時関門 `B_max - OPS_MEM_MANDATORY(C, 576) >= OPS_PRED_WORST` および毎歩 `ops_used <= B_max`・ローリング 3600s 窓 `<= ops_per_hour` をすべて検証する。

### B3. 1 歩接続順序・`Y_t`・オーバーフロー扱い
1. 歩頭死亡検査（`dead` / `_empty_body` → 吸収死、読書・書込・決済・コミット 0）。
2. `step_aue!` 内 draw hook（2 パッチ候補の選択歩のみ）：`C_spec == 0` は `ctx_key` 非計算・メモリ演算 0；`C_spec > 0` は `old` から `ctx_key` 算出 → `read_memory_pair`（`R-MID`）→ `pi_u4` → 53-bit 抽選。非選択歩は読出し・書込み候補生成をスキップ。
3. 既存 `OneLife` 更新（`KC` 引落 → 採餌 → `MCOST` 引落 → 外部供給 → `LabCore.step!(w, ())`）→ `mid_state` 完成（`bed_mem` が `B_pre`, `port_pre`, `mem_pre` をスナップショット）。
4. `body_post = [i for i in eachindex(w.C) if w.C[i] != 0]` 確定。空なら代謝死（`alive = false`、決済・書込スキップ、状態凍結）。
5. 生存かつ `C_spec > 0`:
   - 選択歩かつ残演算枠 `>= OPS_MEM_WRITE_WORST(C)` なら `cand = copy(M)` に **`Y_t := (y[a_t] > 0)`**（選択行為座標系；`take` は別途記述記録、循環ラベル回避）で `write_memory_candidate!`（R1＋`K-UNIQ-CLEAR`＋D1）を適用。非選択歩または残枠不足なら `cand = copy(M)` 無変更。
   - `p_ref = Ref(w.port.reservoir)` で `S90MemCore.settle_upkeep!(cfg, M, w.B, body_post, p_ref; cand = cand)` を実行後、`w.port.reservoir = p_ref[]`・`w.port.outflow += st.port_delta`。
   - **ポート上限 `2^40` 超過時の扱い**: クランプ禁止・`InvalidResourceError` で即停止し、個体死とは区別して **「ラン無効（`run invalid`）・分析から除外・発生件数を 5 容量すべてで報告」** と事前凍結する（容量間の選択的ドロップアウトによるバイアスを防止）。

### B4. `ctx_key`（L1）と 53-bit 抽選式（〔判断点 L5B-3〕）
- **`ctx_key(t)`**: `t == 0`（初回歩）は `UInt64(64)`、それ以外は前歩受容器 `old = st.active`（`b.perm` 適用済み body-frame、`nw` は絶対渡さない）の `R1IDX = (1, 2, 3, 4, 7, 8)` 6-bit（`bit i-1 = old[R1IDX[i]]`）。ビット順・行為座標系・`b.perm` 扱い・初期値 `64` を `mapping_spec_hash` に固定刻印する。
- **抽選式（S91 単独契約）**: `u = Float64(inp.rand_u64 >> 11) * 2.0^-53`、厳密不等号 **`u < Float64(pi1)`** で行動 `1`（それ以外は行動 `2`）。`Float32 → Float64` 変換は厳密。S69 r3 の未決点へは逆流させない。閾値等号 `u == Float64(pi1)` の境界単体テストおよび `C0` 基準との RNG 消費一致を関門化する。

### B6. 二段分割（P-c）とベース予測器（〔判断点 L5B-4〕）
- **二段分割**:
  - **S91a（本段）**: ベース予測器は既存の **`TracePred`（`P_DECAY = 8`、既存の `K_win = 0.002` 読取保持条件をそのまま全 5 容量で完全同一に維持）** とし、規則変更ゼロ・S64 C0 非依存で `[memory]` の実身体統合と経済淘汰を純粋検証する。
  - **S91b（次段）**: オンライン学習器（`TabL` または小規模オンライン `TrmL`）＋`[memory]` の閉ループ適応試験。
- **R1 発火検証の必須化（codex R1 反例対策）**: `p != 0.5` のみでは R1 発火を保証できないため、(a) `TracePred` で到達可能な厳密誤予測 → 同一鍵再訪 → 一致抽選下での行動分岐を確認する確定フィクスチャ関門 **`GB-M6`** を必須化し、(b) 自然走行 3 環境での実ヒット数・R1 書込数・維持費退去数を個別報告する。

### B5. 評価環境・独立種子区画・事前凍結（〔判断点 L5B-5〕）
- **独立種子区画**: **`910101..`**（例：各環境 12 種子 × 3 環境 = 36 種子、または 16 種子 × 3 環境など、S91a 仕様凍結時に厳密リストを固定。未使用主列 `1600–1617`, `2860–2899` は完全非接触）。同一種子で 5 容量すべてをペア比較する。
- **3 環境（事前凍結・結果後の追加禁止）**:
  1. **定常（stationary）**: 既存 `OneLife` の標準季節周期（例：`P = 1000` 正弦波駆動）。
  2. **季節反転（seasonal reversal）**: 途中時刻（例：`t = 2000`）で `cross!(b.perm)` または区画収量位相反転を起こす環境。
  3. **枯渇ストレス（depletion stress）**: 供給振幅を抑え、保持中スロットの維持費 `K_mem = 0.002` が `w.B[body_post]` を圧迫して維持費退去（`upkeep_evicted > 0`）が自然発火する環境。
- **凍結手続き**: 実装・本走り前に `discussion/specs/S91a-draft-aue-memory.md` と `experiments/s91_aue_memory/predictions.toml`（E1.. + 反証条件 + `run invalid` 規約）を `experiments/freeze-s91a.txt` へ `shasum -a 256` 凍結し、3 者独立 I-R クローズ後にのみ本走りを行う。

---

## 3. S91a 必須関門（`GB-M1`〜`GB-M6`）および負の対照（`NC-M1`〜`NC-M5`）

### 必須関門
1. **既存 4 シーム全関門回帰**: ポート違反拒否、種境界違反拒否、瞬間・3600s 窓予算超過拒否、休眠無料記憶拒否、吸収死後 0 コミット、死後胞子拒否、共有媒質二重消費拒否、`adapter_aue_b.jl`（`[memory]` 未指定）無変更通過、`replay_from_audit` 全行ハッシュ一致。
2. **`GB-M1`（`C0_B8` / `C0_B9` 基準同値・抽選境界）**: `C0_B8`・`C0_B9`（9B 全 `0x00`）が記憶なし `OneLife + TracePred + U4` 基準と行為列・RNG 消費・残高・寿命・`state_digest`（記憶バイト除く）で全歩ビット一致、メモリ演算 0。`u == Float64(pi1)` 境界単体検証、`OPS_PRED_WORST <= 64` 単体検証。
3. **`GB-M2`（実残高による維持費淘汰・非創造保存則・ポート上限境界）**: 枯渇フィクスチャで最古枠からの自動退去が発火し、独立 2 相スナップショット上で `0 <= port_delta <= paid_lo <= exact_E`・`paid_lo >= kept * K_mem`・`total_post <= total_pre` が全歩成立。ポート上限 `2^40` ちょうど・1 単位下での保存則検証と超過時の `InvalidResourceError`（状態不変）検証。
4. **`GB-M3`（死亡吸収・記憶凍結）**: 代謝死歩（`!alive`）で `paid_lo == 0`, `port_delta == 0`, `ops_mem_settle == 0`, `B_post === B_pre`, `port_post === port_pre`, `mem_post == mem_pre`、死後ステップ 0 回。
5. **`GB-M4`（未来漏れゼロ・`ctx_key` 同型・`Y_t` 境界）**: `old` 固定で当歩 `y` を変化させても `ctx_key`・`p_pre`・`pi`・`a_t` がビット不変。通常順列と `cross!` 反転順列の双方で `ctx_key` が S90 定義と完全一致。`y[a_t] > 0 ∧ take == 0` 境界ケースの動作検証。
6. **`GB-M5`（非選択歩の無料保持禁止・監査鎖完全再生）**: 非選択歩でも保持スロットへの前払い決済が 1 歩 1 回必ず実行されること。`replay_from_audit` が入力行のみから全 `commit` ハッシュと全 2 相保存則を完全再生すること。
7. **`GB-M6`（`TracePred` 到達可能 R1 発火・一致抽選行動分岐）**: 確定フィクスチャで `TracePred` が厳密誤予測 → R1 書込 → 同一鍵再訪で `R-MID` ヒット → 一致 `rand_u64` 下で `C > 0` と `C0_B8` の選択行為が設計どおり分岐すること。

### 負の対照（全 5 件が想定関門で失敗必須）
- **`NC-M1`**: `C0_B9` の余剰 1 バイト非ゼロ化または `C0` 時の `ctx_key` 呼出／`adapter_aue_b` 回帰破壊 → `GB-M1` / 既存回帰で失敗。
- **`NC-M2`（架空支払い 2 種）**: (a) 実残高 `B` 不変のまま `B_before` を水増しして `paid_lo > 0` 申告、(b) `port_reservoir` 不変のまま `port_delta > 0` 申告 → いずれも `bed_mem` 独立 2 相スナップショット検証で拒否。
- **`NC-M3`（未来漏れ）**: `old` ではなく当歩 `nw` を `ctx_key` へ渡す変異 → `GB-M4` で検出。
- **`NC-M4`（非選択歩の無料保持）**: 非選択歩で `settle_upkeep!` をスキップ（`kept > 0, paid == 0`） → `bed_mem`（`GB-M5`）で拒否。
- **`NC-M5`（誤配線／シャッフル）**: `M` 読出しシャッフルまたは `route_det`（抽選を記録しつつ DET 行為を渡す）変異 → `GB-M6` で検出。

---

## 4. ユーザー承認票（S91a 仕様起草・凍結前の判断待ち 5 点）

| ID | 判断項目 | 3 者合意の推奨案 | 補足・反証条件 |
|---|---|---|---|
| **L5B-1** | `bed_mem.jl` とアダプタの監査責務分離 | 種非依存の **独立 2 相スナップショット**（`B_pre/B_post`, `port_pre/port_post`, `mem_pre/mem_post`）＋非創造保存則＋許容誤差ゼロ `paid_lo >= kept * K_mem`＋死亡歩完全凍結＋`adapter_aue_b` 無変更回帰 | `NC-M2`（2 種）または `NC-M4` を 1 件でも通したら棄却 |
| **L5B-2** | 共通プリミティブ演算予算と検査容量集合 | 検査容量集合は S90 同一の **`{C0_B8, C0_B9, C1, C2, C130}`**（`C16` 不採用）、`N_max = 576`、`OPS_PRED_WORST = 64`、全容量共通 **`ops_per_step = 6_000_000`**・`ops_per_hour = 2_160_000_000`（`K_mem = 0.002` 既存値維持） | いずれかの歩で実測演算が予約超過すれば予算案は無効 |
| **L5B-3** | `ctx_key`・`Y_t`・53-bit 抽選式・オーバーフロー扱い | `ctx_key` は `old`（`b.perm` 適用済み前歩 6 受容器、初回 `64`）、`Y_t = (y[a_t] > 0)`、S91 単独の **53-bit 厳密 `<` 抽選**（S69 r3 へ逆流させない）、`port > 2^40` はクランプ禁止で `run invalid`（除外＋件数報告） | `GB-M4` 違反または `u == Float64(pi1)` 境界不一致で修正 |
| **L5B-4** | 二段分割（S91a / S91b）とベース予測器 | **S91a = 既存 `TracePred`（`P_DECAY = 8`, `K_win = 0.002` 維持）＋`[memory]`** で実身体シーム・経済淘汰を検証し、オンライン学習器は **S91b** へ分離（J3 維持） | 自然走行で R1 ヒットが極端に少ない場合、S91b（表/TRM 学習器）での評価を主とする |
| **L5B-5** | 3 環境パラメータと独立種子区画 | 新規独立種子区画 **`910101..`**（未使用主列 `1600–1617`, `2860–2899` 非接触）、3 環境＝定常・季節反転・枯渇ストレス（具体パラメータは S91a 仕様草案で提示・事前凍結） | 3 環境とも 5 容量同一種子ペア比較・結果後の環境追加禁止 |
