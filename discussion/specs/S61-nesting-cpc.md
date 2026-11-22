# S61 個体内増殖＋コアなし集合的予測符号化（CPC）の Stage 1 系譜スパン・判別器検証（r3）

- 作成: 2026-11-22（`neon-lab`、r1 の 9 指摘＋r2 の `codex-lab` 2 指摘［無向閉包・合流タイブレーク］＋偽摂動種子明記を全反映。3 系統体制 §1.3 改訂［案 A］・§1.4 準拠）
- ゲート確認済み: `julia ~/bridge-protocol/tools/verify/decision_gate.jl status` → `pending_A = 0, warning = false, hard_stop = false`（2026-11-22 10:54 確認済み、U-BL1 停止解除済み）。
- 出典:
  - `~/bridge-protocol/formal/ERIEC/MetaSelection.lean:279-365`、`formal/ERIEC/Lineage.lean:1-100`
  - `discussion/notes/D-NESTING-CPC.md`（O14〜O17、U-NC1〜U-NC3）
  - `discussion/notes/L3-STAGE0-WITNESS-AND-EXPLORATION.md`（O21〜O22）
  - `discussion/specs/S61-draft-nesting-cpc-exploration.md`、`discussion/user-decisions.md`

---

## 1. 目的・非目標
- **目的**: 着地方針 L3（U-NC2）に基づき、
  1. **Lean（`formal/NestingLineage.lean`）** で、互いに素な時間添字担体上の Stage 0 型レベル破綻証人（`H_persist` vs `H_replace`）と Stage 1 整形式隣接時点系譜スパン（1 分裂あたり最大 1 継続出力、merge 吸収/融合区別、身体不可逆性）および分離定理を証明する（`sorry` 0、標準公理のみ）。
  2. **Julia（`experiments/nesting_cpc/`）** で、身体層＋6 系＋抜落キャッシュ負試験（計 7 構成）を実装し、R1〜R6（Stage 0/1 分離、R2 整形式＋遷移内 M1 担体連続性＋負試験 2 件、E1 暴走分離、E2 外部非干渉＋絶対時計時間シフト不変性、E3′ 身体隔離＋規則一括無効化＋交換試験＋迂回証人＋独立目録・キャッシュ貫通監査）を検証する。
- **非目標**:
  - `~/bridge-protocol` の変更（読み取り専用で `formal/check.sh` 照合のみ）。
  - 既存 `core/`・`rust/`・S54 試運転への変更。
  - Stage 2（fibration／operad）の持ち込み（U-NC2）。
  - `phenomenal_claim` に関わる主張（`phenomenal_claim = :not_certified` 固定）。

---

## 2. 用語（`discussion/glossary.md` 準拠・生活比喩禁止）
- **身体（Body / コア）**: U-NC1(a)(c) により、機能終了の不可逆性（`alive == false` 吸収状態）と共通維持費プール $R_t$・未払い維持費負債 $D_t$ の器。「`bridge-protocol` においては身体をコアに含めることも包含する。`bridge-agency-lab` においてはその条件の一要素として個体同一性・系譜において身体をコアに含める。」
- **担体 ID（M1 連続性アンカー）**: 単調増加アロケータ `next_id` が発行する再利用不可の正整数 ID。互いに素な時点担体 $V_t = \{(t, W)\} \cup \{(t, \mathrm{id}) \mid \mathrm{id} \in M_t\}$ と明示対応づける。
- **隣接時点系譜スパン $L_t$**: $V_t$ と $V_{t+1}$ を結ぶ整形式タグ付き関係（`persist` / `split`［継続出力最大 1］ / `merge`［`absorption` | `fusion`］）、および $\mathrm{Death}_t, \mathrm{Birth}_{t+1}$。

---

## 3. 対象集団・固定更新則・種子（凍結対象）

### 3.1 環境再生テープ（Replay Tape）と種子
- **再生テープ**: 種子 `seed` から `Random.Xoshiro(seed)` で長さ $T = 120$ の決定的な列 `tape = [(x_k, h_base_k, rng_k) for k in 1:120]` を事前生成する（`x_k ∈ {1,2,3,4}`、基礎周期 12 の決定パターン＋確率 `0.05` 雑音、$k = 41, 81$ で信号写像の巡回置換、`h_base_k = 1.2` for $k \in [45, 65]$ else `3.0`）。時間シフト試験（E2）や介入比較（E3′）は**同一の `tape`** を供給し、収穫倍率も含めて完全再現する。
- **種子割当（主列 886〜、完全分離）**:
  - 開発・煙確認用（実装確認・$t^*$ 可実現性確認のみ、評価集計外）: **`886..889`**（4 種子）
  - 本評価用（予測凍結後に 1 回評価、事前調整禁止）: **`890..909`**（20 種子）
  - 次回の未使用主列種子: **`910`**

### 3.2 1 歩の確定更新順序と数式（全パラメータ凍結）
- 身体初期値: `alive = true`, $R_0 = 20.0, R_{\max} = 40.0, D_0 = 0.0, D_{\mathrm{lethal}} = 12.0$。
- 初期モジュール: $|M_0| = 4$（`id = 1..4`, `next_id = 5`）、各 $u_0 = 4.0$、各 $4 \times 4$ ロジット表 $\theta_i[c, s]$ を種子から決定初期化（初期文脈 $c_0 = 1$）。
- **1 歩の順序（`step!(sys, x_k, h_base_k, step_rng, t_abs)`）**:
  1. **機能終了チェック**: `!alive` なら即終了（吸収状態、`W_t` の出力辺なし）。
  2. **予測と連合行為**: 各 $i \in M_t$ が $\hat{p}_{i,t} = \mathrm{softmax}(\theta_i[c_t, \cdot])$ を算出。重み $w_{i,t} = \frac{\max(u_{i,t}, 0.1)}{\sum_j \max(u_{j,t}, 0.1)}$、連合分布 $\hat{p}_{\mathrm{coal},t} = \sum_i w_{i,t}\hat{p}_{i,t}$、行為 $a_t = \arg\max_s \hat{p}_{\mathrm{coal},t}[s]$（同率は最小添字）。
  3. **収穫**: $h_t = h_{\mathrm{base},k} \cdot (1.0 + 1.5 \cdot \mathbb{I}[a_t == x_k])$。
  4. **残差とモジュール間 CPC 更新（構成別、$\eta_{\mathrm{self}} = 0.35, \eta_{\mathrm{cpc}} = 0.45$）**:
     - 局所残差 $e_{i,t}[s] = \mathbb{I}[s == x_k] - \hat{p}_{i,t}[s]$、精度 $\mathrm{acc}_{i,t} = \hat{p}_{i,t}[x_k]$。
     - **無向 2-連結リング＋弦グラフの配線則**（活性モジュールを `id` 昇順の 0-起算配列 `ids[0..|M|-1]` で整列）：
       - 辺集合 $E$ は**無向辺（対称閉包）**として定義する：$|M| \ge 4$ なら環辺 $\{j, (j+1) \bmod |M|\}$ と対向弦 $\{j, (j + \lfloor |M|/2 \rfloor) \bmod |M|\}$ の無向和集合（例：$|M|=5$ では $E = K_5$ となり `N(0) = {1,2,3,4}`、$|M|=6$ では `N(0) = {1,3,5}`）、$|M|=3$ なら完全 3 角形 $K_3$、$|M| \le 2$ なら全結合。入力近傍と出力近傍は一致し、分裂・合流・消滅のたびに同一規則で決定的に再配線する。
     - **`CPC-Prolif`・`Runaway-Cancer`・`Hidden-Age-Control`**: 各隣接辺 $(k \to i)$ が独立の局所規則 `local_link(k→i)` として残差 $e_{k,t}$ を送り、$\Delta \theta_i = \eta_{\mathrm{self}} e_{i,t} + \eta_{\mathrm{cpc}} \frac{1}{|N(i)|}\sum_{k \in N(i)} e_{k,t}$。
     - **`Fixed-Core`**: 固定ハブ（`ids[1]`）が必須単一規則 `R_fixed` で $z_t = \frac{1}{|M|}\sum_k e_{k,t}$ を計算し全モジュールへ配信（$\Delta \theta_i = \eta_{\mathrm{self}} e_{i,t} + \eta_{\mathrm{cpc}} z_t$）。
     - **`Rotating-Mediator-Failover`**: 毎歩ホストが回転（`h = ids[(step % |M|) + 1]`）して単一必須規則 `R_rot_fo` を実行（$\bigcap_t \mathrm{Ess}(t) = \emptyset$）。単一ホスト経路の遮断時には次ホストへ即フェイルオーバーする。
     - **`Rotating-Mediator-Redundant`（正のキャッシュ記載対照）**: 回転する 2 ホストが同一必須認可規則 `R_rot_red` を並列実行し 2 本の冗長リンク（ホスト粒度最小カット $\ge 2$）で認可を配信、かつ 1 歩キャッシュ欄 `grant_cache` を持ち、**`grant_cache` が `GrantInventory` に明記されている**（必ず `core_present` を返すこと）。
     - **`Omitted-Cache-Control`（抜落キャッシュ負試験）**: `Rotating-Mediator-Redundant` と同一力学で `grant_cache` を有効化（新鮮認可停止時のフォールバック読取あり）しつつ、**`grant_cache` のみを `GrantInventory` から意図的に抜落**（必ず `unresolved` を返すこと）。
  5. **維持費・負債・局所痕跡 $u_i$ の確定帳尻（M1）**:
     - 利用可能資源 $R_{\mathrm{avail}} = \min(R_{\max}, R_t + h_t)$、請求額 $B_t = c_{\mathrm{mod}} \cdot |M_t|$（$c_{\mathrm{mod}} = 0.55$）、維持費赤字 $\mathrm{def}_t = \max(0.0, B_t - R_{\mathrm{avail}})$。
     - もし $R_{\mathrm{avail}} \ge B_t$ なら残余 $R_{\mathrm{rem}} = R_{\mathrm{avail}} - B_t$、負債返済 $\mathrm{rep}_t = \min(D_t, R_{\mathrm{rem}})$、$D_{t+1} = D_t - \mathrm{rep}_t$、純余剰 $S_t = R_{\mathrm{rem}} - \mathrm{rep}_t$、成長配分ボーナス $\mathrm{bonus}_t = \min(1.6, 0.25 \cdot S_t)$、$R_{t+1} = S_t - \mathrm{bonus}_t$、支払総額 $P_{\mathrm{paid}} = B_t + \mathrm{bonus}_t$。
     - もし $R_{\mathrm{avail}} < B_t$ なら $R_{t+1} = 0.0$、$D_{t+1} = D_t + \mathrm{def}_t$、$P_{\mathrm{paid}} = R_{\mathrm{avail}}$。
     - 各モジュールの局所痕跡更新：$g_{i,t} = P_{\mathrm{paid}} \cdot \frac{\mathrm{acc}_{i,t} + 0.1}{\sum_j (\mathrm{acc}_{j,t} + 0.1)}$、$u_{i,t+1} = u_{i,t} + g_{i,t} - c_{\mathrm{mod}}$。
  6. **内生的 turnover の確定順序と $L_t$ 記録**:
     - (i) **消滅（`death`）**: $u_{i,t+1} \le 0.0$ のモジュールを削除（残存 0 なら `alive = false`）。
     - (ii) **合流（`merge`）**: $|M| \ge 4$ のとき、無向グラフ辺 $\{i, j\} \in E$ のうち $u_i < 1.2 \land u_j < 1.2$ を満たす候補対が存在すれば、辞書式タプル **`(u_i + u_j, min(id_i, id_j), max(id_i, id_j))` を最小化する一意の対**を 1 組だけ合流させる（$|u_i - u_j| > 0.05$ なら `absorption`［高 $u$ 親 ID 継続・他親終了］、$\le 0.05$ なら `fusion`［両親 ID 終了・新規 `next_id` 発行］）。
     - (iii) **分裂（`split`／出芽）**:
       - `CPC-Prolif`・`Fixed-Core`・`Rotating-*`・`Omitted-*`: $R_{t+1} > 14.0 \land D_{t+1} == 0.0$ かつ最高 $u$ モジュールが $u_i > 5.5$ なら 1 個だけ出芽分裂（親は ID 継続の**一意継続出力**、$c_{\mathrm{split}} = 1.5$ 消費、$u_{\mathrm{parent}} \leftarrow 0.55(u_i - c_{\mathrm{split}})$、$u_{\mathrm{child}} \leftarrow 0.45(u_i - c_{\mathrm{split}})$、子に新規 `next_id` と決定的小摂動 $\pm 0.05$）。
       - `Runaway-Cancer`: $R_{t+1}, D_{t+1}$ を無視し、4 歩ごとに全活性モジュールを分裂（分裂費 $c_{\mathrm{split}}$ は不足分を $D_{t+1}$ へ加算）。
       - `Hidden-Age-Control`: `CPC-Prolif` の規則に加え、**絶対時計 `t_abs == 15`** の歩で最高 $u$ モジュールを強制分裂させる（許可状態には年齢欄を持たず、絶対時計のみに依存）。
     - (iv) **致死判定**: $D_{t+1} > D_{\mathrm{lethal}} = 12.0$ または $|M_{t+1}| == 0$ なら `alive = false`（不可逆）。
     - (v) 最後に配線再構築、文脈 $c_{t+1} = x_k$。

---

## 4. 要件・関門（GATE: すべて終了コード 0 で合格）

- **G0（Lean 形式証明）**:
  - `formal/NestingLineage.lean` が `ERIEC.MetaSelection` を import し、次の名前つき定理を `sorry` 0・標準公理のみ（`#print axioms` 出力で確認）で証明し、`sh formal/check.sh` に `NestingLineage.lean` が含まれて PASS すること：
    1. `stage0_isomorphic`（互いに素な担体 `V0, V1` 上の `PartOfHierarchy`・`WorldDecomposition`・`WorldIrreducible` の同型性）
    2. `stage1_separates_persist_and_replace`（`H_persist` と `H_replace` が同一 Stage 0 観測を持ちつつ整形式 Stage 1 `LineageSpan` で分離される）
    3. `split_continuant_unique`（整形式 `LineageSpan` で 1 分裂あたり継続出力は最大 1 個）
    4. `merge_fusion_no_continuant`（融合 `fusion` は親 ID を継承せず継続出力 0 個、吸収 `absorption` はちょうど 1 親継続）
    5. `body_death_irreversible`（身体ノードは機能終了後に再接続不能）
- **G1（R1・R2 整形式＋遷移内 M1 連続性＋負試験 2 件）**:
  - Julia の離散証人（`H_persist`, `H_replace`, `H_shifting`）で Stage 0 同型・Stage 1 分離を確認。
  - 全 20 評価種子（890..909）×全歩で R2 違反 0 件（端点排他、1 分裂最大 1 継続出力、単調増加非再利用 ID、遷移内での担体生存中断なし、身体不可逆性）。
  - R2 負試験 2 件（`deepcopy` による 2 継続出力注入、親破壊後のスロット再利用コピー注入）を 100% 検出（fail）。
- **G2（E1 暴走分離、P-05 準拠・根拠なき数値閾値なし）**:
  - 20 評価種子（890..909）で `CPC-Prolif` と `Runaway-Cancer` を比較し、(a) 生存の厳密優越（`CPC-Prolif` の生存種子集合 $\supsetneq$ `Runaway-Cancer` の生存種子集合）、(b) `CPC-Prolif` の平均最大負債 $<$ `Runaway-Cancer` の平均最大負債、(c) `CPC-Prolif` の全生存歩プール（20 種子合算、死後打ち切り）での同歩誕生数 `birth_t` と維持費赤字 `deficit_t` のピアソン相関 $r < 0$（分散 0 で `NaN` なら予測外れ）を報告。
- **G3（E2 非干渉＋絶対時計時間シフト不変性）**:
  - 同一の許可初期状態・同一 `tape` 上で、(a) 外部禁止入力（ダミー `Φ_rich`・通訳文字列）変化、(b) 開始絶対時刻シフト `t_start = 0` vs `t_start = 20` の双方を実行。
  - `CPC-Prolif` は 20/20 評価種子で全許可状態・turnover・$L_t$ がビット一致すること。
  - `Hidden-Age-Control` は同一時間シフト操作（`t_start = 0` は歩 15 で `t_abs == 15` 強制分裂、`t_start = 20` は非通過）により 20/20 評価種子で `L_t` の不一致が検出されること。
- **G4（E3′ 厳格分離・優先順位 `unresolved > core_present > no_core_witnessed`）**:
  - **適格交代歩 $t^*$**: 各評価種子で、最初の $L_t$ メンバー変化（`split`/`death`/`merge`）かつ前後プローブ窓 $[t^*-\Delta-1, t^*-1]$・$[t^*+1, t^*+\Delta+1]$ が生存・$|M| \ge 3$ で完全に収まる $t^*$ を選ぶ。適格 $t^*$ が存在しない種子は即 **G4 FAIL**（スキップ禁止）。
  - **身体隔離＋偽摂動校正**: $(R_t, D_t)$ を一致固定。全 20 評価種子（890..909）すべてで偽摂動 $\delta_{\mathrm{pert}} = 0.0$ の差分が $|\Delta \hat{p}_j| \equiv 0.0$ であることを確認した上で、$\delta_{\mathrm{pert}} = 0.8$ により $t^*$ 前後・ローテーション位相切替前後とも窓 $\Delta = 2$ 内のモジュール間伝播（$|\Delta \hat{p}_j| > 10^{-9}$）を検査。
  - **独立目録監査＋キャッシュ貫通プローブ（優先順位 1 位）**: `fieldnames(typeof(sys))` 反射による全状態欄の列挙と `GrantInventory` の突合、および**キャッシュ準備済み状態で新鮮認可を停止（輸送路保持）したときに未記載欄経由の読取・伝播が残るか**を独立検証。抜落または未説明残余依存があれば直ちに **`unresolved`** を返す（`core_present` 判定より優先）。
  - **規則レベル一括無効化＋時間固定切除＋交換試験＋迂回証人＋粒度別カット（優先順位 2 位）**: ホスト粒度・規則粒度の両方の最小頂点カットを算出。候補規則 $R$ を全ホスト・全コピー・全記載キャッシュで一括無効化（輸送路保持）し、全活性位相で有効モジュール間修正が止まり復元で戻る場合、または交換試験で全 $\Delta\theta_j$ が $z_t$ に追随する場合は **`core_present`** として棄却。全候補規則に対し正の迂回証人が存在しホスト/規則とも最小カット $\ge 2$ でかつ前後残差伝播が成立する場合のみ **`no_core_witnessed`**。
  - 期待判定（全 20 評価種子）：`CPC-Prolif` → 20/20 `no_core_witnessed`、`Fixed-Core`・`Rotating-Mediator-Failover`・`Rotating-Mediator-Redundant`（キャッシュ記載正対照） → すべて 20/20 `core_present`、`Omitted-Cache-Control` → 20/20 `unresolved`。
- **G5（決定性・凍結 SHA-256 照合）**: 2 回独立実行の全出力ビット一致、および `experiments/freeze-nesting-cpc.txt` の SHA-256 一致。

---

## 5. `FILE:` 許可範囲
- `formal/NestingLineage.lean`（新規）
- `experiments/nesting_cpc/NestingCPC.jl`（新規）
- `experiments/nesting_cpc/run_gates.jl`（新規）
- 出力：`experiments/results-nesting-cpc.out`
- 既存 `core/`・`rust/`・`formal/*.lean`・`~/bridge-protocol` は一切変更しない。
