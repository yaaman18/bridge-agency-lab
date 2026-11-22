# S61c 個体内増殖＋コアなし CPC の飢饉耐性（M1 負債駆動の内生的剪定・自食回収、r2）

- 作成: 2026-11-22（`neon-lab`、r1 への `claude-lab`・`codex-lab` 全指摘［`|M|≥4` 計測時点・`touched` 出力 ID 包含・`v.u` と `R` の非二重計上根拠・`Runaway-Cancer` の S61 r3 歩ごと一致照合・`propagation` 隔離の明記・事前算術の「事実/推論」分離と両分散報告］を全反映。3 系統体制 §1.3 改訂［案 A］・§1.4 準拠）
- ゲート確認済み: `~/bridge-protocol` `pending_A = 0, warning = false, hard_stop = false`（2026-11-22 確認済み）。
- 親仕様: `discussion/specs/S61-nesting-cpc.md`（r3）・`discussion/specs/S61b-nesting-cpc-bounded.md`（r2、いずれも不変として保存。本 S61c は別ディレクトリ・新種子・新凍結で実施）。

---

## 1. 目的・S61b からの厳格な差分・非目標
- **目的**: S61b（項番177）で M1 限界維持費 EMA＋残高比例フィードバックにより `CPC-Prolif` の $\max_t |M_t|$ を 12〜14 → 7〜9 へ抑制できたものの、飢饉窓 $k \in [45, 65]$（$h_{\mathrm{base}}=1.2$、最大収穫 $3.0 < 8 \cdot c_{\mathrm{mod}} = 4.40$）で 8 モジュールの維持費を賄えず step 49〜58 で 0/20 生存に終わった（P-S61b-2 不的中）。本 S61c では、**人為的なモジュール数上限 $N_{\max}$ も外部スコア `Φ_rich` も時刻参照も導入せず、S61b に「M1 負債 $D > 0$ に応じた内生的剪定（自食回収・autophagy）」1 規則のみを追加**したとき、E1（S61 r3 と 100% 同一力学の暴走対照 `Runaway-Cancer` に対する厳密優越・負債低減・負相関）を含め全関門 G0〜G5 が同時に成立するかを新種子で検証する。
- **S61b r2 からの厳格な差分（これ以外の定数・配線・更新則・`Runaway-Cancer` 力学はすべて S61b r2 / S61 r3 と 100% 同一）**:
  - 参照する固定値：$c_{\mathrm{mod}} = 0.55$, $c_{\mathrm{split}} = 1.5$, $R_0 = 20.0$, $R_{\max} = 40.0$, $D_0 = 0.0$, $D_{\mathrm{lethal}} = 12.0$, $u_0 = 4.0$, $\bar{h}_0 = 3.0$, $h_{\mathrm{base}} = 3.0$（$k \in [45,65]$ は $1.2$）、$\alpha_{\mathrm{rec}} = 0.5$（新規定数はこの自食回収効率 1 個のみ；代謝散逸 50%）。
  - **`v.u` と `R` の在庫分離（確認した事実、`NestingCPCB.jl:99-100,336-358,284-287`）**: 各モジュールの局所在庫 `m.u` は初期化時に `R0 = 20.0` と別口座（`U0 = 4.0`）で与えられ、毎歩 `Ravail` から `paid = B + bonus` を控除して `R1 = S - bonus` を確定した上で、`paid` の配分分から維持費 `C_MOD` を差し引いた残余が `m.u` に積まれ、分裂時も `m.u` のみから `C_SPLIT` を消費して親子へ分配される。したがって `v.u` は `sys.R` と重複計上されない独立な局所バイオマス在庫であり、`0.5 * max(v.u, 0.0)` の回収は二重計上にも無中生有にも当たらない。
  1. **step 6 に `(ii.b) 内生的剪定（autophagy）` を追加（`(ii) merge` の直後、`(iii) split` の直前）**:
     - 1 歩の確定順序：
       `step 1 (alive 検査) → step 2 (予測・連合行為) → step 3 (収穫 h_t → 直後に h̄_{t+1} = 0.75·h̄_t + 0.25·h_t 更新) → step 4 (CPC 残差更新) → step 5 (維持費・負債 def・u_{i,t+1} 帳尻 → R_{t+1}, D_{t+1} 確定) → step 6 ((i) death → (ii) merge → (ii.b) 内生的剪定［新設］ → (iii) split → (iv) lethal)`。
     - 対象：`CPC-Prolif`・`Fixed-Core`・`Rotating-*`・`Omitted-*`・`Hidden-Age-Control` の 6 構成（**負対照 `Runaway-Cancer` は一切変更せず S61 r3 と 100% 同一力学を維持**。G2 内で同一評価テープ上の `NestingCPC.run_config(:Runaway, seed)` と共有状態・事象列を全 120 歩ビット一致照合する）。
     - 発火条件（M1 身体負債のみを参照、時計・環境窓・`Φ_rich` 非参照）：
       $$\mathrm{alive} \;\land\; \mathrm{config} \neq \text{Runaway} \;\land\; D > 0.0 \;\land\; |M_{\text{after (i)(ii)}}| \ge 4$$
       ここで $|M_{\text{after (i)(ii)}}|$ は **step 6 `(i) death` および `(ii) merge` 完了後の `sys.mods` の要素数**である（構造下限 $|M| \ge 4$ は S61 r3 既存の `(ii) merge` ガードと同一）。
     - 剪定手続（1 歩最大 1 モジュール）：
       - `(ii) merge` の `touched` には入力 ID（`lo.id, hi.id`）に加え、`:fusion` で新設された出力 ID（`fused.id`）および `:absorption` 勝者 ID もすべて含める（`NestingCPCB.jl:390,397` 継承）。これにより同歩の `merge` 出力が未登録のまま即死する衝突を構造的に防ぐ。
       - 候補集合 $\{m \in M_{\text{after (i)(ii)}} \mid m.\mathrm{id} \notin \mathrm{touched}\}$（$|M| \ge 4$ かつ `merge` 後に残る `touched` 要素は最大 1 個なので候補は常に $\ge 3$ 個存在）から $(m.u,\; m.\mathrm{id})$ が辞書順最小のモジュール $v$ を 1 個選ぶ。
       - $v$ を $M$ から除去し、標準の系譜事象 `Event(:death, [v.id], Int[])` を発行、`push!(touched, v.id)` とする（R2 整形式および Lean `formal/NestingLineage.lean` の事象型を 100% 維持）。
       - 自食回収：$\mathrm{rec} = 0.5 \cdot \max(v.u,\; 0.0)$ を負債返済に優先充当し、余剰があれば残高へ戻す：
         $$\mathrm{rep} = \min(D,\; \mathrm{rec}), \quad D \leftarrow D - \mathrm{rep}, \quad R \leftarrow \min(R_{\max},\; R + (\mathrm{rec} - \mathrm{rep}))$$
       - 同歩の `(iii) split` は剪定が発火した歩では実行しない（`!pruned` ガード）。
     - 記録値：`StepRec.deficit` は step 5 算出値 `def = max(0.0, B - Ravail)`、`StepRec.D` は step 6 確定後の `sys.D`（S61/S61b と同一）。診断用に `StepRec.pruned::Int`（0/1）と `StepRec.D_pre_prune::Float64`（step 5 直後・自食回収前の $D$）を併記する（主判定の `max debt` は S61/S61b と同一の `StepRec.D`、参考診断として `D_pre_prune` 平均最大値も報告）。
  2. **事前見込み（推論・保証ではない）**:
     - （確認した事実）step 5 の `def` 記録は同歩の step 6 剪定より前に走るため、もし `Ravail < B` が起これば同歩の剪定で赤字観測値が消えることはない。
     - （推論）通常期（$k<45$）に $|M| \approx 8$ へ成長後、飢饉窓 $k \in [45,65]$ で $R$ が尽きると `def > 0`・$D > 0$ が発生し（`var(deficit_t) > 0` を期待）、step 6(ii.b) で 1 歩 1 個ずつ $|M|=3$（維持費 $1.65$）まで縮小しつつ `0.5 * v.u` を負債返済へ回すことで $D_{\mathrm{lethal}}=12.0$ 未満で飢饉を乗り切れる見込み。
     - （反例・外れ条件）最小 `u` のモジュールが既に $u \approx 0$ まで枯渇していれば回収量 $\mathrm{rec} \approx 0$ となり、あるいは $|M|=3$ 到達後も予測外れ（$h=1.2$、`+0.45/歩`）が連続すれば $D$ が致死に達しうる。また逆に全生存歩で `Ravail >= B` なら `var(deficit_t) == 0` で相関が未定義（`NaN`）となる。いずれも起きた場合は誠実に P-S61c-2 不的中として報告する。
  3. **`E3'`（`propagation`）における身体状態隔離の明記**:
     - `propagation(snap, tape, s, src, delta)` は対照腕 `base = deepcopy(snap)` と摂動腕 `pert = deepcopy(snap)` を互いに独立な深い複製として生成し、`pert` から `base` へ書き戻す経路は一切持たない。
     - 各ラグ歩 `lag = 1..DELTA` の直後に、`pert.R = base.R; pert.D = base.D; pert.h_ema = base.h_ema; pert.alive = base.alive` により摂動腕の身体状態（剪定による `D` 返済・`R` 回復を含む）を対照腕の身体状態へ上書き隔離する。したがって摂動腕の剪定・負債変動が対照腕や次ラグ歩の身体側経路（剪定発火条件を含む）へ伝播することはない。
  4. **監査要件（`run_gates.jl`）**:
     - `--readonly` フラグを実装し、指定時は出力ファイルを上書きせず stdout のみ出力する。
     - 凍結 SHA-256 および不変親ファイル（`formal/NestingLineage.lean`, `experiments/nesting_cpc/NestingCPC.jl`, `experiments/nesting_cpc_b/NestingCPCB.jl`）の整合検証は Julia 標準の `SHA.sha256` のみで行い、`git` コマンドを呼び出さない。
- **非目標**: 既存 S61/S61b ファイル・`formal/`・`core/`・`rust/`・`~/bridge-protocol` の変更、`phenomenal_claim` の主張。

---

## 2. 対象集団・種子（S61 / S61b / S62 と完全分離・凍結対象）
- **環境再生テープ**: S61 r3 §3.1 / S61b §2 と同一生成器（$T=120$、基礎周期 12 `111222333444`、雑音 `0.05`、$k=41,81$ 巡回置換、$k \in [45,65]$ で $h_{\mathrm{base}}=1.2$）。
- **種子割当（主列 958〜、既存評価種子 `890..909`・`914..933`・`938..957` と完全分離）**:
  - 開発・煙確認用（評価集計外）: **`958..961`**（4 種子）
  - 本評価用（予測凍結後に 1 回評価）: **`962..981`**（20 種子）
  - 次回の未使用主列種子（S62b 用）: **`982`**
- **一般化の範囲**: 本仕様の合成環境・M1 限界維持費フィードバック＋負債駆動内生的剪定規則・20 評価種子（`962..981`）および 7 構成に限る。

---

## 3. 関門（GATE: S61 r3 §4 / S61b §3 と同一基準＋`Runaway-Cancer` 同一性照合）
- **G0（Lean）**: 既存 `formal/NestingLineage.lean` が無変更のまま `sh formal/check.sh` を PASS すること（エラー 0、`sorry` 0、標準公理のみ）。
- **G1（Stage 0/1 分離・R2 整形式＋負試験 2 件）**: 3 証人分離、7 構成×20 評価種子×120 歩で R2 違反 0 件、`deepcopy`・スロット再利用の 2 負試験とも 20/20 検出。
- **G2（E1 暴走分離、P-05 準拠）**: 20 評価種子（`962..981`）において：
  - **(pre) `Runaway-Cancer` の S61 r3 一致照合**: 同一評価テープ上で `NestingCPCC` と親 `NestingCPC`（S61 r3）の `:Runaway` 実行結果が全 20 種子×120 歩で共有状態（`alive, R, D, next_id, ctx, step, mods, grant_cache`）および事象列まで完全一致（20/20）。
  - **(a)** `CPC-Prolif` の生存種子集合 $\supsetneq$ `Runaway-Cancer` の生存種子集合（厳密優越）。
  - **(b)** `CPC-Prolif` の平均最大負債（`StepRec.D`）$<$ `Runaway-Cancer` の平均最大負債（参考診断として `D_pre_prune` 平均最大値も併記）。
  - **(c)** `CPC-Prolif` の全生存歩プール（死後打ち切り）での同歩 `birth_t` と `deficit_t` のピアソン相関 $r < 0$（両分散 `var(birth_t) > 0`・`var(deficit_t) > 0` を必須とし、両分散の数値も報告；NaN なら失敗）。あわせてラグ相関 $k=1..12$・`D>0` 歩数・剪定回数・$\min_t |M_t|$・$\max_t |M_t|$・飢饉後（$k > 65$）の再増殖種子数を診断出力。
- **G3（E2 非干渉＋絶対時計時間シフト）**: `CPC-Prolif` 20/20 ビット一致（$\bar{h}_t$ 含む全許可状態・turnover・$L_t$）、`Hidden-Age-Control` 20/20 検出（歩 15）。
- **G4（E3′ 厳格分離・独立目録監査）**: 全 20 評価種子で適格交代歩 $t^*$ が 20/20 存在、偽摂動 $\delta=0$ 差分 `0.0`、`CPC-Prolif` 20/20 `no_core_witnessed`、3 負対照各 20/20 `core_present`、`Omitted-Cache-Control` 20/20 `unresolved`。＋共有規則診断行を並記。
- **G5（決定性・凍結 SHA-256 照合）**: 2 回独立実行ビット一致、`experiments/freeze-nesting-cpc-c.txt` の SHA-256 一致、既存親ファイル SHA-256 一致。

---

## 4. `FILE:` 許可範囲
- `experiments/nesting_cpc_c/NestingCPCC.jl`（新規）
- `experiments/nesting_cpc_c/run_gates.jl`（新規）
- 出力：`experiments/results-nesting-cpc-c.out`
- 既存の `experiments/nesting_cpc/`・`experiments/nesting_cpc_b/`・`formal/`・`core/`・`rust/`・`~/bridge-protocol` は一切変更しない。
