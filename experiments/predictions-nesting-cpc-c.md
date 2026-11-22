# S61c 予測と反証条件（r2・実行前に凍結）

- 対象仕様: `discussion/specs/S61c-nesting-cpc-pruning.md`（r2）
- 評価種子: `962..981`（20 種子、開発用 `958..961` および既存 S61/S61b/S62 評価種子と完全分離）
- 規律: 結果を見た後に本ファイルを書き換えない。外れた予測は外れたと報告する。`phenomenal_claim = :not_certified`。

## 予測（P-S61c-1〜P-S61c-5）

- **P-S61c-1（G0・G1：Lean 継承・Stage 0/1 分離・R2 整形式）**:
  - `formal/NestingLineage.lean` が無変更で `sh formal/check.sh` を通過し、Julia 側で 7 構成×20 評価種子×120 歩（内生的剪定の `:death` 事象を含む）にわたり R2 違反 0 件、負試験 2 件とも 20/20 検出。

- **P-S61c-2（G2：E1 飢饉耐性・暴走対照への厳密優越）**:
  - 同一評価テープ上で `Runaway-Cancer` が親 `NestingCPC`（S61 r3）と全 20 種子×120 歩で共有状態・事象列まで完全一致（20/20）した上で：
  - (a) 20 評価種子（`962..981`）において、`CPC-Prolif` の生存種子集合は `Runaway-Cancer` の生存種子集合を**厳密に包含**する（`survivors(CPC-Prolif) ⊋ survivors(Runaway-Cancer)`）。
  - (b) `CPC-Prolif` の平均最大負債（`StepRec.D`）は `Runaway-Cancer` の平均最大負債より厳密に小さい（参考診断の自食回収前 `D_pre_prune` 平均最大値も併記）。
  - (c) `CPC-Prolif` の全生存歩プール（死後打ち切り）における `var(birth_t) > 0` かつ `var(deficit_t) > 0` であり、同歩ピアソン相関 $r(\mathrm{birth}_t, \mathrm{deficit}_t) < 0$ となる（両分散・ラグ相関 $k=1..12$・剪定回数・`min|M_t|`・`max|M_t|`・飢饉後再増殖を診断報告）。

- **P-S61c-3（G3：E2 外部非干渉＋絶対時計時間シフト）**:
  - `CPC-Prolif` は外部禁止入力変化および開始時刻シフト（`t_start = 0` vs `20`）の両方で 20/20 ビット一致（$\bar{h}_t$ を含む全許可状態・turnover・$L_t$）。
  - `Hidden-Age-Control` は同一時間シフトで 20/20 検出（歩 15）。

- **P-S61c-4（G4：E3′ 厳格分離・優先順位 `unresolved > core_present > no_core_witnessed`）**:
  - 全 20 評価種子で適格交代歩 $t^*$ が 20/20 存在し、偽摂動 $\delta=0$ 差分は `0.0`。
  - `CPC-Prolif` 20/20 `no_core_witnessed`、3 負対照すべて 20/20 `core_present`、`Omitted-Cache-Control` 20/20 `unresolved`。
  - （診断・非合否）全辺を単一共有規則へ潰した診断では `CPC-Prolif` も `core_present` になることを確認・記録。

- **P-S61c-5（G5：決定性・凍結整合・既存親ファイル不変）**:
  - 2 回独立実行ビット一致、凍結 SHA-256 一致、既存親ファイル SHA-256 一致。

## 反証条件
1. P-S61c-2 の `Runaway-Cancer` 同一性照合、(a) 厳密優越、(b) 平均最大負債低下、(c) 両分散正かつ $r < 0$ のいずれか 1 つでも不成立（例：剪定が間に合わず致死負債に達する、または全生存歩で `Ravail >= B` となり `var(deficit_t) == 0` で `r` が未定義になる）。
2. P-S61c-1・P-S61c-3・P-S61c-4・P-S61c-5 のいずれかが 1 種子でも外れる（例：剪定と `merge` の衝突で R2 違反が発生する、または $t^*$ が欠落する）。
3. `phenomenal_claim` 逸脱、または既存 S61/S61b ファイル・`formal/`・`core/`・`~/bridge-protocol` への無断変更。
