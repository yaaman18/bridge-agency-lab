# S91a 仕様（r3）: L5 `(β)` 実身体 `OneLife`＋4 シーム共通床への `[memory]` 最小閉ループ統合（`TracePred` ベース）

- **改訂履歴**:
  - **r1**（2026-11-28、`neon-lab` 起草）: L5B-1〜L5B-5 承認（`decisions-log.md` #91）に基づき初版起草。
  - **r2**（2026-11-28、並列 S-R Round 1 `claude-lab` P1–P9・`codex-lab` P1–P10 反映）: bed 所有コピー 2 相スナップショット、偽死亡/早書き/許可外書込封じ、`TracePred` 死亡歩更新整合、`ctx_key(0)=64`、分離丸め落ち上界、`Mulberry` 混合 2 語 `rand_u64`、`port=2^40` 4 点境界、`E1`〜`E3` 厳密化。
  - **r3**（2026-11-28、並列 S-R Round 2 `claude-lab` P1–P3・`codex-lab` P1–P2 全反映、`predictions.toml` r2 は無変更で両者 ACCEPT）:
    1. **ポート側丸め落ち上界の正確な明記（claude P1・codex P1）**: 無変更 `mem_core.jl` はスロット単位逐次加算（`kept` 回の `port_arg`）であるため、ポート側丸め落ち上界は `kept * eps(max(port_post, K_mem))` であり、`port = 2^40` では `kept = 1` で `≈ 2.44e-4`、`kept = 130` で `≈ 3.17e-2` へ緩む事実を明記。`GB-M2` のリーク注入拒否テストを 3 条件（`kept=1, port=2^40, 1e-3`／`kept=130, port=2^40, 0.05`／`kept=130, port=300.0, 1e-10`）へ拡充。
    2. **スカラー `memory_upkeep_paid` の厳密一致強制（codex P2）**: `bed_mem` が検証済み `slot_paid_lo` から `verified_mem_paid = Float64(sum_paid_lo)` を直接導出し、`settle_cost.memory_upkeep_paid === verified_mem_paid` を毎歩強制（`kept == 0` で非ゼロ申告する負対照 `NC-M2c` を追加）。`commit` 行・`ledger`・E1 集計はすべて `verified_mem_paid` のみを使用。
    3. **`pending_write` の置き場統一（claude P2）**: 当歩の選択トランザクション値 `(drawn, k, a, Y_t, p_pre, p_base, remaining_ops)` は `mid_state` 内の明示的 1 フィールド `pending_write` に格納し、`digest_excl_settle` に含め、Phase 2 では読み取り専用（変更禁止、次歩 Phase 1 で上書き）とする。負対照 `NC-M7b`（Phase 2 で `pending_write.a` 改ざん → `digest_excl_settle` 不一致拒否）を追加。
    4. **細胞側上界の正の対照追加（claude P3）**: `GB-M2` に正の対照（`B_i ∈ [10.0, 100.0], N = 576, kept = 130` の決済が分離上界で誤拒否されず通過すること；Sterbenz 補題による `dec_lo` 厳密性の実測確認）を追加。
- **依拠する決定・仕様**:
  - ユーザー承認票 **L5B-1〜L5B-5**（2026-11-28、`discussion/user-decisions.md`, `discussion/decisions-log.md` #91、`discussion/notes/D-L5-BETA-AUE-SEAM.md` r2）。
  - 紙上記憶型仕様: `discussion/specs/L2L-TRM-draft-memory-type.md`（r7、#90）。
  - オフライン先行試験: `discussion/notes/S90-results.md`、`experiments/s90_l2l_trm/mem_core.jl`（sha `e09341e7dfd0e8c93d935c754f169b061c5a592ecf9886b9000a8d75f4d07a08`）。
- **絶対非変更境界（J3・2 ライン分離厳守）**:
  - 以下は 1 バイトも変更しない: `~/bridge-protocol/`、`core/`、`rust/`、`formal/`、`experiments/aue_seam/`、`experiments/onestep/`、`experiments/s90_l2l_trm/`（`mem_core.jl` を無変更 `include` するのみ）、S64〜S69 凍結資産、未使用主列種子（`1600–1617`, `2860–2899`）。
  - 新規コード・出力はすべて隔離ディレクトリ **`experiments/s91_aue_memory/`** に置く。
  - 最良容量 $C$ の採択禁止（#89）、`phenomenal_claim = :not_certified` 固定、R1 / R-MID / `K-UNIQ-CLEAR` / D1 規則の無断変更禁止。

---

## §0 問いの分離
- **問うこと**:
  1. 種非依存の `bed_mem.jl`（独立 2 相スナップショット・非創造保存則・偽死亡/早書き/許可外改ざん封じ）が、既存 `adapter_aue_b.jl` の無変更回帰と新規 `OneLife + TracePred + [memory]` の全関門（`GB-M0`〜`GB-M6`）・全負の対照（`NC-M1`〜`NC-M8`）をすべて通過するか。
  2. 独立種子区画 `910101..910136`・3 環境（定常・季節反転・枯渇ストレス）上で、5 容量 `{C0_B8, C0_B9, C1, C2, C130}` を同一種子ペア比較したとき、実維持費支払い（$K_{\text{mem}} = 0.002$）・維持費退去・閉ループ行為分岐・予測適合（`ΔBrier`）・資源残高・生存歩数がどう振る舞うか。
- **問わないこと**:
  - オンライン学習器の閉ループ統合（**S91b**）、S64 C0 凍結 TRM 重み確定（J3 維持）、Rust 実機配備、最良容量 $C$ 採択、`phenomenal_claim`。

---

## §1 構成ファイル（`experiments/s91_aue_memory/` のみ）
1. `species_aue_a_mem.toml`（および容量別設定生成）: L5B-2 に基づく `[memory]` 付き新種仕様。
2. `bed_mem.jl`（module `AUESeamBedMem`）: 種非依存 4 シーム床＋`[memory]` スキーマ・独立 2 相スナップショット監査。**種固有トークン（`AUE-A`, `AUE-B`, `AUEA`, `AUEB`, `OneLife`, `LabCore`, `NestingCPCC`, `CPC-Prolif`, `Runaway-Cancer`, `body_org`, `TracePred`, `R-MID`, `ctx_key`, `S90MemCore`）をソース内に 0 件含むこと**（静的不変条件関門）。
3. `adapter_aue_a_mem.jl`（module `AdapterAUEAMem`）: `core/one_life.jl`（`OneLife{LawL2}`）＋無変更 `experiments/s90_l2l_trm/mem_core.jl`＋既存 `TracePred`（`P_DECAY = 8`, `K_win = 0.002`）を接続する 2 相決済アダプタ。
4. `s91a_run.jl`: `smoke`（全関門のみ、本走り指標・E1–E3 一切未出力）および `run`（凍結照合＋`neg_controls.out` の 5 ファイル SHA 照合＋全関門通過後にのみ 3 環境・5 容量統計と E1–E3 を出力し `out/s91a.out` へ保存）。
5. `neg_controls.jl`: `NC-M1`〜`NC-M8`（計 13 ケース）を実行し、実装 4 ファイル（`bed_mem.jl`, `adapter_aue_a_mem.jl`, `s91a_run.jl`, `neg_controls.jl`）＋無変更 `mem_core.jl` の SHA-256 を記録して `out/neg_controls.out` へ保存。
6. `predictions.toml`: E1〜E3 と関門優先則を凍結（`experiments/freeze-s91a.txt`：ちょうど 2 エントリ `predictions.toml`・`S91a-draft-aue-memory.md` を厳密照合）。

---

## §2 種仕様・容量集合・演算予算（L5B-2）

### §2.1 容量集合（全 5 点等価報告、最良容量採択禁止）
- `C0_B8` (`B=8, C=0`), `C0_B9` (`B=9, C=0`, 余剰 1 B 全 `0x00`), `C1` (`B=24, C=1`), `C2` (`B=40, C=2`), `C130` (`B=2088, C=130`)。
- 共通固定値: `header_bytes = 8`, `slot_bytes = 16`, `upkeep_rate_per_slot = 0.002`（既存 `KC`/`S90`/`K_win` と同一）, `max_body_cells = 576`（`24x24` 物理絶対上界）, `max_read_ops_per_step = OPS_MEM_READ_WORST(C_spec)`。

### §2.2 共通プリミティブ演算予算
- `OPS_PRED_WORST = 64`（`TracePred` 1 歩：`predict`＋`update`＋`pi_u4`＋53-bit draw の実測最悪上限を単体関門で毎歩 `<= 64` 検査）。
- `C=130, N_max=576` の厳密最悪予約: `OPS_CTX_KEY(16) + OPS_MEM_READ_WORST(1048) + OPS_MEM_SETTLE_WORST(4,948,459) + OPS_MEM_WRITE_WORST(1056) + OPS_PRED_WORST(64) = 4,950,643`。
- 全 5 容量共通の `[budget]`（`species_aue_a_mem.toml`）:
  - `step_granularity_sec = 10.0`, **`ops_per_step = 6_000_000`**, **`ops_per_hour = 2_160_000_000`**（`= 360 * 6_000_000`；注記: 1 歩上限と同一比率のため 3600s 窓は単歩違反なしの系では非拘束であり、4 シームの窓超過拒否は既存通り負対照・低窓テストで別途検証する）。
- 毎歩 `ops_used = ops_pred + ops_mem_read + ops_mem_write + ops_mem_settle`（`C_spec == 0` ではメモリ 3 項すべて厳密 `0`）。

---

## §3 `bed_mem.jl` 独立 2 相スナップショット契約（L5B-1）

- `[memory]` 未指定の既存種（`adapter_aue_b.jl` 等）はデフォルト `reserved_bytes = 8, C_spec = 0`・従来単相 `step_species`・4 引数 `StepCost` で無変更通過する。
- 2 相決済プロトコル（`[memory]` 宣言種、**`C_spec == 0` を含む全 5 容量で共通の監査フックを検査**）:
  1. **歩前スナップショット（bed 所有コピー）**: `mem_init = copy(memory_bytes(adapter, state))` を取得。
  2. **Phase 1（決済前更新）**: `mid_state, phase1_out, phase1_cost, spore_req = step_species_pre_settle(adapter, state, si, budget)`（`mid_state` は `state` と独立な新状態）。
  3. **決済直前の独立判定・スナップショット（すべて bed 所有コピー）**:
     - `mem_pre = copy(memory_bytes(adapter, mid_state))`。**Phase 1 早書き禁止**: `mem_pre == mem_init` を必須検証（違反時は `MemoryAccountingViolation`）。
     - **偽死亡封じ**: `bed_mem` 自身が `alive_post = is_alive(adapter, mid_state)` を独立判定し、同時に `ids_pre = copy(body_cell_ids(adapter, mid_state))` が `alive_post == !isempty(ids_pre)` と一致することを検証する（アダプタ自己申告の `alive` は使わない）。
     - `B_pre = copy(body_balances(adapter, mid_state))`（`length(B_pre) == length(ids_pre)`）、`port_pre = Float64(port_balance(adapter, mid_state))`、`total_pre = Float64(total_matter(adapter, mid_state))`、`excl_pre = digest_excl_settle(adapter, mid_state)`（許可書込集合 `{body B, port, M}` を除いた全状態［`pending_write` 含む］の SHA-256）を取得。
     - `mid_copy = deepcopy(mid_state)` を Phase 2 に渡す（例外送出時に `mid_state` 原型と完全比較可能にする）。
  4. **Phase 2（決済専用）**: `next_state, settle_cost = settle_species_memory!(adapter, mid_copy, alive_post, budget)`。
     - もし `InvalidResourceError` が送出された場合: 呼出側の `mid_state` 原型は不変であり、当該ランは個体死ではなく **`run invalid`** と分類する。
  5. **決済直後の独立スナップショット（すべて bed 所有コピー）と厳密検査**:
     - `ids_post = copy(body_cell_ids(adapter, next_state))`、`B_post = copy(body_balances(adapter, next_state))`、`port_post = Float64(port_balance(adapter, next_state))`、`total_post = Float64(total_matter(adapter, next_state))`、`mem_post = copy(memory_bytes(adapter, next_state))`、`excl_post = digest_excl_settle(adapter, next_state)`。
     - **許可外書込禁止・細胞 ID 安定性（全歩）**: `excl_post == excl_pre` かつ `ids_post == ids_pre` かつ `is_alive(adapter, next_state) == alive_post`。
     - **固定長バイト形式（全歩）**: `length(mem_post) == spec.memory_reserved_bytes`、ヘッダ `pad_h == 0`、空枠・余剰バイト全 `0x00`、`kept = get_le(UInt32, mem_post, 0) <= C_spec` かつ `kept == settle_cost.memory_slots_kept`。
     - **`C_spec == 0`（全歩）**: `kept == 0`, `isempty(settle_cost.slot_paid_lo)`, `settle_cost.memory_upkeep_paid === 0.0`, `settle_cost.memory_port_delta === 0.0`, `settle_cost.memory_settle_ops == 0`, `B_post == B_pre`, `port_post === port_pre`, `mem_post == mem_pre`。
     - **`alive_post == false`（代謝死歩）**: `isempty(settle_cost.slot_paid_lo)`, `settle_cost.memory_upkeep_paid === 0.0`, `settle_cost.memory_port_delta === 0.0`, `settle_cost.memory_settle_ops == 0`, `B_post == B_pre`, `port_post === port_pre`, `mem_post == mem_pre`（完全凍結）。
     - **`alive_post == true` かつ `C_spec > 0`（選択・非選択を問わず全生存歩）**:
       - 購入済スロット別 `paid_lo` 列 `settle_cost.slot_paid_lo::Vector{Float64}` について `length == kept`、各要素 `p >= K_mem`（`Float64` 厳密、r7 §3.3 と同一）。
       - `BigFloat`（2400-bit）で `exact_E = sum(BigFloat(B_pre[i]) - BigFloat(B_post[i]) for i in eachindex(B_pre))`、`port_delta = BigFloat(port_post) - BigFloat(port_pre)`、`sum_paid_lo = sum(BigFloat.(settle_cost.slot_paid_lo); init = BigFloat(0))`、`req_exact = BigFloat(kept) * BigFloat(K_mem)` を独立算出し、検証済みスカラー支払額 **`verified_mem_paid = Float64(sum_paid_lo)`** を `bed_mem` 自身が導出する：
         1. **許容誤差ゼロ課金＆スカラー一致強制**: `sum_paid_lo >= req_exact` かつ **`settle_cost.memory_upkeep_paid === verified_mem_paid`**（`kept == 0` なら `0.0` 厳密一致、`NC-M2c` を拒否；非選択歩でも `kept > 0` なら必須＝無料保持禁止）。
         2. **報告値と実測値の一致**: `BigFloat(settle_cost.memory_port_delta) == port_delta`（`NC-M2b` を確実に検出）。
         3. **非創造保存則**: `0 <= port_delta <= sum_paid_lo <= exact_E`、全細胞 `B_post[i] <= B_pre[i]`、`BigFloat(total_post) <= BigFloat(total_pre)`。
         4. **分離した有界丸め落ち上界（スロット逐次加算対応）**: 無変更 `mem_core.jl` は `kept` スロットそれぞれで `port_arg`（`add_down`）を 1 回ずつ呼ぶため、細胞側（`K_mem` 桁、Sterbenz 補題により `dec_lo` は高残高域でも誤差ゼロ）とポート側（スロット当たり `1 ulp(port_post)` × `kept` 回）を分離した数学的上界を課す：
            $$\mathrm{exact\_E} - \mathrm{port\_delta} \le \mathrm{BigFloat}(\mathrm{kept}) \cdot \Bigl(\mathrm{BigFloat}(3 N + 4)\cdot \mathrm{BigFloat}(\mathrm{eps}(\max(2.0 K_{\mathrm{mem}},\, 2.0\,\mathrm{eps}(\max(1.0, B_{\max}))))) + \mathrm{BigFloat}(\mathrm{eps}(\max(\mathrm{port\_post}, K_{\mathrm{mem}})))\Bigr)$$
            （ここで $N = \mathrm{length}(B_{\mathrm{pre}})$, $B_{\max} = \max_i B_{\mathrm{pre}}[i]$。注記: 通常域 `port = 300.0` では `kept = 130` でも上界 `≈ 7.4e-12` と極めて厳しい一方、上限極値 `port = 2^40` では `kept` 回丸めゆえ上界が `kept × 2.44e-4`［`kept=1` で `2.44e-4`、`kept=130` で `3.17e-2`］へ比例緩和する限界を明示する）。
  6. **監査鎖**: `state_digest` に `mem_post`（固定長 $B$ バイト）を含め、`commit` 行へ `mem_kept`, `mem_paid`（`verified_mem_paid`）, `mem_port_delta`, `mem_ops` を記録。`ledger.cumulative_memory_upkeep` および E1 集計はすべて `verified_mem_paid` のみを用いる。`replay_from_audit` が入力テキスト行のみから全行ハッシュ一致と全 2 相保存則を再検証する。

---

## §4 `OneLife` 接続・`ctx_key`・`Y_t`・抽選・オーバーフロー（L5B-3, L5B-4）

### §4.1 初期状態（全 5 容量で 1 ビットも同一の成熟個体）
- `make_s91a_initial_state(seed, cfg)`:
  - 無変更 `core/one_life.jl` の `onelife_birth(seed, LawL2)` から、`LabCore.BO_CUR`（800 歩、整数駆動 `Int.(BO_CUR[i])`）を無変更 `onelife_step` で進めた個体 `life0` に、空メモリ `MemoryState()`・初期 `TracePred()`・実験歩カウンタ `exp_step = 0`・初期 `pending_write = NOPENDING` を載せる。
  - 全 36 種子（`910101..910136`）が `BO_CUR` 800 歩終了時点で生存であることを `GB-M0` で検証する。

### §4.2 1 歩の厳密接続順序（`core/`・`mem_core.jl` 無変更）
- `experiments/onestep/onestep.jl` 流に `core/circuit.jl` の `step!` と `core/one_life.jl` の `_live` を隔離モジュール内でコピーし、draw hook へ **`old`（前歩受容器 `st.active`、`nw` は絶対渡さない）** を渡す `step_s91a!`・`_live_s91a` を生成する。
- **Phase 1（決済前、`M` は一切変更しない）**:
  1. 歩頭死亡検査（`life.dead` または `_empty_body(life)` → 吸収死）。
  2. `_live_s91a` 内 draw hook（2 パッチ候補の選択歩のみ）：
     - 既存 `TracePred` で `(pred_eff, p1_base, p2_base) = predict(pred, body_R(life))`（既存 `K_win = 0.002` 読取判定を維持；`p1_f32 = Float32(p1_base)`, `p2_f32 = Float32(p2_base)`）。
     - `cfg.C == 0`: `ctx_key` 非計算・メモリ読出し演算 `0`、`p1 = p1_f32, p2 = p2_f32`。
     - `cfg.C > 0`: `k = ctx_key_s91a(old, exp_step)`（**実験開始点リセット規約 H**: `exp_step == 0 -> UInt64(64)`、それ以外は `R1IDX = (1, 2, 3, 4, 7, 8)` について `old[R1IDX[i]]` を bit `i-1` にパック）→ `S90MemCore.read_memory_pair(cfg, M, () -> k, p1_f32, p2_f32)`（読み取り専用、`M` 不変）。
     - `pis = S90MemCore.pi_u4(p1, p2)`、`u = Float64(si.ports["rand_u64"] >> 11) * 2.0^-53`、**厳密不等号 `a = (u < Float64(pis[1])) ? 1 : 2`**。
     - `Y_t = (y[a] > 0)`（選択行為座標系；実獲得量 `take` は別途記録）。
  3. 既存 `OneLife{LawL2}` 更新（`KC = 0.002` → 採餌 → `MCOST = 0.004` → 外部供給 → `LabCore.step!(w, ())`）。
  4. **`TracePred` 更新（`onestep.jl:122` 完全一致）**: `r.drawn` が真なら（当歩が死亡歩であっても）`pred2 = update(pred_eff, a, Y_t)`、非選択歩なら `pred2 = pred`。
  5. **歩トランザクション欄の固定**: 当歩の `(drawn, k, a, Y_t, p_pre, p_base, remaining_ops)` を **`mid_state.pending_write`** の 1 フィールドへ格納する。`pending_write` は `digest_excl_settle` に含め、**Phase 2 では読み取り専用（変更禁止）** とし、次の歩の Phase 1 が新しく上書きする（アダプタ側の可変脇道を持たない）。
- **Phase 2（決済専用、`{w.B, w.port, M}` 以外の全フィールド不変）**:
  - `alive_post == false` または `cfg.C == 0`: 何も変更せず 0 コスト返却（`slot_paid_lo = Float64[]`, `memory_upkeep_paid = 0.0`, `memory_port_delta = 0.0`）。
  - `alive_post == true` かつ `cfg.C > 0`:
    - `pw = mid_copy.pending_write` を読み取り、`cand = copy(M)`。`pw.drawn` かつ `pw.remaining_ops >= OPS_MEM_WRITE_WORST(cfg)` なら `write_memory_candidate!(cfg, cand, pw.k, UInt8(pw.a), UInt8(pw.Y_t), pw.p_pre, pw.p_base; remaining_ops = pw.remaining_ops)` を適用（非選択歩・残枠不足なら `cand` 無変更）。
    - `body_post = [i for i in eachindex(w.C) if w.C[i] != 0]`、`p_ref = Ref(w.port.reservoir)`。
    - `st = S90MemCore.settle_upkeep!(cfg, M, w.B, body_post, p_ref; cand = cand)` を実行後、**`w.port.reservoir = p_ref[]`**・**`w.port.outflow += st.port_delta`**（`port_give!` の重複呼出禁止、`core/matter.jl:20` の定義 `reservoir += x; outflow += x` と完全一致）。
    - `slot_paid_lo = Float64[tr.paid_lo for tr in st.trace if tr.purchased]`、`memory_upkeep_paid = Float64(sum(BigFloat.(slot_paid_lo); init = BigFloat(0)))`、`memory_port_delta = st.port_delta`。
    - `port > 2^40`（`RES_HI = ldexp(1.0, 40)` 厳密超過、または事前入力が `> 2^40`）で `InvalidResourceError` 送出時は、クランプせず当該ランを **`run invalid`**（個体死と区別、分析除外、全 5 容量で件数報告）とする。

---

## §5 3 環境・独立種子区画・決定的 `rand_u64` 生成（L5B-5）

- **全 36 種子（`910101..910136`、未使用主列 `1600–1617`, `2860–2899` と完全素集合、事前覗き見・チューニング禁止）**:
  - 各環境 12 種子 × 5 容量 = 各環境 60 ラン、計 180 ラン。各ラン長 **`STEPS = 4000` 歩**（`s = 0..3999`）。
- **3 環境の厳密駆動定義（すべて整数 `g ∈ {0..5}^2`、`bo_season` 由来）**:
  1. **`env_stat`（定常、`910101..910112`）**: `Int.(LabCore.bo_season(s))`（周期 1000: `1..300 (3,2)`, `301..600 (0,5)`, `601..1000 (5,0)`）。
  2. **`env_rev`（季節反転、`910113..910124`）**: `s < 2000` は `Int.(LabCore.bo_season(s))`、`s >= 2000` は `(g[2], g[1])`（`REV = 2000`）。
  3. **`env_depl`（枯渇ストレス、`910125..910136`）**: 200 歩周期、`c = (s % 200) + 1` とし `c <= 60 -> (2, 1)`, `61 <= c <= 120 -> (1, 2)`, `121 <= c <= 200 -> (0, 0)`（80 歩飢饉）。
     - 記述必須項目: 飢饉突入時残高（`s = 120` 時点の `Σ w.B`）、初回飢饉（`s = 120..199`）通過率、維持費退去総数（`upkeep_evicted`）、4000 歩完走率（右側打切り数）。
- **決定的 `rand_u64` 生成（`core/jsmath.jl:111-117` 準拠）**:
  - 種子 `seed` ごとに `rng = LabCore.Mulberry(seed + 100_000)` を用い、各歩 `s = 0..3999` で混合済み 32-bit 出力 2 語：
    ```julia
    u1 = UInt32(trunc(UInt64, rng() * 4294967296.0))
    u2 = UInt32(trunc(UInt64, rng() * 4294967296.0))
    rand_u64 = (UInt64(u1) << 32) | UInt64(u2)
    ```
    を生成して `StampedInput` に刻印する（5 容量すべてで同一入力列）。`GB-M0` で `(seed = 910101, s = 0)` の既知 `rand_u64` 決定値照合と、4000 歩の `u` 列ラグ 1 自己相関 `|acf1| < 0.1` を検証する。

---

## §6 必須関門（`GB-M0`〜`GB-M6`）および負の対照（`NC-M1`〜`NC-M8`）

- **既存 4 シーム全関門回帰**: `bed_mem.jl` 内の種固有トークン 0 件、ポート違反・種境界違反・瞬間/3600s 窓予算超過・休眠無料記憶・吸収死後 0 コミット・死後胞子・共有媒質二重消費の各拒否、**既存 `experiments/aue_seam/adapter_aue_b.jl`（`[memory]` 未指定）無変更回帰通過**、`replay_from_audit` 全行ハッシュ一致。
- **`GB-M0`（凍結照合・初期育成生存・種子素集合・`rand_u64` 品質）**: `experiments/freeze-s91a.txt` の 2 SHA-256 厳密一致、全 36 種子（`910101..910136`）の `BO_CUR` 800 歩後生存確認、主列 `1600–1617`/`2860–2899` との素集合確認、`(seed=910101, s=0)` の既知 `rand_u64` 値一致＋`u` 系列 `|acf1| < 0.1`。
- **`GB-M1`（`C0_B8`/`C0_B9` 基準同値・抽選死亡歩一致・境界・演算上限）**:
  - `C0_B8`・`C0_B9`（9B 全 `0x00`）が記憶なし `OneLife + TracePred + U4` 基準（`onestep.jl` 同一更新則）と行為列・RNG 消費・残高・寿命・`state_digest`（記憶バイト除く）で全歩ビット一致、メモリ演算 0。
  - **抽選歩で代謝死するフィクスチャ**上で、`pred` ダイジェストを含め基準と全歩ビット一致。
  - `u == Float64(pi1)` 等号境界で行動 `2` となる単体検証、`OPS_PRED_WORST <= 64` 単体検証。
- **`GB-M2`（実残高による維持費淘汰・分離上界の正負対照・ポート `2^40` 4 点境界）**:
  - 枯渇フィクスチャで `upkeep_evicted >= 1` が発火し、独立 2 相スナップショット上の全保存則・分離丸め落ち上界が成立。
  - **正の対照（claude P3）**: `B_i ∈ [10.0, 100.0]`, `N = 576`, `kept = 130` の決済が分離上界で誤拒否されず通過すること。
  - **リーク注入拒否 3 ケース（claude P1・codex P1）**: (i) `kept = 1, port = 2^40` で `1e-3` 物質消失注入を拒否、(ii) `kept = 130, port = 2^40` で `0.05` 物質消失注入を拒否、(iii) `kept = 130, port = 300.0` で `1e-10` 物質消失注入を拒否。
  - **ポート `RES_HI = ldexp(1.0, 40)` 4 点境界検証**: (a) `prevfloat(2^40)` からの非超過決済（通過）、(b) ちょうど `2^40` 到達決済（通過）、(c) 事前不正入力 `nextfloat(2^40)` の即時 `InvalidResourceError` 拒否、(d) 有効入力 `port <= 2^40` から決済で `2^40` を跨ぐ超過の `InvalidResourceError` 拒否。エラー送出時は Phase 2 前コピーと全状態ビット完全一致。
- **`GB-M3`（死亡吸収・記憶凍結）**: 飢饉死フィクスチャで代謝死歩（`!alive_post`）に `paid === 0.0`, `port_delta === 0.0`, `ops_settle == 0`, `B_post == B_pre`, `port_post === port_pre`, `mem_post == mem_pre`、死後ステップ 0 回。
- **`GB-M4`（未来漏れゼロ・`ctx_key` 同型・`Y_t` 境界）**: `old` 固定で当歩 `y` を変化させても `ctx_key`・`p_pre`・`pi`・`a_t` がビット不変。通常順列と `cross!` 反転順列の双方で `ctx_key` が S90 定義と一致。`y[a_t] > 0 ∧ take == 0` 境界ケースで `Y_t == true` かつ `take == 0.0` 別記録を検証。
- **`GB-M5`（非選択歩の無料保持禁止・監査鎖完全再生）**: 非選択歩で保持スロットへの前払い決済が 1 歩 1 回必ず課金されること。`replay_from_audit` が入力テキスト行のみから全 `commit` ハッシュと全 2 相保存則を完全再生すること。
- **`GB-M6`（`TracePred` 到達可能 R1 発火・一致抽選実行パッチ分岐）**: 空メモリから到達可能な有限プレフィックスで `TracePred` が厳密誤予測 → R1 書込 → 同一鍵・同一パッチ再訪で `R-MID` ヒットを起こし、`min(Float64(pis_ON[1]), Float64(pis_OFF[1])) <= u < max(Float64(pis_ON[1]), Float64(pis_OFF[1]))` を満たす決定論的 `rand_u64` を与え、`C > 0` と `C0_B8` で**実際に身体へ実行されたパッチ `a_exec`** が設計期待値どおり分岐することを検証。
- **負の対照 `NC-M1`〜`NC-M8`（全 13 ケースが想定関門で失敗必須）**:
  - `NC-M1a`: `C0_B9` 余剰 1B 非ゼロ化 → `GB-M1` 失敗
  - `NC-M1b`: `C0` 時 `ctx_key` 呼出 → `GB-M1` 失敗
  - `NC-M1c`: 既存 `adapter_aue_b`（`[memory]` 未指定）回帰破壊 → 既存回帰失敗
  - `NC-M2a`: 架空支払い（`B_before` 水増し・実残高不変で `paid > 0` 申告） → `bed_mem` 2 相検証拒否
  - `NC-M2b`: 架空返還（`port_reservoir` 不変で `port_delta > 0` 申告） → `bed_mem` 2 相検証拒否
  - `NC-M2c`: スカラー支払額水増し（`kept == 0`・残高不変で `memory_upkeep_paid = 1.0` 申告） → `bed_mem` スカラー一致検証拒否
  - `NC-M3`: 未来漏れ（`s > 0` で `old` と `nw` がパック対象 6 bit で異なる歩に `nw` を渡す） → `GB-M4` 検出
  - `NC-M4`: 非選択歩の無料保持（`kept > 0` で決済スキップ `paid == 0`） → `bed_mem`（`GB-M5`）拒否
  - `NC-M5`: 誤配線（`route_det` または `M` シャッフルで実行パッチ `a_exec` 不一致） → `GB-M6` 検出
  - `NC-M6`: 偽死亡申告（生存体に対し偽死亡報告で無料保持を狙う） → `bed_mem` 独立 `is_alive` 検証拒否
  - `NC-M7a`: Phase 2 許可外書込（決済中に `circuit`/`pred`/`t` を改ざん） → `bed_mem` `digest_excl_settle` 不一致拒否
  - `NC-M7b`: Phase 2 内の `pending_write.a` 改ざん → `bed_mem` `digest_excl_settle` 不一致拒否
  - `NC-M8`: Phase 1 記憶早書き（Phase 1 中に `M` を変更） → `bed_mem` `mem_pre == mem_init` 不一致拒否

---

## §7 事前予測（`experiments/s91_aue_memory/predictions.toml`、凍結対象）
- **関門優先則**: 既存 4 シーム回帰・`GB-M0`〜`GB-M6`・`NC-M1`〜`NC-M8`（`out/neg_controls.out` の 5 ファイル SHA 照合含む）のいずれか 1 つでも失敗すれば `S91a-E1 = miss`, `S91a-E2 = undecidable`, `S91a-E3 = undecidable`。
- **S91a-E1（同一環境内の実課金・R1 書込・閉ループ行動分岐の実在性）**:
  - 3 環境のいずれか **同一の環境 $e$** 内で、(a) 全 3 有限容量 `C ∈ {1, 2, 130}` の有効ラン合計で R1 書込 `>= 1` かつ累計検証済実維持費 `> 0.0`、かつ (b) 少なくとも 1 有限容量の有効 `(C, C0_B8)` ペア種子で共通生存・共通抽選歩上の実行パッチ `a_exec` が異なる種子が `>= 1` 存在する（全環境・全有限容量で有効ペア 0 なら `undecidable`、条件成立で `hit`、さもなくば `miss`）。
  - 併記記述: 初回分岐歩の原因内訳（`R-MID hit` 由来 vs 維持費による `body_R`/`K_win` 経済由来）、および生存歩数差の単独発生件数。
- **S91a-E2（枯渇ストレス環境 `env_depl` での閉ループ生存負荷）**:
  - `env_depl`（`910125..910136`）の有効 `(C130, C0_B8)` ペア種子上で、`mean(surv_steps(C130) - surv_steps(C0_B8)) < 0`（ここで `surv_steps = death_step`［代謝死時］または `4000`［完走時、右側打切り］）。有効ペア 0 なら `undecidable`、`< 0` で `hit`、`>= 0` で `miss`（維持費を回収した非劣化/改善または全完走として正直報告）。
  - 併記記述（同語反復性を開示）: `final_B`（完走時は 4000 歩決済後 `Σ w.B[body_post]`、死亡時は `0.0`）の全容量ペア平均、4000 歩完走率、飢饉突入時残高、初回飢饉通過率、維持費退去総数。
- **S91a-E3（閉ループ `R_hit(130)` 上の予測適合）**:
  - `env_stat`＋`env_rev` の **有効な `C130` ランのみ**（`run invalid` ランは全プレフィックスを含め除外）から、実行パッチ `a_t` について `[memory]` がヒットした選択歩 `R_hit(130)` を歩単位でプールし、抽選前 `Float32` 予測 `p_ON = p_pre[a_t]`・`p_OFF = p_base[a_t]` と同歩 `Y_t = (y[a_t] > 0)` で `mean(ΔBrier(130)) = mean((Float64(p_ON) - Float64(Y_t))^2 - (Float64(p_OFF) - Float64(Y_t))^2) < 0`（改善方向；`|R_hit(130)| == 0` なら `undecidable`、`< 0` で `hit`、`>= 0` で `miss`；種子等重み平均も副次併記）。
- **全点記述報告（採択禁止・#89 厳守）**: 3 環境 × 5 容量の全 15 セルについて、有効ラン数/`run invalid` 数、選択歩数・非選択歩数、`|R_hit|`・R1 書込数・`K-UNIQ-CLEAR`・D1 退去・維持費退去（`upkeep_evicted`）、累計検証済実支払維持費、`C0_B8` との行動不一致種子数・初回分岐原因、ヒット歩 `ΔBrier`（歩プール＆種子等重み）・`acc_ON - acc_OFF`、累計実収穫 `take`、平均生存歩数・完走率、平均 `final_B`、飢饉突入残高・初回飢饉通過率、`replay_from_audit` 一致率を全表出力する。
